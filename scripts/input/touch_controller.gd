class_name TouchController
extends Node
## Turns raw touches into jelly and camera interactions.
##
## On a jelly:
##   tap          -> poke ripple
##   drag         -> grab & stretch (jelly follows the finger)
##   flick        -> throw with the finger's release velocity
##   two fingers  -> pinch to scale the touched jelly
## On empty space (the camera):
##   drag         -> orbit around the room
##   two fingers  -> pan (move together) and zoom (pinch)
##   double-tap   -> reset the view
##
## Mouse works too (project setting "emulate touch from mouse").

signal poked(jelly: JellyObject)
signal grabbed(jelly: JellyObject)
signal thrown(jelly: JellyObject, speed: float)
signal released(jelly: JellyObject)
signal empty_tapped(screen_pos: Vector2)

const TAP_MAX_TIME := 0.22
const TAP_MAX_MOVE := 14.0          # pixels (scaled by DPI below)
const FLICK_WINDOW := 0.09          # seconds of history used for release speed
const THROW_GAIN := 1.0
const MAX_THROW_SPEED := 16.0
const FOLLOW_TIME := 0.07           # how quickly a held jelly catches the finger

const DOUBLE_TAP_TIME := 0.32

var camera: CameraRig
var room: Room
## Callable(pos: Vector2) -> bool. Lets the HUD swallow touches on its buttons.
var is_over_ui: Callable
## False in photo mode: touches only move the camera.
var enabled := true

var _touches := {}                  # index -> Touch
var _pinch: Dictionary = {}         # active jelly pinch state
var _cam_pinch: Dictionary = {}     # active camera pan/zoom state
var _last_empty_tap := -10.0
var _px_scale := 1.0


class Touch:
	var index := 0
	var start_pos := Vector2.ZERO
	var pos := Vector2.ZERO
	var start_time := 0.0
	var jelly: JellyObject
	var grabbing := false
	var local_anchor := Vector3.ZERO   # grab point in the jelly's body space
	var plane: Plane
	var history: Array = []           # [time, world_point]
	var orbiting := false             # empty-space drag moving the camera
	var last_move_time := 0.0


