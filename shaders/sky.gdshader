shader_type canvas_item;
render_mode unshaded;
// Screen-covering sky. Above the works it is weather and daylight; lower down
// it sinks into the fogged abyss behind everything.

uniform vec3 top_col = vec3(0.35, 0.5, 0.7);
uniform vec3 horizon_col = vec3(0.8, 0.82, 0.85);
uniform vec3 abyss_col = vec3(0.06, 0.08, 0.1);
uniform vec3 sun_col = vec3(1.0, 0.9, 0.7);
uniform vec2 sun_dir = vec2(0.3, 0.2);   // screen-space position of the sun/moon glow (0..1)
uniform float sun_amount = 0.6;
uniform float cloud_amount = 0.5;
uniform float star_amount = 0.0;
uniform float cam_y = 0.0;      // camera centre in world px
uniform float horizon_y = 1100.0;
uniform float abyss_y = 2400.0;
uniform float view_h = 720.0;
uniform float water_y = 3264.0;   // below the flooded line, openings look into deep water

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

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// world y squashed: the sky moves slowly as you climb
	float wy = cam_y * 0.35 + (UV.y - 0.5) * view_h;
	float t = clamp(wy / horizon_y, 0.0, 1.0);
	vec3 col = mix(top_col, horizon_col, pow(t, 1.4));
	float ab = smoothstep(horizon_y * 0.85, abyss_y, wy);
	col = mix(col, abyss_col, ab);
	vec2 uv = UV;
	float d = length((uv - sun_dir) * vec2(1.6, 1.0));
	col += sun_col * sun_amount * (exp(-d * 6.0) * 0.7 + exp(-d * 30.0) * 1.2) * (1.0 - ab);
	// slow cloud bands
	vec2 cp = vec2(uv.x * 3.0 + TIME * 0.006 + world.x * 0.0004, wy * 0.004);
	float cl = vnoise(cp * vec2(1.0, 3.0)) * 0.6 + vnoise(cp * vec2(2.3, 7.0)) * 0.4;
	col = mix(col, horizon_col * 1.05, smoothstep(0.5, 0.85, cl) * cloud_amount * (1.0 - ab) * 0.5);
	// a soft breath of light deep down, so openings feel like distance, not paint
	col *= 1.0 + ab * (vnoise(world * 0.004 + TIME * 0.02) - 0.5) * 0.25;
	col = mix(col, vec3(0.02, 0.06, 0.08), smoothstep(water_y - 120.0, water_y + 200.0, world.y));
	// stars
	vec2 sp = floor(UV * vec2(420.0, 240.0));
	float st = step(0.996, hash12(sp)) * star_amount * (1.0 - t) * (1.0 - ab);
	col += vec3(st) * (0.6 + 0.4 * sin(TIME * 2.0 + hash12(sp * 1.3) * 20.0));
	COLOR = vec4(col, 1.0);
}
