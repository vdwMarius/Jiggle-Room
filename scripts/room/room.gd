class_name Room
extends Node3D
## The customisable room: surfaces, invisible walls, lighting, props, wall modes.
##
## The room is an axis-aligned box: floor at y = 0, centred on x = 0 and z = 0.
## The front face (toward the camera) has a collider but no visual.

signal rebuilt

const SURFACE_SHADER := preload("res://shaders/room_surface.gdshader")
const WALL_THICKNESS := 2.0

var theme: RoomTheme
var dimensions := Vector3(3.0, 4.2, 2.4)

var _walls: Array[StaticBody3D] = []
var _visuals := {}   # name -> MeshInstance3D
var _wall_material := PhysicsMaterial.new()
var _floor_material := PhysicsMaterial.new()
var _props_root: Node3D
var _sun: DirectionalLight3D
var _lamp: OmniLight3D
var _env: WorldEnvironment


func _ready() -> void:
	_build_static()


func _build_static() -> void:
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 2.0
	_sun.directional_shadow_max_distance = 20.0
	_sun.rotation_degrees = Vector3(-62, 28, 0)
	add_child(_sun)

	_lamp = OmniLight3D.new()
	_lamp.omni_range = 8.0
	_lamp.light_energy = 0.8
	add_child(_lamp)

	_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = false
	_env.environment = env
	add_child(_env)

	for n in ["floor", "ceiling", "back", "left", "right", "front"]:
		var body := StaticBody3D.new()
		body.name = n.capitalize() + "Wall"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("room_walls")
		body.physics_material_override = _floor_material if n == "floor" else _wall_material
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		body.add_child(cs)
		add_child(body)
		_walls.append(body)
		if n != "front":
			var mi := MeshInstance3D.new()
			mi.mesh = QuadMesh.new()
			var mat := ShaderMaterial.new()
			mat.shader = SURFACE_SHADER
			mi.material_override = mat
			add_child(mi)
			_visuals[n] = mi

	_props_root = Node3D.new()
	_props_root.name = "Props"
	add_child(_props_root)


## Apply theme + player overrides (GameState.room dictionary).
func apply_settings(settings: Dictionary, new_theme: RoomTheme) -> void:
	theme = new_theme
	_apply_surfaces(settings)
	_apply_lighting(settings)
	_apply_modes(settings)
	_rebuild_props(settings.get("props", true))


func set_dimensions(dims: Vector3) -> void:
	dimensions = dims
	var w := dims.x
	var h := dims.y
	var d := dims.z
	var t := WALL_THICKNESS
	# name -> [box size, box centre, visual size, visual transform]
	var layout := {
		"floor": [Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, -t / 2, 0)],
		"ceiling": [Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, h + t / 2, 0)],
		"back": [Vector3(w + 2 * t, h + 2 * t, t), Vector3(0, h / 2, -d / 2 - t / 2)],
		"front": [Vector3(w + 2 * t, h + 2 * t, t), Vector3(0, h / 2, d / 2 + t / 2)],
		"left": [Vector3(t, h + 2 * t, d + 2 * t), Vector3(-w / 2 - t / 2, h / 2, 0)],
		"right": [Vector3(t, h + 2 * t, d + 2 * t), Vector3(w / 2 + t / 2, h / 2, 0)],
	}
	for body in _walls:
		var key := String(body.name).trim_suffix("Wall").to_lower()
		var entry: Array = layout[key]
		var cs := body.get_child(0) as CollisionShape3D
		(cs.shape as BoxShape3D).size = entry[0]
		body.position = entry[1]

	# Visual quads (QuadMesh faces +Z by default).
	_place_quad("floor", Vector2(w, d), Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, 0)))
	_place_quad("ceiling", Vector2(w, d), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, h, 0)))
	_place_quad("back", Vector2(w, h), Transform3D(Basis(), Vector3(0, h / 2, -d / 2)))
	_place_quad("left", Vector2(d, h), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-w / 2, h / 2, 0)))
	_place_quad("right", Vector2(d, h), Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(w / 2, h / 2, 0)))

	_lamp.position = Vector3(0, h * 0.85, d * 0.1)
	if theme:
		_rebuild_props(GameState.room.get("props", true))
	rebuilt.emit()


func _place_quad(key: String, size2: Vector2, xform: Transform3D) -> void:
	var mi: MeshInstance3D = _visuals[key]
	(mi.mesh as QuadMesh).size = size2
	mi.transform = xform


## True if `p` (world) is inside the room, shrunk by `margin`.
func contains(p: Vector3, margin: float = 0.0) -> bool:
	var half := dimensions * 0.5
	return absf(p.x) < half.x - margin and p.y > margin and p.y < dimensions.y - margin \
		and absf(p.z) < half.z - margin


func clamp_inside(p: Vector3, margin: float) -> Vector3:
	var half := dimensions * 0.5
	return Vector3(
		clampf(p.x, -half.x + margin, half.x - margin),
		clampf(p.y, margin, dimensions.y - margin),
		clampf(p.z, -half.z + margin, half.z - margin))


