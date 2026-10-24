extends Node2D
## Verdigris: builds the world from the baked data and runs the loop around the
## player: camera, light and weather, interaction, resting, the map and saving.

const World = preload("res://scripts/world.gd")
const Palette = preload("res://scripts/palette.gd")
const TerrainView = preload("res://scripts/terrain_view.gd")
const Backdrop = preload("res://scripts/backdrop.gd")
const WaterSim = preload("res://scripts/water_sim.gd")
const Weather = preload("res://scripts/weather.gd")
const Player = preload("res://scripts/player.gd")
const Hud = preload("res://scripts/hud.gd")
const Audio = preload("res://scripts/audio.gd")
const Plant = preload("res://scripts/obj/plant.gd")
const Seed = preload("res://scripts/obj/seed.gd")
const Vine = preload("res://scripts/obj/vine.gd")
const Lantern = preload("res://scripts/obj/lantern.gd")
const Nest = preload("res://scripts/obj/nest.gd")
const Kite = preload("res://scripts/obj/kite.gd")
const Trundler = preload("res://scripts/obj/trundler.gd")
const Glimmers = preload("res://scripts/obj/glimmers.gd")
const Vent = preload("res://scripts/obj/vent.gd")
const Wisp = preload("res://scripts/obj/wisp.gd")
const Echo = preload("res://scripts/obj/echo.gd")
const Foreground = preload("res://scripts/foreground.gd")

const SAVE_PATH := "user://verdigris_save.json"
const MAX_VINES := 40

var world: World
var weather: Node
var water: Node
var terrain: Node2D
var backdrop: Node2D
var audio: Node
var hud: CanvasLayer
var player: Node2D
var cam: Camera2D
var canvas_mod: CanvasModulate
var sky_rect: ColorRect
var sky_mat: ShaderMaterial
var atmos_rect: ColorRect
var atmos_mat: ShaderMaterial
var foreground: Node2D
var motes: CPUParticles2D
var fireflies: CPUParticles2D
var light_tex: Texture2D

var lantern_nodes := {}
var nest_nodes := {}
var plants: Array = []
var kites: Array = []
var trundlers: Array = []
var vines: Array = []
var echoes: Array = []
var echo_lines := {}   # echo id -> line index it showed

var cam_pos := Vector2.ZERO
var zoom := 1.0
var ambient_now := Color(0.6, 0.6, 0.7)
var openness := 0.5
var sky_open := 0.5
var cur_region := -1
var seen_regions := {}
var started := false
var map_open := false
var rest_spot: Node = null
var call_cd := 0.0
var used_call := false
var play_time := 0.0
var peek := 0.0
var grade_mat: ShaderMaterial
var light_tint := Color(1.0, 0.86, 0.62)
var shadow_tint := Color(0.88, 0.98, 1.04)
## each region has its own light: amber hollows, rust pipeworks, gold canopy,
## cold teal galleries, rose-gold spire; and its own shade in the shadows
const LIGHT_TINT := [Color(1.0, 0.84, 0.6), Color(1.0, 0.7, 0.44), Color(1.0, 0.94, 0.58), Color(0.6, 0.88, 1.0), Color(1.0, 0.82, 0.78)]
const SHADE_TINT := [Color(0.86, 0.98, 1.03), Color(0.93, 0.94, 1.03), Color(0.9, 1.0, 0.97), Color(0.82, 0.96, 1.09), Color(0.93, 0.93, 1.07)]
var peek_t := 0.0
var reveal_t := 0.0
var refresh_t := 0.0
var autosave_t := 120.0
var region_t := 0.0
var drip_t := 4.0
var finale_done := false
var test_mode := false
var zoom_override := 0.0
var snap_light := false
var rng := RandomNumberGenerator.new()


func _init() -> void:
	_register_inputs()


