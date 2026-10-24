shader_type canvas_item;
render_mode unshaded;
// Final colour grade over the world (not the HUD): split toning (cool shadows,
// warm highlights), a gentle film curve, lifted blacks, vignette and grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec3 shadow_tint = vec3(0.88, 0.98, 1.06);
uniform vec3 highlight_tint = vec3(1.07, 1.0, 0.88);
uniform vec3 lift = vec3(0.018, 0.022, 0.03);
uniform float contrast = 0.35;
uniform float saturation = 0.92;
uniform float vignette = 0.42;
uniform float grain = 0.022;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 over = max(c - 1.0, vec3(0.0));
	c = min(c, vec3(1.0));
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c *= mix(shadow_tint, highlight_tint, smoothstep(0.08, 0.7, l));
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);
	float l2 = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l2), c, saturation);
	c = c * (1.0 - lift) + lift;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.82);
	c *= clamp(1.0 - dot(d, d) * vignette * 2.2, 0.0, 1.0);
	c += (hash12(SCREEN_UV * vec2(1913.0, 1171.0) + fract(TIME * 7.0) * 91.0) - 0.5) * grain;
	COLOR = vec4(c + over, 1.0);
}