# ------------------------------------------------------------------ looks

func _color_or(settings: Dictionary, key: String, fallback: Color) -> Color:
	var v: String = settings.get(key, "")
	return Color.html(v) if not v.is_empty() and Color.html_is_valid(v) else fallback


func _apply_surfaces(settings: Dictionary) -> void:
	var wall := _color_or(settings, "wall_color", theme.wall_color)
	# A custom colour replaces the theme's pair; the pattern uses a darker shade.
	var wall_b := theme.wall_color_b if settings.get("wall_color", "") == "" else wall.darkened(0.12)
	var floor_c := _color_or(settings, "floor_color", theme.floor_color)
	var floor_b := theme.floor_color_b if settings.get("floor_color", "") == "" else floor_c.darkened(0.15)
	var ceil_c := _color_or(settings, "ceiling_color", theme.ceiling_color)
	for key in _visuals:
		var mat: ShaderMaterial = _visuals[key].material_override
		var a: Color
		var b: Color
		var pattern: int
		var tex: Texture2D
		match key:
			"floor":
				a = floor_c
				b = floor_b
				pattern = theme.floor_pattern
				tex = theme.floor_texture
			"ceiling":
				a = ceil_c
				b = ceil_c.darkened(0.08)
				pattern = RoomTheme.Pattern.PLAIN if theme.wall_pattern != RoomTheme.Pattern.STARS else RoomTheme.Pattern.STARS
				tex = null
			_:
				a = wall
				b = wall_b
				pattern = theme.wall_pattern
				tex = theme.wall_texture
		mat.set_shader_parameter("color_a", a)
		mat.set_shader_parameter("color_b", b)
		mat.set_shader_parameter("pattern", pattern)
		mat.set_shader_parameter("pattern_scale", theme.pattern_scale)
		mat.set_shader_parameter("use_texture", tex != null)
		if tex:
			mat.set_shader_parameter("tex", tex)
		mat.set_shader_parameter("roughness_value", 0.35 if key == "floor" and pattern == RoomTheme.Pattern.PLANKS else 0.85)


func _apply_lighting(settings: Dictionary) -> void:
	var light_c := _color_or(settings, "light_color", theme.light_color)
	var energy := float(settings.get("light_energy", 1.0))
	_sun.light_color = light_c
	_sun.light_energy = theme.light_energy * energy
	_lamp.light_color = light_c
	_lamp.light_energy = 0.8 * energy
	var env := _env.environment
	env.background_color = theme.wall_color.darkened(0.6)
	env.ambient_light_color = theme.ambient_color.lerp(light_c, 0.3)
	env.ambient_light_energy = theme.ambient_energy * lerpf(0.5, 1.0, clampf(energy, 0.0, 1.0))
	env.glow_enabled = theme.glow or energy < 0.4
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05


## Speeds up/slows the animated room patterns along with slow-motion.
func set_time_scale(s: float) -> void:
	for key in _visuals:
		(_visuals[key].material_override as ShaderMaterial).set_shader_parameter("time_scale", s)


func _apply_modes(settings: Dictionary) -> void:
	var mode: String = settings.get("wall_mode", "normal")
	_wall_material.bounce = 0.65 if mode == "bouncy" else 0.0
	_wall_material.friction = 0.9 if mode == "sticky" else 0.5
	_floor_material.bounce = 0.65 if mode == "bouncy" else 0.0
	_floor_material.friction = 0.01 if settings.get("slippery_floor", false) else 0.7
	for j in get_tree().get_nodes_in_group("jellies"):
		(j as JellyObject).sticky_walls = mode == "sticky"


func is_sticky() -> bool:
	return GameState.room.get("wall_mode", "normal") == "sticky"


# ------------------------------------------------------------------ props

