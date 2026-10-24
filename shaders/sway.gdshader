shader_type canvas_item;
// Foliage meshes: UV.y is how far a vertex is from its root, so tips sway.

uniform float wind = 0.2;
uniform float glow = 1.0;   // night boost for emissive vertices (UV.x > 0.5)

void vertex() {
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float s = UV.y;
	float t = TIME * (1.1 + wind * 1.5);
	VERTEX.x += (sin(t + wp.x * 0.045 + wp.y * 0.02) * 1.6 + sin(t * 2.3 + wp.x * 0.13) * 0.6) * s * (0.6 + wind * 3.0);
	VERTEX.y += sin(t * 1.7 + wp.x * 0.07) * 0.4 * s;
	if (UV.x > 0.5) {
		COLOR.rgb *= glow;
	}
}
