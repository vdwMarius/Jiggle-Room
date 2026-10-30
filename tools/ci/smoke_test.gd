extends Node
## Headless functional smoke test. Run:
##   godot --headless --path . res://tools/ci/smoke_test.tscn
## Prints "SMOKE <step>" lines, then "SMOKE OK" (exit 0) or "SMOKE FAIL" (exit 1).
## Script errors still have to be caught from the log (build_android.sh greps it).

var main: Node
var failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps running through photo-mode pause
	# Runs on a build machine; GameState may autosave there, which is harmless.
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(30)
	_step("main scene up")

	await _test_rooms()
	await _test_jellies()
	await _test_gestures()
	await _test_camera()
	await _test_modes()
	await _test_merge()
	await _test_photo()

	if failures.is_empty():
		print("SMOKE OK")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SMOKE FAIL: " + f)
		get_tree().quit(1)


func _test_rooms() -> void:
	for t in GameState.room_themes:
		GameState.room.theme = String(t.id)
		main.apply_room()
		await _frames(10)
		var furniture: Node = main.room.get_node("Furniture")
		_check(furniture.get_child_count() > 3, "room %s has furniture" % t.id)
		_check(absf(main.room.dimensions.x - t.room_size.x * float(GameState.room.size)) < 0.01,
			"room %s uses its own size" % t.id)
		_check_camera_inside("after switching to %s" % t.id)
	GameState.room.theme = "living_room"
	GameState.room.size = 1.3
	main.apply_room()
	await _frames(10)
	GameState.room.size = 1.0
	main.apply_room()
	await _frames(10)
	_step("rooms: %d themes built" % GameState.room_themes.size())


func _test_jellies() -> void:
	main.clear_jellies()
	await _frames(2)
	for jd in GameState.jelly_types:
		var j: JellyObject = main.spawn_jelly(jd.id)
		_check(j != null, "spawn %s" % jd.id)
		await _frames(4)
	await _frames(120)   # let them fall, land and sag
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		_check(main.room.contains(j.global_position, -0.1), "%s stayed inside the room" % j.data.id)
		_check_springs(j, "after landing")
	_step("jellies: %d spawned and landed" % get_tree().get_nodes_in_group("jellies").size())


func _test_gestures() -> void:
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		var top := j.global_position + Vector3.UP * j.world_radius()
		j.poke(top, Vector3.UP, 1.3)
		j.jolt(Vector3(1.5, 2.0, 0.0))
		j.begin_grab(top)
		j.update_grab(Vector3(0.4, 0.3, 0.0))
		await _frames(5)
		j.end_grab()
		j.set_size(1.8)
		j.set_size(0.7)
		j.set_size(1.0)
	await _frames(60)
	for jn in get_tree().get_nodes_in_group("jellies"):
		_check_springs(jn as JellyObject, "after gestures")
	main.motion.shake(Vector3(20, 5, 0))
	await _frames(60)
	_step("gestures: poke, jolt, grab, resize, shake")


func _test_camera() -> void:
	var cam: CameraRig = main.camera
	cam.begin_drag()
	for i in 20:
		cam.orbit(Vector2(40, 15), 0.016)
		await _frames(1)
	cam.end_drag()
	cam.pan(Vector2(300, -200))
	cam.zoom(0.4)
	cam.zoom(10.0)
	await _frames(40)
	_check_camera_inside("after orbit/pan/zoom")
	cam.focus(Vector3(0, 0.5, 0), 1.2)
	cam.reset_view()
	await _frames(40)
	_check_camera_inside("after reset")
	_step("camera: orbit, pan, zoom, focus, reset")


func _test_modes() -> void:
	for i in 3:
		main.cycle_gravity()
		await _frames(30)
	main.toggle_slow_motion()
	await _frames(30)
	main.toggle_slow_motion()
	for mode in ["bouncy", "sticky", "normal"]:
		GameState.room.wall_mode = mode
		main.apply_room()
		await _frames(30)
	GameState.room.props = false
	main.apply_room()
	await _frames(5)
	GameState.room.props = true
	main.apply_room()
	await _frames(5)
	_check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored")
	_step("modes: gravity x3, slow-mo, wall modes, props toggle")


func _test_merge() -> void:
	main.clear_jellies()
	await _frames(2)
	var a: JellyObject = main.spawn_jelly(&"blob")
	var b: JellyObject = main.spawn_jelly(&"blob")
	await _frames(10)
	var r_before := a.world_radius()
	main.merge_jellies(a, b)
	await _frames(10)
	var left := get_tree().get_nodes_in_group("jellies")
	_check(left.size() == 1, "merge leaves one jelly (got %d)" % left.size())
	if left.size() == 1:
		_check((left[0] as JellyObject).world_radius() > r_before, "merged jelly is bigger")
	_step("merge")


func _test_photo() -> void:
	main.set_photo_mode(true)
	await _frames(10)
	_check(get_tree().paused, "photo mode pauses")
	main.camera.orbit(Vector2(100, 0), 0.016)
	await _frames(10)
	main.set_photo_mode(false)
	await _frames(5)
	_check(not get_tree().paused, "photo mode unpauses")
	_step("photo mode")


# ------------------------------------------------------------------ helpers

func _check_springs(j: JellyObject, when: String) -> void:
	var s := j.springs
	var values := [s.stretch, s.impact, s.sag, s.wobble2, s.sway.length(), s.lag.length(), s.grab.length()]
	for v in values:
		if is_nan(v) or is_inf(v):
			_check(false, "%s springs finite %s" % [j.data.id, when])
			return
	_check(absf(s.sag) <= j.data.max_deformation + 0.001, "%s sag within cap %s" % [j.data.id, when])


func _check_camera_inside(when: String) -> void:
	var p: Vector3 = main.camera.global_position
	_check(main.room.contains(p, 0.0), "camera inside room %s (at %s)" % [when, p])


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("SMOKE FAIL: " + what)


func _step(what: String) -> void:
	print("SMOKE " + what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
