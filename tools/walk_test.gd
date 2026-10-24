extends Node
## Drives the sprig with scripted input and checks each movement mechanic.
## tools\godot.cmd --headless res://scenes/game.tscn -- --walktest

const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")

var game: Node
var p: Node2D
var w: World
var fails := 0
var passes := 0


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		passes += 1
		print("  ok   ", name, "  ", info)
	else:
		fails += 1
		print("  FAIL ", name, "  ", info)


func frames(n: int, inp := {}) -> void:
	p.script_input = inp.duplicate()
	if p.script_input.is_empty():
		p.script_input = {"x": 0.0}
	for k in n:
		await get_tree().physics_frame


func put(tile: Vector2i) -> void:
	p.place(Vector2((tile.x + 0.5) * 16.0, (tile.y + 1) * 16.0 - 6.01))
	p.frozen = false
	p.seeds = 0
	p.release_kite()
	await frames(2)


func standing(x: int, y: int) -> bool:
	return not w.is_solid(x, y) and (w.is_solid(x, y + 1)) and not w.has_flag(x, y, World.F_WATER)


func find_flat(min_run: int, need_head: int) -> Vector2i:
	for y in range(10, w.h - 10):
		for x in range(10, w.w - 10):
			var ok := true
			for k in min_run:
				if not standing(x + k, y) or w.flag(x + k, y) != 0:
					ok = false
					break
				for hh in range(1, need_head + 1):
					if w.is_solid(x + k, y - hh):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func run() -> void:
	p = game.player
	w = game.world
	await get_tree().process_frame
	print("walk test")
	# 1. walking on flat ground
	var flat := find_flat(12, 7)
	await put(flat)
	await frames(10)
	check("lands on floor", p.state == Player.St.GROUND, str(p.pos))
	var x0: float = p.pos.x
	await frames(40, {"x": 1.0})
	check("walks right", p.pos.x - x0 > 60.0, "moved %.0f px" % (p.pos.x - x0))
	# 2. jump height
	await put(flat + Vector2i(3, 0))
	await frames(5)
	var y0: float = p.pos.y
	var peak := y0
	p.script_input = {"x": 0.0, "jump": true}
	for k in 60:
		await get_tree().physics_frame
		peak = minf(peak, p.pos.y)
	check("full jump rises 4+ tiles", y0 - peak >= 64.0, "%.1f px" % (y0 - peak))
	await frames(40)
	await put(flat + Vector2i(3, 0))
	await frames(5)
	y0 = p.pos.y
	peak = y0
	p.script_input = {"x": 0.0, "jump": true}
	await get_tree().physics_frame
	await get_tree().physics_frame
	p.script_input = {"x": 0.0, "jump": false}
	for k in 50:
		await get_tree().physics_frame
		peak = minf(peak, p.pos.y)
	check("tap jump is a short hop", y0 - peak < 40.0 and y0 - peak > 8.0, "%.1f px" % (y0 - peak))
	# 3. pole climbing
	var pole := Vector2i(-1, -1)
	for y in range(5, w.h - 5):
		for x in range(5, w.w - 5):
			if w.has_flag(x, y, World.F_POLE_V) and standing(x, y) and w.has_flag(x, y - 6, World.F_POLE_V) and not w.has_flag(x, y, World.F_WATER):
				pole = Vector2i(x, y)
				break
		if pole.x >= 0:
			break
	await put(pole)
	await frames(3)
	y0 = p.pos.y
	await frames(50, {"y": -1.0})
	check("grabs and climbs a pole", p.state == Player.St.POLE_V and y0 - p.pos.y > 48.0, "state %d rose %.0f" % [p.state, y0 - p.pos.y])
	await frames(20, {"x": 0.0, "jump": true})
	check("jumps off the pole", p.state != Player.St.POLE_V)
	# 4. rock wall climbing
	var wall := Vector2i(-1, -1)
	for y in range(5, 200):
		for x in range(5, w.w - 5):
			if standing(x, y) and w.mat(x + 1, y) == World.ROCK and w.mat(x + 1, y - 1) == World.ROCK and w.mat(x + 1, y - 2) == World.ROCK and w.mat(x + 1, y - 3) == World.ROCK and not w.is_solid(x, y - 1) and not w.is_solid(x, y - 2) and not w.is_solid(x, y - 3) and not w.is_solid(x, y - 4):
				wall = Vector2i(x, y)
				break
		if wall.x >= 0:
			break
	await put(wall)
	await frames(3)
	y0 = p.pos.y
	await frames(6, {"x": 1.0, "jump": true})
	await frames(50, {"x": 1.0, "y": -1.0})
	check("clings to and climbs rock", y0 - p.pos.y > 30.0, "state %d rose %.0f" % [p.state, y0 - p.pos.y])
	# 5. concrete is too smooth to cling to
	var cwall := Vector2i(-1, -1)
	for y in range(5, 200):
		for x in range(5, w.w - 5):
			if standing(x, y) and w.mat(x + 1, y) == World.CONC and w.mat(x + 1, y - 1) == World.CONC and w.mat(x + 1, y - 2) == World.CONC and w.mat(x + 1, y - 3) == World.CONC and w.mat(x + 1, y - 4) == World.CONC and w.mat(x + 1, y - 5) == World.CONC and not w.is_solid(x, y - 1) and not w.is_solid(x, y - 2) and not w.is_solid(x, y - 3) and not w.is_solid(x, y - 4) and w.flag(x, y) == 0 and w.flag(x, y - 2) == 0:
				cwall = Vector2i(x, y)
				break
		if cwall.x >= 0:
			break
	await put(cwall)
	await frames(6, {"x": 1.0, "jump": true})
	await frames(60, {"x": 1.0, "y": -1.0})
	check("cannot cling to concrete", p.state != Player.St.WALL, "state %d" % p.state)
	# 6. swimming
	var wt := Vector2i(-1, -1)
	for y in range(210, w.h - 4):
		for x in range(5, w.w - 5):
			if w.has_flag(x, y, World.F_WATER) and w.has_flag(x, y + 2, World.F_WATER) and not w.is_solid(x, y - 1) and not w.is_solid(x, y + 1):
				wt = Vector2i(x, y)
				break
		if wt.x >= 0:
			break
	p.place(Vector2(wt) * 16.0 + Vector2(8, 8))
	await frames(5)
	check("swims in water", p.state == Player.St.SWIM)
	y0 = p.pos.y
	await frames(40, {"y": -1.0})
	check("swims upward", y0 - p.pos.y > 30.0 or p.at_surface, "%.0f" % (y0 - p.pos.y))
	# 7. seeds grow climbable vines
	await put(flat + Vector2i(5, 0))
	await frames(5)
	p.seeds = 1
	var vines_before: int = game.vines.size()
	await frames(2, {"y": 1.0, "throw_p": true})
	await frames(90)
	check("thrown seed sprouts a vine", game.vines.size() == vines_before + 1)
	if game.vines.size() > vines_before:
		var v: Node = game.vines[game.vines.size() - 1]
		await frames(120)
		check("vine marks tiles climbable", w.has_flag(v.col, v.bot, World.F_VINE) and w.has_flag(v.col, v.top, World.F_VINE), "x %d rows %d..%d" % [v.col, v.top, v.bot])
		p.place(Vector2((v.col + 0.5) * 16.0, (v.bot + 1) * 16.0 - 6.01))
		await frames(3)
		y0 = p.pos.y
		await frames(60, {"y": -1.0})
		check("climbs the vine", y0 - p.pos.y > 40.0, "rose %.0f" % (y0 - p.pos.y))
	# 8. picking seeds
	var plant: Node2D = game.plants[0]
	p.place(plant.bulb_world() + Vector2(0, 10))
	await frames(4)
	p.seeds = 0
	plant.ripe = true
	await frames(2, {"grab_p": true})
	check("picks a springseed", p.seeds == 1 and not plant.ripe)
	# 9. lanterns
	var lant: Node2D = game.lantern_nodes[0]
	p.place(lant.position + Vector2(0, -7))
	await frames(10)
	await frames(2, {"grab_p": true})
	check("sings a lantern awake", lant.lit)
	lant.lit = false
	lant.glow = 0.0
	# 10. kites slow the fall
	var kite: Node2D = game.kites[0]
	p.place(kite.position)
	await frames(1)
	await frames(2, {"grab_p": true})
	check("grabs a drift-kite", p.kite == kite)
	await frames(40)
	check("glides slowly", p.vel.y <= 45.0 or p.state == Player.St.GROUND, "vy %.0f" % p.vel.y)
	p.release_kite()
	# 11. nests
	var nest: Node2D = game.nest_nodes[1]
	p.place(nest.rest_point())
	await frames(10)
	await frames(10, {"y": 1.0})
	check("rests at a nest", p.is_resting(), "state %d dist %.1f pos %s nest %s draft %s" % [p.state, p.pos.distance_to(nest.rest_point()), str(p.pos), str(nest.position), str(w.flag_px(p.pos, World.F_DRAFT))])
	await frames(4, {"x": 1.0})
	check("wakes when moving", not p.is_resting())
	game.weather.time_scale = 1.0
	# 12. dropping through a grate
	var gt := Vector2i(-1, -1)
	for y in range(5, 200):
		for x in range(5, w.w - 5):
			if w.has_flag(x, y + 1, World.F_GRATE) and not w.is_solid(x, y) and not w.is_solid(x, y + 2) and not w.is_solid(x, y + 3) and not w.has_flag(x, y + 1, World.F_POLE_V):
				gt = Vector2i(x, y)
				break
		if gt.x >= 0:
			break
	if gt.x >= 0:
		await put(gt)
		await frames(10)
		check("stands on a grate", p.state == Player.St.GROUND, "state %d tile %s pos %s draft %s flags %d" % [p.state, str(gt), str(p.pos), str(w.flag_px(p.pos, World.F_DRAFT)), w.flag(gt.x, gt.y + 1)])
		y0 = p.pos.y
		await frames(25, {"y": 1.0, "jump": true})
		check("drops through a grate", p.pos.y - y0 > 10.0, "%.0f" % (p.pos.y - y0))
	# 13. calling: a mote of light sets off towards a sleeping lantern
	await put(flat)
	var before := 0
	for ch in game.get_children():
		if ch is Node2D and ch.get_script() == load("res://scripts/obj/wisp.gd"):
			before += 1
	game.call_cd = 0.0
	await frames(2, {"call_p": true})
	var after := 0
	for ch in game.get_children():
		if ch is Node2D and ch.get_script() == load("res://scripts/obj/wisp.gd"):
			after += 1
	check("calling sends a wisp", after == before + 1)
	# 14. echoes
	var echo: Node2D = game.echoes[0]
	p.place(echo.interact_point() + Vector2(0, -4))
	await frames(10)
	await frames(2, {"grab_p": true})
	check("reads an echo", echo.read and game.echo_lines.size() >= 1, "%d echoes in world" % game.echoes.size())
	# 15. a lit lantern is a place to rest
	var rl: Node2D = null
	for l in game.lantern_nodes.values():
		if l.kind == "lamp":
			rl = l
			break
	rl.light_up(true)
	p.place(rl.rest_point())
	await frames(10)
	await frames(10, {"y": 1.0})
	check("rests beside a lit lantern", p.is_resting(), "state %d" % p.state)
	await frames(4, {"x": 1.0})
	rl.lit = false
	game.weather.time_scale = 1.0
	# 16. W at the foot of a rough wall starts the climb
	await put(wall)
	await frames(6)
	p.facing = 1
	await frames(20, {"y": -1.0})
	check("climbs rock from the ground with W", p.state == Player.St.WALL, "state %d" % p.state)
	# 17. soak: random input never leaves the sprig inside solid ground
	await put(flat)
	var stuck := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 2400:
		if k % 20 == 0:
			p.script_input = {"x": rng.randf_range(-1, 1), "y": rng.randf_range(-1, 1), "jump": rng.randf() < 0.4}
		await get_tree().physics_frame
		if w.box_solid(p.pos, Player.HALF - Vector2(0.5, 0.5)):
			stuck += 1
	check("random wandering never clips into rock", stuck == 0, "%d frames inside, ended %s state %d" % [stuck, str(w.tile_of(p.pos)), p.state])
	print("walk test: %d passed, %d failed" % [passes, fails])
	get_tree().quit()
