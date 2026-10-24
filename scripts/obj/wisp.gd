extends Node2D
## The sprig's call, made visible: a mote of light that drifts off towards the
## nearest sleeping lantern and fades, so you know which way to wander.

var target := Vector2.ZERO
var life := 3.2
var t := 0.0
var trail := PackedVector2Array()
var light: PointLight2D
var col := Color(1.8, 1.4, 0.75)


func setup(from: Vector2, to: Vector2, light_tex: Texture2D) -> void:
	position = from
	target = to
	z_index = 26
	light = PointLight2D.new()
	light.texture = light_tex
	light.texture_scale = 0.55
	light.energy = 0.7
	light.color = Color(1.0, 0.85, 0.55)
	add_child(light)


func _process(dt: float) -> void:
	t += dt
	var to := target - position
	var dist := to.length()
	if dist > 4.0:
		var dir := to / dist
		var side := Vector2(-dir.y, dir.x) * sin(t * 6.0) * 30.0
		var speed := 190.0 * clampf(dist / 120.0, 0.25, 1.0)
		position += (dir * speed + side) * dt
	trail.append(position)
	if trail.size() > 18:
		trail.remove_at(0)
	var fade := clampf(life - t, 0.0, 1.0) * clampf(t * 4.0, 0.0, 1.0)
	modulate.a = fade
	light.energy = 0.7 * fade
	if t >= life:
		queue_free()
	queue_redraw()


func _draw() -> void:
	for i in trail.size():
		var a := float(i) / trail.size()
		draw_circle(trail[i] - position, 0.6 + a * 1.6, Color(col.r, col.g, col.b, a * 0.35), true, -1.0, true)
	draw_circle(Vector2.ZERO, 7.0, Color(1.0, 0.8, 0.5, 0.12), true, -1.0, true)
	draw_circle(Vector2.ZERO, 2.4, col, true, -1.0, true)
