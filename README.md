# Jiggle Room

A relaxing, tactile jelly-physics toy for Android, built with **Godot 4.3+**
(GDScript, Mobile renderer, 3D). Pick a jelly (blob, cube, star, duck, dolphin,
octopus, heart, or your own Blender models), then poke, drag, fling, pinch and
shake it around a furnished room (living room, bedroom, playroom, kitchen,
plus unlockable aquarium and space station). Bounce it off the sofa, drop it
on the bed, and move the camera anywhere in the room.

The jelly is **not** a soft-body simulation. Each jelly is a `RigidBody3D` for
motion, plus a vertex shader whose deformation is driven by a few damped
springs that run on the CPU. It's cheap, stable at 60 FPS on mid-range phones,
and every part of the feel can be tuned.

| Doc | What's in it |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the jelly effect works: springs, shader passes, transparency |
| [docs/TUNING_GUIDE.md](docs/TUNING_GUIDE.md) | Which parameters change the feel, and recipes |
| [docs/BLENDER_WORKFLOW.md](docs/BLENDER_WORKFLOW.md) | Modelling, painting floppiness weights, glTF export |
| [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md) | APK/AAB export, permissions, signing, performance checklist |

---

## Step-by-step setup

1. **Install Godot 4.3 or newer** (standard build, not .NET) from godotengine.org.
   4.3 is the minimum because the haptics call uses the `amplitude` argument of
   `Input.vibrate_handheld`.
2. **Clone this repo** and open `project.godot` from the Godot Project Manager.
   The first import takes a few seconds. The project is already set to the
   **Mobile** renderer.
3. **Press F5.** The game runs on desktop with the mouse standing in for touch
   (`input_devices/pointing/emulate_touch_from_mouse`). Desktop shortcuts:
   `S` shake, `G` cycle gravity, `M` slow-mo, `P` photo mode, `R` reset view,
   the mouse wheel to zoom, and right-drag to pan.
4. **To try a different window shape**, open Project Settings → Display →
   Window and set the size to 1280×720 to check landscape. The UI and room
   re-layout live.
5. **To play on a phone**, follow [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md):
   install the Android export templates, set the SDK path, enable USB
   debugging, then use the one-click deploy button (top-right of the editor).

### Controls

| Gesture | Effect |
| --- | --- |
| Tap a jelly | Ripple spreads out from the finger, small dent and nudge |
| Drag | Grab: the jelly follows the finger and stretches toward it, then springs back |
| Flick and release | Throw, using the finger's speed over the last ~90 ms |
| Two-finger pinch on a jelly | Scale the jelly (0.5×–2.6×) |
| Drag empty space | Orbit the camera around the room (with a little glide) |
| Two fingers on empty space | Pan (move together) and zoom (pinch) |
| Double-tap empty space, or **View** | Reset to the room's default view |
| Shake the phone | Every jelly gets jolted (accelerometer) |
| **Grav** button | Gravity on → zero-g (gentle drift) → reversed |
| More → *Tilt phone* | Gravity follows the phone's tilt |
| **Slow** | 0.25× time to admire the wobble |
| **Photo** | Freeze, move the camera (*Focus* jumps to the last-touched jelly), save a PNG or a 2.5 s GIF |
| Jelly → *Merge: On* | Drag one jelly into another (or smash them together) to merge into a bigger one |

---

## Project structure

```
project.godot            Mobile renderer, autoloads, portrait+landscape, sensors on
export_presets.cfg       Android APK (debug/sideload) + AAB (Play Store) presets
icon.svg
scenes/
  main.tscn              Root (everything else is created by scripts/main.gd)
  jelly_object.tscn      RigidBody3D + Mesh + Shape — the JellyObject scene
scripts/
  main.gd                Wiring: spawning, merging, room fitting, modes
  autoload/
    game_state.gd        Save/load (JSON), per-jelly custom settings, stats, unlocks
    feedback.gd          Haptics + synthesised squelch/boing/pop sounds
    ads_service.gd       Optional rewarded-ads wrapper (no SDK required)
  jelly/
    jelly_data.gd        JellyData resource: geometry, feel and look of one jelly type
    jelly_object.gd      JellyObject: physics, contacts, touch API, feeds the shader
    jelly_springs.gd     Damped-spring system: stretch, lag, twist, impact, grab, ripples
    jelly_mesh_factory.gd  Procedural placeholder meshes + custom glTF mesh preparation
  room/
    room_theme.gd        RoomTheme resource: layout, size, colours, lighting
    room.gd              Walls/colliders, surfaces, lights, furniture layouts, wall modes
    furniture.gd         Primitive-built furniture with colliders (soft pieces are bouncy)
  input/
    touch_controller.gd  Tap / drag / flick / pinch
    motion_controller.gd Gravity modes, tilt steering, shake detection
  ui/
    ui_kit.gd            Touch-friendly theme and widget helpers
    hud.gd               Toolbar + panels (jelly, colour/feel, room, more), photo bar
  util/
    camera_rig.gd        Free orbit/pan/zoom camera that stays inside the room
    photo_mode.gd        Freeze, PNG screenshots, GIF capture
    gif_encoder.gd       Small GIF89a/LZW encoder (runs on a thread)
shaders/
  jelly.gdshader         The single jelly shader (8 ripples via uniform arrays)
  room_surface.gdshader  Procedural wall/floor patterns
assets/
  jellies/*.tres         One JellyData per jelly type (drop in more!)
  rooms/*.tres           One RoomTheme per theme
  models/                Your Blender .glb files
  audio/                 Optional custom sounds (override the synthesised ones)
tools/blender/jelly_prep.py  Blender script: centre, decimate, auto-weights, export .glb
```

### Adding a new jelly (no code)

1. Model it in Blender and run `tools/blender/jelly_prep.py` (see the
   [Blender workflow](docs/BLENDER_WORKFLOW.md)). Copy the `.glb` into
   `assets/models/`.
2. In Godot: FileSystem → `assets/jellies/` → right-click → **New Resource →
   JellyData**, then save it as e.g. `turtle.tres`.
3. Set `id`, `display_name`, and drag the `.glb` into **model_scene**.
4. Tune **Feel** and **Look** (see the [tuning guide](docs/TUNING_GUIDE.md)).
   Optionally set an `unlock_rule` such as `pokes:200`.
5. Run. The picker lists every `.tres` in the folder.

Adding a room works the same way: create a **RoomTheme** in `assets/rooms/`,
pick a `layout` (living room, bedroom, kitchen, playroom, aquarium, space),
set `room_size`, and recolour the walls, floor, fabric, wood, accent and the
sky seen through the windows. New furniture arrangements go in
`Room._rebuild_furniture` using the `Furniture` builders.

### Unlocks and ads

Duck, dolphin, octopus, heart, the kitchen, aquarium and space station unlock
through play: pokes, throws, merges, minutes played and spawns. The rules are plain
strings on each resource. There are **no interstitials or banners**. A locked
item can show an optional "Watch ad to unlock" button, but only when an ad
plugin is installed (`AdsService.is_available()`). In debug builds a fake 2 s
"ad" lets you test the flow.

### Saving

Everything is saved to `user://jiggle_room.json`: each jelly type's colour,
transparency, extras and feel; room settings; options; stats; and unlocks. It
saves on app pause/quit and every 20 s while there are changes.
