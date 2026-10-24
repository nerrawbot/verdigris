extends Node2D
## A thrown springseed. Wherever it strikes stone it sprouts a climbable vine.

const World = preload("res://scripts/world.gd")

var game: Node
var world: World
var vel := Vector2.ZERO
var life := 6.0
var spin := 0.0
var wet := false
var trail := PackedVector2Array()


func _ready() -> void:
	z_index = 4


func _physics_process(dt: float) -> void:
	var in_w := world.water_px(position)
	if in_w and not wet:
		wet = true
		game.splash_at(position, 0.25)
	if in_w:
		vel = vel.move_toward(Vector2(0, 45), 520.0 * dt)
	else:
		vel.y += 760.0 * dt
	spin += vel.x * dt * 0.2
	var steps := maxi(1, ceili(vel.length() * dt / 4.0))
	for s in steps:
		var d := vel * dt / steps
		var nx := position + Vector2(d.x, 0)
		if world.solid_px(nx):
			_hit(Vector2(signf(d.x), 0))
			return
		position = nx
		var ny := position + Vector2(0, d.y)
		var t0 := world.tile_of(position)
		var t1 := world.tile_of(ny)
		var grate_cross := d.y > 0.0 and t1.y > t0.y and world.has_flag(t1.x, t1.y, World.F_GRATE)
		if world.solid_px(ny) or grate_cross:
			_hit(Vector2(0, signf(d.y)))
			return
		position = ny
	trail.append(position)
	if trail.size() > 6:
		trail.remove_at(0)
	life -= dt
	if life <= 0.0:
		queue_free()
	queue_redraw()


func _hit(n: Vector2) -> void:
	game.sprout(position, n)
	queue_free()


func _draw() -> void:
	for i in trail.size():
		draw_circle(trail[i] - position, 0.6 + i * 0.25, Color(0.5, 1.4, 1.1, 0.08 * i), true, -1.0, true)
	draw_circle(Vector2.ZERO, 4.0, Color(0.4, 1.0, 0.8, 0.15), true, -1.0, true)
	draw_circle(Vector2.ZERO, 2.2, Color(0.55, 1.75, 1.25), true, -1.0, true)
	draw_line(Vector2.ZERO, Vector2(cos(spin), sin(spin)) * 3.0, Color(0.25, 0.4, 0.2), 1.0, true)
