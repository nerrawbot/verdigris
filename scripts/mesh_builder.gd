extends RefCounted
## Collects coloured triangles into one 2D ArrayMesh. UV.x = 1 marks emissive
## vertices (brightened at night), UV.y is the sway weight for sway.gdshader.

var verts := PackedVector2Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()


func tri(a: Vector2, b: Vector2, c: Vector2, ca: Color, cb: Color, cc: Color, sa := 0.0, sb := 0.0, sc := 0.0, em := 0.0) -> void:
	verts.append_array([a, b, c])
	cols.append_array([ca, cb, cc])
	uvs.append_array([Vector2(em, sa), Vector2(em, sb), Vector2(em, sc)])


func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, s_ab := 0.0, s_cd := 0.0, em := 0.0) -> void:
	# a,b on one end, c,d on the other (a-b-c-d around the outline)
	tri(a, b, c, col, col, col, s_ab, s_ab, s_cd, em)
	tri(a, c, d, col, col, col, s_ab, s_cd, s_cd, em)


func rect(r: Rect2, col: Color, sway := 0.0, em := 0.0) -> void:
	quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col, sway, sway, em)


func line(a: Vector2, b: Vector2, w0: float, w1: float, c0: Color, c1: Color, s0 := 0.0, s1 := 0.0, em := 0.0) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized()
	var p0 := a + n * w0 * 0.5
	var p1 := a - n * w0 * 0.5
	var p2 := b - n * w1 * 0.5
	var p3 := b + n * w1 * 0.5
	tri(p0, p1, p2, c0, c0, c1, s0, s0, s1, em)
	tri(p0, p2, p3, c0, c1, c1, s0, s1, s1, em)


func polyline(pts: PackedVector2Array, w0: float, w1: float, c0: Color, c1: Color, s0 := 0.0, s1 := 1.0, em := 0.0) -> void:
	var n := pts.size()
	for i in n - 1:
		var t0 := float(i) / (n - 1)
		var t1 := float(i + 1) / (n - 1)
		line(pts[i], pts[i + 1], lerpf(w0, w1, t0), lerpf(w0, w1, t1), c0.lerp(c1, t0), c0.lerp(c1, t1), lerpf(s0, s1, t0), lerpf(s0, s1, t1), em)


func circle(c: Vector2, r: float, col: Color, sway := 0.0, em := 0.0, segs := 8) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		tri(c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r, col, col, col, sway, sway, sway, em)


func ellipse(c: Vector2, r: Vector2, col: Color, sway := 0.0, em := 0.0, segs := 10) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		tri(c, c + Vector2(cos(a0) * r.x, sin(a0) * r.y), c + Vector2(cos(a1) * r.x, sin(a1) * r.y), col, col, col, sway, sway, sway, em)


func is_empty() -> bool:
	return verts.is_empty()


func build() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return m
