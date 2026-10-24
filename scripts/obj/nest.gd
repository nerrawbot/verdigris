extends Node2D
## A woven nest. Curl up in one (hold down) to rest: the game saves, time drifts
## by, and from a nest you can dream your way to any other nest you have found.

var id := 0
var found := false
var hint := 0.0
var twigs: Array = []


func setup(tile: Vector2i, nid: int) -> void:
	id = nid
	position = Vector2((tile.x + 0.5) * 16.0, (tile.y + 1) * 16.0)
	z_index = -9
	var rng := RandomNumberGenerator.new()
	rng.seed = nid * 977 + 13
	for k in 26:
		var a := rng.randf_range(0.15, PI - 0.15)
		var r := rng.randf_range(9.0, 13.0)
		var p := Vector2(-cos(a) * r, -sin(a) * r * 0.42 - 1.0)
		var d := Vector2(rng.randf_range(4.0, 8.0), rng.randf_range(-1.5, 1.5)).rotated(rng.randf_range(-0.5, 0.5))
		twigs.append([p - d * 0.5, p + d * 0.5, Color(0.42, 0.33, 0.22).lerp(Color(0.6, 0.55, 0.36), rng.randf())])


func rest_point() -> Vector2:
	return position + Vector2(0, -7)


func answer() -> void:
	hint = 1.0
	queue_redraw()


func _draw() -> void:
	if hint > 0.01:
		draw_circle(Vector2(0, -6), 18.0, Color(1.0, 0.85, 0.6, 0.06 * hint), true, -1.0, true)
	var bowl := PackedVector2Array()
	for k in 13:
		var a := PI * k / 12.0
		bowl.append(Vector2(-cos(a) * 12.0, sin(a) * 4.0 - 3.0))
	draw_colored_polygon(bowl, Color(0.3, 0.24, 0.16))
	for tw in twigs:
		draw_line(tw[0], tw[1], tw[2], 1.3, true)
	for k in 5:
		var x := -9.0 + k * 4.5
		draw_line(Vector2(x, -3), Vector2(x + 2.0, -9.0 - (k % 2) * 3.0), Color(0.45, 0.55, 0.3), 1.0, true)
	if found:
		draw_circle(Vector2(8, -6), 1.4, Color(1.6, 1.2, 0.6), true, -1.0, true)
