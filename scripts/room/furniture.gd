class_name Furniture
extends RefCounted
## Builds furniture and decor out of primitive meshes, with matching colliders.
##
## Every builder returns a Node3D whose origin sits on the floor at the piece's
## footprint centre, facing +Z (its "front"). The room places and rotates it.
## Soft pieces (cushions, mattresses, beanbags) get a bouncy physics material,
## so jellies trampoline off sofas and beds.

static var _soft: PhysicsMaterial
static var _hard: PhysicsMaterial
static var _mat_cache := {}


static func _phys(bounce: float, friction: float) -> PhysicsMaterial:
	var p := PhysicsMaterial.new()
	p.bounce = bounce
	p.friction = friction
	return p


static func mat(c: Color, roughness: float = 0.75, emission: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), roughness, emission]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	_mat_cache[key] = m
	return m


# ------------------------------------------------------------------ primitives

## Static body holding one or more shapes; `soft` makes it bouncy.
static func body(parent: Node3D, soft: bool = false) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 0
	if _soft == null:
		_soft = _phys(0.45, 0.8)
		_hard = _phys(0.08, 0.6)
	b.physics_material_override = _soft if soft else _hard
	b.add_to_group("props")
	parent.add_child(b)
	return b


static func box(parent: Node3D, centre: Vector3, size: Vector3, c: Color,
		collide: bool = true, soft: bool = false, roughness: float = 0.75) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(c, roughness)
	mi.position = centre
	parent.add_child(mi)
	if collide:
		var b := body(parent, soft)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = centre
		b.add_child(cs)
	return mi


