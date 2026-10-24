extends Control
## The map: the works as you have explored them, lanterns, nests and you.
## When opened from a nest it also lets you choose a nest to dream your way to.

const World = preload("res://scripts/world.gd")

var game: Node
var world: World
var base_tex: ImageTexture
var seen_img: Image
var seen_tex: ImageTexture
var travel := false
var choices: Array = []     # rest spots (nests and lit lanterns)
var choice := 0
var rect := Rect2()
var map_rect: TextureRect
var icons: Control
var t := 0.0


func setup(g: Node, w: World) -> void:
	game = g
	world = w
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := Image.create(w.w, w.h, false, Image.FORMAT_RGBA8)
	var reg_c := [Color(0.62, 0.7, 0.6), Color(0.72, 0.62, 0.5), Color(0.6, 0.74, 0.52), Color(0.5, 0.62, 0.72), Color(0.82, 0.82, 0.88)]
	for y in w.h:
		for x in w.w:
			var i := y * w.w + x
			var c := Color(0.1, 0.11, 0.11, 0.0)
			if w.solid[i] == World.AIR:
				c = reg_c[w.region[i]]
				if w.flags[i] & World.F_WATER:
					c = c.lerp(Color(0.25, 0.45, 0.7), 0.6)
				if w.flags[i] & (World.F_POLE_V | World.F_POLE_H):
					c = c.darkened(0.25)
			else:
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if w.inb(x + d.x, y + d.y) and w.solid[(y + d.y) * w.w + x + d.x] == World.AIR:
						edge = true
				c = Color(0.2, 0.22, 0.2, 1.0) if edge else Color(0.12, 0.13, 0.13, 1.0)
			img.set_pixel(x, y, c)
	base_tex = ImageTexture.create_from_image(img)
	seen_img = Image.create(w.w, w.h, false, Image.FORMAT_L8)
	seen_tex = ImageTexture.create_from_image(seen_img)
	map_rect = TextureRect.new()
	map_rect.texture = base_tex
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nuniform sampler2D seen : filter_linear;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat s = smoothstep(0.15, 0.85, texture(seen, UV).r);\n\tCOLOR = vec4(c.rgb, c.a * s);\n}\n"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("seen", seen_tex)
	map_rect.material = m
	add_child(map_rect)
	icons = _Icons.new()
	icons.mv = self
	icons.set_anchors_preset(Control.PRESET_FULL_RECT)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icons)


func reveal(tile: Vector2i, r: int) -> bool:
	var changed := false
	for y in range(maxi(tile.y - r, 0), mini(tile.y + r + 1, world.h)):
		for x in range(maxi(tile.x - r, 0), mini(tile.x + r + 1, world.w)):
			var d := Vector2(x - tile.x, (y - tile.y) * 1.3).length()
			if d > r:
				continue
			if seen_img.get_pixel(x, y).r < 0.5:
				seen_img.set_pixel(x, y, Color(1, 1, 1))
				changed = true
	return changed


func refresh() -> void:
	seen_tex.update(seen_img)


func seen_data() -> PackedByteArray:
	return seen_img.get_data()


func load_seen(d: PackedByteArray) -> void:
	if d.size() == world.w * world.h:
		seen_img = Image.create_from_data(world.w, world.h, false, Image.FORMAT_L8, d)
		seen_tex.update(seen_img)


func is_seen(tile: Vector2i) -> bool:
	if not world.inb(tile.x, tile.y):
		return false
	return seen_img.get_pixel(tile.x, tile.y).r > 0.5


func _process(dt: float) -> void:
	if visible:
		t += dt
		queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.03, 0.88))
	var aspect := float(world.w) / world.h
	var mh := vs.y * 0.82
	var mw := mh * aspect
	if mw > vs.x * 0.9:
		mw = vs.x * 0.9
		mh = mw / aspect
	rect = Rect2((vs - Vector2(mw, mh)) * 0.5 + Vector2(0, 14), Vector2(mw, mh))
	map_rect.position = rect.position
	map_rect.size = rect.size
	icons.queue_redraw()


func _draw_icons(c_item: Control) -> void:
	var vs := get_viewport_rect().size
	var sc := rect.size.x / world.w
	# icons
	for n in game.nest_nodes.values():
		var tile: Vector2i = world.tile_of(n.position - Vector2(0, 8))
		if not is_seen(tile):
			continue
		var p: Vector2 = rect.position + (n.position / World.TILE) * sc
		var c := Color(1.0, 0.85, 0.55) if n.found else Color(0.75, 0.7, 0.6, 0.6)
		c_item.draw_arc(p + Vector2(0, -3), 5.0, 0.2, PI - 0.2, 10, c, 2.0, true)
	for l in game.lantern_nodes.values():
		var tile: Vector2i = world.tile_of(l.position - Vector2(0, 8))
		if not is_seen(tile):
			continue
		var p: Vector2 = rect.position + (l.position / World.TILE) * sc + Vector2(0, -4)
		var pts := PackedVector2Array([p + Vector2(0, -6), p + Vector2(4, 0), p + Vector2(0, 6), p + Vector2(-4, 0)])
		if l.lit:
			c_item.draw_circle(p, 9.0, Color(1, 0.7, 0.3, 0.2), true, -1.0, true)
			c_item.draw_colored_polygon(pts, Color(2.0, 1.3, 0.6))
		else:
			pts.append(pts[0])
			c_item.draw_polyline(pts, Color(0.9, 0.9, 0.85, 0.8), 1.4, true)
	for e in game.echoes:
		if not e.read:
			continue
		var p: Vector2 = rect.position + (e.position / World.TILE) * sc
		c_item.draw_arc(p, 3.0, 0, TAU, 10, Color(0.6, 0.95, 0.85, 0.8), 1.2, true)
	var pp: Vector2 = rect.position + (game.player.pos / World.TILE) * sc
	c_item.draw_circle(pp, 4.0 + sin(t * 4.0) * 1.2, Color(1, 1, 1, 0.3), true, -1.0, true)
	c_item.draw_circle(pp, 2.6, Color(1.0, 0.95, 0.85), true, -1.0, true)
	if travel and choices.size() > 0:
		var n: Node2D = choices[choice]
		var p: Vector2 = rect.position + (n.position / World.TILE) * sc + Vector2(0, -3)
		c_item.draw_arc(p, 11.0 + sin(t * 3.0) * 1.5, 0, TAU, 24, Color(1.0, 0.85, 0.5), 2.0, true)
	var font := ThemeDB.fallback_font
	var title := "the works, as far as you have wandered"
	if travel:
		title = "dream to a nest or lantern:  A / D to choose,  E to go,  M to stay"
	c_item.draw_string(font, Vector2(0, rect.position.y - 18), title, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 16, Color(0.85, 0.85, 0.8, 0.8))


class _Icons extends Control:
	var mv: Control

	func _draw() -> void:
		mv._draw_icons(self)
