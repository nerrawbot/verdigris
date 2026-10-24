shader_type canvas_item;
render_mode unshaded;
// Water over the play layer: refraction, depth tint, a bright wavy surface
// line (driven by the spring simulation in waves) and drifting caustics.

#include "res://shaders/common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D waves : filter_linear, repeat_disable;
uniform float wave_cols = 880.0;
uniform vec3 ambient = vec3(1.0);
uniform vec3 shallow = vec3(0.12, 0.3, 0.34);
uniform vec3 deep = vec3(0.03, 0.10, 0.17);

float water_at(vec2 w) {
	return texture(map_b, muv(w)).b;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = world;
	float wave = texture(waves, vec2((w.x / 8.0 + 0.5) / wave_cols, 0.5)).r;
	float ripple = sin(w.x * 0.09 + TIME * 1.7) * 0.6 + sin(w.x * 0.21 - TIME * 2.3) * 0.35;
	vec2 ws = w + vec2(0.0, wave + ripple);
	float wa = water_at(ws);
	float thr = 0.039;
	if (wa < thr || solid_field(w) > 0.5 || texture(map_c, muv(ws)).a < 0.5) {
		discard;
	}
	float depth_t = clamp((wa * 255.0 / 20.0), 0.0, 12.0);   // rows below the surface
	// distance below the local surface in px (only meaningful near it)
	float above = water_at(ws - vec2(0.0, 4.0));
	float surf = 1.0 - smoothstep(thr, 0.075, above);
	float line = surf * (1.0 - smoothstep(thr, thr + 0.03, water_at(ws - vec2(0.0, 1.5))));

	vec2 distort = vec2(sin(w.y * 0.08 + TIME * 1.3), cos(w.x * 0.06 + TIME * 1.1)) * 0.004;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + distort, 0.0).rgb;
	float dk = smoothstep(0.0, 7.0, depth_t);
	// the canvas ambient multiplies this output, so undo it on what is already lit behind
	behind /= max(ambient, vec3(0.08));
	vec3 tint = mix(shallow, deep, dk);
	vec3 col = mix(behind * mix(vec3(0.55, 0.78, 0.82), vec3(0.25, 0.42, 0.5), dk), tint, 0.35 + 0.5 * dk);
	// caustics near the surface
	float c1 = vnoise(w * 0.05 + vec2(TIME * 0.5, TIME * 0.2));
	float c2 = vnoise(w * 0.09 - vec2(TIME * 0.3, -TIME * 0.4));
	float caustic = smoothstep(0.55, 0.95, c1 * c2 * 2.2) * (1.0 - smoothstep(0.0, 3.5, depth_t)) * 0.12;
	col += caustic * vec3(0.6, 0.9, 0.9);
	col += surf * 0.06;
	col = mix(col, vec3(0.75, 0.95, 0.95), line * 0.85);
	COLOR = vec4(col, 1.0);
}
