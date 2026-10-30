# How the jelly works

```
 touch / contacts / velocity              CPU, per jelly, per frame               GPU, per vertex
┌───────────────────────────┐   ┌────────────────────────────────────┐   ┌──────────────────────────────┐
│ RigidBody3D (JellyObject) │──▶│ JellySprings                       │──▶│ jelly.gdshader vertex()       │
│  velocity, accel,         │   │  stretch   (scalar + axis)         │   │ 1 impact flatten (anchored)  │
│  angular accel, contacts  │   │  lag       (vec3)  ← -accel        │   │ 2 squash & stretch           │
│ TouchController           │   │  twist     (vec3)  ← -ang. accel   │   │ 3 lag/twist × weight × reach │
│  poke / grab / flick      │   │  impact    (scalar + normal)       │   │ 4 grab (gaussian falloff)    │
└───────────────────────────┘   │  grab      (vec3)  ← finger        │   │ 5 up to 8 ripples            │
                                │  ripples   8× (origin, t0, amp)    │   │ 6 soft cap (max_deformation) │
                                └────────────────────────────────────┘   └──────────────────────────────┘
```

## 1. Motion: a plain rigid body

`JellyObject` extends `RigidBody3D` and uses a convex hull (or a sphere, box or
capsule) as its collider. The body itself never deforms. That keeps collisions
cheap and stable. Scaling (pinch, merge) rebuilds the collision shape at the
new size instead of scaling the body node, which Godot physics doesn't support.

Each physics step, `_integrate_forces` does three things:

* Estimates **linear and angular acceleration** from the change in velocity.
  These drive the secondary motion.
* Reads **contacts**. The contact normal is oriented against the incoming
  velocity, and the impact speed is `-(v_prev - v_other) · n`. The strongest
  contact of the step kicks the impact spring and emits `impacted`, which
  drives haptics and sound.
* Handles **sticky walls**. On wall contact the jelly cancels gravity and
  bleeds off velocity for about 0.6 s, then slowly lets go.

## 2. The springs (`jelly_springs.gd`)

Every channel is a damped harmonic oscillator:

    x'' = -ω² (x - target) - 2ζω x' + drive        ω = 2π · wobble_frequency,  ζ = damping

It's integrated with semi-implicit Euler and sub-stepped so `ω·h < 0.35`.
That keeps it stable even at 8 Hz on a 30 FPS hitch.

| Channel | Target / drive | What you see |
| --- | --- | --- |
| `stretch` | `speed × stretch_per_speed` along the (smoothed) velocity axis | Elongates when fast, overshoots into a squash when it stops |
| `lag` | Drive = `-acceleration` (local space) | Floppy parts trail behind, then overshoot past the body |
| `twist` | Drive = `-angular acceleration` | Tentacles and fins swing behind a spin |
| `impact` | Velocity kick `amount × ω` on a hit | Flattens, rebounds, and rings 2–4 times |
| `grab` | Follows the finger while held (critically damped); target becomes 0 on release (underdamped) | Stretches toward the finger, then snaps back with a wobble |
| ripples | Ring buffer of 8 `(origin, start time, amplitude)` | Concentric waves from each tap |
| `sway` | Drive = `-sideways acceleration`; kicked by pokes, grab release and jolts. Runs at 0.7× the frequency | The top sways over a planted base, like gelatin on a plate |
| `sag` | Target = `sag_amount` while resting on something, 0 in the air, in zero-g or while held | Soft resting squash; landing wobbles down into it |
| `wobble2` | Kicked on every hit around a random axis across the hit. Runs at 1.65× the frequency | Faster elliptical shimmer on top of the main bounce |

The springs use their own clock (`time += delta`). That means slow-motion
(`Engine.time_scale`) slows the wobble too, and photo mode (`SceneTree.paused`)
freezes the jelly mid-squish.

## 3. The shader (`shaders/jelly.gdshader`)

All vectors are in **mesh-local space**, so one material per jelly is enough
and no per-object matrices are needed. The vertex stage applies these steps in
order:

1. **Impact.** Volume-preserving scale `k = 1 - impact` along the contact
   normal, anchored at the mesh's support point on the contact side. The
   anchor comes from the AABB, so a long dolphin flattens against the floor
   instead of sinking into it. When it compresses along the normal, the
   perpendicular axes grow by `1/√k`, which is why it bulges sideways.
   **Ground frame.** A volume-preserving `sag` along local "up" (from
   gravity), anchored at the base, then the `wobble2` ellipse, then a `sway`
   shear that grows with height above the base (`h^1.5`), with its normals
   corrected by the shear's inverse-transpose.
2. **Squash and stretch.** The same volume-preserving scale, along the
   velocity axis.
3. **Secondary motion.** `p += lag × w × reach²` plus a rotation of
   `twist × w × reach²`. Here `w` is the painted weight (vertex colour **red**)
   and `reach` is the distance from the centre divided by the radius, so tips
   move most.