## Box with rounded look: a box plus capsule edges isn't worth the vertices on
## mobile, so cushions use a squashed sphere-capped capsule instead.
static func cushion(parent: Node3D, centre: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	var r := minf(size.y, size.z) * 0.5
	cm.radius = r
	cm.height = maxf(size.x, r * 2.0)
	cm.radial_segments = 16
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = mat(c, 0.95)
	mi.position = centre
	mi.rotation.z = PI / 2.0
	# Capsule axis is rotated onto X; stretch the round profile to fill the box.
	mi.scale = Vector3(size.y / (r * 2.0), 1.0, size.z / (r * 2.0))
	parent.add_child(mi)
	var b := body(parent, true)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size * Vector3(1.0, 0.9, 0.95)
	cs.shape = shape
	cs.position = centre
	b.add_child(cs)


static func cylinder(parent: Node3D, centre: Vector3, radius: float, height: float, c: Color,
		collide: bool = true, top_radius: float = -1.0, soft: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = mat(c)
	mi.position = centre
	parent.add_child(mi)
	if collide:
		var b := body(parent, soft)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(radius, cm.top_radius)
		shape.height = height
		cs.shape = shape
		cs.position = centre
		b.add_child(cs)
	return mi


static func sphere(parent: Node3D, centre: Vector3, radius: float, c: Color,
		collide: bool = true, squash := Vector3.ONE, soft: bool = false, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	mi.scale = squash
	mi.material_override = mat(c, 0.8, emission)
	mi.position = centre
	parent.add_child(mi)
	if collide:
		var b := body(parent, soft)
		var cs := CollisionShape3D.new()
		if squash == Vector3.ONE:
			var s := SphereShape3D.new()
			s.radius = radius
			cs.shape = s
		else:
			var pts := PackedVector3Array()
			for v in sm.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
				pts.append(v * squash)
			var hull := ConvexPolygonShape3D.new()
			hull.points = pts
			cs.shape = hull
		cs.position = centre
		b.add_child(cs)
	return mi


static func light(parent: Node3D, pos: Vector3, c: Color, energy: float, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = c
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	parent.add_child(l)
	return l


static func piece(parent: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(n)
	return n


# ------------------------------------------------------------------ living room

static func sofa(p: Node3D, fabric: Color, width: float = 2.2) -> void:
	var frame := fabric.darkened(0.25)
	box(p, Vector3(0, 0.2, 0), Vector3(width, 0.3, 0.9), frame)                            # base
	box(p, Vector3(0, 0.6, -0.36), Vector3(width, 0.55, 0.2), frame, true, true)           # back
	for side in [-1.0, 1.0]:
		box(p, Vector3(side * (width * 0.5 - 0.1), 0.45, 0.0), Vector3(0.2, 0.55, 0.9), frame, true, true)
	var seats := 3 if width > 1.6 else 2
	var seat_w := (width - 0.4) / seats
	for i in seats:
		var x := -width * 0.5 + 0.2 + seat_w * (i + 0.5)
		cushion(p, Vector3(x, 0.44, 0.05), Vector3(seat_w - 0.04, 0.18, 0.7), fabric)
		cushion(p, Vector3(x, 0.78, -0.22), Vector3(seat_w - 0.06, 0.4, 0.16), fabric.lightened(0.06))
	# Throw pillows.
	sphere(p, Vector3(-width * 0.5 + 0.38, 0.68, -0.08), 0.16, fabric.lightened(0.3), true, Vector3(1, 1, 0.45), true)
	sphere(p, Vector3(width * 0.5 - 0.38, 0.68, -0.08), 0.16, Color(0.98, 0.85, 0.4), true, Vector3(1, 1, 0.45), true)


static func armchair(p: Node3D, fabric: Color) -> void:
	sofa(p, fabric, 1.0)


static func coffee_table(p: Node3D, wood: Color) -> void:
	box(p, Vector3(0, 0.42, 0), Vector3(1.2, 0.06, 0.65), wood, true, false, 0.35)
	box(p, Vector3(0, 0.12, 0), Vector3(1.05, 0.03, 0.5), wood.darkened(0.1))
	for x in [-0.54, 0.54]:
		for z in [-0.27, 0.27]:
			box(p, Vector3(x, 0.2, z), Vector3(0.05, 0.4, 0.05), wood.darkened(0.2))
	# A mug and a book to sell the scale.
	cylinder(p, Vector3(0.3, 0.5, 0.1), 0.045, 0.1, Color(0.95, 0.95, 0.95), false)
	box(p, Vector3(-0.25, 0.465, -0.05), Vector3(0.28, 0.03, 0.2), Color(0.3, 0.5, 0.75), false)


static func tv_unit(p: Node3D, wood: Color) -> void:
	box(p, Vector3(0, 0.25, 0), Vector3(1.8, 0.5, 0.45), wood)
	box(p, Vector3(0, 0.25, 0.226), Vector3(1.7, 0.4, 0.01), wood.darkened(0.15), false)
	box(p, Vector3(0, 0.98, -0.05), Vector3(1.4, 0.8, 0.06), Color(0.05, 0.05, 0.07), true, false, 0.2)
	var screen := box(p, Vector3(0, 0.98, -0.015), Vector3(1.32, 0.72, 0.01), Color(0.15, 0.25, 0.4), false)
	screen.material_override = mat(Color(0.2, 0.35, 0.55), 0.15, 0.35)
	box(p, Vector3(0, 0.53, -0.05), Vector3(0.3, 0.06, 0.2), Color(0.1, 0.1, 0.12))


static func bookshelf(p: Node3D, wood: Color, height: float = 1.9) -> void:
	var w := 1.0
	var d := 0.35
	box(p, Vector3(0, height * 0.5, -d * 0.5 + 0.01), Vector3(w, height, 0.02), wood.darkened(0.15), false)
	for side in [-1.0, 1.0]:
		box(p, Vector3(side * w * 0.5, height * 0.5, 0), Vector3(0.04, height, d), wood)
	var shelves := 5
	var book_colors := [Color(0.8, 0.3, 0.3), Color(0.3, 0.5, 0.8), Color(0.9, 0.75, 0.3),
		Color(0.35, 0.65, 0.45), Color(0.6, 0.4, 0.7), Color(0.95, 0.9, 0.8)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in shelves:
		var y := 0.04 + i * (height - 0.08) / (shelves - 1)
		box(p, Vector3(0, y, 0), Vector3(w, 0.03, d), wood)
		if i == shelves - 1:
			continue
		var x := -w * 0.5 + 0.06
		while x < w * 0.5 - 0.12:
			var bw := rng.randf_range(0.03, 0.06)
			var bh := rng.randf_range(0.2, 0.3)
			box(p, Vector3(x + bw * 0.5, y + 0.015 + bh * 0.5, 0.02), Vector3(bw, bh, 0.22),
				book_colors[rng.randi() % book_colors.size()], false)
			x += bw + 0.005
			if rng.randf() < 0.12:
				x += 0.12
	# One shared collider for the books: a jelly can't fit between them anyway.
	var b := body(p)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, height, d)
	cs.shape = shape
	cs.position = Vector3(0, height * 0.5, 0)
	b.add_child(cs)


static func floor_lamp(p: Node3D, light_color: Color) -> void:
	cylinder(p, Vector3(0, 0.02, 0), 0.18, 0.04, Color(0.2, 0.2, 0.22))
	cylinder(p, Vector3(0, 0.8, 0), 0.02, 1.6, Color(0.25, 0.22, 0.2))
	cylinder(p, Vector3(0, 1.62, 0), 0.24, 0.3, light_color.lerp(Color.WHITE, 0.4), true, 0.15)
	light(p, Vector3(0, 1.5, 0), light_color, 1.2, 4.0)


static func plant(p: Node3D, big: bool = true) -> void:
	var s := 1.0 if big else 0.55
	cylinder(p, Vector3(0, 0.2 * s, 0), 0.2 * s, 0.4 * s, Color(0.85, 0.5, 0.35), true, 0.24 * s)
	var leaf := Color(0.25, 0.6, 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 if big else 11
	for i in 7:
		var a := TAU * i / 7.0
		var h := rng.randf_range(0.5, 1.1) * s
		sphere(p, Vector3(cos(a) * 0.17 * s, 0.4 * s + h * 0.5, sin(a) * 0.17 * s), 0.16 * s,
			leaf.lightened(rng.randf_range(0.0, 0.2)), false, Vector3(0.7, h / (0.32 * s) * 0.6, 0.7))
	cylinder(p, Vector3(0, 0.75 * s, 0), 0.22 * s, 0.7 * s, leaf, true)


static func rug(p: Node3D, size: Vector2, c: Color, circular: bool = false) -> void:
	if circular:
		cylinder(p, Vector3(0, 0.006, 0), size.x * 0.5, 0.012, c, false)
		cylinder(p, Vector3(0, 0.008, 0), size.x * 0.42, 0.012, c.lightened(0.15), false)
	else:
		box(p, Vector3(0, 0.006, 0), Vector3(size.x, 0.012, size.y), c, false)
		box(p, Vector3(0, 0.008, 0), Vector3(size.x - 0.2, 0.012, size.y - 0.2), c.lightened(0.12), false)


## A window on a wall: glowing "outside" panel, frame, sill and curtains.
## The node's +Z faces into the room.
static func window(p: Node3D, size: Vector2, sky: Color, curtains: Color) -> void:
	var glass := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	glass.mesh = qm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = sky
	glass.material_override = gm
	glass.position = Vector3(0, 0, 0.005)
	p.add_child(glass)
	var frame := Color(0.96, 0.95, 0.93)
	var t := 0.06
	box(p, Vector3(0, size.y * 0.5, 0.03), Vector3(size.x + t * 2, t, 0.06), frame, false)
	box(p, Vector3(0, -size.y * 0.5, 0.06), Vector3(size.x + 0.3, t, 0.18), frame, false)
	box(p, Vector3(0, 0, 0.03), Vector3(t * 0.6, size.y, 0.05), frame, false)
	box(p, Vector3(0, 0, 0.03), Vector3(size.x, t * 0.6, 0.05), frame, false)
	for side in [-1.0, 1.0]:
		box(p, Vector3(side * (size.x * 0.5 + t * 0.5), 0, 0.03), Vector3(t, size.y, 0.06), frame, false)
		box(p, Vector3(side * (size.x * 0.5 + 0.18), -0.1, 0.1), Vector3(0.32, size.y + 0.6, 0.05), curtains, false)
	var rod := cylinder(p, Vector3(0, size.y * 0.5 + 0.25, 0.12), 0.015, size.x + 1.0, Color(0.3, 0.3, 0.3), false)
	rod.rotation.z = PI / 2.0


static func picture(p: Node3D, size: Vector2, art: Color) -> void:
	box(p, Vector3(0, 0, 0.02), Vector3(size.x + 0.08, size.y + 0.08, 0.03), Color(0.2, 0.15, 0.12), false)
	box(p, Vector3(0, 0, 0.036), Vector3(size.x, size.y, 0.005), Color(0.97, 0.96, 0.92), false)
	sphere(p, Vector3(-size.x * 0.12, size.y * 0.05, 0.04), size.y * 0.22, art, false, Vector3(1, 1, 0.05))
	box(p, Vector3(size.x * 0.15, -size.y * 0.15, 0.04), Vector3(size.x * 0.4, size.y * 0.3, 0.005), art.lightened(0.35), false)


static func door(p: Node3D, c: Color) -> void:
	box(p, Vector3(0, 1.02, 0.02), Vector3(0.95, 2.04, 0.04), c, false)
	box(p, Vector3(0, 1.05, 0.01), Vector3(1.07, 2.12, 0.02), Color(0.96, 0.95, 0.93), false)
	sphere(p, Vector3(0.36, 1.0, 0.06), 0.035, Color(0.8, 0.7, 0.4), false)


static func ceiling_light(p: Node3D, light_color: Color, energy: float) -> void:
	cylinder(p, Vector3(0, -0.2, 0), 0.01, 0.4, Color(0.2, 0.2, 0.2), false)
	sphere(p, Vector3(0, -0.45, 0), 0.18, light_color.lerp(Color.WHITE, 0.6), false, Vector3(1, 0.7, 1), false, 1.5)
	light(p, Vector3(0, -0.6, 0), light_color, energy, 7.0)


# ------------------------------------------------------------------ bedroom

static func bed(p: Node3D, linen: Color, wood: Color) -> void:
	box(p, Vector3(0, 0.18, 0), Vector3(1.7, 0.3, 2.1), wood)
	box(p, Vector3(0, 0.6, -1.03), Vector3(1.8, 1.0, 0.08), wood.darkened(0.1))
	cushion(p, Vector3(0, 0.42, 0.02), Vector3(1.6, 0.22, 2.0), Color(0.97, 0.97, 0.98))  # mattress
	box(p, Vector3(0, 0.55, 0.4), Vector3(1.66, 0.06, 1.3), linen, false)                   # duvet
	for x in [-0.4, 0.4]:
		cushion(p, Vector3(x, 0.62, -0.75), Vector3(0.62, 0.16, 0.36), Color(1, 1, 1))


static func nightstand(p: Node3D, wood: Color, light_color: Color) -> void:
	box(p, Vector3(0, 0.27, 0), Vector3(0.5, 0.54, 0.42), wood)
	box(p, Vector3(0, 0.3, 0.211), Vector3(0.4, 0.15, 0.01), wood.darkened(0.15), false)
	cylinder(p, Vector3(0, 0.62, 0), 0.07, 0.16, Color(0.9, 0.85, 0.75), false)
	cylinder(p, Vector3(0, 0.78, 0), 0.16, 0.18, light_color.lerp(Color.WHITE, 0.5), false, 0.1)
	light(p, Vector3(0, 0.8, 0.1), light_color, 0.6, 2.5)


static func wardrobe(p: Node3D, wood: Color) -> void:
	box(p, Vector3(0, 1.05, 0), Vector3(1.4, 2.1, 0.6), wood)
	box(p, Vector3(0, 1.05, 0.301), Vector3(0.01, 2.0, 0.01), wood.darkened(0.3), false)
	for x in [-0.08, 0.08]:
		box(p, Vector3(x, 1.1, 0.32), Vector3(0.02, 0.25, 0.03), Color(0.75, 0.7, 0.6), false)


static func desk(p: Node3D, wood: Color) -> void:
	box(p, Vector3(0, 0.74, 0), Vector3(1.3, 0.04, 0.65), wood, true, false, 0.4)
	for x in [-0.6, 0.6]:
		box(p, Vector3(x, 0.36, 0), Vector3(0.04, 0.72, 0.6), wood.darkened(0.1))
	box(p, Vector3(-0.2, 0.95, -0.15), Vector3(0.5, 0.35, 0.03), Color(0.08, 0.08, 0.1), false)
	chair(piece(p, Vector3(0, 0, 0.6), 180.0), wood.darkened(0.2))


static func chair(p: Node3D, c: Color) -> void:
	box(p, Vector3(0, 0.45, 0), Vector3(0.45, 0.05, 0.45), c)
	box(p, Vector3(0, 0.75, -0.2), Vector3(0.45, 0.55, 0.04), c)
	for x in [-0.19, 0.19]:
		for z in [-0.19, 0.19]:
			box(p, Vector3(x, 0.22, z), Vector3(0.04, 0.45, 0.04), c.darkened(0.15), false)


# ------------------------------------------------------------------ kitchen

static func counter_run(p: Node3D, length: float, cabinet: Color, top: Color, with_sink: bool) -> void:
	box(p, Vector3(0, 0.44, 0), Vector3(length, 0.88, 0.6), cabinet)
	box(p, Vector3(0, 0.9, 0.01), Vector3(length + 0.02, 0.04, 0.64), top, true, false, 0.3)
	box(p, Vector3(0, 0.05, 0.27), Vector3(length, 0.1, 0.06), cabinet.darkened(0.3), false)
	var doors := int(length / 0.6)
	for i in doors:
		var x := -length * 0.5 + 0.3 + i * (length - 0.6) / maxf(doors - 1, 1)
		box(p, Vector3(x, 0.5, 0.301), Vector3(0.55, 0.7, 0.01), cabinet.lightened(0.05), false)
		box(p, Vector3(x + 0.2, 0.75, 0.315), Vector3(0.02, 0.12, 0.02), Color(0.7, 0.7, 0.72), false)
	if with_sink:
		box(p, Vector3(0.3, 0.915, 0.02), Vector3(0.6, 0.02, 0.42), Color(0.75, 0.77, 0.8), false, false, 0.2)
		cylinder(p, Vector3(0.3, 1.05, -0.2), 0.015, 0.28, Color(0.8, 0.8, 0.82), false)
	# Wall cabinets.
	box(p, Vector3(0, 1.85, -0.12), Vector3(length, 0.7, 0.35), cabinet)
	# Hob.
	box(p, Vector3(-length * 0.3, 0.925, 0.0), Vector3(0.6, 0.01, 0.5), Color(0.08, 0.08, 0.1), false, false, 0.15)


static func fridge(p: Node3D) -> void:
	box(p, Vector3(0, 0.95, 0), Vector3(0.75, 1.9, 0.7), Color(0.92, 0.93, 0.95), true, false, 0.3)
	box(p, Vector3(0, 1.28, 0.351), Vector3(0.74, 0.01, 0.01), Color(0.7, 0.7, 0.72), false)
	box(p, Vector3(0.3, 1.0, 0.37), Vector3(0.03, 0.4, 0.03), Color(0.7, 0.7, 0.72), false)


static func dining_table(p: Node3D, wood: Color, chair_color: Color) -> void:
	box(p, Vector3(0, 0.75, 0), Vector3(1.4, 0.05, 0.85), wood, true, false, 0.35)
	for x in [-0.62, 0.62]:
		for z in [-0.35, 0.35]:
			box(p, Vector3(x, 0.37, z), Vector3(0.06, 0.73, 0.06), wood.darkened(0.15))
	for x in [-0.35, 0.35]:
		chair(piece(p, Vector3(x, 0, 0.65), 180.0), chair_color)
		chair(piece(p, Vector3(x, 0, -0.65)), chair_color)
	sphere(p, Vector3(0, 0.83, 0), 0.12, Color(0.95, 0.6, 0.2), false, Vector3(1.4, 0.5, 1.4))


# ------------------------------------------------------------------ playroom

static func toy_blocks(p: Node3D) -> void:
	var colors := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(0.98, 0.8, 0.25), Color(0.35, 0.8, 0.45)]
	for i in 4:
		box(p, Vector3(i * 0.3 - 0.45, 0.13, 0), Vector3(0.26, 0.26, 0.26), colors[i])
	box(p, Vector3(-0.3, 0.39, 0), Vector3(0.26, 0.26, 0.26), colors[2])
	box(p, Vector3(0.0, 0.39, 0), Vector3(0.26, 0.26, 0.26), colors[0])
	box(p, Vector3(-0.15, 0.65, 0), Vector3(0.26, 0.26, 0.26), colors[1])


static func beanbag(p: Node3D, c: Color) -> void:
	sphere(p, Vector3(0, 0.3, 0), 0.5, c, true, Vector3(1.0, 0.6, 1.0), true)
	sphere(p, Vector3(0, 0.55, -0.25), 0.35, c.lightened(0.05), false, Vector3(1.0, 0.8, 0.6))


static func toy_box(p: Node3D) -> void:
	box(p, Vector3(0, 0.25, 0), Vector3(0.9, 0.5, 0.5), Color(0.95, 0.55, 0.3))
	var lid := box(p, Vector3(0, 0.52, -0.22), Vector3(0.92, 0.04, 0.5), Color(0.95, 0.75, 0.3), false)
	lid.rotation.x = -0.9
	sphere(p, Vector3(0.2, 0.55, 0.05), 0.1, Color(0.4, 0.8, 1.0), false)


static func slide(p: Node3D) -> void:
	var c := Color(0.95, 0.5, 0.75)
	box(p, Vector3(-0.6, 0.45, 0), Vector3(0.5, 0.9, 0.55), Color(0.4, 0.7, 0.95))
	# Build the ramp inside a rotated pivot so mesh and collider tilt together.
	var ramp := piece(p, Vector3(0.05, 0.47, 0))
	ramp.rotation.z = -0.65
	box(ramp, Vector3.ZERO, Vector3(1.0, 0.05, 0.5), c)


static func toy_ball(p: Node3D, c: Color, radius: float = 0.16) -> RigidBody3D:
	var ball := RigidBody3D.new()
	ball.collision_layer = 4
	ball.collision_mask = 1 | 2 | 4
	ball.mass = 0.3
	ball.physics_material_override = _phys(0.7, 0.5)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = mat(c, 0.4)
	ball.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	cs.shape = shape
	ball.add_child(cs)
	ball.add_to_group("props")
	p.add_child(ball)
	return ball
