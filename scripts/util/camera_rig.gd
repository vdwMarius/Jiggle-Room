class_name CameraRig
extends Camera3D
## Free camera that lives inside the room.
##
## An orbit camera around a pivot point: drag on empty space to orbit, two
## fingers to pan (move the pivot) and pinch to zoom. Everything is smoothed
## and has a little inertia, and the camera is kept inside the walls so it
## never looks out of the room. Used both in play and photo mode.
##
## Input arrives from TouchController (empty-space touches) plus the mouse
## wheel / right-drag here for desktop testing.

const FOV := 55.0
const MIN_DISTANCE := 0.6
const MIN_PITCH := -1.396       # -80 degrees (looking down)
const MAX_PITCH := 0.262        # +15 degrees (looking slightly up)
const WALL_MARGIN := 0.18
const ORBIT_SPEED := 0.006      # radians per pixel
const SMOOTH := 14.0            # higher = snappier follow
const INERTIA_DECAY := 5.0

var room: Room

var _pivot := Vector3(0, 0.6, 0)
var _yaw := 0.0
var _pitch := deg_to_rad(-25.0)
var _distance := 4.0
# Smoothed values actually used for the camera.
var _s_pivot := Vector3(0, 0.6, 0)
var _s_yaw := 0.0
var _s_pitch := deg_to_rad(-25.0)
var _s_distance := 4.0
var _orbit_velocity := Vector2.ZERO   # rad/s, from finger flicks
var _dragging := false
var _mouse_pan := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working in photo mode (paused)
	fov = FOV
	near = 0.05
	far = 60.0


## Default view: from the front-right, slightly above, looking at the room.
func reset_view(instant: bool = false) -> void:
	if room == null:
		return
	var dims := room.dimensions
	_pivot = Vector3(0, 0.55, -dims.z * 0.1)
	_yaw = deg_to_rad(18.0)
	_pitch = deg_to_rad(-22.0)
	_distance = max_distance() * 0.95
	_orbit_velocity = Vector2.ZERO
	if instant:
		_snap()


## Smoothly move the pivot to a point of interest (e.g. a jelly).
func focus(point: Vector3, distance: float = -1.0) -> void:
	_pivot = _clamp_pivot(point)
	if distance > 0.0:
		_distance = clampf(distance, MIN_DISTANCE, max_distance())


## Where the camera is looking (the orbit pivot).
func get_pivot() -> Vector3:
	return _pivot


func max_distance() -> float:
	if room == null:
		return 6.0
	return Vector2(room.dimensions.x, room.dimensions.z).length() * 0.7


# ------------------------------------------------------------------ gestures

func begin_drag() -> void:
	_dragging = true
	_orbit_velocity = Vector2.ZERO


func orbit(pixels: Vector2, dt: float = 0.016) -> void:
	_yaw -= pixels.x * ORBIT_SPEED
	_pitch = clampf(_pitch - pixels.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
	if dt > 0.0:
		_orbit_velocity = _orbit_velocity.lerp(Vector2(-pixels.x, -pixels.y) * ORBIT_SPEED / dt, 0.5)


func end_drag() -> void:
	_dragging = false
	# Keep only a gentle glide.
	_orbit_velocity = _orbit_velocity.limit_length(4.0)


## Two-finger pan: moves the pivot in the camera's view plane.
func pan(pixels: Vector2) -> void:
	var vp_h := maxf(get_viewport().get_visible_rect().size.y, 1.0)
	var metres_per_px := 2.0 * _s_distance * tan(deg_to_rad(fov) * 0.5) / vp_h
	var b := global_transform.basis
	_pivot = _clamp_pivot(_pivot - b.x * pixels.x * metres_per_px + b.y * pixels.y * metres_per_px)
	_orbit_velocity = Vector2.ZERO


## factor < 1 zooms in.
func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, MIN_DISTANCE, max_distance())


func _unhandled_input(event: InputEvent) -> void:
	# Desktop helpers: wheel zoom, right/middle-drag pan.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
	elif event is InputEventMouseMotion and _mouse_pan:
		pan((event as InputEventMouseMotion).relative)


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	# Real time, so the camera stays responsive in slow-mo and photo mode.
	var dt := delta / maxf(Engine.time_scale, 0.01) if not get_tree().paused else delta
	dt = minf(dt, 0.05)
	if not _dragging and _orbit_velocity.length_squared() > 1e-4:
		_yaw += _orbit_velocity.x * dt
		_pitch = clampf(_pitch + _orbit_velocity.y * dt, MIN_PITCH, MAX_PITCH)
		_orbit_velocity *= exp(-INERTIA_DECAY * dt)
	var k := 1.0 - exp(-SMOOTH * dt)
	_s_pivot = _s_pivot.lerp(_pivot, k)
	_s_yaw = lerp_angle(_s_yaw, _yaw, k)
	_s_pitch = lerpf(_s_pitch, _pitch, k)
	_s_distance = lerpf(_s_distance, _distance, k)
	_apply()


func _snap() -> void:
	_s_pivot = _pivot
	_s_yaw = _yaw
	_s_pitch = _pitch
	_s_distance = _distance
	_apply()


func _apply() -> void:
	var dir := Vector3(sin(_s_yaw) * cos(_s_pitch), -sin(_s_pitch), cos(_s_yaw) * cos(_s_pitch))
	var dist := _s_distance
	if room:
		dist = minf(dist, _distance_to_walls(_s_pivot, dir))
	var pos := _s_pivot + dir * dist
	global_position = pos
	if not pos.is_equal_approx(_s_pivot):
		look_at(_s_pivot, Vector3.UP)


## How far the camera can back away from `from` along `dir` before hitting a
## wall, floor or ceiling (minus a margin).
func _distance_to_walls(from: Vector3, dir: Vector3) -> float:
	var half := room.dimensions * 0.5
	var lo := Vector3(-half.x, 0.0, -half.z) + Vector3.ONE * WALL_MARGIN
	var hi := Vector3(half.x, room.dimensions.y, half.z) - Vector3.ONE * WALL_MARGIN
	var t := INF
	for axis in 3:
		var d: float = dir[axis]
		if absf(d) < 1e-5:
			continue
		var limit: float = hi[axis] if d > 0.0 else lo[axis]
		var start: float = from[axis]
		t = minf(t, (limit - start) / d)
	return maxf(t, MIN_DISTANCE * 0.5)


func _clamp_pivot(p: Vector3) -> Vector3:
	if room == null:
		return p
	return room.clamp_inside(p, 0.3)