func _register_inputs() -> void:
	var keys := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE, KEY_Z], "grab": [KEY_E, KEY_X], "throw": [KEY_F, KEY_C], "map": [KEY_M],
		"pause": [KEY_ESCAPE, KEY_P], "show_lanterns": [KEY_TAB], "call": [KEY_Q],
	}
	var pads := {"jump": [JOY_BUTTON_A], "grab": [JOY_BUTTON_X], "throw": [JOY_BUTTON_B], "map": [JOY_BUTTON_Y], "pause": [JOY_BUTTON_START], "show_lanterns": [JOY_BUTTON_BACK], "call": [JOY_BUTTON_RIGHT_SHOULDER],
		"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT], "up": [JOY_BUTTON_DPAD_UP], "down": [JOY_BUTTON_DPAD_DOWN]}
	var axes := {"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0], "up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in keys:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a, 0.35)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
		for b in pads.get(a, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(a, jb)
		if axes.has(a):
			var jm := InputEventJoypadMotion.new()
			jm.axis = axes[a][0]
			jm.axis_value = axes[a][1]
			InputMap.action_add_event(a, jm)
	if not InputMap.has_action("throw_mouse"):
		InputMap.add_action("throw_mouse")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("throw_mouse", mb)


func _ready() -> void:
	rng.randomize()
	test_mode = "--walktest" in OS.get_cmdline_user_args() or "--shots" in OS.get_cmdline_user_args()
	world = World.new()
	world.load_data(load("res://assets/world/world.res"))
	world.build_textures()
	light_tex = Player.make_light_texture()
	weather = Weather.new()
	add_child(weather)
	water = WaterSim.new()
	add_child(water)
	water.setup(world)
	var view := get_viewport_rect().size
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_rect = ColorRect.new()
	sky_rect.material = sky_mat
	sky_rect.z_index = -100
	sky_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# sky and far layers live on their own canvas so the ambient light does not dim them
	var far_layer := CanvasLayer.new()
	far_layer.layer = -1
	far_layer.follow_viewport_enabled = true
	add_child(far_layer)
	far_layer.add_child(sky_rect)
	backdrop = Backdrop.new()
	far_layer.add_child(backdrop)
	backdrop.build(world, view)
	terrain = TerrainView.new()
	add_child(terrain)
	terrain.build(world, water.tex)
	atmos_mat = terrain._terrain_mat("res://shaders/atmos.gdshader")
	atmos_rect = ColorRect.new()
	atmos_rect.material = atmos_mat
	atmos_rect.z_index = 30
	atmos_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(atmos_rect)
	foreground = Foreground.new()
	add_child(foreground)
	foreground.build(world.size_px())
	_spawn_objects()
	player = Player.new()
	player.world = world
	player.game = self
	add_child(player)
	player.landed.connect(_on_landed)
	player.jumped.connect(func():
		audio.play("jump", -20.0, 0.08)
		if player.state == Player.St.AIR and player.world.on_floor(player.pos + Vector2(0, 2), Player.HALF):
			puff(player.pos + Vector2(0, 6), "dust", 0.4))
	player.stepped.connect(func(): audio.play("step", -24.0, 0.15))
	player.splashed.connect(func(s: float): splash_at(player.pos, s))
	player.grabbed.connect(func(w: String): audio.play("grab", -18.0, 0.1))
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)
	_setup_environment()
	_setup_particles(view)
	_setup_grade()
	hud = Hud.new()
	add_child(hud)
	hud.map_view.setup(self, world)
	hud.resume_pressed.connect(_resume)
	hud.restart_pressed.connect(_restart)
	hud.quit_pressed.connect(func(): save_game(); get_tree().quit())
	audio = Audio.new()
	add_child(audio)
	var spawn := _start_pos()
	player.place(spawn)
	player.facing = 1
	if not _load_game():
		player.rest()
		nest_nodes[0].found = true
	cam_pos = player.pos
	_update_camera(0.0, true)
	hud.set_seeds(player.seeds)
	hud.set_lit(_lit_ids())
	hud.lamp_show = 0.0
	if test_mode:
		started = true
		hud.fade.color.a = 0.0
		audio.muted_music = true
		var runner_path := "res://tools/shot_runner.gd" if "--shots" in OS.get_cmdline_user_args() else "res://tools/walk_test.gd"
		var runner: Node = load(runner_path).new()
		runner.game = self
		add_child(runner)
		runner.run()
		return
	player.frozen = true
	hud.fade_to(0.0, 3.5)
	hud.show_title(true)


func _start_pos() -> Vector2:
	return Vector2((world.start.x + 0.5) * World.TILE, (world.start.y + 1) * World.TILE - 6.01)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_grade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	grade_mat = ShaderMaterial.new()
	grade_mat.shader = load("res://shaders/grade.gdshader")
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = grade_mat
	layer.add_child(r)


func _setup_particles(view: Vector2) -> void:
	motes = CPUParticles2D.new()
	motes.amount = 70
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.local_coords = false
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = view * 0.65
	motes.direction = Vector2(1, -0.3)
	motes.spread = 180.0
	motes.gravity = Vector2(0, -2)
	motes.initial_velocity_min = 3.0
	motes.initial_velocity_max = 10.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.2
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 0.95, 0.0))
	g.set_color(1, Color(1, 1, 0.95, 0.0))
	g.add_point(0.3, Color(1, 1, 0.92, 0.35))
	g.add_point(0.7, Color(1, 1, 0.92, 0.3))
	motes.color_ramp = g
	motes.z_index = 25
	add_child(motes)
	fireflies = CPUParticles2D.new()
	fireflies.amount = 36
	fireflies.lifetime = 7.0
	fireflies.preprocess = 7.0
	fireflies.local_coords = false
	fireflies.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fireflies.emission_rect_extents = view * 0.6
	fireflies.spread = 180.0
	fireflies.gravity = Vector2.ZERO
	fireflies.initial_velocity_min = 5.0
	fireflies.initial_velocity_max = 16.0
	fireflies.scale_amount_min = 1.6
	fireflies.scale_amount_max = 2.6
	var fg := Gradient.new()
	fg.set_color(0, Color(1.6, 1.9, 0.6, 0.0))
	fg.set_color(1, Color(1.6, 1.9, 0.6, 0.0))
	fg.add_point(0.2, Color(1.8, 2.1, 0.7, 1.0))
	fg.add_point(0.45, Color(1.0, 1.3, 0.4, 0.2))
	fg.add_point(0.7, Color(1.8, 2.1, 0.7, 1.0))
	fireflies.color_ramp = fg
	fireflies.z_index = 6
	fireflies.light_mask = 0
	add_child(fireflies)


