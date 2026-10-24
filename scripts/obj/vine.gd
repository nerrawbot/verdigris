extends Node2D
## A vine grown from a springseed: one tile column, climbable like a pole once
## grown. Underwater it becomes kelp. It withers when too many vines exist.

const World = preload("res://scripts/world.gd")

var world: World
var game: Node
var col := 0
var top := 0          # top tile row (inclusive)
var bot := 0          # bottom tile row (inclusive)
var root_bottom := true
var kelp := false
var grow := 0.0       # 0..1
var wither := 0.0     # >0 while dying
var claimed := 0      # tiles flagged so far
var phase := 0.0
var seed_value := 0


func setup(w: World, x: int, y_top: int, y_bot: int, from_bottom: bool, instant := false) -> void:
	world = w
	col = x
	top = y_top
	bot = y_bot
	root_bottom = from_bottom
	kelp = w.has_flag(x, y_bot, World.F_WATER)
	phase = randf() * TAU
	seed_value = hash(Vector2i(x, y_top))
	position = Vector2((x + 0.5) * 16.0, 0)
	z_index = -11
	if instant:
		grow = 1.0
	_claim()


func length_tiles() -> int:
	return bot - top + 1


func _claim() -> void:
	var want := int(ceil(grow * length_tiles()))
	while claimed < want:
		var y := (bot - claimed) if root_bottom else (top + claimed)
		world.set_vine(col, y, true)
		claimed += 1


func start_wither() -> void:
	if wither > 0.0:
		return
	wither = 0.001
	for k in claimed:
		var y := (bot - k) if root_bottom else (top + k)
		world.set_vine(col, y, false)
	claimed = 0


func save_data() -> Dictionary:
	return {"x": col, "top": top, "bot": bot, "rb": root_bottom}


func _process(dt: float) -> void:
	if wither > 0.0:
		wither += dt * 0.6
		modulate.a = clampf(1.0 - wither, 0.0, 1.0)
		if wither >= 1.0:
			queue_free()
		queue_redraw()
		return
	if grow < 1.0:
		grow = minf(1.0, grow + dt / (0.12 * length_tiles() + 0.4))
		_claim()
		queue_redraw()
	elif game.near_camera(Vector2(position.x, (top + bot) * 8.0), 800.0):
		queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var t := Time.get_ticks_msec() * 0.001
	var y_root := (bot + 1) * 16.0 if root_bottom else top * 16.0
	var y_end := top * 16.0 if root_bottom else (bot + 1) * 16.0
	var dirv := -1.0 if root_bottom else 1.0
	var full := absf(y_end - y_root)
	var cur := full * grow
	var segs := maxi(3, int(cur / 5.0))
	var pts := PackedVector2Array()
	for k in segs + 1:
		var d := cur * k / segs
		var u := d / maxf(full, 1.0)
		var sway := sin(t * (1.6 if kelp else 0.9) + phase + d * 0.05) * (3.0 if kelp else 1.2) * u
		pts.append(Vector2(sin(d * 0.08 + phase) * 2.5 + sway, y_root + dirv * d))
	var stem := Color(0.22, 0.38, 0.15) if not kelp else Color(0.25, 0.35, 0.16)
	for k in segs:
		draw_line(pts[k], pts[k + 1], stem.lightened(0.04 * (k % 3)), lerpf(3.2, 1.6, float(k) / segs), true)
	var night: float = game.weather.night
	var k2 := 2
	while k2 < pts.size():
		var p := pts[k2]
		var s := 1.0 if (k2 / 2) % 2 == 0 else -1.0
		if kelp:
			var tipk := p + Vector2(s * 6.0, dirv * 4.0 + sin(t * 2.0 + k2) * 1.5)
			draw_line(p, tipk, Color(0.3, 0.42, 0.18), 2.4, true)
			if rng.randf() < 0.3:
				draw_circle(tipk, 1.6, Color(0.45, 0.55, 0.25), true, -1.0, true)
		else:
			var tipl := p + Vector2(s * 6.5, dirv * 2.5)
			var leaf := PackedVector2Array([p, p.lerp(tipl, 0.5) + Vector2(0, -2.0), tipl, p.lerp(tipl, 0.5) + Vector2(0, 1.6)])
			draw_colored_polygon(leaf, Color(0.28, 0.5, 0.2).lightened(rng.randf() * 0.12))
			if rng.randf() < 0.18:
				var fc := Color(1.2, 1.0, 1.6).lerp(Color(1.8, 1.3, 2.4), night)
				draw_circle(tipl, 1.8, fc * (0.6 + night * 0.6), true, -1.0, true)
		k2 += 2
	if grow < 1.0 and pts.size() > 0:
		draw_circle(pts[pts.size() - 1], 2.5, Color(0.55, 1.6, 1.2), true, -1.0, true)
