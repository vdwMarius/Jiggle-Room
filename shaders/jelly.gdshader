// Jiggle Room - the one jelly shader.
//
// Motion comes from the RigidBody3D; all the "jelly" is faked here in the vertex
// stage from a handful of spring values the CPU integrates every frame
// (see scripts/jelly/jelly_springs.gd). Every vector uniform is in the mesh's
// LOCAL space so the shader never needs per-object matrices.
//
// Vertex colour RED = floppiness weight painted in Blender
// (1 = floppy fin/tail/tentacle, 0 = rigid core).
//
// Transparency: the jelly reads the screen behind it (refraction) and blends
// it in manually, then writes depth. That puts it in the transparent pass for
// the screen copy but produces a fully resolved colour per pixel, so there is
// no back-to-front sorting inside a mesh and no flicker on concave shapes.
// Trade-off: a jelly seen through another jelly is not visible through it.

shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

#define MAX_RIPPLES 8

// ---------------- look ----------------
uniform vec4 base_color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform vec4 gradient_color : source_color = vec4(1.0, 0.45, 0.75, 1.0);
uniform float gradient_amount : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.1, 1.0) = 0.55;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.9;
uniform float inner_glow : hint_range(0.0, 2.0) = 0.35;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.05;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
uniform float glitter_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow_in_dark : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// ---------------- deformation ----------------
uniform float jelly_time = 0.0;          // own clock: freezes in photo mode, slows in slow-mo
uniform float bound_radius = 0.5;        // mesh-local radius
uniform float max_deform = 0.28;         // fraction of bound_radius
uniform float core_floppiness = 0.25;    // weight of black (rigid) vertices

uniform vec4 ripple_origin[MAX_RIPPLES]; // xyz = local origin, w = start time (<0 = unused)
uniform float ripple_amp[MAX_RIPPLES];   // local units
uniform float ripple_freq = 50.0;        // rad/s
uniform float ripple_decay = 3.0;        // 1/s
uniform float ripple_wavenumber = 22.0;  // rad per local unit

uniform vec3 grab_point = vec3(0.0);     // where the finger grabbed
uniform vec3 grab_offset = vec3(0.0);    // spring-driven pull toward the finger
uniform float grab_radius = 0.3;

uniform vec3 stretch_axis = vec3(0.0, 1.0, 0.0);
uniform float stretch_amount = 0.0;      // >0 elongate along axis, <0 squash (volume kept)

uniform vec3 lag_offset = vec3(0.0);     // secondary-motion trail of floppy parts
uniform vec3 lag_twist = vec3(0.0);      // axis * angle, rotational trail

uniform vec3 impact_normal = vec3(0.0, 1.0, 0.0); // points from the wall into the jelly
uniform float impact_amount = 0.0;       // >0 flattened, <0 rebound bulge
uniform vec3 impact_anchor = vec3(0.0, -0.5, 0.0); // point on the contact side that stays put

// Ground frame: the classic "gelatin on a plate" wobble. The base stays put,
// the top sways side to side, and the body sags a little under its own weight.
uniform vec3 ground_up = vec3(0.0, 1.0, 0.0);      // local "up" (against gravity)
uniform vec3 ground_anchor = vec3(0.0, -0.5, 0.0); // lowest point of the mesh along ground_up
uniform float body_height = 1.0;                    // mesh extent along ground_up
uniform float sag = 0.0;                            // >0 squashed by weight (volume kept)
uniform vec3 sway = vec3(0.0);                      // top displacement / body_height (tangent)

uniform vec3 wobble2_axis = vec3(1.0, 0.0, 0.0);   // second, faster wobble mode
uniform float wobble2 = 0.0;

varying vec3 v_local;
varying float v_weight;

