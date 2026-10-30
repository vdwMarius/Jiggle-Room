extends Node3D
## Root of the game. Wires the room, jellies, input, camera, photo mode and HUD.

const JELLY_SCENE := preload("res://scenes/jelly_object.tscn")
const MAX_JELLIES := 8
const BASE_ROOM_HEIGHT := 3.6
const BASE_ROOM_DEPTH := 2.2
const SLOW_MO := 0.25
const MERGE_MAX_RADIUS := 1.1

var room: Room
var camera: CameraRig
var touch: TouchController
var motion: MotionController
var photo: PhotoMode
var hud: Hud
var merge_mode := false
var selected: JellyObject

var _merging := false


func _ready() -> void:
	room = Room.new()
	room.name = "Room"
	add_child(room)

	camera = CameraRig.new()
	camera.room = room
	add_child(camera)
	camera.make_current()

	motion = MotionController.new()
	motion.camera = camera
	motion.mode_changed.connect(func(m: int) -> void: hud.set_gravity_mode(m))
	add_child(motion)

	touch = TouchController.new()
	touch.camera = camera
	touch.room = room
	add_child(touch)

	photo = PhotoMode.new()
	photo.camera = camera
	add_child(photo)

	hud = Hud.new()
	hud.main = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	touch.is_over_ui = hud.is_point_over_ui
	photo.hide_during_capture.assign([hud._root])
	photo.status.connect(func(msg: String) -> void: hud.toast(msg, 3.0))
	photo.recording_changed.connect(func(on: bool) -> void: hud.set_recording(on))

	touch.poked.connect(_on_poked)
	touch.grabbed.connect(_select)
	touch.thrown.connect(func(j: JellyObject, _speed: float) -> void:
		_select(j)
		GameState.add_stat("throws"))
	GameState.unlocked.connect(_on_unlocked)
	AdsService.reward_granted.connect(func(id: String) -> void:
		GameState.grant_bonus_unlock(id)
		hud.refresh())
	AdsService.ad_failed.connect(func(_id: String) -> void: hud.toast("No ad available right now"))

	get_viewport().size_changed.connect(_on_resized)
	apply_room(true)
	apply_options()
	spawn_jelly(StringName(GameState.options.get("last_jelly", "blob")))


# ------------------------------------------------------------------ jellies

func spawn_jelly(id: StringName, at: Variant = null) -> JellyObject:
	var jellies := get_tree().get_nodes_in_group("jellies")
	if jellies.size() >= MAX_JELLIES:
		hud.toast("That's a lot of jelly! (max %d)" % MAX_JELLIES)
		return null
	var data := GameState.get_custom_jelly(id)
	if data == null:
		return null
	var j: JellyObject = JELLY_SCENE.instantiate()
	add_child(j)
	j.setup(data, 1.0)
	j.sticky_walls = room.is_sticky()
	var pos: Vector3
	if at is Vector3:
		pos = at
	else:
		var dims := room.dimensions
		pos = Vector3(randf_range(-0.25, 0.25) * dims.x, dims.y * 0.75, randf_range(-0.15, 0.15) * dims.z)
	j.global_position = room.clamp_inside(pos, j.world_radius())
	j.rotation.y = randf_range(-0.4, 0.4)
	j.impacted.connect(_on_jelly_impacted)
	j.body_entered.connect(_on_jelly_body_entered.bind(j))
	j.jolt(Vector3.DOWN * 0.5)
	_select(j)
	GameState.options.last_jelly = String(id)
	GameState.add_stat("spawns")
	return j


func remove_selected() -> void:
	if is_instance_valid(selected):
		selected.queue_free()
		selected = null
		hud.set_selected(null)


func clear_jellies() -> void:
	touch.cancel_all()
	for j in get_tree().get_nodes_in_group("jellies"):
		j.queue_free()
	selected = null
	hud.set_selected(null)


func respawn_selected() -> void:
	if is_instance_valid(selected):
		selected.global_position = Vector3(0, room.dimensions.y - selected.world_radius() * 1.2, 0)
		selected.linear_velocity = Vector3.ZERO
		selected.angular_velocity = Vector3(randf(), randf(), randf())
		selected.sleeping = false


func _select(j: JellyObject) -> void:
	selected = j
	hud.set_selected(j)


func _on_poked(j: JellyObject) -> void:
	_select(j)
	GameState.add_stat("pokes")


func _on_jelly_impacted(_j: JellyObject, speed: float) -> void:
	Feedback.impact(speed)


## Merge: in merge mode, two jellies that bump together (or one dragged into
## another) become one bigger jelly with the combined volume.
func _on_jelly_body_entered(other: Node, j: JellyObject) -> void:
	if not merge_mode or _merging or not other is JellyObject:
		return
	var o := other as JellyObject
	if j.is_queued_for_deletion() or o.is_queued_for_deletion():
		return
	var rel := (j.linear_velocity - o.linear_velocity).length()
	if rel < 1.2 and not (j.held or o.held):
		return
	if j.get_instance_id() > o.get_instance_id():
		return  # handle each pair once
	# Contact signals fire while physics is flushing; shapes can't change then.
	_merging = true
	_deferred_merge.call_deferred(j, o)


