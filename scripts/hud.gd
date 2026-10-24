extends CanvasLayer
## Quiet interface: region banners, a hint line, seed pips, the lantern row
## (shown when it changes or while Tab is held), title card, fades and pause.

signal resume_pressed
signal restart_pressed
signal quit_pressed

var font: SystemFont
var banner_title: Label
var banner_sub: Label
var banner_box: VBoxContainer
var toast: Label
var prompt_lbl: Label
var pips: Control
var lamps: Control
var fade: ColorRect
var title_box: VBoxContainer
var pause_panel: PanelContainer
var map_view: Control
var seeds := 0
var lit: Array = []
var lamp_alpha := 0.0
var lamp_show := 0.0
var toast_t := 0.0
var toast_prio := 0
var toast_queue: Array = []
var prompt_t := 0.0
var title_on := false
var banner_tw: Tween
var title_tw: Tween
var fade_tw: Tween


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# banner
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_box.position = Vector2(-400, 150)
	banner_box.size = Vector2(800, 120)
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_box.modulate.a = 0.0
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner_box)
	banner_title = _label(38, Color(0.95, 0.93, 0.86), 6)
	banner_sub = _label(17, Color(0.85, 0.85, 0.8, 0.85), 2)
	banner_box.add_child(banner_title)
	banner_box.add_child(banner_sub)
	# toast + prompt
	toast = _label(17, Color(0.92, 0.9, 0.84), 1)
	toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast.position = Vector2(-450, -96)
	toast.size = Vector2(900, 30)
	toast.modulate.a = 0.0
	root.add_child(toast)
	prompt_lbl = _label(15, Color(0.95, 0.88, 0.7), 1)
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.position = Vector2(-300, -60)
	prompt_lbl.size = Vector2(600, 26)
	prompt_lbl.modulate.a = 0.0
	root.add_child(prompt_lbl)
	# seed pips and lantern row
	pips = _Pips.new()
	pips.hud = self
	pips.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pips.position = Vector2(34, -46)
	pips.size = Vector2(100, 30)
	root.add_child(pips)
	lamps = _Lamps.new()
	lamps.hud = self
	lamps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lamps.position = Vector2(-300, 26)
	lamps.size = Vector2(270, 30)
	root.add_child(lamps)
	# map
	map_view = load("res://scripts/map_view.gd").new()
	map_view.visible = false
	root.add_child(map_view)
	# fade
	fade = ColorRect.new()
	fade.color = Color(0.0, 0.0, 0.0, 1.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	# title
	title_box = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.modulate.a = 0.0
	root.add_child(title_box)
	var t1 := _label(64, Color(0.9, 0.95, 0.88), 18)
	t1.text = "VERDIGRIS"
	var t2 := _label(18, Color(0.8, 0.85, 0.8, 0.9), 3)
	t2.text = "a quiet wander through the overgrown works"
	var t3 := _label(14, Color(0.95, 0.85, 0.65, 0.8), 2)
	t3.text = "\n\npress any key"
	for l in [t1, t2, t3]:
		title_box.add_child(l)
	_build_pause(root)


func _label(size: int, col: Color, spacing: int) -> Label:
	var l := Label.new()
	var fv := FontVariation.new()
	fv.base_font = font
	fv.spacing_glyph = spacing
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_pause(root: Control) -> void:
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-260, -170)
	pause_panel.size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.08, 0.86)
	sb.border_color = Color(0.5, 0.6, 0.5, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(26)
	pause_panel.add_theme_stylebox_override("panel", sb)
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	var h := _label(28, Color(0.9, 0.93, 0.86), 6)
	h.text = "resting a moment"
	v.add_child(h)
	var help := _label(14, Color(0.8, 0.82, 0.78), 0)
	help.text = "move  A D / arrows      jump  Space      climb  W S\ngrab, pick, sing  E      throw seed  F / left click\nmap  M      lanterns  Tab      rest at a nest  hold S\ngrab poles by holding up, climb rough rock by pushing into it\nseeds grow vines wherever they land"
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(help)
	for b in [["continue", resume_pressed], ["begin again", restart_pressed], ["leave", quit_pressed]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 18)
		btn.flat = true
		btn.add_theme_color_override("font_color", Color(0.85, 0.88, 0.82))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.55))
		btn.add_theme_color_override("font_focus_color", Color(1.0, 0.85, 0.55))
		var sig: Signal = b[1]
		btn.pressed.connect(func(): sig.emit())
		v.add_child(btn)


