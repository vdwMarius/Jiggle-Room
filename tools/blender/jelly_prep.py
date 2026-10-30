"""
Jiggle Room - Blender helper (Blender 3.6 / 4.x).

Prepares the ACTIVE mesh object for use as a jelly and exports it as .glb:

  1. Applies scale/rotation, moves the origin to the bounding-box centre.
  2. Optionally decimates to stay under the 5k-vertex budget.
  3. Creates a "JellyWeight" colour attribute and fills it with automatic
     floppiness weights (RED channel; black = rigid core, red = floppy):
       - from distance to the centre (far = floppy), and
       - boosted by an optional vertex group named "Floppy" (paint it in
         Weight Paint mode on fins, tails, tentacles), and
       - reduced by an optional vertex group named "Core".
     You can then refine the colours by hand in Vertex Paint mode.
  4. Exports <blend dir>/<object name>.glb with vertex colours.

Usage: open the Scripting tab, load this file, select your mesh, adjust the
SETTINGS below, press "Run Script". Re-running only rebuilds the weights if
OVERWRITE_WEIGHTS is True, so hand-painted weights are preserved otherwise.
"""

import os

import bpy

# ------------------------------------------------------------------ SETTINGS
TARGET_MAX_VERTS = 4500        # stay under the game's ~5k budget
INNER = 0.45                   # fraction of radius that is fully rigid core
OUTER = 1.0                    # fraction of radius that is fully floppy
FLOPPY_GROUP = "Floppy"        # optional vertex group: adds floppiness
CORE_GROUP = "Core"            # optional vertex group: removes floppiness
ATTR_NAME = "JellyWeight"
OVERWRITE_WEIGHTS = True
EXPORT = True
EXPORT_DIR = ""                # "" = next to the .blend file
# ---------------------------------------------------------------------------


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / max(e1 - e0, 1e-6)))
    return t * t * (3.0 - 2.0 * t)


def prepare(obj):
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    # 1. Apply transforms and centre the origin.
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0.0, 0.0, 0.0)

    # 2. Decimate if needed.
    mesh = obj.data
    if len(mesh.vertices) > TARGET_MAX_VERTS:
        ratio = TARGET_MAX_VERTS / len(mesh.vertices) * 0.95
        mod = obj.modifiers.new("JellyDecimate", "DECIMATE")
        mod.ratio = ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
        print(f"Decimated to {len(obj.data.vertices)} vertices")
        mesh = obj.data

    # Smooth shading looks much better on jelly.
    for poly in mesh.polygons:
        poly.use_smooth = True

    # 3. Floppiness weights in a colour attribute (point domain).
    attr = mesh.color_attributes.get(ATTR_NAME)
    fresh = attr is None
    if attr is None:
        attr = mesh.color_attributes.new(ATTR_NAME, "FLOAT_COLOR", "POINT")
    mesh.color_attributes.active_color = attr
    try:
        mesh.color_attributes.render_color_index = mesh.color_attributes.find(ATTR_NAME)
    except AttributeError:
        pass

    if fresh or OVERWRITE_WEIGHTS:
        radius = max((v.co.length for v in mesh.vertices), default=1.0)
        floppy = obj.vertex_groups.get(FLOPPY_GROUP)
        core = obj.vertex_groups.get(CORE_GROUP)
        for v in mesh.vertices:
            w = smoothstep(INNER, OUTER, v.co.length / radius)
            for g in v.groups:
                if floppy and g.group == floppy.index:
                    w = max(w, g.weight)
                if core and g.group == core.index:
                    w *= 1.0 - g.weight
            # Linear value: the game reads COLOR.r directly.
            attr.data[v.index].color = (w, 0.0, 0.0, 1.0)
        print(f"Wrote floppiness weights for {len(mesh.vertices)} vertices")

    print(f"{obj.name}: {len(mesh.vertices)} vertices, radius {radius_of(mesh):.3f} m")


def radius_of(mesh):
    return max((v.co.length for v in mesh.vertices), default=0.0)


def export(obj):
    directory = EXPORT_DIR or os.path.dirname(bpy.data.filepath) or os.path.expanduser("~")
    path = os.path.join(directory, f"{obj.name}.glb")
    common = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=False,
        export_materials="NONE",
        export_animations=False,
    )
    try:
        # Blender 4.2+
        bpy.ops.export_scene.gltf(**common, export_vertex_color="ACTIVE")
    except TypeError:
        # Blender 3.6 - 4.1
        bpy.ops.export_scene.gltf(**common, export_colors=True)
    print(f"Exported {path}")


obj = bpy.context.active_object
if obj is None or obj.type != "MESH":
    raise RuntimeError("Select the jelly mesh object first.")
prepare(obj)
if EXPORT:
    export(obj)
