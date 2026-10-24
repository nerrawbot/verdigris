// Shared helpers for the terrain shaders.

uniform sampler2D map_a : filter_linear, repeat_disable;   // r rock, g built, b back, a moss
uniform sampler2D map_b : filter_linear, repeat_disable;   // r solid depth, g air dist, b water depth, a sky
uniform sampler2D map_c : filter_nearest, repeat_disable;  // r metal, g grate, b region
uniform sampler2D reg_a : filter_linear, repeat_disable;
uniform sampler2D reg_b : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(440.0, 256.0);
uniform float tile = 16.0;

uniform vec3 pal_rock[5];
uniform vec3 pal_built[5];
uniform vec3 pal_moss[5];
uniform vec3 pal_back[5];
uniform vec3 pal_fog[5];
uniform vec3 sky_tint = vec3(1.0);
uniform float fog_amount = 0.45;
uniform sampler2D sun_map : filter_linear, repeat_disable;  // baked rays (see worldgen._sunlight)
uniform vec3 sun_col = vec3(1.0, 0.88, 0.66);
uniform float sun_strength = 1.0;
uniform vec2 sun_dir = vec2(0.41, 0.912);                   // direction the light travels

varying vec2 world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

vec2 muv(vec2 w) {
	return w / (tile * map_size);
}

vec4 region_w(vec2 w) {
	return texture(reg_a, muv(w));
}

vec3 blend5(vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec4 a, float b) {
	float s = a.r + a.g + a.b + a.a + b + 0.0001;
	return (c0 * a.r + c1 * a.g + c2 * a.b + c3 * a.a + c4 * b) / s;
}

#define PAL(P, A, B) blend5(P[0], P[1], P[2], P[3], P[4], A, B)

// Smoothed solid fields with a noisy edge for rock, a chamfered one for built.
float rock_field(vec2 w) {
	float f = texture(map_a, muv(w)).r;
	return f + (fbm(w * 0.09) - 0.5) * 0.34;
}

float built_field(vec2 w) {
	float f = texture(map_a, muv(w)).g;
	return f + (vnoise(w * 0.35) - 0.5) * 0.07;
}

float solid_field(vec2 w) {
	return max(rock_field(w), built_field(w));
}

float solid_raw(vec2 w) {
	vec4 a = texture(map_a, muv(w));
	return max(a.r, a.g);
}

// Sunlight at a point: the baked tile rays, sharpened by a short march back
// towards the light so shadows near stone have crisp slanted edges.
float sun_at(vec2 w) {
	// three taps across the beam soften the stepped edges of the baked rays
	vec2 across = vec2(-sun_dir.y, sun_dir.x) * 5.0;
	vec2 c = w + sun_dir * 6.0;
	float baked = (texture(sun_map, muv(c)).r * 2.0 + texture(sun_map, muv(c + across)).r + texture(sun_map, muv(c - across)).r) * 0.25;
	if (baked < 0.01) {
		return 0.0;
	}
	float lit = 1.0;
	for (int i = 1; i <= 8; i++) {
		lit = min(lit, smoothstep(0.62, 0.4, solid_raw(w - sun_dir * float(i) * 6.0)));
	}
	return clamp(baked * 1.15, 0.0, 1.0) * lit;
}
