extends RefCounted
## Region colours (Hollows, Pipeworks, Canopy, Sunken, Spire). The terrain shaders
## get these as uniform arrays; foliage meshes use them directly.

const ROCK := [Color(0.4, 0.43, 0.37), Color(0.45, 0.37, 0.3), Color(0.4, 0.33, 0.25), Color(0.29, 0.38, 0.43), Color(0.52, 0.5, 0.55)]
const BUILT := [Color(0.48, 0.48, 0.45), Color(0.56, 0.45, 0.35), Color(0.45, 0.42, 0.36), Color(0.34, 0.43, 0.49), Color(0.66, 0.64, 0.68)]
const MOSS := [Color(0.38, 0.6, 0.25), Color(0.52, 0.52, 0.22), Color(0.34, 0.64, 0.24), Color(0.22, 0.52, 0.46), Color(0.5, 0.62, 0.36)]
const BACK := [Color(0.3, 0.36, 0.34), Color(0.37, 0.3, 0.25), Color(0.25, 0.33, 0.23), Color(0.2, 0.29, 0.35), Color(0.5, 0.5, 0.56)]
const FOG := [Color(0.46, 0.58, 0.56), Color(0.66, 0.52, 0.38), Color(0.6, 0.68, 0.46), Color(0.26, 0.46, 0.56), Color(0.76, 0.76, 0.84)]
const GLOW := [Color(0.5, 1.6, 1.2), Color(1.8, 1.1, 0.4), Color(1.2, 1.7, 0.5), Color(0.4, 1.3, 1.8), Color(1.5, 1.4, 1.8)]


static func vec3s(cols: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in cols:
		out.append(Vector3(c.r, c.g, c.b))
	return out


static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("pal_rock", vec3s(ROCK))
	mat.set_shader_parameter("pal_built", vec3s(BUILT))
	mat.set_shader_parameter("pal_moss", vec3s(MOSS))
	mat.set_shader_parameter("pal_back", vec3s(BACK))
	mat.set_shader_parameter("pal_fog", vec3s(FOG))
