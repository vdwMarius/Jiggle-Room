// Room walls / floor / ceiling: cheap procedural patterns so themes need no
// texture files. Patterns are computed in world space so walls of any size
// tile seamlessly when the room is resized.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.9, 0.85, 0.8, 1.0);
uniform vec4 color_b : source_color = vec4(0.8, 0.75, 0.7, 1.0);
uniform int pattern = 0; // matches RoomTheme.Pattern
uniform float pattern_scale = 1.0;
uniform bool use_texture = false;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness_value = 0.8;
uniform float time_scale = 1.0;

varying vec3 wpos;
varying vec3 wnormal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Planar projection onto the surface's dominant axis.
	vec3 an = abs(wnormal);
	vec2 uv = an.y > 0.5 ? wpos.xz : (an.x > 0.5 ? wpos.zy : wpos.xy);
	uv *= pattern_scale;
	float m = 0.0;
	vec3 extra = vec3(0.0);
	if (pattern == 1) { // stripes (wallpaper)
		m = step(0.5, fract(uv.x * 2.5));
	} else if (pattern == 2) { // checker (playroom)
		vec2 c = floor(uv * 2.0);
		m = mod(c.x + c.y, 2.0);
	} else if (pattern == 3) { // wooden planks
		float row = floor(uv.y * 4.0);
		float off = hash12(vec2(row, 1.0));
		float plank = floor(uv.x * 1.0 + off * 3.0);
		m = hash12(vec2(plank, row)) * 0.7 + 0.15 * sin(uv.x * 40.0 + row * 7.0);
		m *= step(0.04, fract(uv.y * 4.0));
	} else if (pattern == 4) { // aquarium caustics
		vec2 p = uv * 3.0;
		float t = TIME * 0.6 * time_scale;
		float c = sin(p.x + t + sin(p.y * 1.3 + t)) + sin(p.y * 1.1 - t * 0.8 + sin(p.x * 0.9 - t));
		m = smoothstep(1.2, 1.9, c);
	} else if (pattern == 5) { // space-station panels
		vec2 f = fract(uv * vec2(1.0, 1.5));
		m = 1.0 - step(0.03, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		extra = vec3(0.1, 0.4, 0.6) * step(0.92, hash12(floor(uv * vec2(1.0, 1.5)))) * step(0.85, f.x) * step(0.8, f.y);
	} else if (pattern == 6) { // stars
		vec2 cell = floor(uv * 6.0);
		float h = hash12(cell);
		vec2 f = fract(uv * 6.0) - 0.5;
		m = step(0.9, h) * smoothstep(0.08, 0.0, length(f));
	} else if (pattern == 7) { // polka dots
		vec2 f = fract(uv * 3.0) - 0.5;
		m = smoothstep(0.2, 0.18, length(f));
	}
	vec3 col = mix(color_a.rgb, color_b.rgb, m);
	if (use_texture) {
		col *= texture(tex, uv * 0.5).rgb;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	EMISSION = extra + (pattern == 6 ? color_b.rgb * m * 1.5 : vec3(0.0));
}
