class_name JellyMeshFactory
extends RefCounted
## Builds jelly meshes.
##
## - Procedural placeholder shapes (blob, cube, star, duck, dolphin, octopus,
##   heart) so the game runs with zero art. Each is a deformed UV sphere whose
##   vertex colour RED carries the floppiness weight, exactly like a mesh painted
##   in Blender would.
## - Preparation of custom (Blender/glTF) meshes: merges surfaces, generates
##   fallback weights if the artist didn't paint any, and warns about high
##   vertex counts.

const MAX_VERTICES := 5000
const SEGMENTS := 72
const RINGS := 56

static var _cache: Dictionary = {}


static func get_mesh(data: JellyData) -> ArrayMesh:
	var key: String
	if data.mesh:
		key = data.mesh.resource_path + str(data.mesh.get_instance_id())
	elif data.model_scene:
		key = data.model_scene.resource_path
	else:
		key = "proc_%d" % data.procedural_shape
	if _cache.has(key):
		return _cache[key]
	var m: ArrayMesh
	if data.mesh:
		m = prepare_custom(data.mesh)
	elif data.model_scene:
		m = prepare_custom(_mesh_from_scene(data.model_scene))
	else:
		m = build_procedural(data.procedural_shape)
	_cache[key] = m
	return m


## Max distance of any vertex from the mesh origin (= shader `bound_radius`).
static func bound_radius(mesh: Mesh) -> float:
	var r := 0.0
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			r = maxf(r, v.length())
	return maxf(r, 0.001)


# ---------------------------------------------------------------- custom meshes

static func _mesh_from_scene(scene: PackedScene) -> Mesh:
	var root := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			found = (n as MeshInstance3D).mesh
		stack.append_array(n.get_children())
	root.free()
	if found == null:
		push_error("JellyData model_scene has no MeshInstance3D; using a blob.")
		return build_procedural(JellyData.Shape.BLOB)
	return found


static func prepare_custom(src: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var had_colors := true
	for s in src.get_surface_count():
		if src.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(s)
		var base := verts.size()
		var sv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		verts.append_array(sv)
		var sn = arrays[Mesh.ARRAY_NORMAL]
		if sn is PackedVector3Array and sn.size() == sv.size():
			normals.append_array(sn)
		else:
			for v in sv:
				normals.append(v.normalized())
		var sc = arrays[Mesh.ARRAY_COLOR]
		if sc is PackedColorArray and sc.size() == sv.size():
			colors.append_array(sc)
		else:
			had_colors = false
			for v in sv:
				colors.append(Color(-1, 0, 0))  # filled below
		var si = arrays[Mesh.ARRAY_INDEX]
		if si is PackedInt32Array and si.size() > 0:
			for i in si:
				indices.append(base + i)
		else:
			for i in sv.size():
				indices.append(base + i)

	if verts.size() > MAX_VERTICES:
		push_warning("Jelly mesh has %d vertices (budget %d). Decimate it in Blender." % [verts.size(), MAX_VERTICES])

	# Recentre on the bounding-box centre so deformation pivots sensibly.
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var centre := aabb.get_center()
	var radius := 0.0
	for i in verts.size():
		verts[i] -= centre
		radius = maxf(radius, verts[i].length())

	if not had_colors:
		push_warning("Jelly mesh has no vertex colours; generating distance-based weights.")
		for i in colors.size():
			if colors[i].r < 0.0:
				var t := clampf((verts[i].length() / radius - 0.55) / 0.45, 0.0, 1.0)
				colors[i] = Color(t, t, t)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


# ------------------------------------------------------------ procedural shapes

## An ellipsoid "part" for the radial-union shapes.
class Part:
	var xform: Transform3D
	var inv: Transform3D
	var weight: float

	func _init(center: Vector3, radii: Vector3, rot: Vector3, w: float) -> void:
		xform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(radii), center)
		inv = xform.affine_inverse()
		weight = w

	## Distance along unit direction `d` from the origin to the far side of this
	## ellipsoid, or 0 if the ray misses it.
	func hit(d: Vector3) -> float:
		var o := inv.origin
		var dd := inv.basis * d
		var a := dd.dot(dd)
		var b := 2.0 * o.dot(dd)
		var c := o.dot(o) - 1.0
		var disc := b * b - 4.0 * a * c
		if disc < 0.0:
			return 0.0
		var t := (-b + sqrt(disc)) / (2.0 * a)
		return maxf(t, 0.0)


