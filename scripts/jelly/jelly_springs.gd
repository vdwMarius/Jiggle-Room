class_name JellySprings
extends RefCounted
## Damped springs that drive the jelly shader.
##
## Every spring obeys  x'' = -w^2 (x - target) - 2*zeta*w*x' + force
## where w = 2*pi*wobble_frequency and zeta = damping ratio. With zeta ~0.2 an
## impulse rings for 2-4 visible cycles and settles in roughly 4 / (zeta*w)
## seconds (~1-1.2 s at 3.2 Hz) - "firm gelatin dessert".
##
## All vectors are in mesh-local space. Integration is semi-implicit Euler with
## sub-stepping so high frequencies stay stable at any frame rate.

const MAX_RIPPLES := 8

var omega := 20.0
var zeta := 0.2
var stiffness := 0.45

# Squash & stretch along velocity.
var stretch := 0.0
var stretch_vel := 0.0
var stretch_target := 0.0
var stretch_axis := Vector3.UP

# Secondary motion (floppy parts trailing).
var lag := Vector3.ZERO
var lag_vel := Vector3.ZERO
var twist := Vector3.ZERO
var twist_vel := Vector3.ZERO

# Impact flatten / rebound.
var impact := 0.0
var impact_vel := 0.0
var impact_normal := Vector3.UP
var impact_anchor := Vector3(0, -0.5, 0)

# Grab (finger pull).
var grab := Vector3.ZERO
var grab_vel := Vector3.ZERO
var grab_target := Vector3.ZERO
var grab_point := Vector3.ZERO
var grabbing := false

# Ripples: ring buffer.
var ripple_origins := PackedFloat32Array()
var ripple_amps := PackedFloat32Array()
var _next_ripple := 0

var time := 0.0


func _init() -> void:
	ripple_origins.resize(MAX_RIPPLES * 4)
	ripple_amps.resize(MAX_RIPPLES)
	for i in MAX_RIPPLES:
		ripple_origins[i * 4 + 3] = -1.0


func configure(data: JellyData) -> void:
	omega = TAU * data.wobble_frequency
	zeta = data.damping
	stiffness = data.stiffness


func add_ripple(local_origin: Vector3, amplitude: float) -> void:
	var i := _next_ripple
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	ripple_origins[i * 4 + 0] = local_origin.x
	ripple_origins[i * 4 + 1] = local_origin.y
	ripple_origins[i * 4 + 2] = local_origin.z
	ripple_origins[i * 4 + 3] = time
	ripple_amps[i] = amplitude


## Kick the impact spring. `amount` is the flatten fraction (0.1 = 10% flatter).
func add_impact(local_normal: Vector3, amount: float) -> void:
	# If a new hit comes from a very different direction, blend the normal
	# rather than snapping, so a jelly in a corner doesn't pop.
	if absf(impact) > 0.02:
		impact_normal = (impact_normal * absf(impact) + local_normal * amount).normalized()
	else:
		impact_normal = local_normal
	# Give the spring a velocity that peaks at roughly `amount`.
	impact_vel += amount * omega


func update(dt: float, local_accel: Vector3, local_ang_accel: Vector3, local_velocity: Vector3, data: JellyData) -> void:
	if dt <= 0.0:
		return
	time += dt
	var softness := lerpf(1.6, 0.4, stiffness)

	# Stretch target follows speed along the motion direction.
	var speed := local_velocity.length()
	if speed > 0.05:
		var axis := local_velocity / speed
		# Stretch is symmetric, so +axis and -axis are the same shape: pick the
		# closer one, then rotate smoothly so direction changes never snap.
		if stretch_axis.dot(axis) < 0.0:
			axis = -axis
		stretch_axis = stretch_axis.slerp(axis, clampf(dt * 12.0, 0.0, 1.0)).normalized()
	stretch_target = clampf(speed * data.stretch_per_speed * softness, 0.0, data.max_deformation)

	var steps := maxi(1, ceili(dt * omega / 0.35))
	var h := dt / steps
	var w2 := omega * omega
	var c := 2.0 * zeta * omega
	# Lag spring is a touch softer & slower than the body so tips visibly trail.
	var lw := omega * 0.8
	var lw2 := lw * lw
	var lc := 2.0 * zeta * lw
	var lag_drive := -local_accel * data.lag_amount * softness * 0.012
	var twist_drive := -local_ang_accel * data.lag_amount * softness * 0.0025
	for _i in steps:
		stretch_vel += (-w2 * (stretch - stretch_target) - c * stretch_vel) * h
		stretch += stretch_vel * h

		lag_vel += (-lw2 * lag - lc * lag_vel + lag_drive * lw2) * h
		lag += lag_vel * h
		twist_vel += (-lw2 * twist - lc * twist_vel + twist_drive * lw2) * h
		twist += twist_vel * h

		impact_vel += (-w2 * impact - c * impact_vel) * h
		impact += impact_vel * h

		var gt := grab_target if grabbing else Vector3.ZERO
		# Grab follows the finger stiffly (critically damped) and wobbles on release.
		var gc := 2.0 * (1.0 if grabbing else zeta) * omega
		grab_vel += (-w2 * (grab - gt) - gc * grab_vel) * h
		grab += grab_vel * h

	var cap := data.max_deformation
	impact = clampf(impact, -cap * 0.6, cap * 1.3)
	lag = lag.limit_length(cap * 1.5)
	twist = twist.limit_length(0.6)


func is_settled() -> bool:
	return absf(stretch) < 0.002 and absf(stretch_vel) < 0.01 \
		and lag.length_squared() < 1e-6 and lag_vel.length_squared() < 1e-5 \
		and absf(impact) < 0.002 and absf(impact_vel) < 0.01 \
		and grab.length_squared() < 1e-6 and not grabbing


func apply_to(mat: ShaderMaterial, radius: float) -> void:
	mat.set_shader_parameter("jelly_time", time)
	mat.set_shader_parameter("stretch_axis", stretch_axis)
	mat.set_shader_parameter("stretch_amount", stretch)
	mat.set_shader_parameter("lag_offset", lag * radius)
	mat.set_shader_parameter("lag_twist", twist)
	mat.set_shader_parameter("impact_normal", impact_normal)
	mat.set_shader_parameter("impact_amount", impact)
	mat.set_shader_parameter("impact_anchor", impact_anchor)
	mat.set_shader_parameter("grab_point", grab_point)
	mat.set_shader_parameter("grab_offset", grab)
	mat.set_shader_parameter("ripple_origin", ripple_origins)
	mat.set_shader_parameter("ripple_amp", ripple_amps)
