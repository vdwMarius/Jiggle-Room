class_name Room
extends Node3D
## A furnished room the jellies live in: walls, floor, ceiling (all visible,
## the camera is inside), lighting, furniture with colliders and wall modes.
##
## The room is an axis-aligned box: floor at y = 0, centred on x = 0 and z = 0.
## Back wall at -z, front wall at +z, left -x, right +x.

signal rebuilt

const SURFACE_SHADER := preload("res://shaders/room_surface.gdshader")
const WALL_THICKNESS := 2.0

var theme: RoomTheme
var dimensions := Vector3(6.0, 2.8, 5.0)

var _walls: Array[StaticBody3D] = []
var _visuals := {}   # name -> MeshInstance3D
var _wall_material := PhysicsMaterial.new()
var _floor_material := PhysicsMaterial.new()
var _props_root: Node3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _built_key := ""


func _ready() -> void:
	_build_static()


func _build_static() -> void:
	# Soft "daylight through the windows" key light; the ceiling and walls
	# don't cast shadows, so it reaches the furniture and jellies.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.shadow_blur = 2.0
	_sun.directional_shadow_max_distance = 14.0
	_sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(_sun)

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
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = SURFACE_SHADER
		mi.material_override = mat
		add_child(mi)
		_visuals[n] = mi

	_props_root = Node3D.new()
	_props_root.name = "Furniture"
	add_child(_props_root)


## Apply theme + player overrides (GameState.room dictionary).
func apply_settings(settings: Dictionary, new_theme: RoomTheme) -> void:
	theme = new_theme
	_apply_surfaces(settings)
	_apply_lighting(settings)
	_apply_modes(settings)
	# Furniture only rebuilds when something that affects it changed.
	var key := "%s|%s|%s|%s" % [theme.id, dimensions, settings.get("props", true), settings.get("light_color", "")]
	if key != _built_key:
		_built_key = key
		_rebuild_furniture(settings)


func set_dimensions(dims: Vector3) -> void:
	dimensions = dims
	var w := dims.x
	var h := dims.y
	var d := dims.z
	var t := WALL_THICKNESS
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

	# Visual quads face into the room (QuadMesh faces +Z by default).
	_place_quad("floor", Vector2(w, d), Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, 0)))
	_place_quad("ceiling", Vector2(w, d), Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, h, 0)))
	_place_quad("back", Vector2(w, h), Transform3D(Basis(), Vector3(0, h / 2, -d / 2)))
	_place_quad("front", Vector2(w, h), Transform3D(Basis(Vector3.UP, PI), Vector3(0, h / 2, d / 2)))
	_place_quad("left", Vector2(d, h), Transform3D(Basis(Vector3.UP, PI / 2), Vector3(-w / 2, h / 2, 0)))
	_place_quad("right", Vector2(d, h), Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(w / 2, h / 2, 0)))
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
		var shiny: bool = key == "floor" and (pattern == RoomTheme.Pattern.PLANKS or pattern == RoomTheme.Pattern.TILES)
		mat.set_shader_parameter("roughness_value", 0.35 if shiny else 0.88)


func _light_color(settings: Dictionary) -> Color:
	return _color_or(settings, "light_color", theme.light_color)


func _apply_lighting(settings: Dictionary) -> void:
	var light_c := _light_color(settings)
	var energy := float(settings.get("light_energy", 1.0))
	_sun.light_color = theme.sky_color.lerp(light_c, 0.6)
	_sun.light_energy = theme.light_energy * energy * 0.7
	for l in get_tree().get_nodes_in_group("room_lamps"):
		var lamp := l as OmniLight3D
		lamp.light_energy = lamp.get_meta("base_energy", 1.0) * energy
	var env := _env.environment
	env.background_color = theme.wall_color.darkened(0.6)
	env.ambient_light_color = theme.ambient_color.lerp(light_c, 0.3)
	env.ambient_light_energy = theme.ambient_energy * lerpf(0.4, 1.0, clampf(energy, 0.0, 1.0))
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


