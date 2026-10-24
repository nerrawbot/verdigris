extends Node2D
## An old works lantern. Sing to it ([E]) and it wakes, adding a voice to the music.
## Kinds: lamp (post and cage), deep (sunken dome lamp), beacon (top of the Spire).

var id := 0
var kind := "lamp"
var lit := false
var glow := 0.0
var light: PointLight2D
var game: Node
var flick := 0.0
var t := 0.0
var ping := 0.0


func setup(tile: Vector2i, lid: int, k: String, light_tex: Texture2D) -> void:
	id = lid
	kind = k
	position = Vector2((tile.x + 0.5) * 16.0, (tile.y + 1) * 16.0)
	z_index = -10
	light = PointLight2D.new()
	light.texture = light_tex
	light.position = Vector2(0, -24) if kind == "lamp" else (Vector2(0, -12) if kind == "deep" else Vector2(0, -26))
	light.color = Color(1.0, 0.72, 0.42) if kind != "deep" else Color(0.45, 0.95, 1.0)
	light.energy = 0.15
	light.texture_scale = 0.6
	add_child(light)


func light_up(instant := false) -> void:
	lit = true
	if instant:
		glow = 1.0


func interact_point() -> Vector2:
	return position + Vector2(0, -8)


func rest_point() -> Vector2:
	return position + Vector2(-12, -6.01)


## Heard a call: flare up for a moment so the player can find it.
func answer() -> void:
	ping = 1.0


func _process(dt: float) -> void:
	t += dt
	var target := 1.0 if lit else 0.0
	glow = move_toward(glow, target, dt / 2.5)
	flick = sin(t * 7.3) * 0.03 + sin(t * 2.1) * 0.04
	var e_lit := 2.2 if kind == "beacon" else 1.35
	var s_lit := 3.2 if kind == "beacon" else 1.9
	ping = maxf(0.0, ping - dt * 0.4)
	light.energy = lerpf(0.12 + sin(t * 1.3) * 0.04, e_lit + flick, glow) + ping * 1.2
	light.texture_scale = lerpf(0.5, s_lit, glow) + ping * 1.5
	if game.near_camera(position, 900.0) or kind == "beacon":
		queue_redraw()


func _flame_col() -> Color:
	if kind == "deep":
		return Color(0.25, 0.22, 0.2).lerp(Color(0.6, 1.8, 2.2), glow)
	return Color(0.28, 0.22, 0.18).lerp(Color(2.8, 1.7, 0.7), glow)


func _draw() -> void:
	var metal := Color(0.24, 0.22, 0.21)
	var fc := _flame_col() * (1.0 + flick * glow) + Color(1.4, 1.0, 0.5) * ping
	var halo := Color(fc.r, fc.g, fc.b, 0.12 * maxf(glow, ping))
	match kind:
		"lamp":
			draw_rect(Rect2(-6, -3, 12, 3), metal.darkened(0.2))
			draw_rect(Rect2(-1.5, -34, 3, 32), metal)
			draw_rect(Rect2(-1.5, -34, 9, 2), metal)
			draw_line(Vector2(6, -32), Vector2(6, -28), metal, 1.0)
			var c := Vector2(6, -21)
			draw_circle(c, 14.0, halo, true, -1.0, true)
			draw_circle(c, 7.0, Color(halo.r, halo.g, halo.b, halo.a * 2.0), true, -1.0, true)
			draw_rect(Rect2(c.x - 4.5, c.y - 7, 9, 13), Color(0.12, 0.11, 0.1, 0.85))
			draw_circle(c + Vector2(0, 0.5), 3.0, fc, true, -1.0, true)
			for k in 3:
				draw_line(Vector2(c.x - 4.5 + k * 4.5, c.y - 7), Vector2(c.x - 4.5 + k * 4.5, c.y + 6), metal, 1.0)
			draw_rect(Rect2(c.x - 5.5, c.y - 8.5, 11, 2), metal)
			draw_rect(Rect2(c.x - 5.5, c.y + 5.5, 11, 2), metal)
		"deep":
			draw_rect(Rect2(-9, -4, 18, 4), metal.darkened(0.3))
			draw_circle(Vector2(0, -11), 18.0, halo, true, -1.0, true)
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(Vector2(cos(a) * 7.0, -4 + sin(a) * 10.0))
			draw_colored_polygon(dome, Color(0.15, 0.2, 0.22, 0.9))
			draw_circle(Vector2(0, -8), 3.4, fc, true, -1.0, true)
			draw_polyline(dome, metal.lightened(0.1), 1.2, true)
			draw_line(Vector2(0, -14), Vector2(0, -16), metal, 1.5)
		"beacon":
			if glow > 0.01:
				var beam := PackedVector2Array([Vector2(-5, -36), Vector2(5, -36), Vector2(70, -900), Vector2(-70, -900)])
				var bc := PackedColorArray([Color(1.4, 1.0, 0.6, 0.35 * glow), Color(1.4, 1.0, 0.6, 0.35 * glow), Color(1, 0.8, 0.5, 0.0), Color(1, 0.8, 0.5, 0.0)])
				draw_polygon(beam, bc)
			draw_rect(Rect2(-12, -6, 24, 6), metal.darkened(0.2))
			draw_rect(Rect2(-9, -10, 18, 4), metal)
			draw_circle(Vector2(0, -22), 26.0, halo, true, -1.0, true)
			draw_rect(Rect2(-7, -32, 14, 22), Color(0.14, 0.13, 0.12, 0.85))
			draw_circle(Vector2(0, -21), 5.0, fc, true, -1.0, true)
			for k in 4:
				draw_line(Vector2(-7 + k * 4.66, -32), Vector2(-7 + k * 4.66, -10), metal, 1.2)
			draw_rect(Rect2(-9, -36, 18, 4), metal)
			draw_line(Vector2(0, -36), Vector2(0, -44), metal, 1.5)
			draw_circle(Vector2(0, -45), 1.6, fc * 0.8, true, -1.0, true)
