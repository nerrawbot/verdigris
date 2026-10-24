extends Node2D
## A school of small glowing fish. They drift together, follow a calm swimmer and
## scatter from a fast one.

const World = preload("res://scripts/world.gd")

var game: Node
var world: World
var home := Vector2.ZERO
var ps := PackedVector2Array()
var vs := PackedVector2Array()
var light: PointLight2D


func setup(p: Vector2, light_tex: Texture2D) -> void:
	home = p
	z_index = 3
	for k in 9:
		ps.append(p + Vector2(randf_range(-20, 20), randf_range(-12, 12)))
		vs.append(Vector2(randf_range(-30, 30), randf_range(-10, 10)))
	light = PointLight2D.new()
	light.texture = light_tex
	light.color = Color(0.45, 0.95, 1.0)
	light.energy = 0.55
	light.texture_scale = 0.9
	add_child(light)


func _physics_process(dt: float) -> void:
	if not game.near_camera(home, 1200.0):
		return
	var n := ps.size()
	var com := Vector2.ZERO
	var avg_v := Vector2.ZERO
	for i in n:
		com += ps[i]
		avg_v += vs[i]
	com /= n
	avg_v /= n
	var pl: Node2D = game.player
	var pp: Vector2 = pl.pos
	var pv: Vector2 = pl.vel
	var near_player: bool = pp.distance_to(com) < 130.0 and pl.in_water
	for i in n:
		var p := ps[i]
		var acc := (com - p) * 0.8 + (avg_v - vs[i]) * 0.5 + (home - p) * 0.06
		for j in n:
			if i != j:
				var d := p - ps[j]
				var l := d.length()
				if l < 7.0 and l > 0.01:
					acc += d / l * (7.0 - l) * 30.0
		acc += Vector2(sin(Time.get_ticks_msec() * 0.001 + i), cos(Time.get_ticks_msec() * 0.0013 + i * 2.0)) * 25.0
		if near_player:
			var d := pp - p
			if pv.length() > 230.0:
				acc -= d.normalized() * 500.0
			else:
				acc += d * 0.9 + Vector2(-d.y, d.x).normalized() * 40.0
		vs[i] += acc * dt
		var sp := vs[i].length()
		if sp > 95.0:
			vs[i] = vs[i] / sp * 95.0
		var np := p + vs[i] * dt
		if world.water_px(np) and not world.solid_px(np):
			ps[i] = np
		else:
			vs[i] = -vs[i] * 0.6
	if near_player:
		home = home.lerp(com, dt * 0.5)
	light.position = com - position
	queue_redraw()


func _draw() -> void:
	for i in ps.size():
		var p := ps[i] - position
		var d := vs[i].normalized() if vs[i].length() > 1.0 else Vector2.RIGHT
		var side := Vector2(-d.y, d.x)
		var c := Color(0.5, 1.7, 1.9)
		draw_circle(p, 3.0, Color(0.4, 1.0, 1.0, 0.1), true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([p + d * 2.5, p + side * 1.4, p - d * 2.5, p - side * 1.4]), c)
		var tw := sin(Time.get_ticks_msec() * 0.02 + i) * 1.2
		draw_colored_polygon(PackedVector2Array([p - d * 2.0, p - d * 4.5 + side * (1.6 + tw), p - d * 4.5 - side * (1.6 - tw)]), c * 0.7)