vec3 rotate_axis(vec3 v, vec3 axis, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

// Volume-preserving scale by `k` along unit axis `a`, around point `c`.
vec3 axis_scale(vec3 p, vec3 c, vec3 a, float k) {
	vec3 rel = p - c;
	float along = dot(rel, a);
	vec3 perp = rel - a * along;
	return c + a * along * k + perp * inversesqrt(k);
}

// Matching normal transform (inverse transpose of the scale above).
vec3 axis_scale_normal(vec3 n, vec3 a, float k) {
	float along = dot(n, a);
	vec3 perp = n - a * along;
	return normalize(a * along / k + perp * sqrt(k));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	vec3 rest = VERTEX;
	vec3 p = VERTEX;
	vec3 n = NORMAL;
	float w = mix(core_floppiness, 1.0, COLOR.r);
	v_local = rest;
	v_weight = w;

	// 1. Impact: flatten against the contact normal, anchored on the contact side.
	if (abs(impact_amount) > 0.0001) {
		float k = clamp(1.0 - impact_amount, 0.55, 1.6);
		p = axis_scale(p, impact_anchor, impact_normal, k);
		n = axis_scale_normal(n, impact_normal, k);
	}

	// 1b. Weight sag + faster secondary wobble mode (both volume preserving).
	if (abs(sag) > 0.0001) {
		float k = clamp(1.0 - sag, 0.6, 1.5);
		p = axis_scale(p, ground_anchor, ground_up, k);
		n = axis_scale_normal(n, ground_up, k);
	}
	if (abs(wobble2) > 0.0001) {
		float k = clamp(1.0 + wobble2, 0.7, 1.4);
		p = axis_scale(p, vec3(0.0), wobble2_axis, k);
		n = axis_scale_normal(n, wobble2_axis, k);
	}

	// 1c. Sway: shear that grows with height above the base (h^1.5), so the
	// bottom stays planted and the top wobbles side to side.
	if (dot(sway, sway) > 1e-8) {
		float h = clamp(dot(p - ground_anchor, ground_up) / body_height, 0.0, 1.3);
		float f = pow(h, 1.5);
		float df = 1.5 * sqrt(h) / body_height;
		vec3 s = sway * body_height * mix(0.75, 1.0, w);
		p += s * f;
		// Inverse-transpose of the shear for the normal.
		n = normalize(n - ground_up * dot(s, n) * df);
	}

	// 2. Squash & stretch along velocity (volume preserving).
	if (abs(stretch_amount) > 0.0001) {
		float k = clamp(1.0 + stretch_amount, 0.6, 1.6);
		p = axis_scale(p, vec3(0.0), stretch_axis, k);
		n = axis_scale_normal(n, stretch_axis, k);
	}

	// 3. Secondary motion: floppy, far-from-centre vertices trail and overshoot.
	float reach = clamp(length(rest) / bound_radius, 0.0, 1.5);
	float lw = (w - core_floppiness * 0.5) * reach * reach;
	p += lag_offset * lw;
	float twist = length(lag_twist) * lw;
	if (twist > 0.0001) {
		vec3 axis = normalize(lag_twist);
		p = rotate_axis(p, axis, twist);
		n = rotate_axis(n, axis, twist);
	}

	// 4. Grab: gaussian pull toward the finger.
	vec3 gd = rest - grab_point;
	float gf = exp(-dot(gd, gd) / (grab_radius * grab_radius));
	p += grab_offset * gf * mix(0.65, 1.0, w);

	// 5. Ripples: amp * exp(-decay*t) * sin(freq*t - dist*k) along the normal.
	float disp = 0.0;
	vec3 slope = vec3(0.0);
	float wave_speed = ripple_freq / ripple_wavenumber;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 o = ripple_origin[i];
		if (o.w < 0.0) {
			continue;
		}
		float t = jelly_time - o.w;
		if (t < 0.0) {
			continue;
		}
		vec3 to_v = rest - o.xyz;
		float d = length(to_v);
		// Only the part of the surface the wavefront has reached moves.
		float front = clamp((wave_speed * t - d) * ripple_wavenumber * 0.5 + 1.0, 0.0, 1.0);
		float env = ripple_amp[i] * exp(-ripple_decay * t) * front;
		float phase = ripple_freq * t - d * ripple_wavenumber;
		disp += env * sin(phase);
		// d(disp)/d(dist), used to tilt the normal so ripples catch the light.
		float deriv = -env * cos(phase) * ripple_wavenumber;
		vec3 tangent = to_v - NORMAL * dot(to_v, NORMAL);
		float tl = length(tangent);
		if (tl > 0.0001) {
			slope += tangent / tl * deriv;
		}
	}
	float ripple_w = mix(0.55, 1.0, w);
	p += NORMAL * disp * ripple_w;
	n = normalize(n - slope * ripple_w);

	// 6. Never mushy: softly cap the total displacement (~25-30% of radius).
	vec3 delta = p - rest;
	float len = length(delta);
	float cap = max_deform * bound_radius;
	if (len > 0.0001) {
		p = rest + delta * (cap * tanh(len / cap) / len);
	}

	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power);

	float grad_t = smoothstep(-bound_radius, bound_radius, v_local.y);
	vec3 col = mix(base_color.rgb, gradient_color.rgb, gradient_amount * grad_t);

	// Refraction: bend the room behind by the view-space normal; thicker in the middle.
	vec2 ruv = SCREEN_UV - NORMAL.xy * refraction_strength * (0.4 + ndv);
	vec3 behind = texture(screen_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb;
	vec3 tinted_behind = behind * mix(vec3(1.0), col, 0.45 + 0.4 * opacity);

	// Body colour is lit normally; the see-through part is added unlit so
	// the room behind is not double-shaded.
	float body = clamp(opacity + fres * 0.35, 0.0, 1.0);
	ALBEDO = col * body;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
	// Light passing through thin edges: cheap subsurface look (works on Mobile).
	BACKLIGHT = col * 0.45;

	vec3 emission = tinted_behind * (1.0 - body);
	// Subsurface-style inner glow: brightest where the jelly is "thick".
	emission += col * inner_glow * ndv * ndv * (0.4 + 0.6 * v_weight) * 0.5;
	// Fresnel rim.
	emission += mix(col, vec3(1.0), 0.6) * fres * rim_strength * 0.6;
	// Glow in the dark.
	emission += col * glow_in_dark * 1.6;

	// Glitter: tiny random facets that twinkle as the view or the jelly moves.
	if (glitter_amount > 0.0) {
		vec3 cell = floor(v_local * 70.0);
		float h = hash13(cell);
		vec3 facet = normalize(vec3(hash13(cell + 1.7), hash13(cell + 5.3), hash13(cell + 9.1)) - 0.5);
		float sparkle = pow(max(dot(normalize(NORMAL + facet * 0.8), VIEW), 0.0), 60.0);
		sparkle *= step(1.0 - glitter_amount * 0.35, h);
		emission += vec3(1.0, 0.97, 0.9) * sparkle * 4.0;
	}

	EMISSION = emission;
}