func _rebuild_props(enabled: bool) -> void:
	for c in _props_root.get_children():
		c.queue_free()
	if not enabled or theme == null:
		return
	var w := dimensions.x
	var d := dimensions.z
	var h := dimensions.y
	match theme.props:
		RoomTheme.Props.LOUNGE:
			var sofa := Color(0.55, 0.3, 0.35)
			_box(Vector3(-w * 0.18, 0.18, -d / 2 + 0.3), Vector3(w * 0.5, 0.36, 0.6), sofa)
			_box(Vector3(-w * 0.18, 0.5, -d / 2 + 0.08), Vector3(w * 0.5, 0.6, 0.16), sofa.darkened(0.1))
			_box(Vector3(-w * 0.18 - w * 0.25, 0.3, -d / 2 + 0.3), Vector3(0.14, 0.6, 0.6), sofa.darkened(0.15))
			_box(Vector3(-w * 0.18 + w * 0.25, 0.3, -d / 2 + 0.3), Vector3(0.14, 0.6, 0.6), sofa.darkened(0.15))
			_cylinder(Vector3(w * 0.36, 0.7, -d / 2 + 0.25), 0.03, 1.4, Color(0.3, 0.25, 0.2))
			_sphere(Vector3(w * 0.36, 1.45, -d / 2 + 0.25), 0.2, Color(1.0, 0.9, 0.6), 1.2)
			_cylinder(Vector3(0, 0.005, 0.1), w * 0.3, 0.01, Color(0.9, 0.75, 0.55), false)
		RoomTheme.Props.AQUARIUM:
			_sphere(Vector3(-w * 0.3, 0.05, -d / 2 + 0.4), 0.35, Color(0.45, 0.45, 0.5), 0.0, Vector3(1.3, 0.6, 1.0))
			_sphere(Vector3(w * 0.25, 0.0, -d / 2 + 0.5), 0.3, Color(0.5, 0.48, 0.42), 0.0, Vector3(1.0, 0.8, 1.2))
			for i in 4:
				var x := lerpf(-w * 0.4, w * 0.4, i / 3.0)
				_cylinder(Vector3(x, 0.4 + 0.15 * (i % 2), -d / 2 + 0.15), 0.05, 0.8 + 0.3 * (i % 2), Color(0.2, 0.6, 0.35))
			_box(Vector3(w * 0.05, 0.15, -d / 2 + 0.35), Vector3(0.5, 0.3, 0.32), Color(0.6, 0.4, 0.15))
		RoomTheme.Props.SPACE:
			_box(Vector3(-w * 0.32, 0.25, -d / 2 + 0.35), Vector3(0.5, 0.5, 0.5), Color(0.75, 0.78, 0.82))
			_box(Vector3(-w * 0.32, 0.65, -d / 2 + 0.35), Vector3(0.3, 0.3, 0.3), Color(0.9, 0.55, 0.2))
			_cylinder(Vector3(w * 0.35, h * 0.5, -d / 2 + 0.15), 0.12, h, Color(0.55, 0.6, 0.7))
			_sphere(Vector3(w * 0.1, h * 0.72, -d / 2 + 0.45), 0.28, Color(0.6, 0.4, 0.9), 0.4)
		RoomTheme.Props.PLAYROOM:
			var block_colors := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(0.98, 0.8, 0.25), Color(0.35, 0.8, 0.45)]
			for i in 4:
				_box(Vector3(-w * 0.35 + i * 0.32, 0.14, -d / 2 + 0.3), Vector3(0.28, 0.28, 0.28), block_colors[i])
			_box(Vector3(-w * 0.35 + 0.48, 0.42, -d / 2 + 0.3), Vector3(0.28, 0.28, 0.28), block_colors[2])
			var ramp := _box(Vector3(w * 0.28, 0.2, -d / 2 + 0.5), Vector3(0.9, 0.06, 0.7), Color(0.95, 0.6, 0.8))
			ramp.rotation = Vector3(0, 0, 0.35)
			_toy_ball(Vector3(w * 0.1, 1.2, 0.0))


func _prop_body(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = pos
	body.add_to_group("props")
	_props_root.add_child(body)
	return body


func _std_mat(c: Color, emission: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _box(pos: Vector3, size3: Vector3, c: Color) -> StaticBody3D:
	var body := _prop_body(pos)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size3
	mi.mesh = bm
	mi.material_override = _std_mat(c)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size3
	cs.shape = shape
	body.add_child(cs)
	return body


func _cylinder(pos: Vector3, radius: float, height: float, c: Color, collide: bool = true) -> StaticBody3D:
	var body := _prop_body(pos)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _std_mat(c)
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		cs.shape = shape
		body.add_child(cs)
	return body


func _sphere(pos: Vector3, radius: float, c: Color, emission: float = 0.0, squash := Vector3.ONE) -> StaticBody3D:
	var body := _prop_body(pos)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.scale = squash
	mi.material_override = _std_mat(c, emission)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	if squash == Vector3.ONE:
		var shape := SphereShape3D.new()
		shape.radius = radius
		cs.shape = shape
	else:
		# Non-uniformly scaled collision isn't supported; use a matching hull.
		var pts := PackedVector3Array()
		for v in sm.get_mesh_arrays()[Mesh.ARRAY_VERTEX]:
			pts.append(v * squash)
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		cs.shape = hull
	body.add_child(cs)
	if emission > 0.0:
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = emission * 0.6
		l.omni_range = 2.0
		body.add_child(l)
	return body


func _toy_ball(pos: Vector3) -> void:
	var ball := RigidBody3D.new()
	ball.collision_layer = 4
	ball.collision_mask = 1 | 2 | 4
	ball.mass = 0.3
	ball.position = pos
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.7
	ball.physics_material_override = pm
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	mi.mesh = sm
	mi.material_override = _std_mat(Color(1.0, 0.45, 0.2))
	ball.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	cs.shape = shape
	ball.add_child(cs)
	ball.add_to_group("props")
	_props_root.add_child(ball)
