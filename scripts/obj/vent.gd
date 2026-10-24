extends Node2D
## Updraft column: steam from a works vent, or a warm thermal beside the Spire.
## The lift itself comes from F_DRAFT tiles; this node only shows it.

var kind := "steam"


func setup(tile: Vector2i, w: int, h: int, k: String, puff: Texture2D) -> void:
	kind = k
	position = Vector2(tile.x * 16.0 + w * 8.0, (tile.y + 1) * 16.0)
	z_index = 8 if kind == "steam" else -30
	var p := CPUParticles2D.new()
	p.amount = 28 if kind == "steam" else 40
	p.lifetime = h * 16.0 / (90.0 if kind == "steam" else 110.0)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(w * 6.0, 2.0)
	p.direction = Vector2(0, -1)
	p.spread = 6.0
	p.gravity = Vector2(0, -20)
	p.initial_velocity_min = 70.0 if kind == "steam" else 90.0
	p.initial_velocity_max = 110.0 if kind == "steam" else 130.0
	p.local_coords = false
	var grad := Gradient.new()
	if kind == "steam":
		p.texture = puff
		p.scale_amount_min = 0.06
		p.scale_amount_max = 0.14
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.3))
		sc.add_point(Vector2(1, 1.0))
		p.scale_amount_curve = sc
		grad.set_color(0, Color(1, 1, 1, 0.0))
		grad.set_color(1, Color(1, 1, 1, 0.0))
		grad.add_point(0.15, Color(0.95, 0.92, 0.88, 0.22))
		grad.add_point(0.7, Color(0.9, 0.9, 0.9, 0.08))
	else:
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.0
		p.angular_velocity_min = -90.0
		p.angular_velocity_max = 90.0
		grad.set_color(0, Color(0.9, 0.85, 0.6, 0.0))
		grad.set_color(1, Color(0.9, 0.85, 0.6, 0.0))
		grad.add_point(0.1, Color(0.95, 0.9, 0.6, 0.55))
		grad.add_point(0.8, Color(0.9, 0.8, 0.5, 0.3))
	p.color_ramp = grad
	add_child(p)
	if kind == "steam":
		queue_redraw()


func _draw() -> void:
	if kind != "steam":
		return
	var c := Color(0.2, 0.19, 0.18)
	draw_rect(Rect2(-14, -4, 28, 4), c)
	for k in 6:
		draw_rect(Rect2(-12 + k * 4.5, -4, 1.5, 4), c.lightened(0.2))