func _spawn_objects() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = 99
	for o in world.objects:
		var t := Vector2i(o["x"], o["y"])
		match o["t"]:
			"nest":
				var n := Nest.new()
				n.setup(t, o["id"])
				add_child(n)
				nest_nodes[o["id"]] = n
			"lantern":
				var l := Lantern.new()
				l.game = self
				l.setup(t, o["id"], o["kind"], light_tex)
				add_child(l)
				lantern_nodes[o["id"]] = l
			"plant":
				var p := Plant.new()
				p.game = self
				p.setup(t, prng)
				add_child(p)
				plants.append(p)
			"kite":
				var k := Kite.new()
				k.game = self
				k.world = world
				k.setup(Vector2(t) * World.TILE + Vector2(8, 8), prng)
				add_child(k)
				kites.append(k)
			"trundler":
				var tr := Trundler.new()
				tr.game = self
				tr.world = world
				tr.setup(t, prng)
				add_child(tr)
				trundlers.append(tr)
				world.platforms.append(tr)
			"glimmers":
				var g := Glimmers.new()
				g.game = self
				g.world = world
				g.setup(Vector2(t) * World.TILE + Vector2(8, 8), light_tex)
				add_child(g)
			"echo":
				var e := Echo.new()
				e.game = self
				e.setup(t, o["id"])
				add_child(e)
				echoes.append(e)
			"vent":
				var v := Vent.new()
				v.setup(t, o["w"], o["h"], o["kind"], light_tex)
				add_child(v)


# ------------------------------------------------------------------ helpers

func near_camera(p: Vector2, r: float) -> bool:
	return p.distance_squared_to(cam_pos) < r * r


func _lit_ids() -> Array:
	var out: Array = []
	for l in lantern_nodes.values():
		if l.lit:
			out.append(l.id)
	return out


## Little one-shot bursts: dust from feet, droplets from water.
func puff(p: Vector2, kind: String, strength := 1.0) -> void:
	var q := CPUParticles2D.new()
	q.one_shot = true
	q.explosiveness = 0.95
	q.local_coords = false
	q.position = p
	q.z_index = 14
	var g := Gradient.new()
	if kind == "splash":
		q.amount = int(10 + 14 * strength)
		q.lifetime = 0.7
		q.direction = Vector2(0, -1)
		q.spread = 50.0
		q.initial_velocity_min = 60.0 * strength + 40.0
		q.initial_velocity_max = 160.0 * strength + 60.0
		q.gravity = Vector2(0, 600)
		q.scale_amount_min = 1.2
		q.scale_amount_max = 2.2
		g.set_color(0, Color(0.75, 0.92, 0.95, 0.9))
		g.set_color(1, Color(0.75, 0.92, 0.95, 0.0))
	else:
		q.amount = int(6 + 8 * strength)
		q.lifetime = 0.55
		q.direction = Vector2(0, -1)
		q.spread = 80.0
		q.initial_velocity_min = 20.0
		q.initial_velocity_max = 60.0 * strength + 20.0
		q.gravity = Vector2(0, 40)
		q.damping_min = 40.0
		q.damping_max = 80.0
		q.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		q.emission_rect_extents = Vector2(6, 1)
		q.scale_amount_min = 1.5
		q.scale_amount_max = 3.0
		var dc: Color = Palette.FOG[world.region_px(p)].lerp(Color(0.8, 0.78, 0.7), 0.4)
		g.set_color(0, Color(dc.r, dc.g, dc.b, 0.5))
		g.set_color(1, Color(dc.r, dc.g, dc.b, 0.0))
	q.color_ramp = g
	add_child(q)
	q.emitting = true
	get_tree().create_timer(q.lifetime + 0.2).timeout.connect(q.queue_free)


func splash_at(p: Vector2, s: float) -> void:
	puff(Vector2(p.x, world.water_surface_y(p + Vector2(0, 8)) if world.water_px(p + Vector2(0, 8)) else p.y), "splash", s)
	water.splash(p.x, -170.0 * s, 3 + int(s * 3.0))
	audio.play("splash", lerpf(-22.0, -8.0, s), 0.1)


func _on_landed(speed: float) -> void:
	if speed > 220.0:
		puff(player.pos + Vector2(0, 6), "dust", clampf(speed / 560.0, 0.3, 1.0))
	if speed > 160.0:
		audio.play("land", lerpf(-24.0, -10.0, clampf(speed / 560.0, 0.0, 1.0)), 0.1)


# ------------------------------------------------------------------ interaction

