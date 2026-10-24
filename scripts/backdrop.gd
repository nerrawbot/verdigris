extends Node2D
## Far parallax layers: distant megastructures sinking into fog. Each layer is
## drawn once in its own space and shifted against the camera.

const World = preload("res://scripts/world.gd")

var layers: Array = []   # [{node, factor}]
var world_size := Vector2.ZERO
var view := Vector2(1280, 720)


func build(w: World, view_size: Vector2) -> void:
	world_size = w.size_px()
	view = view_size
	var specs := [
		{"f": 0.06, "tone": 0.82, "seed": 11, "kind": "far"},
		{"f": 0.16, "tone": 0.64, "seed": 23, "kind": "mid"},
		{"f": 0.32, "tone": 0.44, "seed": 37, "kind": "near"},
		{"f": 0.5, "tone": 0.62, "seed": 51, "kind": "forest"},
	]
	for s in specs:
		var n := _Layer.new()
		n.factor = s["f"]
		n.tone = s["tone"]
		n.kind = s["kind"]
		n.seed_value = s["seed"]
		n.span = Vector2(world_size.x * s["f"] + view.x * 2.5, world_size.y * s["f"] + view.y * 2.5)
		n.view = view
		var tex_path := "res://assets/backdrop/%s.png" % s["kind"]
		if ResourceLoader.exists(tex_path):
			n.tex = load(tex_path)
		n.light_mask = 0
		n.z_index = -90 + layers.size()
		add_child(n)
		layers.append(n)


func follow(cam_center: Vector2, sil: Color, fog: Color) -> void:
	for n in layers:
		# screen pos of layer point p = p - cam * f; keep the layer origin a bit up-left
		n.position = cam_center * (1.0 - n.factor) - view * 1.0
		n.modulate = fog.lerp(sil, 1.0 - n.tone)
		if n.kind == "forest":
			n.modulate = Color(1, 1, 1).lerp(fog, 0.45)
		n.modulate.a = 1.0


