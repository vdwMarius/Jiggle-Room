class_name JellyObject
extends RigidBody3D
## One jelly. Rigid body for motion + spring-driven vertex shader for the wobble.
##
## Scene: scenes/jelly_object.tscn (RigidBody3D > Mesh: MeshInstance3D, Shape: CollisionShape3D).
## Call `setup(data)` after instancing.

signal impacted(jelly: JellyObject, speed: float)

const JELLY_SHADER := preload("res://shaders/jelly.gdshader")
const MIN_SIZE := 0.5
const MAX_SIZE := 2.6

@export var data: JellyData

var springs := JellySprings.new()
var size := 1.0
## Set by the room: when true, wall contacts make the jelly cling for a moment.
var sticky_walls := false
var held := false
## Seconds the jelly stays stuck after hitting a wall in sticky mode.
var stick_timer := 0.0

@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var collision: CollisionShape3D = $Shape

var _material: ShaderMaterial
var _mesh_radius := 0.5           # mesh-local bound radius
var _base_shape: Shape3D
var _prev_velocity := Vector3.ZERO
var _prev_ang_velocity := Vector3.ZERO
var _accel := Vector3.ZERO
var _ang_accel := Vector3.ZERO
var _mesh_aabb := AABB()
var _pending_impacts: Array = []   # [world_normal, speed] gathered in physics
var _impact_cooldown := 0.0


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	can_sleep = true
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	if data:
		setup(data)


func setup(new_data: JellyData, new_size: float = -1.0) -> void:
	data = new_data
	if not is_node_ready():
		return
	var mesh := JellyMeshFactory.get_mesh(data)
	mesh_instance.mesh = mesh
	_mesh_radius = JellyMeshFactory.bound_radius(mesh)
	_mesh_aabb = mesh.get_aabb()
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = JELLY_SHADER
		mesh_instance.material_override = _material
	_base_shape = _make_shape(mesh)
	springs.configure(data)
	apply_look()
	_apply_physics_material()
	set_size(new_size if new_size > 0.0 else size)


## Push colours/opacity/glitter etc. to the shader (call after editing `data`).
func apply_look() -> void:
	_material.set_shader_parameter("base_color", data.color)
	_material.set_shader_parameter("gradient_color", data.gradient_color)
	_material.set_shader_parameter("gradient_amount", data.gradient_amount)
	_material.set_shader_parameter("opacity", data.opacity)
	_material.set_shader_parameter("glitter_amount", data.glitter)
	_material.set_shader_parameter("glow_in_dark", data.glow_in_dark)
	_material.set_shader_parameter("bound_radius", _mesh_radius)
	_material.set_shader_parameter("max_deform", data.max_deformation)
	_material.set_shader_parameter("core_floppiness", data.core_floppiness)
	_material.set_shader_parameter("grab_radius", _mesh_radius * 0.75)
	var w := TAU * data.wobble_frequency * data.ripple_frequency_scale
	_material.set_shader_parameter("ripple_freq", w)
	_material.set_shader_parameter("ripple_decay", data.ripple_decay)
	_material.set_shader_parameter("ripple_wavenumber", TAU / (data.ripple_wavelength * _mesh_radius))


## Push feel settings (stiffness, damping, mass ...) after editing `data`.
func apply_feel() -> void:
	springs.configure(data)
	_apply_physics_material()
	apply_look()
	mass = data.mass * size * size * size


func _apply_physics_material() -> void:
	var pm := PhysicsMaterial.new()
	pm.bounce = data.bounciness
	pm.friction = data.friction
	physics_material_override = pm
	mass = data.mass * size * size * size
	angular_damp = 0.6
	linear_damp = 0.05


func world_radius() -> float:
	return data.base_radius * size


func set_size(s: float) -> void:
	size = clampf(s, MIN_SIZE, MAX_SIZE)
	var k := world_radius() / _mesh_radius
	# Never scale a RigidBody3D itself; scale the visual and rebuild the shape.
	mesh_instance.scale = Vector3.ONE * k
	collision.shape = _scaled_shape(k)
	mass = data.mass * size * size * size


func _make_shape(mesh: Mesh) -> Shape3D:
	var aabb := mesh.get_aabb()
	if data.collision == JellyData.Collision.SPHERE:
		var s := SphereShape3D.new()
		s.radius = _mesh_radius * 0.85
		return s
	if data.collision == JellyData.Collision.BOX:
		var b := BoxShape3D.new()
		b.size = aabb.size * 0.92
		return b
	if data.collision == JellyData.Collision.CAPSULE:
		var c := CapsuleShape3D.new()
		c.radius = minf(aabb.size.x, aabb.size.z) * 0.45
		c.height = maxf(aabb.size.y * 0.95, c.radius * 2.0)
		return c
	return mesh.create_convex_shape(true, true)


func _scaled_shape(k: float) -> Shape3D:
	if _base_shape is SphereShape3D:
		var s := SphereShape3D.new()
		s.radius = (_base_shape as SphereShape3D).radius * k
		return s
	if _base_shape is BoxShape3D:
		var b := BoxShape3D.new()
		b.size = (_base_shape as BoxShape3D).size * k
		return b
	if _base_shape is CapsuleShape3D:
		var c := CapsuleShape3D.new()
		c.radius = (_base_shape as CapsuleShape3D).radius * k
		c.height = (_base_shape as CapsuleShape3D).height * k
		return c
	var convex := ConvexPolygonShape3D.new()
	var pts: PackedVector3Array = (_base_shape as ConvexPolygonShape3D).points.duplicate()
	for i in pts.size():
		pts[i] *= k
	convex.points = pts
	return convex


# ------------------------------------------------------------------ touch API