func _nearest_interactable(p: Node2D) -> Array:
	var best: Node = null
	var kind := ""
	var bd := 1e9
	for l in lantern_nodes.values():
		if l.lit:
			continue
		var d: float = p.pos.distance_to(l.interact_point())
		if d < 30.0 and d < bd:
			bd = d
			best = l
			kind = "lantern"
	if p.seeds < Player.MAX_SEEDS:
		for pl in plants:
			if not pl.ripe:
				continue
			var d: float = p.pos.distance_to(pl.bulb_world())
			if d < 24.0 and d < bd:
				bd = d
				best = pl
				kind = "plant"
	if p.kite == null:
		for k in kites:
			var d: float = p.pos.distance_to(k.position)
			if d < 26.0 and d < bd:
				bd = d
				best = k
				kind = "kite"
	for tr in trundlers:
		var d: float = p.pos.distance_to(tr.position - Vector2(0, 10))
		if d < 26.0 and d < bd:
			bd = d
			best = tr
			kind = "trundler"
	for e in echoes:
		var d: float = p.pos.distance_to(e.interact_point())
		if d < 26.0 and d < bd:
			bd = d
			best = e
			kind = "echo"
	return [kind, best]


func interact(p: Node2D) -> bool:
	var r := _nearest_interactable(p)
	var kind: String = r[0]
	var node: Node = r[1]
	match kind:
		"lantern":
			light_lantern(node)
		"plant":
			if node.pick():
				p.seeds += 1
				hud.set_seeds(p.seeds)
				audio.play("pop", -10.0, 0.1)
				if p.seeds == 1 and not seen_regions.has("seed_tip"):
					seen_regions["seed_tip"] = true
					hud.say("a springseed. throw it [F] at stone and it will grow a vine to climb", 6.0)
		"kite":
			node.held = true
			p.take_kite(node)
			audio.play("flutter", -12.0, 0.1)
		"trundler":
			node.pet()
			audio.play("hum", -10.0, 0.08)
		"echo":
			read_echo(node)
		_:
			return false
	return true


func light_lantern(l: Node) -> void:
	if l.lit:
		return
	l.light_up()
	audio.play("chirp", -8.0)
	var ids := _lit_ids()
	audio.lantern_lit(ids.size())
	hud.set_lit(ids)
	var total := lantern_nodes.size()
	if ids.size() < total:
		hud.say("the lantern wakes.  %d of %d sing" % [ids.size(), total], 5.0)
		if ids.size() == 1:
			get_tree().create_timer(5.5).timeout.connect(hint.bind("lantern_rest", "a woken lantern is a warm place: rest beside it, and dream back to it from any nest", 7.0))
	elif not finale_done:
		finale_done = true
		hud.banner("The works remember warmth", "every lantern sings. wander as long as you like")
		weather.rain_target = 0.0
	save_game()


func read_echo(e: Node) -> void:
	if not echo_lines.has(e.id):
		echo_lines[e.id] = echo_lines.size()
		e.read = true
		audio.play("chime_%d" % (echo_lines.size() % 6), -12.0)
		save_game()
	var line: String = Echo.LINES[int(echo_lines[e.id]) % Echo.LINES.size()]
	hud.say("\"" + line + "\"      echo %d of %d" % [echo_lines.size(), echoes.size()], 9.0, 2)


func throw_seed(at: Vector2, v: Vector2) -> void:
	var s := Seed.new()
	s.game = self
	s.world = world
	s.position = at
	s.vel = v
	add_child(s)
	hud.set_seeds(player.seeds)
	audio.play("throw", -16.0, 0.1)


func sprout(p: Vector2, n: Vector2) -> void:
	var t := world.tile_of(p)
	if world.is_solid(t.x, t.y):
		t = world.tile_of(p - n * 5.0)
	if world.is_solid(t.x, t.y):
		return
	var top := t.y
	var bot := t.y
	var rb := true
	if n.y > 0.0:
		var wet := world.has_flag(t.x, t.y, World.F_WATER)
		var maxl := 30 if wet else 14
		while bot - top + 1 < maxl and not world.is_solid(t.x, top - 1):
			top -= 1
			if wet and not world.has_flag(t.x, top + 2, World.F_WATER):
				break
	elif n.y < 0.0:
		rb = false
		while bot - top + 1 < 12 and not world.is_solid(t.x, bot + 1) and not world.has_flag(t.x, bot + 1, World.F_WATER):
			bot += 1
	else:
		while top > t.y - 8 and not world.is_solid(t.x, top - 1):
			top -= 1
		while bot < t.y + 4 and not world.is_solid(t.x, bot + 1) and not world.has_flag(t.x, bot + 1, World.F_WATER):
			bot += 1
	if bot - top < 1:
		return
	add_vine(t.x, top, bot, rb, false)
	audio.play("grow", -12.0, 0.1)


