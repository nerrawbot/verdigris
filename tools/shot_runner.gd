extends Node
## Renders views of the world to shots/*.png. Run (not headless):
## tools\godot.cmd res://scenes/game.tscn -- --shots [only=name,name]

const World = preload("res://scripts/world.gd")

var game: Node


func run() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var views: Array = []
	var w: World = game.world
	views.append(["start", Vector2(w.start), 0.32, 0.0])
	for o in w.objects:
		if o["t"] == "lantern":
			views.append(["lantern_%d_%s" % [o["id"], World.REGION_NAMES[w.region[o["y"] * w.w + o["x"]]].replace(" ", "_")], Vector2(o["x"], o["y"]), 0.4, 0.0])
	var g_spot := Vector2.ZERO
	var k_spot := Vector2.ZERO
	for o in w.objects:
		if o["t"] == "glimmers" and g_spot == Vector2.ZERO:
			g_spot = Vector2(o["x"], o["y"])
		if o["t"] == "kite" and w.region[o["y"] * w.w + o["x"]] == World.R_CANOPY and k_spot == Vector2.ZERO:
			k_spot = Vector2(o["x"], o["y"])
	views.append(["underwater", g_spot, 0.4, 0.0])
	views.append(["canopy_rain", k_spot, 0.45, 0.9])
	views.append(["spire_dusk", Vector2(200, 50), 0.76, 0.0])
	views.append(["start_night", Vector2(w.start), 0.95, 0.0])
	views.append(["spire_day", Vector2(196, 40), 0.45, 0.0])
	await get_tree().process_frame
	if only.has("debughole"):
		game.player.place(Vector2((w.start.x + 0.5) * 16.0, (w.start.y + 1) * 16.0 - 6.01))
		game.player.frozen = true
		game.weather.t_day = 0.32
		game.cam_pos = game.player.pos
		game._update_camera(0.0, true)
		for step in [["a_all", true, true], ["b_noatmos", false, true], ["c_noatmos_nofar", false, false]]:
			game.atmos_rect.visible = step[1]
			game.sky_rect.visible = step[2]
			for k in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://shots/dbghole_%s.png" % step[0])
		get_tree().quit()
		return
	if only.has("debugsky"):
		var t: Vector2 = Vector2(196, 40)
		game.player.place(Vector2((t.x + 0.5) * 16.0, (t.y + 1) * 16.0 - 6.01))
		game.player.frozen = true
		game.weather.t_day = 0.45
		game.cam_pos = game.player.pos
		game._update_camera(0.0, true)
		for step in [["a_all", true, true], ["b_nobackdrop", false, true], ["c_noatmos", false, false]]:
			game.backdrop.visible = step[1]
			game.atmos_rect.visible = step[2]
			for k in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://shots/dbg_%s.png" % step[0])
		game.backdrop.visible = true
		game.atmos_rect.visible = true
		for i in game.backdrop.layers.size():
			for j in game.backdrop.layers.size():
				game.backdrop.layers[j].visible = (i == j)
			for k in 10:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://shots/dbg_layer_%d.png" % i)
			print("layer ", i, " pos ", game.backdrop.layers[i].position, " span ", game.backdrop.layers[i].span)
		print("sky params top ", game.sky_mat.get_shader_parameter("top_col"), " cam_y ", game.sky_mat.get_shader_parameter("cam_y"), " rect ", game.sky_rect.position, game.sky_rect.size, " bd mod ", game.backdrop.layers[0].modulate)
		get_tree().quit()
		return
	if only.has("ui"):
		var hud: CanvasLayer = game.hud
		game.player.place(Vector2((w.start.x + 0.5) * 16.0, (w.start.y + 1) * 16.0 - 6.01))
		game.player.rest()
		game.weather.t_day = 0.3
		game.cam_pos = game.player.pos
		game._update_camera(0.0, true)
		hud.fade.color.a = 0.35
		hud.show_title(true)
		for k in 200:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://shots/ui_title.png")
		hud.show_title(false)
		hud.fade.color.a = 0.0
		for y in range(60, 200, 6):
			for x in range(100, 330, 6):
				hud.map_view.reveal(Vector2i(x, y), 9)
		game.lantern_nodes[0].light_up(true)
		game.nest_nodes[1].found = true
		game._open_map()
		for k in 90:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://shots/ui_map.png")
		game._close_map()
		hud.show_pause(true)
		for k in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://shots/ui_pause.png")
		get_tree().quit()
		return
	if only.has("bench"):
		await _bench(views)
		get_tree().quit()
		return
	if only.has("closeups"):
		await _closeups()
		get_tree().quit()
		return
	for v in views:
		if only.size() > 0 and not only.has(v[0]):
			continue
		var t: Vector2 = v[1]
		game.player.place(Vector2((t.x + 0.5) * 16.0, (t.y + 1) * 16.0 - 6.01))
		game.player.frozen = true
		game.weather.t_day = v[2]
		game.weather.rain = v[3]
		game.weather.rain_target = v[3]
		game.cam_pos = game.player.pos
		game._update_camera(0.0, true)
		for k in 40:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://shots/%s.png" % v[0])
		print("shot ", v[0])
	get_tree().quit()


