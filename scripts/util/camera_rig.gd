class_name CameraRig
extends Camera3D
## Frames the room in play mode; free orbit / zoom in photo mode.

const PLAY_FOV := 50.0

var room: Room
var orbiting := false

var _yaw := 0.0
var _pitch := -0.12
var _distance := 4.0
var _target := Vector3.ZERO
var _touches := {}
var _pinch_start := 0.0
var _pinch_dist_start := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fov = PLAY_FOV
	near = 0.05
	far = 60.0


## Position the camera outside the (invisible) front wall so the whole room fits.
func frame_room() -> void:
	if room == null:
		return
	var dims := room.dimensions
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var half_v := deg_to_rad(fov) * 0.5
	var half_h := atan(tan(half_v) * aspect)
	var dist_v := (dims.y * 0.5) / tan(half_v)
	var dist_h := (dims.x * 0.5) / tan(half_h)
	var dist := maxf(dist_v, dist_h) * 1.03
	global_position = Vector3(0, dims.y * 0.5, dims.z * 0.5 + dist)
	look_at(Vector3(0, dims.y * 0.5, dims.z * 0.5), Vector3.UP)


func begin_orbit(target: Vector3) -> void:
	orbiting = true
	_target = target
	var offset := global_position - target
	_distance = clampf(offset.length() * 0.6, 1.0, 6.0)
	_yaw = atan2(offset.x, offset.z)
	_pitch = -0.12
	_touches.clear()
	_apply_orbit()


func end_orbit() -> void:
	orbiting = false
	_touches.clear()
	frame_room()


func _unhandled_input(event: InputEvent) -> void:
	if not orbiting:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var p: Array = _touches.values()
			_pinch_dist_start = (p[0] - p[1]).length()
			_pinch_start = _distance
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_yaw -= event.relative.x * 0.008
			_pitch = clampf(_pitch - event.relative.y * 0.006, -1.3, 1.1)
		elif _touches.size() == 2 and _pinch_dist_start > 1.0:
			var p: Array = _touches.values()
			_distance = clampf(_pinch_start * _pinch_dist_start / maxf((p[0] - p[1]).length(), 1.0), 0.6, 7.0)
		_apply_orbit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.6)
			_apply_orbit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 7.0)
			_apply_orbit()


func _apply_orbit() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(-_pitch), cos(_yaw) * cos(_pitch))
	global_position = _target + dir * _distance
	look_at(_target, Vector3.UP)
