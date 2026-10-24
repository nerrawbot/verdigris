shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
// Over the play layer: drifting mist, shafts of sunlight with dust turning in
// them, and rain where the sky is open.

#include "res://shaders/common.gdshaderinc"

uniform float rain = 0.0;
uniform float mist = 0.25;
uniform vec3 ambient = vec3(1.0);
uniform vec3 rain_col = vec3(0.75, 0.82, 0.9);
uniform float wind = 0.15;
uniform float shaft_amount = 1.0;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = world;
	vec4 ra = texture(reg_a, muv(w));
	float rb = texture(reg_b, muv(w)).r;
	vec3 fog = PAL(pal_fog, ra, rb) * sky_tint;
	float m = fbm(w * 0.004 + vec2(TIME * 0.01, TIME * 0.004));
	float m2 = fbm(w * 0.011 - vec2(TIME * 0.018, 0.0));
	float sky = texture(map_b, muv(w)).a;
	float mist_a = mist * smoothstep(0.35, 0.85, m * 0.6 + m2 * 0.5) * 0.35;
	vec3 col = fog * mist_a;
	float alpha = mist_a;
	// light shafts: only in open air, streaked along the beam, breathing slowly
	float air = 1.0 - smoothstep(0.42, 0.58, solid_raw(w));
	if (air > 0.01 && shaft_amount > 0.01) {
		float s = sun_at(w) * air;
		if (s > 0.01) {
			vec2 across = vec2(-sun_dir.y, sun_dir.x);
			float a_pos = dot(w, across);
			float l_pos = dot(w, sun_dir);
			float streak = 0.45 + 0.55 * vnoise(vec2(a_pos * 0.035, l_pos * 0.0015 - TIME * 0.04));
			streak *= 0.8 + 0.2 * sin(TIME * 0.3 + a_pos * 0.01);
			float haze = (0.35 + 0.65 * m2);
			// shafts read best indoors, against a wall; out in the open they are only a haze
			float walled = smoothstep(0.2, 0.4, texture(map_a, muv(w)).b);
			float shaft = s * streak * haze * shaft_amount * mix(0.05, 0.24, walled);
			// dust motes turning slowly in the light
			vec2 dw = w + vec2(TIME * 4.0, sin(TIME * 0.4) * 6.0);
			vec2 cell = floor(dw / 11.0);
			float h = hash12(cell);
			vec2 off = vec2(hash12(cell + 3.1), hash12(cell + 7.7)) - 0.5;
			float d = length(fract(dw / 11.0) - 0.5 - off * 0.6) * 11.0;
			float mote = step(0.93, h) * smoothstep(1.3, 0.2, d) * (0.5 + 0.5 * sin(TIME * 1.7 + h * 40.0)) * walled;
			vec3 light = sun_col / max(ambient, vec3(0.25));
			col += light * (shaft + mote * s * 0.55);
			alpha += shaft * 0.5 + mote * s * 0.3;
		}
	}
	// openings in the back wall glow with the daylight that comes through them
	float backv = texture(map_a, muv(w)).b;
	float around = 0.0;
	for (int k = 0; k < 4; k++) {
		vec2 o = vec2(cos(float(k) * 1.5708), sin(float(k) * 1.5708)) * 56.0;
		around += step(0.25, texture(map_a, muv(w + o)).b);
	}
	float hole = (1.0 - smoothstep(0.04, 0.4, backv)) * smoothstep(1.5, 3.5, around) * air;
	if (hole > 0.01 && shaft_amount > 0.01) {
		vec3 light = sun_col / max(ambient, vec3(0.25));
		float g = hole * shaft_amount * (0.3 + 0.3 * m);
		col += light * g * 0.16;
		alpha += g * 0.06;
	}
	if (rain > 0.001) {
		vec2 rp = w + vec2(w.y * wind, 0.0);
		float lane = floor(rp.x / 3.0);
		float speed = 900.0 + hash12(vec2(lane, 1.0)) * 500.0;
		float len = 18.0 + hash12(vec2(lane, 2.0)) * 26.0;
		float y = rp.y + TIME * speed + hash12(vec2(lane, 3.0)) * 1000.0;
		float seg = fract(y / 260.0) * 260.0;
		float drop = step(seg, len) * step(hash12(vec2(lane, floor(y / 260.0))), rain * 0.55);
		drop *= smoothstep(0.0, 1.0, fract(rp.x / 3.0) * 2.0) * smoothstep(0.0, 1.0, (1.0 - fract(rp.x / 3.0)) * 2.0);
		float s = smoothstep(0.2, 0.9, sky);
		float ra2 = drop * s * 0.35;
		col += rain_col * ra2;
		alpha += ra2;
		col += fog * rain * s * 0.08;
		alpha += rain * s * 0.08;
	}
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