static func _parts_for(shape: int) -> Array:
	var p: Array = []
	if shape == JellyData.Shape.DUCK:  # faces +X
		p.append(Part.new(Vector3(0, -0.05, 0), Vector3(0.5, 0.33, 0.36), Vector3.ZERO, 0.1))
		p.append(Part.new(Vector3(0.3, 0.32, 0), Vector3(0.22, 0.22, 0.21), Vector3.ZERO, 0.45))
		p.append(Part.new(Vector3(0.52, 0.27, 0), Vector3(0.15, 0.06, 0.1), Vector3.ZERO, 0.85))
		p.append(Part.new(Vector3(-0.45, 0.14, 0), Vector3(0.17, 0.08, 0.14), Vector3(0, 0, -0.6), 1.0))
		for side in [-1.0, 1.0]:
			p.append(Part.new(Vector3(-0.02, 0.02, 0.3 * side), Vector3(0.28, 0.15, 0.08), Vector3(0, 0, -0.3), 0.85))
	elif shape == JellyData.Shape.DOLPHIN:  # faces +X
		p.append(Part.new(Vector3(0, 0, 0), Vector3(0.55, 0.21, 0.2), Vector3.ZERO, 0.1))
		p.append(Part.new(Vector3(0.36, 0.06, 0), Vector3(0.2, 0.15, 0.15), Vector3.ZERO, 0.3))
		p.append(Part.new(Vector3(0.6, -0.03, 0), Vector3(0.16, 0.065, 0.07), Vector3.ZERO, 0.6))
		p.append(Part.new(Vector3(-0.55, 0.02, 0), Vector3(0.28, 0.11, 0.09), Vector3(0, 0, 0.05), 0.7))
		p.append(Part.new(Vector3(-0.82, 0.03, 0), Vector3(0.09, 0.06, 0.3), Vector3.ZERO, 1.0))
		p.append(Part.new(Vector3(-0.06, 0.26, 0), Vector3(0.15, 0.13, 0.045), Vector3(0, 0, 0.55), 0.95))
		for side in [-1.0, 1.0]:
			p.append(Part.new(Vector3(0.2, -0.17, 0.17 * side), Vector3(0.15, 0.045, 0.09), Vector3(0.5 * side, 0, -0.4), 1.0))
	elif shape == JellyData.Shape.OCTOPUS:
		p.append(Part.new(Vector3(0, 0.22, 0), Vector3(0.32, 0.38, 0.32), Vector3.ZERO, 0.1))
		p.append(Part.new(Vector3(0, -0.06, 0), Vector3(0.34, 0.17, 0.34), Vector3.ZERO, 0.35))
		for i in 8:
			var a := TAU * i / 8.0
			var c := Vector3(cos(a) * 0.42, -0.24, sin(a) * 0.42)
			p.append(Part.new(c, Vector3(0.34, 0.075, 0.075), Vector3(0, -a, -0.45), 1.0))
	elif shape == JellyData.Shape.HEART:
		for side in [-1.0, 1.0]:
			p.append(Part.new(Vector3(0.2 * side, 0.14, 0), Vector3(0.3, 0.3, 0.23), Vector3.ZERO, 0.45))
		p.append(Part.new(Vector3(0, -0.1, 0), Vector3(0.34, 0.34, 0.2), Vector3(0, 0, PI / 4.0), 0.55))
	return p


static func _smax(a: float, b: float, k: float) -> float:
	var h := maxf(k - absf(a - b), 0.0) / k
	return maxf(a, b) + h * h * k * 0.25