## Tap: radial ripple from the touch point plus a small nudge.
func poke(world_point: Vector3, world_normal: Vector3, strength: float = 1.0) -> void:
	var local := _to_mesh_local(world_point)
	springs.add_ripple(local, data.ripple_amplitude * _mesh_radius * strength * lerpf(1.4, 0.6, data.stiffness))
	# A poke also dents the surface briefly: reuse the impact spring.
	_kick_impact(_dir_to_mesh_local(world_normal), 0.05 * strength)
	apply_impulse(-world_normal * 0.6 * strength * mass, world_point - global_position)
	sleeping = false


func begin_grab(world_point: Vector3) -> void:
	held = true
	springs.grabbing = true
	springs.grab_point = _to_mesh_local(world_point)
	springs.grab_target = Vector3.ZERO
	sleeping = false


## `world_pull` = vector from the grabbed surface point toward the finger.
func update_grab(world_pull: Vector3) -> void:
	var local := _dir_to_mesh_local_scaled(world_pull)
	# Stretch toward the finger, limited so it never looks mushy.
	var softness := lerpf(1.0, 0.45, data.stiffness)
	springs.grab_target = local.limit_length(_mesh_radius * data.max_deformation * 1.4) * softness


func end_grab() -> void:
	held = false
	springs.grabbing = false
	# The stored pull snaps back with the normal (underdamped) wobble.


## Ripple + impulse used by shake and merges.
func jolt(world_impulse: Vector3) -> void:
	apply_central_impulse(world_impulse * mass)
	var dir := world_impulse.normalized() if world_impulse.length() > 0.001 else Vector3.UP
	_kick_impact(_dir_to_mesh_local(-dir), clampf(world_impulse.length() * 0.03, 0.02, data.max_deformation))
	sleeping = false


# ------------------------------------------------------------------ physics

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	if dt > 0.0:
		_accel = (state.linear_velocity - _prev_velocity) / dt
		_ang_accel = (state.angular_velocity - _prev_ang_velocity) / dt

	for i in state.get_contact_count():
		var n := state.get_contact_local_normal(i)
		# Orient the normal so it opposes the incoming motion (wall -> jelly).
		if n.dot(_prev_velocity) > 0.0:
			n = -n
		var other := state.get_contact_collider_object(i)
		var other_vel := Vector3.ZERO
		if other is RigidBody3D:
			other_vel = (other as RigidBody3D).linear_velocity
		var speed := -(_prev_velocity - other_vel).dot(n)
		if speed > 0.6:
			_pending_impacts.append([n, speed, other])
		if sticky_walls and not held and other is StaticBody3D and (other as Node).is_in_group("room_walls"):
			stick_timer = 0.6

	if stick_timer > 0.0 and not held:
		stick_timer -= dt
		# Cancel gravity and most motion: the jelly clings, then slowly lets go.
		state.linear_velocity *= 0.85
		state.apply_central_force(-state.total_gravity * mass * clampf(stick_timer / 0.6, 0.0, 1.0))

	_prev_velocity = state.linear_velocity
	_prev_ang_velocity = state.angular_velocity


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)
	if _pending_impacts.is_empty():
		return
	# Use the strongest contact this step.
	var best: Array = _pending_impacts[0]
	for imp in _pending_impacts:
		if imp[1] > best[1]:
			best = imp
	_pending_impacts.clear()
	var speed: float = best[1]
	if _impact_cooldown > 0.0 and speed < 3.0:
		return
	_impact_cooldown = 0.08
	var n: Vector3 = best[0]
	var softness := lerpf(1.5, 0.5, data.stiffness)
	var amount := clampf(speed * data.impact_squash_per_speed * softness, 0.0, data.max_deformation)
	_kick_impact(_dir_to_mesh_local(n), amount)
	impacted.emit(self, speed)


func _process(delta: float) -> void:
	if _material == null:
		return
	# Speeds stay in world m/s; only directions are converted to mesh space.
	var local_vel := _dir_to_mesh_local(linear_velocity) * linear_velocity.length()
	var local_acc := _dir_to_mesh_local(_accel) * minf(_accel.length(), 120.0)
	var local_ang := _dir_to_mesh_local(_ang_accel) * minf(_ang_accel.length(), 200.0)
	if held:
		local_acc *= 0.5
	springs.update(delta, local_acc, local_ang, local_vel, data)
	springs.apply_to(_material, _mesh_radius)


# ------------------------------------------------------------------ helpers

## Impact flatten anchored on the mesh's actual surface on the contact side, so
## long shapes (dolphin) flatten against the floor instead of sinking into it.
func _kick_impact(local_normal: Vector3, amount: float) -> void:
	springs.add_impact(local_normal, amount)
	var n := springs.impact_normal
	var half := _mesh_aabb.size * 0.5
	var centre := _mesh_aabb.get_center()
	var support := absf(n.x) * half.x + absf(n.y) * half.y + absf(n.z) * half.z
	springs.impact_anchor = n * (centre.dot(n) - support)


func _to_mesh_local(world_point: Vector3) -> Vector3:
	return mesh_instance.global_transform.affine_inverse() * world_point


## World direction -> unit local direction (rotation only).
func _dir_to_mesh_local(world_dir: Vector3) -> Vector3:
	if world_dir.length_squared() < 1e-10:
		return Vector3.ZERO
	return (mesh_instance.global_transform.basis.orthonormalized().inverse() * world_dir).normalized()


## World vector -> local vector keeping length in mesh-local units.
func _dir_to_mesh_local_scaled(world_vec: Vector3) -> Vector3:
	return mesh_instance.global_transform.basis.inverse() * world_vec
