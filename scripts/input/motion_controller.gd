class_name MotionController
extends Node
## Gravity modes (on / zero-g / reverse), tilt-to-steer gravity and phone shake.

signal mode_changed(mode: int)
signal shaken(strength: float)

enum Mode { NORMAL, ZERO_G, REVERSE }

const G := 9.8
const SHAKE_THRESHOLD := 11.0   # m/s^2 of linear (non-gravity) acceleration
const SHAKE_COOLDOWN := 0.18

var camera: Camera3D
var mode: Mode = Mode.NORMAL
var tilt_enabled := false
var shake_enabled := true

var _accel_smooth := Vector3.ZERO
var _shake_cooldown := 0.0
var _drift_time := 0.0
var _gravity_dir := Vector3.DOWN


func cycle_mode() -> Mode:
	set_mode(((mode + 1) % 3) as Mode)
	return mode


func set_mode(m: Mode) -> void:
	mode = m
	_apply_gravity(true)
	# Wake everything so the change is felt immediately.
	for j in get_tree().get_nodes_in_group("jellies"):
		(j as RigidBody3D).sleeping = false
		if mode == Mode.ZERO_G:
			(j as JellyObject).jolt(Vector3(randf_range(-0.3, 0.3), 0.6, randf_range(-0.2, 0.2)))
	mode_changed.emit(mode)


func _physics_process(delta: float) -> void:
	_apply_gravity(false)
	if mode == Mode.ZERO_G:
		_drift(delta)
	_detect_shake(delta)


func _apply_gravity(force: bool) -> void:
	var dir := Vector3.DOWN
	if tilt_enabled and camera:
		var g := Input.get_gravity()
		if g.length() > 1.0:
			# Device axes: x = screen right, y = screen up, z = out of screen.
			# Mapped onto a level version of the camera (yaw only), so tilting
			# feels the same however far the camera is pitched down.
			var b := _level_basis()
			dir = (b.x * g.x + b.y * g.y + b.z * g.z).normalized()
	if mode == Mode.REVERSE:
		dir = -dir
	var strength := 0.0 if mode == Mode.ZERO_G else G
	if not force and dir.is_equal_approx(_gravity_dir):
		return
	_gravity_dir = dir
	var space := get_viewport().find_world_3d().space
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, dir)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, strength)
	if tilt_enabled:
		for j in get_tree().get_nodes_in_group("jellies"):
			(j as RigidBody3D).sleeping = false


## Zero-g: very gentle, smoothly varying currents so jellies float lazily.
func _drift(delta: float) -> void:
	_drift_time += delta
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		if j.held:
			continue
		var phase := float(j.get_instance_id() % 997)
		var f := Vector3(
			sin(_drift_time * 0.37 + phase),
			sin(_drift_time * 0.29 + phase * 1.7),
			sin(_drift_time * 0.23 + phase * 2.3) * 0.5) * 0.25
		j.apply_central_force(f * j.mass)
		# Keep it lazy: bleed off speed a little.
		j.linear_velocity *= 1.0 - 0.15 * delta


func _detect_shake(delta: float) -> void:
	_shake_cooldown = maxf(_shake_cooldown - delta, 0.0)
	if not shake_enabled:
		return
	var a := Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	# High-pass: remove the slowly changing gravity component.
	_accel_smooth = _accel_smooth.lerp(a, clampf(delta * 4.0, 0.0, 1.0))
	var lin := a - _accel_smooth
	if lin.length() > SHAKE_THRESHOLD and _shake_cooldown <= 0.0:
		_shake_cooldown = SHAKE_COOLDOWN
		shake(lin)


## Shake every jelly. `device_accel` in device axes (also used for keyboard test).
func shake(device_accel: Vector3) -> void:
	var dir := device_accel.normalized()
	if camera:
		var b := _level_basis()
		dir = (b.x * dir.x + b.y * dir.y + b.z * dir.z * 0.3).normalized()
	var strength := clampf(device_accel.length() * 0.18, 1.0, 4.5)
	for jn in get_tree().get_nodes_in_group("jellies"):
		var j := jn as JellyObject
		# Jellies get thrown opposite to the phone's motion (inertia).
		var jitter := Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.3), randf_range(-0.2, 0.2))
		j.jolt((-dir + jitter) * strength)
	Feedback.impact(strength * 2.0)
	shaken.emit(strength)


## Camera basis with the pitch removed: x = right, y = world up, z = toward viewer.
func _level_basis() -> Basis:
	var back := camera.global_transform.basis.z
	back.y = 0.0
	if back.length_squared() < 1e-4:
		back = -camera.global_transform.basis.y
		back.y = 0.0
	back = back.normalized()
	return Basis(Vector3.UP.cross(back).normalized(), Vector3.UP, back)