## Returns [position, weight] for a unit direction on the sphere.
static func _sample(shape: int, d: Vector3, parts: Array) -> Array:
	if shape == JellyData.Shape.CUBE:
		var n := 5.0
		var s := pow(pow(absf(d.x), n) + pow(absf(d.y), n) + pow(absf(d.z), n), 1.0 / n)
		var r := 0.42 / s
		return [d * r, clampf((r - 0.42) / 0.3, 0.0, 1.0) * 0.8 + 0.2]
	elif shape == JellyData.Shape.STAR:
		var theta := atan2(d.y, d.x) - PI / 2.0
		var lobe := pow(0.5 + 0.5 * cos(5.0 * theta), 2.2)
		var rr := 0.24 + 0.34 * lobe
		var rho := Vector2(d.x, d.y).length()
		var pos := Vector3(d.x * rr, d.y * rr, d.z * (0.17 + 0.05 * (1.0 - lobe)))
		return [pos, clampf(lobe * rho * 1.2, 0.0, 1.0)]
	elif shape == JellyData.Shape.BLOB:
		var lump := 1.0 + 0.06 * sin(3.0 * d.x + 1.0) * sin(2.0 * d.y + 0.5) + 0.05 * sin(4.0 * d.z + 2.0) * cos(2.0 * d.x)
		# Slightly flattened bottom, like a pudding.
		var pos := d * 0.48 * lump
		pos.y = pos.y * (0.85 if pos.y < 0.0 else 1.0)
		return [pos, clampf(0.45 + 0.45 * d.y, 0.0, 1.0)]
	# Radial smooth-union of ellipsoid parts.
	var r := 0.0
	var wsum := 0.0
	var wacc := 0.0
	var best := 0.0
	for part in parts:
		var t: float = part.hit(d)
		if t <= 0.0:
			continue
		r = t if r == 0.0 else _smax(r, t, 0.12)
		best = maxf(best, t)
	for part in parts:
		var t: float = part.hit(d)
		if t <= 0.0:
			continue
		var k := exp((t - best) / 0.04)
		wsum += k
		wacc += k * part.weight
	var w := wacc / wsum if wsum > 0.0 else 0.0
	return [d * maxf(r, 0.05), w]


static func build_procedural(shape: int) -> ArrayMesh:
	var parts := _parts_for(shape)
	var verts := PackedVector3Array()
	var colors := PackedColorArray()

	var dirs: Array[Vector3] = [Vector3.UP]
	for ring in range(1, RINGS):
		var phi := PI * ring / RINGS
		for seg in SEGMENTS:
			var theta := TAU * seg / SEGMENTS
			dirs.append(Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)))
	dirs.append(Vector3.DOWN)
	for dir in dirs:
		var s := _sample(shape, dir, parts)
		verts.append(s[0])
		var w: float = s[1]
		colors.append(Color(w, w, w))

	var indices := PackedInt32Array()
	var bottom := verts.size() - 1
	for seg in SEGMENTS:
		indices.append_array(_tri(verts, 0, _row(1, seg), _row(1, seg + 1)))
		indices.append_array(_tri(verts, bottom, _row(RINGS - 1, seg + 1), _row(RINGS - 1, seg)))
	for ring in range(1, RINGS - 1):
		for seg in SEGMENTS:
			var a := _row(ring, seg)
			var b := _row(ring, seg + 1)
			var c := _row(ring + 1, seg)
			var d := _row(ring + 1, seg + 1)
			indices.append_array(_tri(verts, a, c, b))
			indices.append_array(_tri(verts, b, c, d))

	# Smooth normals: accumulate area-weighted face normals.
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, indices.size(), 3):
		var a := verts[indices[i]]
		var b := verts[indices[i + 1]]
		var c := verts[indices[i + 2]]
		var fn := (c - a).cross(b - a)  # outward for Godot's clockwise front faces
		normals[indices[i]] += fn
		normals[indices[i + 1]] += fn
		normals[indices[i + 2]] += fn
	for i in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 0.0 else verts[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _row(ring: int, seg: int) -> int:
	return 1 + (ring - 1) * SEGMENTS + (seg % SEGMENTS)


## Returns a triangle wound clockwise as seen from outside (Godot front face).
static func _tri(verts: PackedVector3Array, a: int, b: int, c: int) -> PackedInt32Array:
	var va := verts[a]
	var vb := verts[b]
	var vc := verts[c]
	var outward := (va + vb + vc) / 3.0
	if (vc - va).cross(vb - va).dot(outward) < 0.0:
		return PackedInt32Array([a, c, b])
	return PackedInt32Array([a, b, c])