func add_vine(x: int, top: int, bot: int, rb: bool, instant: bool) -> void:
	var v := Vine.new()
	v.game = self
	add_child(v)
	v.setup(world, x, top, bot, rb, instant)
	vines.append(v)
	while vines.size() > MAX_VINES:
		var old: Node = vines.pop_front()
		old.start_wither()


# ------------------------------------------------------------------ rest and travel

## Rest spots are the nests plus every lit lantern (not the sunken one).
func _rest_spots() -> Array:
	var out: Array = nest_nodes.values()
	for l in lantern_nodes.values():
		if l.lit and l.kind != "deep":
			out.append(l)
	return out


func _nest_near(p: Vector2, r: float) -> Node:
	for n in _rest_spots():
		if p.distance_to(n.rest_point()) < r:
			return n
	return null


func rest_at(n: Node) -> void:
	player.pos = n.rest_point()
	player.vel = Vector2.ZERO
	player.rest()
	if "found" in n:
		n.found = true
	n.queue_redraw()
	rest_spot = n
	weather.time_scale = 14.0
	save_game()
	hud.say("resting. time drifts by.  [M] dream to another nest or lantern", 5.0)


func on_wake() -> void:
	weather.time_scale = 1.0
	rest_spot = null
	if map_open:
		_close_map()


func _travel_spots() -> Array:
	var out: Array = []
	for n in _rest_spots():
		if n is Nest and not n.found:
			continue
		out.append(n)
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


func _open_map() -> void:
	map_open = true
	hud.map_view.refresh()
	hud.map_view.visible = true
	hud.map_view.travel = false
	if player.is_resting():
		var spots := _travel_spots()
		if spots.size() > 1:
			hud.map_view.travel = true
			hud.map_view.choices = spots
			hud.map_view.choice = maxi(spots.find(rest_spot), 0)
	player.frozen = true


func _close_map() -> void:
	map_open = false
	hud.map_view.visible = false
	player.frozen = not started


func _travel_to(n: Node) -> void:
	_close_map()
	player.frozen = true
	var tw: Tween = hud.fade_to(1.0, 1.0)
	await tw.finished
	player.place(n.rest_point())
	rest_at(n)
	cam_pos = player.pos
	_update_camera(0.0, true)
	await hud.fade_to(0.0, 1.5).finished
	player.frozen = false


# ------------------------------------------------------------------ calling

## Q: the sprig calls out. The nearest sleeping lantern answers with a chime
## (quieter the further it is) and a mote of light drifts off towards it.
func call_out(p: Node2D) -> void:
	if call_cd > 0.0:
		return
	call_cd = 3.0
	audio.play("chirp", -9.0, 0.12)
	used_call = true
	var best: Node2D = null
	var bd := 1e9
	for l in lantern_nodes.values():
		if l.lit:
			continue
		var d: float = p.pos.distance_to(l.position)
		if d < bd:
			bd = d
			best = l
	if best == null:
		for n in nest_nodes.values():
			if n.found:
				continue
			var d: float = p.pos.distance_to(n.position)
			if d < bd:
				bd = d
				best = n
	if best == null:
		hint("call_none", "only the works hum back. every lantern is awake")
		return
	var w := Wisp.new()
	w.setup(p.pos + Vector2(0, -10), best.position + Vector2(0, -16), light_tex)
	add_child(w)
	var delay := clampf(bd / 1800.0, 0.3, 2.2)
	var vol := lerpf(-8.0, -30.0, clampf(bd / 3500.0, 0.0, 1.0))
	get_tree().create_timer(delay).timeout.connect(_answer.bind(best, vol))
	if best is Lantern:
		hint("call_first", "far off, something answers. follow the light", 5.0)
	else:
		hint("call_nest", "no lantern sleeps nearby, but a nest is that way", 5.0)


func _answer(who: Node, vol: float) -> void:
	audio.play("chime_%d" % (who.get_instance_id() % 6), vol)
	if who.has_method("answer"):
		who.answer()


# ------------------------------------------------------------------ hints

func hint(key: String, text: String, secs := 6.0) -> void:
	if seen_regions.has("hint_" + key):
		return
	seen_regions["hint_" + key] = true
	hud.say(text, secs)


func _update_hints(dt: float) -> void:
	if player.frozen or player.is_resting():
		return
	play_time += dt
	var st: int = player.state
	if st == Player.St.WALL:
		hint("wall", "rough rock: W and S to climb, Space to leap away")
	elif st == Player.St.SWIM:
		hint("swim", "you swim as easily as you walk. Space leaps from the surface, or darts underwater")
	elif player.kite != null:
		hint("kite", "the kite lets you down gently, and updrafts lift you. E to let go")
	elif st == Player.St.POLE_H:
		hint("hang", "W pulls you up on top, S lets go")
	elif st != Player.St.POLE_V and player._is_climb_tile(player.pos):
		hint("pole", "hold W to take hold and climb")
	elif st == Player.St.AIR and absf(float(player.inp["x"])) > 0.5:
		var side := 1 if float(player.inp["x"]) > 0.0 else -1
		if player._touching(side) and not player._climbable(side):
			hint("slick", "smooth concrete is too slick to cling to. Space leaps off it")
	elif st == Player.St.GROUND and player._on_oneway() and player.carrier == null:
		hint("grate", "hold S and press Space to drop through a grate")
	if play_time > 50.0 and not used_call:
		hint("call", "press Q to call out. sleeping lanterns will answer", 7.0)

# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not started:
		if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
			_begin()
		return
	if event.is_action_pressed("pause"):
		if map_open:
			_close_map()
		else:
			_pause()
		return
	if event.is_action_pressed("map"):
		if map_open:
			_close_map()
		else:
			_open_map()
		return
	if map_open and hud.map_view.travel:
		var mv: Control = hud.map_view
		if event.is_action_pressed("left"):
			mv.choice = (mv.choice - 1 + mv.choices.size()) % mv.choices.size()
		elif event.is_action_pressed("right"):
			mv.choice = (mv.choice + 1) % mv.choices.size()
		elif event.is_action_pressed("grab") or event.is_action_pressed("jump"):
			var dest: Node = mv.choices[mv.choice]
			if dest != rest_spot:
				_travel_to(dest)
			else:
				_close_map()


func _begin() -> void:
	started = true
	player.frozen = false
	hud.show_title(false)
	hud.fade_to(0.0, 0.5)
	if not seen_regions.has("move_tip"):
		seen_regions["move_tip"] = true
		get_tree().create_timer(2.5).timeout.connect(func(): hud.say("A D to wander, Space to jump, hold W to climb.  Esc for everything else", 7.0))


func _pause() -> void:
	get_tree().paused = true
	hud.show_pause(true)


func _resume() -> void:
	get_tree().paused = false
	hud.show_pause(false)


func _restart() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().paused = false
	get_tree().reload_current_scene()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and started and not test_mode:
		save_game()


# ------------------------------------------------------------------ frame

func _process(dt: float) -> void:
	weather.step(dt)
	water.rain = weather.rain
	_update_camera(dt, false)
	_update_light(dt)
	_update_prompts()
	call_cd -= dt
	if started:
		_update_rest()
		_update_explore(dt)
		_update_hints(dt)
	audio.update_env(dt, sky_open, weather.rain, player.in_water and world.water_px(cam_pos.lerp(player.pos, 0.7)), weather.night, player.is_resting())
	drip_t -= dt
	if drip_t <= 0.0:
		drip_t = rng.randf_range(2.5, 7.0)
		if sky_open < 0.3 and not player.in_water:
			audio.play("drip", -26.0 + weather.rain * 8.0, 0.25)
	autosave_t -= dt
	if autosave_t <= 0.0 and started and not test_mode:
		autosave_t = 120.0
		save_game()


func _sample_open(p: Vector2) -> void:
	var air := 0
	var sk := 0.0
	var n := 0
	var t := world.tile_of(p)
	for dy in range(-9, 10, 3):
		for dx in range(-15, 16, 3):
			n += 1
			var x := t.x + dx
			var y := t.y + dy
			if not world.is_solid(x, y):
				air += 1
			if world.inb(x, y):
				sk += world.sky[y * world.w + x] / 255.0
	openness = clampf((float(air) / n - 0.45) / 0.45, 0.0, 1.0)
	sky_open = clampf(sk / n * 2.2, 0.0, 1.0)


func _update_camera(dt: float, snap: bool) -> void:
	var view := get_viewport_rect().size
	_sample_open(player.pos)
	# standing still and holding W or S lets you peek up or down
	var iy: float = player.inp["y"]
	if player.state == Player.St.GROUND and absf(player.vel.x) < 5.0 and absf(iy) > 0.5 and not player.frozen:
		peek_t += dt
	else:
		peek_t = 0.0
	var want_peek := signf(iy) * 150.0 if peek_t > 0.45 else 0.0
	peek = lerpf(peek, want_peek, 1.0 - exp(-dt * 3.0)) if not snap else 0.0
	var target: Vector2 = player.pos + Vector2(player.vel.x * 0.16, player.vel.y * 0.05) + Vector2(0, -18 + peek)
	var zt := lerpf(1.0, 0.8, openness)
	if zoom_override > 0.0:
		zt = zoom_override
		snap = true
	if snap:
		cam_pos = target
		zoom = zt
		snap_light = true
	else:
		cam_pos = cam_pos.lerp(target, 1.0 - exp(-dt * 4.0))
		zoom = lerpf(zoom, zt, 1.0 - exp(-dt * 0.7))
	var half := view / (2.0 * zoom)
	var ws := world.size_px()
	cam_pos.x = clampf(cam_pos.x, half.x, ws.x - half.x)
	cam_pos.y = clampf(cam_pos.y, half.y, ws.y - half.y)
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	var cover := view / zoom + Vector2(64, 64)
	sky_rect.position = cam_pos - cover * 0.5
	sky_rect.size = cover
	atmos_rect.position = sky_rect.position
	atmos_rect.size = cover
	foreground.follow(cam_pos)
	motes.position = cam_pos
	fireflies.position = cam_pos
	motes.emission_rect_extents = cover * 0.5
	fireflies.emission_rect_extents = cover * 0.5


