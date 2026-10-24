extends Node2D
## Springseed plant: a stalk with a glowing bulb. Picked bulbs regrow, faster in rain.

var game: Node
var ripe := true
var regrow := 0.0
var h := 22.0
var lean := 0.0
var phase := 0.0
var pulse := 0.0
var leaf_side := 1.0


func setup(tile: Vector2i, rng: RandomNumberGenerator) -> void:
	position = Vector2((tile.x + 0.5) * 16.0 + rng.randf_range(-3.0, 3.0), (tile.y + 1) * 16.0 + 1.0)
	h = rng.randf_range(16.0, 28.0)
	lean = rng.randf_range(-0.25, 0.25)
	phase = rng.randf() * TAU
	leaf_side = 1.0 if rng.randf() < 0.5 else -1.0
	z_index = -12


func bulb_world() -> Vector2:
	return position + Vector2(lean * h, -h)


func pick() -> bool:
	if not ripe:
		return false
	ripe = false
	regrow = randf_range(70.0, 110.0)
	queue_redraw()
	return true


func _process(dt: float) -> void:
	if not ripe:
		var rate: float = game.weather.time_scale * (3.5 if game.weather.rain > 0.3 else 1.0)
		regrow -= dt * rate
		if regrow <= 0.0:
			ripe = true
			pulse = 1.0
	pulse = maxf(0.0, pulse - dt * 0.6)
	if game.near_camera(position, 760.0):
		queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var wind: float = game.weather.wind
	var sway := sin(t * 1.3 + phase) * (1.5 + wind * 4.0)
	var tip := Vector2(lean * h + sway, -h)
	var mid := Vector2(lean * h * 0.3 + sway * 0.3, -h * 0.55)
	var pts := PackedVector2Array()
	for k in 9:
		var u := k / 8.0
		pts.append(Vector2.ZERO.lerp(mid, u).lerp(mid.lerp(tip, u), u))
	var stem := Color(0.2, 0.33, 0.16)
	for k in 8:
		draw_line(pts[k], pts[k + 1], stem.lightened(k * 0.03), lerpf(2.4, 1.2, k / 8.0), true)
	for li in 3:
		var p := pts[2 + li * 2]
		var s := leaf_side * (1.0 if li % 2 == 0 else -1.0)
		var tipl := p + Vector2(s * (7.0 - li), -3.0 + li)
		var leaf := PackedVector2Array([p, p.lerp(tipl, 0.5) + Vector2(0, -2.2), tipl, p.lerp(tipl, 0.5) + Vector2(0, 1.6)])
		draw_colored_polygon(leaf, Color(0.26, 0.45, 0.2).lightened(li * 0.05))
	if ripe:
		var breathe := 0.85 + sin(t * 2.1 + phase) * 0.15 + pulse
		var c := Color(0.55, 1.75, 1.25) * breathe
		draw_circle(tip, 7.0, Color(0.4, 1.0, 0.8, 0.12 * breathe), true, -1.0, true)
		draw_circle(tip, 3.6, c, true, -1.0, true)
		draw_circle(tip + Vector2(-1.0, -1.2), 1.2, Color(1.6, 2.2, 2.0), true, -1.0, true)
	else:
		var grow := clampf(1.0 - regrow / 90.0, 0.2, 1.0)
		draw_circle(tip, 2.0 * grow, Color(0.3, 0.5, 0.3), true, -1.0, true)