# ------------------------------------------------------------------ furniture

func _rebuild_furniture(settings: Dictionary) -> void:
	for c in _props_root.get_children():
		_props_root.remove_child(c)
		c.queue_free()
	if theme == null:
		return
	var w := dimensions.x
	var d := dimensions.z
	var h := dimensions.y
	var back := -d * 0.5
	var front := d * 0.5
	var left := -w * 0.5
	var right := w * 0.5
	var light_c := _light_color(settings)
	var root := _props_root

	# Things every interior gets: skirting boards and a ceiling light.
	if theme.layout <= RoomTheme.Layout.PLAYROOM:
		var trim := Color(0.97, 0.96, 0.94)
		Furniture.box(root, Vector3(0, 0.05, back + 0.01), Vector3(w, 0.1, 0.02), trim, false)
		Furniture.box(root, Vector3(0, 0.05, front - 0.01), Vector3(w, 0.1, 0.02), trim, false)
		Furniture.box(root, Vector3(left + 0.01, 0.05, 0), Vector3(0.02, 0.1, d), trim, false)
		Furniture.box(root, Vector3(right - 0.01, 0.05, 0), Vector3(0.02, 0.1, d), trim, false)
		_lamp(Furniture.piece(root, Vector3(0, h, 0)), light_c, 1.4)

	if not settings.get("props", true):
		_tag_lamps()
		return

	match theme.layout:
		RoomTheme.Layout.LIVING_ROOM:
			Furniture.rug(Furniture.piece(root, Vector3(0, 0, -0.3)), Vector2(3.0, 2.1), theme.accent_color)
			Furniture.sofa(Furniture.piece(root, Vector3(0, 0, back + 0.5)), theme.fabric_color, 2.4)
			Furniture.coffee_table(Furniture.piece(root, Vector3(0, 0, back + 1.75)), theme.wood_color)
			Furniture.armchair(Furniture.piece(root, Vector3(right - 0.7, 0, back + 1.9), -70.0), theme.fabric_color.lerp(theme.accent_color, 0.4))
			Furniture.tv_unit(Furniture.piece(root, Vector3(left + 0.25, 0, -0.1), 90.0), theme.wood_color)
			Furniture.bookshelf(Furniture.piece(root, Vector3(right - 0.2, 0, back + 0.55), -90.0), theme.wood_color)
			Furniture.floor_lamp(Furniture.piece(root, Vector3(left + 0.45, 0, back + 0.4)), light_c)
			Furniture.plant(Furniture.piece(root, Vector3(right - 0.45, 0, front - 0.5)))
			Furniture.plant(Furniture.piece(root, Vector3(left + 0.4, 0, front - 0.45)), false)
			Furniture.window(Furniture.piece(root, Vector3(0, 1.65, back + 0.001)), Vector2(1.8, 1.1), theme.sky_color, theme.accent_color.darkened(0.1))
			Furniture.picture(Furniture.piece(root, Vector3(left + 0.001, 1.75, back + 1.2), 90.0), Vector2(0.6, 0.45), theme.accent_color)
			Furniture.picture(Furniture.piece(root, Vector3(right - 0.001, 1.6, 0.6), -90.0), Vector2(0.5, 0.7), theme.fabric_color)
			Furniture.door(Furniture.piece(root, Vector3(right - 1.0, 0, front - 0.001), 180.0), theme.wood_color.lightened(0.2))
		RoomTheme.Layout.BEDROOM:
			Furniture.rug(Furniture.piece(root, Vector3(0, 0, -0.1)), Vector2(2.8, 2.0), theme.accent_color)
			Furniture.bed(Furniture.piece(root, Vector3(0, 0, back + 1.12)), theme.fabric_color, theme.wood_color)
			Furniture.nightstand(Furniture.piece(root, Vector3(-1.25, 0, back + 0.3)), theme.wood_color, light_c)
			Furniture.nightstand(Furniture.piece(root, Vector3(1.25, 0, back + 0.3)), theme.wood_color, light_c)
			Furniture.wardrobe(Furniture.piece(root, Vector3(left + 0.32, 0, back + 1.0), 90.0), theme.wood_color)
			Furniture.desk(Furniture.piece(root, Vector3(right - 0.35, 0, front - 1.2), -90.0), theme.wood_color)
			Furniture.beanbag(Furniture.piece(root, Vector3(left + 0.8, 0, front - 0.8)), theme.accent_color)
			Furniture.plant(Furniture.piece(root, Vector3(right - 0.4, 0, back + 0.4)), false)
			Furniture.window(Furniture.piece(root, Vector3(right - 0.001, 1.55, back + 1.4), -90.0), Vector2(1.2, 1.1), theme.sky_color, theme.fabric_color.lightened(0.3))
			Furniture.picture(Furniture.piece(root, Vector3(0, 1.85, back + 0.001)), Vector2(0.9, 0.5), theme.accent_color)
			Furniture.door(Furniture.piece(root, Vector3(0.6, 0, front - 0.001), 180.0), theme.wood_color.lightened(0.25))
		RoomTheme.Layout.KITCHEN:
			Furniture.counter_run(Furniture.piece(root, Vector3(-0.4, 0, back + 0.3)), minf(w - 1.6, 3.6), theme.fabric_color, theme.accent_color.lightened(0.5), true)
			Furniture.fridge(Furniture.piece(root, Vector3(right - 0.45, 0, back + 0.38)))
			Furniture.dining_table(Furniture.piece(root, Vector3(0.2, 0, 0.6)), theme.wood_color, theme.fabric_color.lightened(0.2))
			Furniture.plant(Furniture.piece(root, Vector3(left + 0.4, 0, front - 0.45)))
			Furniture.window(Furniture.piece(root, Vector3(left + 0.001, 1.5, 0.3), 90.0), Vector2(1.3, 1.0), theme.sky_color, theme.accent_color)
			Furniture.picture(Furniture.piece(root, Vector3(right - 0.001, 1.6, 0.8), -90.0), Vector2(0.5, 0.5), theme.accent_color)
			Furniture.door(Furniture.piece(root, Vector3(-1.2, 0, front - 0.001), 180.0), theme.wood_color)
			var pendant := Furniture.piece(root, Vector3(0.2, h, 0.6))
			_lamp(pendant, light_c, 0.8)
		RoomTheme.Layout.PLAYROOM:
			Furniture.rug(Furniture.piece(root, Vector3(0, 0, 0)), Vector2(2.6, 2.6), theme.accent_color, true)
			Furniture.toy_blocks(Furniture.piece(root, Vector3(left + 1.0, 0, back + 0.5)))
			Furniture.beanbag(Furniture.piece(root, Vector3(right - 0.8, 0, back + 0.8)), theme.fabric_color)
			Furniture.beanbag(Furniture.piece(root, Vector3(right - 0.7, 0, front - 1.0)), theme.accent_color)
			Furniture.toy_box(Furniture.piece(root, Vector3(0.6, 0, back + 0.35)))
			Furniture.slide(Furniture.piece(root, Vector3(left + 0.9, 0, front - 1.2), 90.0))
			Furniture.bookshelf(Furniture.piece(root, Vector3(-0.6, 0, back + 0.2)), theme.wood_color, 1.1)
			Furniture.window(Furniture.piece(root, Vector3(right - 0.001, 1.5, 0.0), -90.0), Vector2(1.4, 1.0), theme.sky_color, theme.accent_color)
			Furniture.picture(Furniture.piece(root, Vector3(left + 0.001, 1.6, 0.0), 90.0), Vector2(0.7, 0.5), theme.fabric_color)
			var ball := Furniture.toy_ball(root, Color(1.0, 0.45, 0.2), 0.18)
			ball.position = Vector3(0.3, 1.0, 0.3)
			var ball2 := Furniture.toy_ball(root, Color(0.35, 0.7, 1.0), 0.12)
			ball2.position = Vector3(-0.5, 1.2, 0.5)
		RoomTheme.Layout.AQUARIUM:
			Furniture.sphere(root, Vector3(left + 1.0, 0.05, back + 0.8), 0.6, Color(0.45, 0.45, 0.5), true, Vector3(1.3, 0.6, 1.0))
			Furniture.sphere(root, Vector3(right - 1.2, 0.0, back + 1.0), 0.5, Color(0.5, 0.48, 0.42), true, Vector3(1.0, 0.8, 1.2))
			Furniture.sphere(root, Vector3(0.8, 0.0, front - 1.0), 0.35, Color(0.55, 0.5, 0.45), true, Vector3(1.2, 0.6, 1.0))
			for i in 7:
				var x := lerpf(left + 0.5, right - 0.5, i / 6.0)
				var tall := 1.0 + 0.6 * float(i % 3)
				Furniture.cylinder(root, Vector3(x, tall * 0.5, back + 0.25 + 0.15 * float(i % 2)), 0.06, tall, Color(0.2, 0.6, 0.35))
			Furniture.box(root, Vector3(0, 0.2, back + 0.6), Vector3(0.8, 0.4, 0.5), Color(0.6, 0.4, 0.15))
			Furniture.sphere(root, Vector3(0, 0.45, back + 0.6), 0.12, Color(1.0, 0.85, 0.3), false, Vector3.ONE, false, 1.5)
			_lamp(Furniture.piece(root, Vector3(0, h, 0)), light_c, 1.0)
		RoomTheme.Layout.SPACE:
			Furniture.box(root, Vector3(left + 0.8, 0.35, back + 0.6), Vector3(0.7, 0.7, 0.7), Color(0.75, 0.78, 0.82))
			Furniture.box(root, Vector3(left + 0.8, 0.9, back + 0.6), Vector3(0.4, 0.4, 0.4), Color(0.9, 0.55, 0.2))
			Furniture.box(root, Vector3(left + 1.6, 0.3, back + 0.5), Vector3(0.6, 0.6, 0.6), Color(0.7, 0.72, 0.78))
			Furniture.cylinder(root, Vector3(right - 0.4, h * 0.5, back + 0.3), 0.15, h, Color(0.55, 0.6, 0.7))
			Furniture.cylinder(root, Vector3(right - 0.9, h * 0.5, back + 0.3), 0.1, h, Color(0.5, 0.55, 0.65))
			Furniture.box(root, Vector3(0.4, 0.5, back + 0.35), Vector3(1.6, 1.0, 0.5), Color(0.3, 0.32, 0.4))
			var console := Furniture.box(root, Vector3(0.4, 1.02, back + 0.3), Vector3(1.4, 0.04, 0.35), Color(0.2, 0.9, 0.8), false)
			console.material_override = Furniture.mat(Color(0.2, 0.9, 0.8), 0.3, 1.2)
			Furniture.sphere(root, Vector3(0.5, h * 0.62, 0.0), 0.35, Color(0.6, 0.4, 0.9), true, Vector3.ONE, true, 0.4)
			Furniture.window(Furniture.piece(root, Vector3(0, 1.5, back + 0.001)), Vector2(2.4, 1.0), theme.sky_color, Color(0.3, 0.32, 0.4))
			_lamp(Furniture.piece(root, Vector3(0, h, 0)), light_c, 0.9)
	_tag_lamps()


func _lamp(at: Node3D, c: Color, energy: float) -> void:
	Furniture.ceiling_light(at, c, energy)


## Remember every furniture light's design energy so the brightness slider
## can scale them all.
func _tag_lamps() -> void:
	var stack: Array[Node] = [_props_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is OmniLight3D:
			n.add_to_group("room_lamps")
			if not n.has_meta("base_energy"):
				n.set_meta("base_energy", (n as OmniLight3D).light_energy)
		stack.append_array(n.get_children())
	_apply_lighting(GameState.room)