func _update_light(dt: float) -> void:
	var reg := world.region_px(player.pos)
	var cave := lerpf(0.84, 1.0, sky_open)
	var reg_f := 0.86 if reg == World.R_SUNKEN else 1.0
	var a: Color = weather.ambient * cave * reg_f
	if player.in_water:
		var sy := world.water_surface_y(player.pos)
		if sy < INF:
			a *= lerpf(1.0, 0.65, clampf((player.pos.y - sy) / 300.0, 0.0, 1.0))
	ambient_now = ambient_now.lerp(a, 1.0 - exp(-dt * 1.5)) if (dt > 0.0 and not snap_light) else a
	snap_light = false
	ambient_now.a = 1.0
	canvas_mod.color = ambient_now
	var w: Node = weather
	sky_mat.set_shader_parameter("top_col", Vector3(w.sky_top.r, w.sky_top.g, w.sky_top.b))
	sky_mat.set_shader_parameter("horizon_col", Vector3(w.sky_horizon.r, w.sky_horizon.g, w.sky_horizon.b))
	# deep openings show the daylight that pours through them (dark at night)
	var ab: Color = (w.sky_horizon * 0.8).lerp(w.sun_col * light_tint, 0.4 * (1.0 - w.rain)) * lerpf(1.25, 0.2, w.night) * (1.0 - w.rain * 0.55)
	sky_mat.set_shader_parameter("abyss_col", Vector3(ab.r, ab.g, ab.b))
	sky_mat.set_shader_parameter("sun_col", Vector3(w.sun_col.r, w.sun_col.g, w.sun_col.b))
	sky_mat.set_shader_parameter("sun_amount", w.sun_amount)
	sky_mat.set_shader_parameter("star_amount", w.star_amount)
	sky_mat.set_shader_parameter("cloud_amount", 0.4 + w.rain * 0.6)
	var day_x := fposmod(w.t_day - 0.25, 0.5) / 0.5
	sky_mat.set_shader_parameter("sun_dir", Vector2(0.1 + day_x * 0.8, 0.12 + 0.3 * (1.0 - sin(PI * day_x))))
	sky_mat.set_shader_parameter("cam_y", cam_pos.y)
	sky_mat.set_shader_parameter("view_h", sky_rect.size.y)
	sky_mat.set_shader_parameter("horizon_y", 430.0)
	sky_mat.set_shader_parameter("abyss_y", 700.0)
	sky_mat.set_shader_parameter("water_y", 204.0 * World.TILE)
	var glow: float = 1.0 + w.night * 1.3
	var k := 1.0 if (snap_light or dt <= 0.0) else 1.0 - exp(-dt * 0.8)
	light_tint = light_tint.lerp(LIGHT_TINT[reg], k)
	shadow_tint = shadow_tint.lerp(SHADE_TINT[reg], k)
	var sun: Color = (w.sun_col * light_tint).lerp(Color(0.55, 0.65, 0.95), w.night * 0.6)
	var sun_strength: float = clampf(0.3 + w.sun_amount * 0.9, 0.3, 1.05) * lerpf(1.0, 0.4, w.night) * (1.0 - 0.65 * w.rain)
	terrain.set_atmosphere(w.sky_tint, 0.42 + w.rain * 0.12, ambient_now, w.wind, glow, sun, sun_strength)
	atmos_mat.set_shader_parameter("sun_col", Vector3(sun.r, sun.g, sun.b))
	atmos_mat.set_shader_parameter("sun_strength", sun_strength)
	atmos_mat.set_shader_parameter("shaft_amount", sun_strength)
	var st := shadow_tint.lerp(Color(0.8, 0.9, 1.12), w.night * 0.5)
	var ht: Color = Color(1.07, 1.0, 0.88).lerp(Color(1.1, 0.95, 0.82), clampf(w.sun_amount - 0.55, 0.0, 0.4) * 2.0)
	grade_mat.set_shader_parameter("shadow_tint", Vector3(st.r, st.g, st.b))
	grade_mat.set_shader_parameter("highlight_tint", Vector3(ht.r, ht.g, ht.b))
	grade_mat.set_shader_parameter("vignette", 0.34 + w.night * 0.16)
	atmos_mat.set_shader_parameter("rain", w.rain)
	atmos_mat.set_shader_parameter("mist", 0.3 + w.rain * 0.3 + w.night * 0.2)
	atmos_mat.set_shader_parameter("ambient", Vector3(ambient_now.r, ambient_now.g, ambient_now.b))
	atmos_mat.set_shader_parameter("wind", 0.08 + w.wind * 0.25)
	atmos_mat.set_shader_parameter("sky_tint", Vector3(w.sky_tint.r, w.sky_tint.g, w.sky_tint.b))
	var depth_fade := 1.0 - clampf((cam_pos.y - 1500.0) / 1100.0, 0.0, 1.0)
	backdrop.follow(cam_pos, Color(0.16, 0.18, 0.24).lerp(w.sky_top, 0.25), w.sky_horizon.lerp(w.sky_top, 0.25))
	backdrop.modulate = Color(1, 1, 1, depth_fade)
	var nightish: float = w.night
	var organic := reg == World.R_HOLLOWS or reg == World.R_CANOPY or reg == World.R_SUNKEN
	fireflies.modulate.a = move_toward(fireflies.modulate.a, nightish if organic and not player.in_water else 0.0, dt * 0.5)
	motes.modulate = Color(w.sky_horizon.r, w.sky_horizon.g, w.sky_horizon.b, 0.6 + 0.4 * (1.0 - nightish))


