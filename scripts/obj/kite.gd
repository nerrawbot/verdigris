extends Node2D
## Drift-kite: a leaf-winged flier that wanders open air. Grab one ([E]) and it
## carries you in a slow glide; in an updraft it lifts you.

const World = preload("res://scripts/world.gd")

var game: Node
var world: World
var home := Vector2.ZERO
var vel := Vector2.ZERO
var wander := 0.0
var held := false
var flee := 0.0
var flap := 0.0
var tint := Color(0.86, 0.9, 0.55)
var ribbons: Array = []


func setup(p: Vector2, rng: RandomNumberGenerator) -> void:
	position = p
	home = p
	wander = rng.randf() * TAU
	flap = rng.randf() * TAU
	tint = Color(0.86, 0.9, 0.55).lerp(Color(0.95, 0.75, 0.55), rng.randf() * 0.6)
	z_index = 3
	for r in 2:
		var pts := PackedVector2Array()
		for k in 6:
			pts.append(p + Vector2(0, 6 + k * 3))
		ribbons.append([pts, pts.duplicate()])


func let_go() -> void:
	held = false
	flee = 1.4
	vel = Vector2(0, -60)


func _physics_process(dt: float) -> void:
	if not held and not game.near_camera(position, 1300.0):
		return
	if held:
		var p: Node2D = game.player
		var target: Vector2 = p.pos + Vector2(-float(p.facing) * 2.0, -18.0)
		position = position.lerp(target, 1.0 - exp(-dt * 18.0))
		flap += dt * 9.0
	else:
		wander += randf_range(-1.4, 1.4) * dt
		var desired := Vector2(cos(wander), sin(wander) * 0.5) * 26.0
		desired += (home - position) * 0.015
		for k in 8:
			var d := Vector2.RIGHT.rotated(TAU * k / 8.0)
			if world.solid_px(position + d * 30.0):
				desired -= d * 34.0
		if world.solid_px(position + Vector2(0, 48)):
			desired.y -= 22.0
		if world.water_px(position + Vector2(0, 30)):
			desired.y -= 40.0
		if world.flag_px(position, World.F_DRAFT):
			desired.y -= 60.0
		if flee > 0.0:
			flee -= dt
			var away: Vector2 = position - game.player.pos
			desired += away.normalized() * 60.0
		vel = vel.lerp(desired, 1.0 - exp(-dt * 1.5))
		var np := position + vel * dt
		if world.solid_px(np):
			vel = -vel * 0.5
		else:
			position = np
		flap += dt * (3.0 + vel.length() * 0.02)
	for r in ribbons:
		var pts: PackedVector2Array = r[0]
		var prev: PackedVector2Array = r[1]
		pts[0] = position + Vector2(0, 5)
		for k in range(1, pts.size()):
			var v := (pts[k] - prev[k]) * 0.92
			prev[k] = pts[k]
			pts[k] += v + Vector2(sin(flap * 0.5 + k) * 6.0, 140.0) * dt * dt
		for it in 2:
			for k in range(1, pts.size()):
				var d := pts[k] - pts[k - 1]
				if d.length() > 0.001:
					pts[k] = pts[k - 1] + d.normalized() * 3.2
		r[0] = pts
		r[1] = prev
	queue_redraw()


func _draw() -> void:
	var span := 11.0 + sin(flap) * 3.0
	var lift := cos(flap) * 2.0
	var wing := PackedVector2Array([Vector2(0, -8), Vector2(span, -2 + lift), Vector2(span * 0.5, 2), Vector2(0, 6), Vector2(-span * 0.5, 2), Vector2(-span, -2 + lift)])
	var c := tint
	c.a = 0.85
	draw_colored_polygon(wing, c)
	var vein := tint.darkened(0.45)
	draw_line(Vector2(0, -8), Vector2(0, 6), vein, 1.2, true)
	draw_line(Vector2(0, -3), Vector2(span * 0.85, -2 + lift), vein, 0.8, true)
	draw_line(Vector2(0, -3), Vector2(-span * 0.85, -2 + lift), vein, 0.8, true)
	draw_line(Vector2(0, 1), Vector2(span * 0.45, 1.5), vein, 0.7, true)
	draw_line(Vector2(0, 1), Vector2(-span * 0.45, 1.5), vein, 0.7, true)
	draw_circle(Vector2(span, -2 + lift), 1.3, Color(1.8, 1.6, 0.7), true, -1.0, true)
	draw_circle(Vector2(-span, -2 + lift), 1.3, Color(1.8, 1.6, 0.7), true, -1.0, true)
	for r in ribbons:
		var pts: PackedVector2Array = r[0]
		var local := PackedVector2Array()
		for p in pts:
			local.append(p - position)
		draw_polyline(local, Color(tint.r, tint.g, tint.b, 0.6), 1.2, true)