func _snap(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://shots/close_%s.png" % name)
	print("shot close_", name)


func _drive(inp: Dictionary, n: int) -> void:
	game.player.script_input = inp
	for k in n:
		await get_tree().physics_frame


func _closeups() -> void:
	var p: Node2D = game.player
	var w: World = game.world
	game.zoom_override = 3.0
	game.weather.t_day = 0.42
	p.frozen = false
	# walking on the start floor
	p.place(Vector2((w.start.x + 0.5) * 16.0, (w.start.y + 1) * 16.0 - 6.01))
	await _drive({"x": 0.0}, 10)
	await _drive({"x": -1.0}, 14)
	await _snap("walk")
	await _drive({"x": 0.0, "jump": true}, 9)
	await _snap("jump")
	# a pole
	for y in range(5, w.h - 5):
		var found := false
		for x in range(5, w.w - 5):
			if w.has_flag(x, y, World.F_POLE_V) and not w.is_solid(x, y) and w.is_solid(x, y + 1) and w.has_flag(x, y - 6, World.F_POLE_V) and not w.has_flag(x, y, World.F_WATER):
				p.place(Vector2((x + 0.5) * 16.0, (y + 1) * 16.0 - 6.01))
				found = true
				break
		if found:
			break
	await _drive({"x": 0.0}, 4)
	await _drive({"y": -1.0}, 30)
	await _snap("pole")
	# kite
	var k: Node2D = game.kites[3]
	p.place(k.position)
	await _drive({"x": 0.0}, 1)
	await _drive({"grab_p": true}, 2)
	await _drive({"x": 1.0}, 40)
	await _snap("kite")
	p.release_kite()
	# swimming beside glimmers
	for o in w.objects:
		if o["t"] == "glimmers":
			p.place(Vector2(o["x"], o["y"]) * 16.0 + Vector2(8, 8))
			break
	await _drive({"x": 1.0, "y": -0.3}, 30)
	await _snap("swim")
	# resting at the start nest
	var n: Node2D = game.nest_nodes[0]
	p.place(n.rest_point())
	await _drive({"x": 0.0}, 5)
	await _drive({"y": 1.0}, 5)
	await _drive({"x": 0.0}, 30)
	await _snap("rest")
	game.weather.time_scale = 1.0
	# a lit lantern at dusk
	var l: Node2D = game.lantern_nodes[1]
	p.place(l.position + Vector2(-14, -7))
	l.light_up(true)
	game.weather.t_day = 0.8
	await _drive({"x": 0.0}, 40)
	await _snap("lantern")
	# an echo, read, then a call
	game.weather.t_day = 0.45
	var e: Node2D = game.echoes[2]
	p.place(e.interact_point() + Vector2(-20, -4))
	await _drive({"x": 0.0}, 10)
	game.read_echo(e)
	game.call_cd = 0.0
	await _drive({"call_p": true}, 2)
	await _drive({"x": 0.0}, 50)
	await _snap("echo_call")


func _bench(views: Array) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var total := 0.0
	for v in views:
		var t: Vector2 = v[1]
		game.player.place(Vector2((t.x + 0.5) * 16.0, (t.y + 1) * 16.0 - 6.01))
		game.player.frozen = true
		game.weather.t_day = v[2]
		game.weather.rain = v[3]
		game.cam_pos = game.player.pos
		game._update_camera(0.0, true)
		for k in 30:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for k in 120:
			await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t0) / 120000.0
		total += ms
		print("bench %-34s %.2f ms" % [v[0], ms])
	print("bench mean %.2f ms" % (total / views.size()))