func show_pause(on: bool) -> void:
	pause_panel.visible = on
	if on:
		(pause_panel.get_child(0).get_child(2) as Button).grab_focus()


func banner(title: String, sub: String) -> void:
	banner_title.text = title
	banner_sub.text = sub
	if banner_tw:
		banner_tw.kill()
	banner_tw = create_tween()
	banner_tw.tween_property(banner_box, "modulate:a", 1.0, 2.0)
	banner_tw.tween_interval(3.5)
	banner_tw.tween_property(banner_box, "modulate:a", 0.0, 2.5)


## prio 2 lines (story) are never cut short; others wait their turn behind them.
func say(text: String, secs := 4.0, prio := 1) -> void:
	if toast_t > 0.6 and toast_prio >= 2 and prio < 2:
		toast_queue.append([text, secs, prio])
		return
	toast.text = text
	toast_t = secs
	toast_prio = prio


func prompt(text: String) -> void:
	if text != "":
		prompt_lbl.text = text
		prompt_t = 0.15


func set_seeds(n: int) -> void:
	seeds = n
	pips.queue_redraw()


func set_lit(arr: Array) -> void:
	lit = arr
	lamp_show = 6.0
	lamps.queue_redraw()


func show_title(on: bool) -> void:
	title_on = on
	# a key pressed while the title is still fading in must win over that fade
	if title_tw:
		title_tw.kill()
	title_tw = create_tween()
	title_tw.tween_property(title_box, "modulate:a", 1.0 if on else 0.0, 2.5 if on else 1.2)


func fade_to(a: float, secs: float) -> Tween:
	if fade_tw:
		fade_tw.kill()
	fade_tw = create_tween()
	fade_tw.tween_property(fade, "color:a", a, secs)
	return fade_tw


func _unhandled_input(event: InputEvent) -> void:
	# the game node is paused with the tree, so the panel handles its own Esc
	if pause_panel.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()


func _process(dt: float) -> void:
	toast_t -= dt
	if toast_t <= 0.0 and toast.modulate.a < 0.05 and toast_queue.size() > 0:
		var q: Array = toast_queue.pop_front()
		say(q[0], q[1], q[2])
	toast.modulate.a = move_toward(toast.modulate.a, 1.0 if toast_t > 0.0 else 0.0, dt * 1.5)
	prompt_t -= dt
	prompt_lbl.modulate.a = move_toward(prompt_lbl.modulate.a, 0.9 if prompt_t > 0.0 else 0.0, dt * 4.0)
	lamp_show -= dt
	var want := 1.0 if (lamp_show > 0.0 or Input.is_action_pressed("show_lanterns")) else 0.0
	lamp_alpha = move_toward(lamp_alpha, want, dt * 1.5)
	lamps.modulate.a = lamp_alpha
	pips.modulate.a = 0.85


class _Pips extends Control:
	var hud: Node

	func _draw() -> void:
		for k in 3:
			var c := Vector2(k * 22.0, 0)
			var has: bool = k < hud.seeds
			draw_circle(c, 7.0, Color(0, 0, 0, 0.35), true, -1.0, true)
			if has:
				draw_circle(c, 8.0, Color(0.4, 1.0, 0.8, 0.15), true, -1.0, true)
				draw_circle(c, 5.0, Color(0.55, 1.6, 1.2), true, -1.0, true)
			else:
				draw_circle(c, 5.0, Color(0.7, 0.75, 0.7, 0.35), false, 1.2, true)


class _Lamps extends Control:
	var hud: Node

	func _draw() -> void:
		for k in 9:
			var c := Vector2(k * 28.0 + 14.0, 12.0)
			var on: bool = hud.lit.has(k)
			var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 0), c + Vector2(0, 9), c + Vector2(-6, 0)])
			if on:
				draw_circle(c, 11.0, Color(1.0, 0.7, 0.35, 0.15), true, -1.0, true)
				draw_colored_polygon(pts, Color(2.0, 1.3, 0.6))
			else:
				pts.append(pts[0])
				draw_polyline(pts, Color(0.8, 0.8, 0.75, 0.5), 1.2, true)