func _update_prompts() -> void:
	if not started or player.frozen or map_open:
		return
	if player.is_resting():
		return
	var r := _nearest_interactable(player)
	match r[0]:
		"lantern":
			hud.prompt("[E]  sing to the lantern")
		"plant":
			hud.prompt("[E]  pick the springseed")
		"kite":
			hud.prompt("[E]  hold on to the drift-kite")
		"trundler":
			hud.prompt("[E]  hum to the trundler")
		"echo":
			hud.prompt("[E]  read the echo")
		_:
			if player.kite != null:
				hud.prompt("[E]  let go")
			elif _nest_near(player.pos, 18.0) != null:
				hud.prompt("hold [S]  curl up and rest")
	for n in nest_nodes.values():
		var h := 1.0 if player.pos.distance_to(n.rest_point()) < 60.0 else 0.0
		if absf(n.hint - h) > 0.01:
			n.hint = move_toward(n.hint, h, 0.05)
			n.queue_redraw()


func _update_rest() -> void:
	if player.frozen or player.is_resting():
		return
	if player.state == Player.St.GROUND and float(player.inp["y"]) > 0.5 and absf(player.vel.x) < 8.0:
		var n := _nest_near(player.pos, 18.0)
		if n != null:
			rest_at(n)


func _update_explore(dt: float) -> void:
	reveal_t -= dt
	if reveal_t <= 0.0:
		reveal_t = 0.25
		if hud.map_view.reveal(world.tile_of(player.pos), 16):
			refresh_t = minf(refresh_t, 0.0) if map_open else refresh_t
	refresh_t -= dt
	if refresh_t <= 0.0:
		refresh_t = 1.0
		hud.map_view.refresh()
	region_t -= dt
	if region_t <= 0.0:
		region_t = 0.5
		var reg := world.region_px(player.pos)
		if reg != cur_region:
			cur_region = reg
			if not seen_regions.has(reg):
				seen_regions[reg] = true
				hud.banner(World.REGION_NAMES[reg], World.REGION_SUBS[reg])


# ------------------------------------------------------------------ save

func save_game() -> void:
	var d := {
		"v": 1,
		"pos": [player.pos.x, player.pos.y],
		"resting": player.is_resting(),
		"lit": _lit_ids(),
		"found": [],
		"vines": [],
		"seeds": player.seeds,
		"t_day": weather.t_day,
		"seen": Marshalls.raw_to_base64(hud.map_view.seen_data()),
		"regions": [],
		"echoes": echo_lines,
	}
	for n in nest_nodes.values():
		if n.found:
			d["found"].append(n.id)
	for v in vines:
		if v.wither <= 0.0:
			d["vines"].append(v.save_data())
	for k in seen_regions.keys():
		d["regions"].append(k)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


func _load_game() -> bool:
	if test_mode or not FileAccess.file_exists(SAVE_PATH):
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for id in d.get("lit", []):
		var l: Node = lantern_nodes.get(int(id))
		if l:
			l.light_up(true)
	finale_done = _lit_ids().size() >= lantern_nodes.size()
	for id in d.get("found", []):
		var n: Node = nest_nodes.get(int(id))
		if n:
			n.found = true
	for v in d.get("vines", []):
		add_vine(int(v["x"]), int(v["top"]), int(v["bot"]), bool(v["rb"]), true)
	var el: Dictionary = d.get("echoes", {})
	for k in el:
		echo_lines[int(k)] = int(el[k])
	for e in echoes:
		if echo_lines.has(e.id):
			e.read = true
			e.glow = 1.0
	player.seeds = int(d.get("seeds", 0))
	weather.t_day = float(d.get("t_day", 0.3))
	for k in d.get("regions", []):
		seen_regions[k if typeof(k) == TYPE_STRING and not str(k).is_valid_int() else int(k)] = true
	var seen: String = d.get("seen", "")
	if seen != "":
		hud.map_view.load_seen(Marshalls.base64_to_raw(seen))
	var p: Array = d.get("pos", [])
	if p.size() == 2:
		player.place(Vector2(p[0], p[1]))
	if d.get("resting", false):
		var n := _nest_near(player.pos, 20.0)
		if n:
			rest_at(n)
			weather.time_scale = 14.0
	return true