func _deferred_merge(a: JellyObject, b: JellyObject) -> void:
	if is_instance_valid(a) and is_instance_valid(b) \
			and not a.is_queued_for_deletion() and not b.is_queued_for_deletion():
		merge_jellies(a, b)
	_merging = false


func merge_jellies(a: JellyObject, b: JellyObject) -> void:
	var ra := a.world_radius()
	var rb := b.world_radius()
	var r := pow(ra * ra * ra + rb * rb * rb, 1.0 / 3.0)
	if r > MERGE_MAX_RADIUS:
		hud.toast("Too big to merge!")
		return
	# The bigger one survives and absorbs the other.
	if rb > ra:
		var t := a
		a = b
		b = t
	var va := ra * ra * ra
	var vb := rb * rb * rb
	var wa := va / (va + vb)
	var momentum := a.linear_velocity * a.mass + b.linear_velocity * b.mass
	var centre := a.global_position.lerp(b.global_position, 1.0 - wa)
	a.data.color = a.data.color.lerp(b.data.color, 1.0 - wa)
	a.data.gradient_color = b.data.color
	a.data.gradient_amount = maxf(a.data.gradient_amount, 0.35 * (1.0 - wa) * 2.0)
	touch.cancel_all()
	b.queue_free()
	a.set_size(r / a.data.base_radius)
	a.apply_look()
	a.global_position = room.clamp_inside(centre, r)
	a.linear_velocity = momentum / a.mass
	a.jolt(Vector3.UP * 2.0)
	a.poke(a.global_position + Vector3.UP * r, Vector3.UP, 1.6)
	Feedback.merge()
	GameState.add_stat("merges")
	_select(a)


func _physics_process(_delta: float) -> void:
	# Held jelly pushed into another in merge mode: merge on overlap even if
	# the physics contact is soft.
	if merge_mode and not _merging and is_instance_valid(selected) and selected.held:
		for jn in get_tree().get_nodes_in_group("jellies"):
			var o := jn as JellyObject
			if o == selected or o.is_queued_for_deletion():
				continue
			var d := o.global_position.distance_to(selected.global_position)
			if d < (o.world_radius() + selected.world_radius()) * 0.8:
				merge_jellies(selected, o)
				break
	# Safety net: anything that tunnelled out of the room comes back.
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		if not room.contains(j.global_position, -0.5):
			j.global_position = room.clamp_inside(j.global_position, j.world_radius())
			j.linear_velocity *= -0.3


# ------------------------------------------------------------------ room

## Re-apply GameState.room. `resize` also rebuilds walls & re-frames the camera.
func apply_room(resize: bool = false) -> void:
	var theme := GameState.get_room_theme(GameState.room.theme)
	room.theme = theme
	if resize:
		_resize_room()
	room.apply_settings(GameState.room, theme)
	GameState.mark_dirty()


func _resize_room() -> void:
	var s: float = GameState.room.size
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var h := BASE_ROOM_HEIGHT * s
	# Fit the room to the screen shape so it fills portrait and landscape alike.
	var w := clampf(h * aspect * 0.98, 1.8 * s, 8.0 * s)
	if aspect > 1.0:
		h = BASE_ROOM_HEIGHT * s * 0.8
		w = clampf(h * aspect * 0.98, 1.8 * s, 8.0 * s)
	room.set_dimensions(Vector3(w, h, BASE_ROOM_DEPTH * s))
	camera.frame_room()
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		j.global_position = room.clamp_inside(j.global_position, j.world_radius())
		j.sleeping = false


func _on_resized() -> void:
	if not photo.active:
		_resize_room()


func apply_options() -> void:
	motion.tilt_enabled = bool(GameState.options.tilt_gravity)
	motion.shake_enabled = bool(GameState.options.shake)
	GameState.mark_dirty()


# ------------------------------------------------------------------ modes

func cycle_gravity() -> void:
	var m := motion.cycle_mode()
	hud.toast(["Gravity on", "Zero-G: float away…", "Gravity reversed!"][m], 1.4)


func toggle_slow_motion() -> void:
	var slow := Engine.time_scale >= 1.0
	Engine.time_scale = SLOW_MO if slow else 1.0
	room.set_time_scale(Engine.time_scale)
	hud.set_slow_motion(slow)
	hud.toast("Slow motion" if slow else "Normal speed", 1.0)


func set_photo_mode(on: bool) -> void:
	touch.cancel_all()
	touch.enabled = not on
	if on:
		var focus := Vector3(0, room.dimensions.y * 0.4, 0)
		if is_instance_valid(selected):
			focus = selected.global_position
		photo.enter(focus)
		hud.toast("Drag to orbit · pinch to zoom", 2.0)
	else:
		photo.exit()
		_resize_room()
	hud.set_photo_mode(on)


func _on_unlocked(kind: String, _id: String, display_name: String) -> void:
	hud.toast("Unlocked: %s %s!" % [display_name, "room" if kind == "room" else "jelly"], 3.0)
	Feedback.merge()
	hud.refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	# Desktop testing shortcuts.
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_S:
			motion.shake(Vector3(randf_range(-1, 1), 1.0, 0).normalized() * 25.0)
		KEY_G:
			cycle_gravity()
		KEY_M:
			toggle_slow_motion()
		KEY_P:
			set_photo_mode(not photo.active)
