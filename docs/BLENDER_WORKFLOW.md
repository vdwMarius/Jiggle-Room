# Blender workflow: modelling jellies and painting floppiness

Target: **Blender 3.6 LTS or 4.x**. Output: one `.glb` per jelly with
**vertex colours** (`COLOR_0`) where **red = floppy** and **black = rigid core**.

## 1. Model

* **Scale:** model at roughly real size. The game rescales every mesh so its
  furthest vertex sits at `JellyData.base_radius` (0.4–0.6 m works well), so
  absolute size doesn't matter. Proportions do.
* **Orientation:** +Y up (Blender Z-up becomes Y-up on export). Face the
  "front" toward **+X** (Blender +X) if you want the side profile to face the
  camera. Dolphin and duck do this.
* **Topology:**
  * Keep it **under ~5,000 vertices** (the prep script decimates if needed).
    About 2,000–4,500 is the sweet spot: ripples need enough density to show.
  * Prefer **even, quad-based density**. Ripples and grabs move vertices, so
    big flat n-gons won't deform, and long thin triangles crease.
  * Make it **one closed, manifold mesh**. Join parts (Ctrl+J) and ideally
    remesh (Voxel Remesh, then Decimate) so fins merge smoothly into the body.
  * Use **smooth shading**. Avoid hard edges/auto-smooth: split normals show as
    seams when the mesh squashes.
  * **No UVs or materials needed.** The game uses its own jelly shader.
* **Pivot:** the origin should be the body's centre of mass. The script sets
  it to the bounding-box centre. For lopsided shapes, move it onto the core by
  hand afterwards and set `INNER` in the script accordingly.

## 2. Paint floppiness weights

The shader reads **vertex colour red** as a per-vertex weight `w`:

| Colour | Meaning | Typical areas |
| --- | --- | --- |
| Black (0) | Rigid core: only gentle global squash | Torso, head centre |
| Dark red (~0.3) | Slightly loose | Cheeks, belly |
| Bright red (1) | Fully floppy: trails, overshoots, ripples most | Fins, tail, tentacle tips, ears, star points |

The secondary motion also multiplies by `reach²` (distance from the centre),
so weights don't need a perfect gradient. A rough mask is enough.

### Option A: automatic (recommended starting point)

1. Select the mesh, open the **Scripting** workspace and open
   `tools/blender/jelly_prep.py`.
2. *(Optional)* In **Weight Paint** mode, create vertex groups:
   * `Floppy`: paint fins, tails and tentacles (weight 1 = floppy).
   * `Core`: paint parts that must stay rigid even far from the centre.
3. Adjust the settings at the top:
   * `INNER`: fraction of the radius that stays fully rigid (default 0.45).
   * `OUTER`: fraction at which vertices become fully floppy (default 1.0).
   * `TARGET_MAX_VERTS`, `EXPORT_DIR`.
4. **Run Script.** It:
   * applies rotation and scale, and centres the origin;
   * decimates if over budget;
   * creates the `JellyWeight` colour attribute
     (`smoothstep(INNER, OUTER, dist/radius)`, then max with `Floppy`, then
     multiplied by (1 − `Core`));
   * exports `<ObjectName>.glb` next to the .blend file.

### Option B: hand painting

1. Switch to **Vertex Paint** mode. Make sure the active colour attribute is
   `JellyWeight` (Object Data → Color Attributes). Create one with domain
   **Vertex** and type **Color** if it doesn't exist.
2. Fill everything black (`Shift+K` with a black brush).
3. Paint pure red `(1, 0, 0)` on the extremities. Then use the **Blur**
   brush, or *Paint → Smooth Vertex Colors*, to get a soft gradient where the
   limb joins the body. Hard red/black borders show as a visible crease when
   the jelly lags.
4. Re-run the script with `OVERWRITE_WEIGHTS = False` just to export, or
   export manually (below).

> **Colour space note.** The game reads the stored (linear) value. Blender's
> brush colour picker displays sRGB, so a "50 % grey" brush stores about 0.21.
> Paint with pure red and pure black, then blur, rather than relying on
> mid-tones.

## 3. Export glTF manually (if not using the script)

**File → Export → glTF 2.0** with these settings:

| Setting | Value |
| --- | --- |
| Format | **glTF Binary (.glb)** |
| Include → Limit to | Selected Objects |
| Transform → +Y Up | ✔ |
| Data → Mesh → Apply Modifiers | ✔ |
| Data → Mesh → Normals | ✔ |
| Data → Mesh → UVs | optional (unused) |
| Data → Mesh → **Vertex Colors** | ✔. In 4.2+, set *Use Vertex Color* to **Active** |
| Data → Material | No export (the game replaces it) |
| Animation | ✘ |

## 4. Bring it into Godot

1. Copy the `.glb` into `assets/models/`. Godot imports it as a scene.
2. Create the JellyData: `assets/jellies/` → New Resource → **JellyData**.
   Set `model_scene` to the `.glb`, then set `id`, `display_name` and
   `base_radius`.
3. **Collision:** leave `AUTO_CONVEX`. A simplified hull is generated from
   the mesh. Use `SPHERE` for round blobs (the most stable resting) or
   `CAPSULE` or `BOX` for long or boxy shapes.
4. Run the game. Check the Output panel for warnings:
   * *"has N vertices (budget 5000)"*: decimate further.
   * *"has no vertex colours"*: the export lost them. Re-check the Vertex
     Colors setting. The game falls back to distance-based weights.

**Optional:** in the glb's Import dock, under Meshes, enable *Save to File*
and assign the saved mesh to `JellyData.mesh` instead of `model_scene`. That
skips instancing the scene at load.

## 5. Checklist

- [ ] One closed mesh, smooth shaded, origin at the core
- [ ] 2k–5k vertices, even density
- [ ] Red on everything that should trail; black core; blurred transitions
- [ ] Exported .glb with vertex colours, +Y up
- [ ] JellyData created, test wobble in-game with **Slow** on
