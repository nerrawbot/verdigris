extends Node2D
## Trundler: a slow, mossy grazer. It wanders flat floors, stops to nibble, and
## does not mind you riding on its back.

const World = preload("res://scripts/world.gd")

var game: Node
var world: World
var dir := 1
var speed := 22.0
var graze := 0.0
var walk_t := 0.0
var delta := Vector2.ZERO
var hum := 0.0
var spots: Array = []


func setup(tile: Vector2i, rng: RandomNumberGenerator) -> void:
	position = Vector2((tile.x + 0.5) * 16.0, (tile.y + 1) * 16.0)
	dir = 1 if rng.randf() < 0.5 else -1
	speed = rng.randf_range(18.0, 26.0)
	z_index = 2
	for k in 5:
		spots.append(Vector2(rng.randf_range(-11, 11), rng.randf_range(-15, -7)))


func platform_rect() -> Rect2:
	return Rect2(position.x - 11.0, position.y - 20.0, 22.0, 4.0)


func platform_delta() -> Vector2:
	return delta


func pet() -> void:
	hum = 1.0
	graze = maxf(graze, 1.5)


func _physics_process(dt: float) -> void:
	var old := position
	hum = maxf(0.0, hum - dt * 0.5)
	if not game.near_camera(position, 1400.0):
		delta = Vector2.ZERO
		return
	if graze > 0.0:
		graze -= dt
	else:
		var ahead := position + Vector2(dir * 17.0, -6.0)
		var foot := position + Vector2(dir * 17.0, 4.0)
		var t := world.tile_of(foot)
		var floor_ok := world.solid_px(foot) or world.has_flag(t.x, t.y, World.F_GRATE)
		if world.solid_px(ahead) or world.solid_px(ahead - Vector2(0, 10)) or not floor_ok or world.water_px(ahead):
			dir = -dir
			graze = randf_range(0.6, 1.4)
		else:
			position.x += dir * speed * dt
		if randf() < dt * 0.07:
			graze = randf_range(3.0, 7.0)
	delta = position - old
	walk_t += absf(delta.x) * 0.3
	queue_redraw()


func _draw() -> void:
	var f := float(dir)
	var night: float = game.weather.night
	var shell := Color(0.36, 0.33, 0.28)
	var leg := Color(0.22, 0.2, 0.18)
	var bob := sin(walk_t * 2.0) * 0.6
	# far legs
	for i in 3:
		var hx := (-8.0 + i * 8.0)
		var ph := walk_t + i * 2.1 + PI
		var foot := Vector2(hx + sin(ph) * 3.0 + 2.0, 0)
		draw_line(Vector2(hx + 2.0, -7 + bob), Vector2(hx + 3.0, -10 + bob), leg.darkened(0.3), 2.0, true)
		draw_line(Vector2(hx + 3.0, -10 + bob), foot - Vector2(0, maxf(0.0, cos(ph)) * 2.0), leg.darkened(0.3), 1.6, true)
	# head
	var down := clampf(graze, 0.0, 1.0)
	var head := Vector2(f * 15.0, -7.0 + down * 4.0 + bob)
	draw_circle(head, 4.2, Color(0.5, 0.46, 0.4), true, -1.0, true)
	draw_circle(head + Vector2(f * 1.8, -0.8), 0.9, Color(0.08, 0.08, 0.08), true, -1.0, true)
	for k in 2:
		draw_line(head + Vector2(f * 1.0, -3.0), head + Vector2(f * (4.0 + k * 2.0), -8.0 + k * 2.0), Color(0.6, 0.55, 0.45), 1.0, true)
	# shell
	var dome := PackedVector2Array()
	for k in 17:
		var a := PI + PI * k / 16.0
		dome.append(Vector2(cos(a) * 15.0, -6.0 + bob + sin(a) * 14.0))
	draw_colored_polygon(dome, shell)
	for k in 4:
		var x := -10.0 + k * 6.5
		draw_line(Vector2(x, -7 + bob), Vector2(x * 0.8, -18 + bob + absf(x) * 0.3), shell.darkened(0.25), 1.0, true)
	var moss := PackedVector2Array()
	for k in 11:
		var a := PI * 1.15 + PI * 0.7 * k / 10.0
		moss.append(Vector2(cos(a) * 15.5, -6.0 + bob + sin(a) * 14.5))
	draw_polyline(moss, Color(0.32, 0.5, 0.22), 3.0, true)
	var gl := 0.35 + night * 0.9 + hum * 1.5
	for s in spots:
		draw_circle(s + Vector2(0, bob), 1.1, Color(0.6, 1.4, 1.1) * gl, true, -1.0, true)
	draw_line(Vector2(-15, -6 + bob), Vector2(15, -6 + bob), shell.darkened(0.35), 2.0, true)
	# near legs
	for i in 3:
		var hx := (-9.0 + i * 8.0)
		var ph := walk_t + i * 2.1
		var foot := Vector2(hx + sin(ph) * 3.0, 0)
		draw_line(Vector2(hx, -6 + bob), Vector2(hx - 1.0, -9 + bob), leg, 2.2, true)
		draw_line(Vector2(hx - 1.0, -9 + bob), foot - Vector2(0, maxf(0.0, cos(ph)) * 2.0), leg, 1.8, true)
