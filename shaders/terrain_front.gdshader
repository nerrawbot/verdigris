shader_type canvas_item;
// Play-layer geometry: rock with ragged edges, chamfered concrete, rusted metal,
// moss on top faces, lit rims and dark interiors.

#include "res://shaders/common.gdshaderinc"

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = world;
	float rf = rock_field(w);
	float bf = built_field(w);
	float aa = 0.06;
	float rock = smoothstep(0.5 - aa, 0.5 + aa, rf);
	float built = step(0.5, bf);
	float a = max(rock, built);
	if (a < 0.01) {
		discard;
	}
	bool is_built = built > 0.5 && bf - 0.5 >= rf - 0.5 - 0.15;
	vec4 ra = texture(reg_a, muv(w));
	float rb = texture(reg_b, muv(w)).r;

	// field gradient -> outward normal and distance to the edge in px
	float e = 1.5;
	float fx, fy, fc;
	if (is_built) {
		fc = texture(map_a, muv(w)).g;
		fx = texture(map_a, muv(w + vec2(e, 0.0))).g - texture(map_a, muv(w - vec2(e, 0.0))).g;
		fy = texture(map_a, muv(w + vec2(0.0, e))).g - texture(map_a, muv(w - vec2(0.0, e))).g;
	} else {
		fc = rf;
		fx = rock_field(w + vec2(e, 0.0)) - rock_field(w - vec2(e, 0.0));
		fy = rock_field(w + vec2(0.0, e)) - rock_field(w - vec2(0.0, e));
	}
	vec2 g = vec2(fx, fy) / (2.0 * e);
	float gl = length(g) + 1e-4;
	float edge_px = (fc - 0.5) / gl;
	vec2 nrm = -g / gl;                       // points out of the solid
	float near_edge = 1.0 - smoothstep(0.0, 5.0, edge_px);

	float depth = texture(map_b, muv(w)).r * 255.0 / 32.0;   // tiles into solid
	vec3 col;
	if (is_built) {
		col = PAL(pal_built, ra, rb);
		bool metal = texture(map_c, muv(w)).r > 0.5;
		// panels, seams, stains
		vec2 pp = w / vec2(tile * 3.0, tile * 2.0);
		vec2 pf = fract(pp);
		float seam = 1.0 - smoothstep(0.0, 0.035, min(min(pf.x, 1.0 - pf.x), min(pf.y, 1.0 - pf.y)) );
		float streak = fbm(vec2(w.x * 0.18, w.y * 0.012));
		col *= 1.0 + (vnoise(floor(pp) * 3.1) - 0.5) * 0.3 * near_edge;
		col *= 1.0 - seam * 0.35;
		col *= 0.75 + 0.45 * streak;
		if (metal) {
			col = mix(col, vec3(0.42, 0.22, 0.13), 0.65 * (1.0 - smoothstep(6.0, 28.0, edge_px)));
			float rivet = 1.0 - smoothstep(1.0, 1.8, length(fract(w / 8.0) * 8.0 - 4.0));
			col += rivet * 0.06 * step(0.7, pf.y);
			col *= 0.8 + 0.4 * fbm(w * 0.07);
		}
	} else {
		col = PAL(pal_rock, ra, rb);
		float strata = fbm(vec2(w.x * 0.012, w.y * 0.07));
		float grain = fbm(w * 0.21);
		float crack = smoothstep(0.035, 0.0, abs(fbm(w * 0.03 + 4.0) - 0.5));
		col *= 0.7 + 0.5 * strata;
		col *= 0.85 + 0.3 * grain;
		col *= 1.0 - crack * 0.4;
	}

	// interiors fall away into darkness, edges catch the sky
	float dark = smoothstep(0.8, 6.0, depth + edge_px / tile * 0.6);
	col *= mix(1.0, 0.36, dark);
	float up = clamp(-nrm.y, 0.0, 1.0);
	float rim = near_edge * (0.25 + 0.75 * up);
	col += PAL(pal_fog, ra, rb) * rim * 0.3 * sky_tint;
	col *= 1.0 - (1.0 - smoothstep(0.0, 1.4, edge_px)) * 0.35 * (1.0 - up);

	// moss creeps over top faces and a little down the sides
	float moss = texture(map_a, muv(w)).a;
	if (moss > 0.01) {
		float tuft = fbm(w * 0.25 + 3.0);
		float band = (1.0 - smoothstep(2.0 + tuft * 7.0, 4.0 + tuft * 9.0, edge_px)) * up;
		band += (1.0 - smoothstep(0.0, 2.5 + tuft * 3.0, edge_px)) * (1.0 - up) * 0.5;
		float m = clamp(band * moss * (0.6 + tuft), 0.0, 1.0);
		vec3 mc = PAL(pal_moss, ra, rb) * (0.75 + 0.5 * vnoise(w * 0.6));
		col = mix(col, mc, m);
	}
	// a fine dark contour so the play layer reads cleanly against the walls
	col *= mix(0.55, 1.0, smoothstep(0.0, 1.1, edge_px));
	// crumbs and pebbles along top faces
	float crumb = step(0.86, hash12(floor(w / 2.0))) * (1.0 - smoothstep(1.0, 4.0, edge_px)) * up;
	col = mix(col, col * 0.55, crumb);
	// a warm rim where an edge faces the sun and the light reaches it
	float facing = clamp(dot(nrm, -sun_dir) * 1.4 + 0.1, 0.0, 1.0);
	float s_edge = sun_at(w + nrm * 5.0) * sun_strength * facing;
	float rim_band = 1.0 - smoothstep(0.0, 3.5 + fbm(w * 0.3) * 3.0, edge_px);
	col += sun_col * s_edge * rim_band * 0.55;
	col = mix(col, col * sun_col * 1.3, s_edge * (1.0 - smoothstep(0.0, 12.0, edge_px)) * 0.5);
	COLOR = vec4(col, a);
	NORMAL = normalize(vec3(nrm * near_edge * 0.9, 1.0));
}