4. **Grab.** `p += grab × exp(-d²/r²)` around the grabbed point.
5. **Ripples.** For each of the 8 slots:
   `disp = A · e^(−decay·t) · sin(freq·t − dist·k) · front`, pushed along the
   normal. `front` masks the region the wave hasn't reached yet (wave speed =
   `freq/k`). The analytic slope `∂disp/∂dist` tilts the normal, so ripples
   catch the light.
6. **Soft cap.** The total displacement is passed through
   `cap · tanh(|δ|/cap)`, with `cap = max_deformation × radius`. Small motions
   stay linear and large ones saturate smoothly. It never goes mushy and never
   looks clipped.

Normals are transformed with the inverse-transpose of each scale, so lighting
stays correct while squashed.

The fragment stage produces the look:

* **Refraction.** It samples `hint_screen_texture` at `SCREEN_UV − normal.xy ×
  strength` and tints it by the jelly colour.
* **Body vs. see-through.** The lit `ALBEDO` is `colour × opacity`. The
  refracted background goes into `EMISSION × (1 − opacity)`, so the room
  behind isn't shaded twice.
* **Fresnel rim**, an **inner glow** that is brightest where the jelly faces
  you (it reads as thickness, a cheap subsurface look), `BACKLIGHT` for light
  through thin edges, soft GGX specular (`roughness ≈ 0.12`), optional
  **gradient** (by local height), **glitter** (hashed facets that twinkle with
  view angle) and **glow-in-the-dark** (emission).

### Transparency without flicker

Classic alpha blending sorts per object, not per triangle, so a concave
translucent mesh (an octopus) flickers as its triangles fight. Jiggle Room
avoids alpha blending altogether:

* The shader reads the screen texture, which places it in the transparent pass
  *after* all opaque room geometry has been drawn.
* It composites "background seen through jelly" itself and writes a fully
  resolved colour.
* With `depth_draw_always` and `cull_back`, each pixel shows only the nearest
  jelly surface. There is no order dependence inside a mesh, and therefore no
  flicker.

**Trade-off:** a jelly seen *through* another jelly is hidden behind it,
because the screen copy only contains opaque geometry. In practice this reads
as "thick gummy" and looks fine. If you need true jelly-through-jelly, add
`ALPHA = opacity;` to the fragment and switch to `depth_draw_opaque`. Expect
some sorting artefacts where jellies overlap.

## 4. Meshes

`JellyMeshFactory` builds the 7 built-in shapes as a UV sphere (72×56, about
4k vertices) whose rays are "radially unioned" with a few ellipsoids. A smooth
max blends the joins, and each ellipsoid carries a floppiness weight that's
written to vertex colour red. Meshes from Blender go through `prepare_custom`,
which merges the surfaces, recentres the mesh, keeps the painted `COLOR_0`
(or generates distance-based weights if it's missing) and warns above 5k
vertices. Meshes are cached and shared between jellies of the same type.

## 5. Performance budget (mid-range Android, 8 jellies)

* Vertex shader: about 4k vertices × 8 jellies × (8 ripple iterations + a few
  scales) is comfortably under 2 ms on an Adreno 6xx or Mali-G7x.
* One screen copy per frame (shared by every jelly).
* CPU: each jelly runs a dozen scalar springs plus one material update. That's
  negligible.
* Physics: convex hulls (simplified) at 60 Hz, `max_contacts_reported = 6`.
* Shadows: one directional light. If you're GPU-bound, drop
  `shadow_blur` or disable it in the Room script.

## 6. Rooms and camera

* **Rooms** are real-scale furnished interiors (e.g. a 6 × 2.8 × 5 m living
  room). All six surfaces are visible because the camera lives inside. Each
  `RoomTheme` picks a `layout`. `Room._rebuild_furniture` places pieces from
  `Furniture` (sofa, armchair, coffee table, TV unit, bookshelf, lamps, bed,
  nightstands, wardrobe, desk, kitchen counters, fridge, dining set, toys,
  beanbags, windows, pictures, doors). Each piece is a handful of primitive
  meshes with box/cylinder/hull colliders. Cushions, mattresses and beanbags
  use a bouncy physics material. Furniture only rebuilds when the theme,
  size, props toggle or light colour changes.
* **Camera** (`CameraRig`) is an orbit camera around a pivot: yaw, pitch and
  distance, all exponentially smoothed, with flick inertia. Before each frame
  the distance is shortened analytically against the room box, so the camera
  never leaves the room. `TouchController` sends it every touch that doesn't
  start on a jelly: one finger orbits, two fingers pan and zoom, and a
  double-tap resets. Grabbed jellies move in an upright plane facing the
  camera, so dragging up always lifts them. Tilt-gravity and shake use the
  camera's yaw only, so they feel the same at any pitch.
