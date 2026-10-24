extends Node2D
## A sparse layer in front of everything, moving a little faster than the world:
## dark, soft hanging vines, chains and sagging cables, as if close to the lens.

const FACTOR := 1.15

var world_size := Vector2.ZERO
var items: Array = []


func build(size: Vector2) -> void:
	world_size = size
	z_index = 40
	light_mask = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var x := 300.0
	while x < size.x * FACTOR:
		var y := rng.randf_range(0.0, size.y * FACTOR)
		var kind := rng.randi_range(0, 2)
		items.append({"kind": kind, "p": Vector2(x, y), "len": rng.randf_range(260.0, 620.0), "w": rng.randf_range(5.0, 11.0), "seed": rng.randi(), "span": rng.randf_range(300.0, 700.0)})
		x += rng.randf_range(350.0, 800.0)


func follow(cam: Vector2) -> void:
	position = cam * (1.0 - FACTOR)


func _draw() -> void:
	var dark := Color(0.02, 0.025, 0.03, 0.9)
	var soft := Color(0.02, 0.025, 0.03, 0.25)
	for it in items:
		var rng := RandomNumberGenerator.new()
		rng.seed = it["seed"]
		var p: Vector2 = it["p"]
		var length: float = it["len"]
		var w: float = it["w"]
		match it["kind"]:
			0:
				# a hanging vine with leaves
				var pts := PackedVector2Array()
				for k in 13:
					var t := k / 12.0
					pts.append(p + Vector2(sin(t * 3.0 + p.x) * 14.0 * t, length * t))
				draw_polyline(pts, soft, w * 2.6, true)
				draw_polyline(pts, dark, w, true)
				for k in range(2, 13):
					var q := pts[k]
					var s := 1.0 if k % 2 == 0 else -1.0
					var leaf := PackedVector2Array([q, q + Vector2(s * w * 2.2, -w * 0.6), q + Vector2(s * w * 3.2, w * 0.8), q + Vector2(s * w * 1.0, w * 0.9)])
					draw_colored_polygon(leaf, dark)
			1:
				# a chain
				var y := 0.0
				var link := 0
				while y < length:
					var q := p + Vector2(0, y)
					if link % 2 == 0:
						draw_arc(q + Vector2(0, w * 0.6), w * 0.55, 0, TAU, 12, dark, w * 0.25, true)
					else:
						draw_line(q, q + Vector2(0, w * 1.4), dark, w * 0.25, true)
					y += w * 1.15
					link += 1
			2:
				# a sagging cable
				var span: float = it["span"]
				var pts := PackedVector2Array()
				for k in 17:
					var t := k / 16.0
					pts.append(p + Vector2(span * t, sin(PI * t) * span * 0.18))
				draw_polyline(pts, soft, w * 1.6, true)
				draw_polyline(pts, dark, w * 0.6, true)