func _ready() -> void:
	_px_scale = maxf(DisplayServer.screen_get_dpi() / 160.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if is_over_ui.is_valid() and is_over_ui.call(st.position):
				return
			_on_down(st.index, st.position)
		else:
			_on_up(st.index, st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.has(sd.index):
			_on_move(sd.index, sd.position)


func cancel_all() -> void:
	for t in _touches.values():
		if t.grabbing and is_instance_valid(t.jelly):
			t.jelly.end_grab()
	_touches.clear()
	_pinch.clear()
	_cam_pinch.clear()
	camera.end_drag()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_down(index: int, pos: Vector2) -> void:
	var t := Touch.new()
	t.index = index
	t.start_pos = pos
	t.pos = pos
	t.start_time = _now()
	t.last_move_time = t.start_time
	var hit := _raycast_jelly(pos) if enabled else {}
	if not hit.is_empty():
		t.jelly = hit.collider
		t.local_anchor = t.jelly.to_local(hit.position)
		t.plane = _drag_plane(hit.position)
	_touches[index] = t

	if _touches.size() == 2:
		_start_pinch()
		if _pinch.is_empty():
			_start_camera_pinch()


func _on_move(index: int, pos: Vector2) -> void:
	var t: Touch = _touches[index]
	var moved := pos - t.pos
	t.pos = pos
	var now := _now()
	var dt := now - t.last_move_time
	t.last_move_time = now
	if not _pinch.is_empty():
		_update_pinch()
		return
	if not _cam_pinch.is_empty():
		_update_camera_pinch()
		return
	if not is_instance_valid(t.jelly):
		# Empty space: orbit the camera once the finger really moves.
		if not t.orbiting and (pos - t.start_pos).length() > TAP_MAX_MOVE * _px_scale:
			t.orbiting = true
			camera.begin_drag()
		if t.orbiting and _touches.size() == 1:
			camera.orbit(moved, dt)
		return
	if not t.grabbing and (pos - t.start_pos).length() > TAP_MAX_MOVE * _px_scale:
		t.grabbing = true
		t.jelly.begin_grab(t.jelly.to_global(t.local_anchor))
		Feedback.grab()
		grabbed.emit(t.jelly)
	if t.grabbing:
		var wp := _plane_point(t.plane, pos)
		t.history.append([_now(), wp])
		while t.history.size() > 2 and _now() - t.history[0][0] > FLICK_WINDOW * 2.0:
			t.history.pop_front()


func _on_up(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Touch = _touches[index]
	_touches.erase(index)
	if not _pinch.is_empty():
		_end_pinch()
		return
	if not _cam_pinch.is_empty():
		_cam_pinch.clear()
		# The remaining finger continues as a fresh orbit drag, without a jump.
		for other in _touches.values():
			other.jelly = null
			other.orbiting = true
		camera.begin_drag()
		return
	if t.orbiting:
		camera.end_drag()
		return
	var dt := _now() - t.start_time
	if is_instance_valid(t.jelly):
		if t.grabbing:
			var v := _release_velocity(t)
			t.jelly.end_grab()
			t.jelly.linear_velocity = v
			if v.length() > 2.5:
				thrown.emit(t.jelly, v.length())
			released.emit(t.jelly)
		elif dt < TAP_MAX_TIME * 2.0:
			var hit := _raycast_jelly(pos)
			var p: Vector3 = hit.position if not hit.is_empty() else t.jelly.to_global(t.local_anchor)
			var n: Vector3 = hit.normal if not hit.is_empty() else camera.global_transform.basis.z
			# Quick taps poke harder than slow presses.
			t.jelly.poke(p, n, lerpf(1.3, 0.8, clampf(dt / TAP_MAX_TIME, 0.0, 1.0)))
			Feedback.poke()
			poked.emit(t.jelly)
	elif dt < TAP_MAX_TIME and (pos - t.start_pos).length() < TAP_MAX_MOVE * _px_scale:
		if _now() - _last_empty_tap < DOUBLE_TAP_TIME:
			camera.reset_view()
			_last_empty_tap = -10.0
		else:
			_last_empty_tap = _now()
		empty_tapped.emit(pos)


func _physics_process(delta: float) -> void:
	for t in _touches.values():
		if not t.grabbing or not is_instance_valid(t.jelly):
			continue
		var j: JellyObject = t.jelly
		var target := _plane_point(t.plane, t.pos)
		if room:
			target = room.clamp_inside(target, j.world_radius() * 0.6)
		var anchor := j.to_global(t.local_anchor)
		var to_target := target - anchor
		# Velocity-based follow: crisp, stable and frame-rate independent.
		# Divided by time_scale so the jelly stays glued to the finger in slow-mo.
		var ts := maxf(Engine.time_scale, 0.05)
		var desired := (target - anchor) / (FOLLOW_TIME * ts)
		desired = desired.limit_length(MAX_THROW_SPEED * 1.5 / ts)
		var blend := clampf(delta / ts * 25.0, 0.0, 1.0)
		j.linear_velocity = j.linear_velocity.lerp(desired, blend)
		j.angular_velocity *= 0.9
		# Visual stretch toward the finger, independent of the body lag.
		j.update_grab(to_target * 2.0 + j.linear_velocity * 0.015)


func _release_velocity(t: Touch) -> Vector3:
	if t.history.size() < 2:
		return Vector3.ZERO
	var last: Array = t.history[-1]
	var first: Array = last
	for i in range(t.history.size() - 1, -1, -1):
		first = t.history[i]
		if last[0] - first[0] >= FLICK_WINDOW:
			break
	var span: float = last[0] - first[0]
	if span <= 0.001 or _now() - last[0] > 0.12:
		return Vector3.ZERO  # finger stopped before lifting: gentle drop
	var v: Vector3 = (last[1] - first[1]) / span * THROW_GAIN
	return v.limit_length(MAX_THROW_SPEED)


# ------------------------------------------------------------------ pinch

func _start_pinch() -> void:
	var ts := _touches.values()
	var j: JellyObject = null
	for t in ts:
		if is_instance_valid(t.jelly):
			j = t.jelly
	if j == null:
		return  # neither finger is on a jelly: the camera gets this pinch
	for t in ts:
		if t.grabbing and is_instance_valid(t.jelly):
			t.jelly.end_grab()
		t.grabbing = false
	_pinch = {
		"jelly": j,
		"start_dist": maxf((ts[0].pos - ts[1].pos).length(), 1.0),
		"start_size": j.size,
	}


func _update_pinch() -> void:
	var ts := _touches.values()
	if ts.size() < 2 or not is_instance_valid(_pinch.jelly):
		return
	var d: float = (ts[0].pos - ts[1].pos).length()
	var j: JellyObject = _pinch.jelly
	var s: float = _pinch.start_size * d / _pinch.start_dist
	var r_before := j.world_radius()
	j.set_size(s)
	# Keep it inside the room as it grows.
	if room:
		j.global_position = room.clamp_inside(j.global_position, j.world_radius() * 0.9)
	if absf(j.world_radius() - r_before) > 0.002:
		j.sleeping = false


func _end_pinch() -> void:
	var j = _pinch.get("jelly")
	_pinch.clear()
	# Remaining finger shouldn't suddenly start a grab or tap.
	for t in _touches.values():
		t.jelly = null
	if is_instance_valid(j):
		(j as JellyObject).jolt(Vector3.UP * 0.5)
		Feedback.grab()


# ------------------------------------------------------------------ camera pinch

func _start_camera_pinch() -> void:
	var ts := _touches.values()
	camera.end_drag()
	for t in ts:
		t.orbiting = false
	_cam_pinch = {
		"mid": (ts[0].pos + ts[1].pos) * 0.5,
		"dist": maxf((ts[0].pos - ts[1].pos).length(), 1.0),
	}


func _update_camera_pinch() -> void:
	var ts := _touches.values()
	if ts.size() < 2:
		return
	var mid: Vector2 = (ts[0].pos + ts[1].pos) * 0.5
	var dist := maxf((ts[0].pos - ts[1].pos).length(), 1.0)
	camera.pan(mid - _cam_pinch.mid)
	camera.zoom(_cam_pinch.dist / dist)
	_cam_pinch.mid = mid
	_cam_pinch.dist = dist


# ------------------------------------------------------------------ helpers

## Plane the grabbed jelly moves in. Upright and facing the camera, so
## dragging up lifts the jelly even when the camera looks down at the room;
## when looking almost straight down, the screen plane works better.
func _drag_plane(point: Vector3) -> Plane:
	var back := camera.global_transform.basis.z
	var flat := Vector3(back.x, 0.0, back.z)
	if flat.length() > 0.45:
		return Plane(flat.normalized(), point)
	return Plane(back, point)


func _raycast_jelly(screen_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 2)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit.collider is JellyObject:
		# Fingers are fat: try a slightly larger probe around the touch.
		var best := {}
		var best_d := INF
		for jn in camera.get_tree().get_nodes_in_group("jellies"):
			var j := jn as JellyObject
			var sp := camera.unproject_position(j.global_position)
			var d := sp.distance_to(screen_pos)
			var r_px := _world_radius_px(j)
			if d < r_px * 1.15 + 18.0 * _px_scale and d < best_d and not camera.is_position_behind(j.global_position):
				best_d = d
				best = {"collider": j, "position": j.global_position + camera.global_transform.basis.z * j.world_radius() * 0.8,
					"normal": camera.global_transform.basis.z}
		return best
	return hit


func _world_radius_px(j: JellyObject) -> float:
	var c := camera.unproject_position(j.global_position)
	var e := camera.unproject_position(j.global_position + camera.global_transform.basis.x * j.world_radius())
	return c.distance_to(e)


func _plane_point(plane: Plane, screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var p = plane.intersects_ray(from, dir)
	return p if p != null else from + dir * 3.0
