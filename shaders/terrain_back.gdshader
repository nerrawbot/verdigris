shader_type canvas_item;
// Back layer: the walls behind the play space, fogged, with the front layer's
// shadow cast on them. Open patches are transparent so the far layers show.

#include "res://shaders/common.gdshaderinc"

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = world;
	float b = texture(map_a, muv(w)).b;
	float edge = fbm(w * 0.05) * 0.25;
	float a = smoothstep(0.2, 0.32, b + edge - 0.1);
	if (a < 0.01) {
		discard;
	}
	vec4 ra = texture(reg_a, muv(w));
	float rb = texture(reg_b, muv(w)).r;
	vec3 col = PAL(pal_back, ra, rb);
	// the wall has thickness: shade it where it breaks open
	float bmax = b;
	for (int k = 0; k < 4; k++) {
		vec2 o = vec2(cos(float(k) * 1.5708), sin(float(k) * 1.5708)) * 22.0;
		bmax = max(bmax, texture(map_a, muv(w + o)).b);
	}
	float rim = 1.0 - smoothstep(0.55, 0.95, b / max(bmax, 0.01));
	bool built = b > 0.75;
	if (built) {
		// big panels, horizontal pipe runs and vertical ribs
		vec2 pp = w / vec2(tile * 6.0, tile * 4.0);
		vec2 pf = fract(pp);
		float seam = 1.0 - smoothstep(0.0, 0.02, min(min(pf.x, 1.0 - pf.x), min(pf.y, 1.0 - pf.y)));
		col *= 0.8 + 0.35 * vnoise(floor(pp) * 2.7);
		col *= 1.0 - seam * 0.4;
		float row = floor(w.y / (tile * 5.0));
		float has_pipe = step(0.55, hash12(vec2(row, 3.0)));
		float py = fract(w.y / (tile * 5.0));
		float pipe = smoothstep(0.08, 0.0, abs(py - 0.3)) * has_pipe;
		col = mix(col, col * 1.35 + vec3(0.02), pipe * (0.5 + 0.5 * smoothstep(0.03, 0.0, abs(py - 0.27))));
		float rib = step(0.93, fract(w.x / (tile * 9.0)));
		col *= 1.0 - rib * 0.25;
		col *= 0.8 + 0.35 * fbm(vec2(w.x * 0.2, w.y * 0.01));
	} else {
		float strata = fbm(vec2(w.x * 0.008, w.y * 0.05));
		col *= 0.65 + 0.6 * strata;
		col *= 0.85 + 0.3 * fbm(w * 0.12);
		float vein = smoothstep(0.03, 0.0, abs(fbm(w * 0.02 + 9.0) - 0.5));
		col *= 1.0 - vein * 0.3;
	}
	// ambient occlusion near the play layer and its cast shadow (light from above-left)
	float ad = texture(map_b, muv(w)).g * 255.0 / 36.0;
	col *= mix(0.45, 1.0, smoothstep(0.0, 2.5, ad));
	float sh = 0.0;
	sh += step(0.5, solid_field(w + vec2(-5.0, -9.0)));
	sh += step(0.5, solid_field(w + vec2(-10.0, -18.0)));
	sh += step(0.5, solid_field(w + vec2(-16.0, -28.0)));
	col *= 1.0 - sh * 0.15;
	col *= 1.0 - rim * 0.55;
	// sunlight falling across the wall in slanted bars
	float s = sun_at(w) * sun_strength;
	col = mix(col * 0.8, col * sun_col * 1.7 + sun_col * 0.04, s);
	// fog, thinner where the light is
	vec3 fog = PAL(pal_fog, ra, rb) * sky_tint;
	col = mix(col, fog, fog_amount * (1.0 - 0.45 * s));
	COLOR = vec4(col, a);
}