class _Layer extends Node2D:
	var factor := 0.1
	var tone := 0.5
	var kind := "far"
	var seed_value := 1
	var span := Vector2(4000, 3000)
	var view := Vector2(1280, 720)
	var tex: Texture2D

	func _draw() -> void:
		if kind == "forest":
			_draw_forest()
			return
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var base := Color(1, 1, 1)
		var dark := Color(0.9, 0.9, 0.92)
		var ground := span.y * 0.42
		var x := -200.0
		if tex != null:
			# Blender-rendered skyline (art_src/backdrops.py) replaces the drawn one
			var sc: float = {"far": 0.42, "mid": 0.5, "near": 0.6}.get(kind, 0.5)
			var tw := tex.get_width() * sc
			var h := tex.get_height() * sc
			var tx := -float(seed_value * 97 % 600)
			while tx < span.x:
				draw_texture_rect(tex, Rect2(tx, ground + 30.0 - h, tw, h), false)
				tx += tw - 2.0
			# ground haze: the feet of the structures dissolve into fog
			var hz := h * 0.45
			var band := PackedVector2Array([Vector2(-200, ground - hz), Vector2(span.x + 200, ground - hz), Vector2(span.x + 200, ground + 40), Vector2(-200, ground + 40)])
			var hc := PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.85)])
			draw_polygon(band, hc)
			base = Color(0.8, 0.8, 0.82)
			x = span.x + 1000.0
		var step := 160.0 if kind == "far" else (120.0 if kind == "mid" else 90.0)
		while x < span.x + 200.0:
			var w := rng.randf_range(0.3, 1.0) * step * (1.6 if kind == "far" else 1.0)
			var top := ground - rng.randf_range(0.15, 0.75) * span.y * (0.5 if kind == "far" else 0.35)
			var c := dark if rng.randf() < 0.5 else base
			match rng.randi() % 5:
				0:
					# tower with stepped crown
					draw_rect(Rect2(x, top, w * 0.5, span.y - top), c)
					draw_rect(Rect2(x + w * 0.1, top - w * 0.3, w * 0.3, w * 0.3), c)
					draw_line(Vector2(x + w * 0.25, top - w * 0.3), Vector2(x + w * 0.25, top - w * 1.4), c, 2.0)
				1:
					# chimney pair
					draw_rect(Rect2(x, top, w * 0.18, span.y - top), c)
					draw_rect(Rect2(x + w * 0.35, top + w * 0.4, w * 0.15, span.y - top), c)
				2:
					# tank
					var r := w * 0.45
					draw_circle(Vector2(x + r, ground - r * 1.2), r, c)
					draw_rect(Rect2(x + r * 0.2, ground - r * 1.2, r * 1.6, span.y), c)
				3:
					# girder pylon
					var h := ground - top
					var pts := PackedVector2Array([Vector2(x, span.y), Vector2(x + w * 0.4, top), Vector2(x + w * 0.5, top), Vector2(x + w * 0.9, span.y)])
					draw_colored_polygon(pts, c)
					var k := top
					while k < span.y:
						draw_line(Vector2(x, k), Vector2(x + w * 0.9, k + h * 0.08), c.darkened(0.15), 2.0)
						k += h * 0.12
				4:
					# arch bridge to the next structure
					var aw := w * 2.2
					for s in 16:
						var a0 := PI * s / 16.0
						var a1 := PI * (s + 1) / 16.0
						var p0 := Vector2(x + aw * 0.5 - cos(a0) * aw * 0.5, top + w * 0.4 - sin(a0) * w * 0.6)
						var p1 := Vector2(x + aw * 0.5 - cos(a1) * aw * 0.5, top + w * 0.4 - sin(a1) * w * 0.6)
						draw_line(p0, p1, c, 5.0)
					draw_rect(Rect2(x, top + w * 0.4, 10, span.y), c)
					draw_rect(Rect2(x + aw - 10, top + w * 0.4, 10, span.y), c)
			x += w + rng.randf_range(0.0, 0.8) * step
		# the ground mass and the deep columns that hold the works up
		draw_rect(Rect2(-200, ground, span.x + 400, span.y), base.darkened(0.08))
		x = rng.randf_range(0, 300)
		while x < span.x:
			var cw := rng.randf_range(30, 90) * (0.6 if kind == "far" else 1.0)
			draw_rect(Rect2(x, ground - 20, cw, span.y), base.darkened(0.2))
			if rng.randf() < 0.5:
				draw_line(Vector2(x + cw * 0.5, ground), Vector2(x + cw * 0.5 + rng.randf_range(-60, 60), span.y), base.darkened(0.3), 3.0)
			x += rng.randf_range(250, 600)


	func _draw_forest() -> void:
		# giant trees behind the Canopy (world x 4928..7040 maps to about these layer x)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var x0 := 4928.0 * factor + view.x * 1.3
		var x1 := 7040.0 * factor + view.x * 1.6
		var bottom := 3072.0 * factor + view.y * 1.6
		var x := x0
		while x < x1:
			var tw := rng.randf_range(16.0, 46.0)
			var top := rng.randf_range(560.0, 1000.0)
			var lean := rng.randf_range(-40.0, 40.0)
			var shade := rng.randf_range(0.0, 1.0)
			var bark := Color(0.32, 0.3, 0.26).lerp(Color(0.42, 0.42, 0.36), shade)
			var leaf := Color(0.3, 0.42, 0.27).lerp(Color(0.42, 0.52, 0.34), shade)
			var trunk := PackedVector2Array([Vector2(x - tw, bottom), Vector2(x + tw, bottom), Vector2(x + lean + tw * 0.4, top), Vector2(x + lean - tw * 0.4, top)])
			draw_colored_polygon(trunk, bark)
			var ends: Array = [Vector2(x + lean, top)]
			for b in rng.randi_range(3, 6):
				var by := lerpf(top, bottom - 600.0, rng.randf_range(0.05, 0.6))
				var bx := x + lean * (1.0 - (by - top) / (bottom - top))
				var dir := -1.0 if rng.randf() < 0.5 else 1.0
				var e := Vector2(bx + dir * rng.randf_range(60.0, 160.0), by - rng.randf_range(20.0, 90.0))
				draw_line(Vector2(bx, by), e, bark, rng.randf_range(4.0, 9.0))
				ends.append(e)
			for e in ends:
				for k in rng.randi_range(5, 9):
					var c: Vector2 = e + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-40.0, 25.0))
					draw_circle(c, rng.randf_range(18.0, 46.0), leaf.lerp(bark, rng.randf() * 0.3))
			# hanging vines
			for k in rng.randi_range(2, 5):
				var hx := x + rng.randf_range(-90.0, 90.0)
				var hy := top + rng.randf_range(0.0, 200.0)
				draw_line(Vector2(hx, hy), Vector2(hx + rng.randf_range(-6.0, 6.0), hy + rng.randf_range(120.0, 400.0)), leaf.darkened(0.2), 2.0)
			x += rng.randf_range(90.0, 200.0)