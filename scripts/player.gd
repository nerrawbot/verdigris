extends Node2D
## The sprig: a small pale climber with glowing antennae. Tile-grid physics
## (no physics engine) so movement is exact and testable. States: ground, air,
## vertical pole/vine, horizontal pole, rock wall, swim, rest.

const World = preload("res://scripts/world.gd")

signal landed(speed: float)
signal jumped
signal splashed(strength: float)
signal stepped
signal grabbed(what: String)

const T := 16.0
const HALF := Vector2(6, 6)
const GRAV := 1050.0
const RUN := 135.0
const JUMP_V := 385.0
const MAX_FALL := 560.0
const MAX_SEEDS := 3

enum St { GROUND, AIR, POLE_V, POLE_H, WALL, SWIM, REST }

var world: World
var game: Node
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var state := St.AIR
var facing := 1
var coyote := 0.0
var jump_buf := 0.0
var wall_side := 0
var wall_lock := 0.0
var regrab := 0.0
var drop_timer := 0.0
var carrier: Object = null
var kite: Node = null
var seeds := 0
var in_water := false
var at_surface := false
var swim_dash := 0.0
var top_hold := 0.0
var stun := 0.0
var hang_y := 0.0
var frozen := false

# input: script_input (tests) replaces the keyboard when not empty
var script_input: Dictionary = {}
var inp := {"x": 0.0, "y": 0.0, "jump": false, "jump_p": false, "grab_p": false, "throw_p": false, "call_p": false}
var _prev_jump := false
var aim_mouse := false

# animation
var squash := 1.0
var squash_v := 0.0
var walk_t := 0.0
var climb_t := 0.0
var blink := 2.0
var vis_off := Vector2.ZERO
var tail: PackedVector2Array = PackedVector2Array()
var tail_prev: PackedVector2Array = PackedVector2Array()
var tips := [Vector2.ZERO, Vector2.ZERO]
var tips_v := [Vector2.ZERO, Vector2.ZERO]
var step_acc := 0.0
var light: PointLight2D
var rest_t := 0.0

const BODY := Color(0.88, 0.86, 0.79)
const BELLY := Color(0.62, 0.63, 0.62)
const GLOW := Color(1.7, 1.2, 0.62)


func _ready() -> void:
	z_index = 5
	light = PointLight2D.new()
	light.texture = make_light_texture()
	light.texture_scale = 1.9
	light.color = Color(1.0, 0.82, 0.58)
	light.energy = 1.0
	light.position = Vector2(0, -8)
	add_child(light)
	reset_body()


static func make_light_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t


func reset_body() -> void:
	tail.clear()
	tail_prev.clear()
	for i in 7:
		var p := pos + Vector2(-facing * (6 + i * 3.2), 1)
		tail.append(p)
		tail_prev.append(p)
	for i in 2:
		tips[i] = pos + Vector2(facing * 2, -16)
		tips_v[i] = Vector2.ZERO


func place(p: Vector2) -> void:
	pos = p
	vel = Vector2.ZERO
	state = St.AIR
	drop_timer = 0.0
	regrab = 0.0
	wall_lock = 0.0
	jump_buf = 0.0
	coyote = 0.0
	stun = 0.0
	carrier = null
	position = pos
	reset_body()


# ------------------------------------------------------------------ input

func _read_input() -> void:
	if not script_input.is_empty():
		var j: bool = script_input.get("jump", false)
		inp["x"] = float(script_input.get("x", 0.0))
		inp["y"] = float(script_input.get("y", 0.0))
		inp["jump"] = j
		inp["jump_p"] = j and not _prev_jump
		_prev_jump = j
		inp["grab_p"] = script_input.get("grab_p", false)
		inp["throw_p"] = script_input.get("throw_p", false)
		inp["call_p"] = script_input.get("call_p", false)
		script_input["grab_p"] = false
		script_input["throw_p"] = false
		script_input["call_p"] = false
		return
	inp["x"] = Input.get_axis("left", "right")
	inp["y"] = Input.get_axis("up", "down")
	inp["jump"] = Input.is_action_pressed("jump")
	inp["jump_p"] = Input.is_action_just_pressed("jump")
	inp["grab_p"] = Input.is_action_just_pressed("grab")
	inp["throw_p"] = Input.is_action_just_pressed("throw")
	inp["call_p"] = Input.is_action_just_pressed("call")
	aim_mouse = false
	if Input.is_action_just_pressed("throw_mouse"):
		inp["throw_p"] = true
		aim_mouse = true


# ------------------------------------------------------------------ update

func _physics_process(dt: float) -> void:
	if frozen or world == null:
		return
	_read_input()
	var ix: float = inp["x"]
	var iy: float = inp["y"]
	if inp["jump_p"]:
		jump_buf = 0.13
	jump_buf -= dt
	coyote -= dt
	regrab -= dt
	wall_lock -= dt
	drop_timer -= dt
	swim_dash -= dt
	stun -= dt
	if absf(ix) > 0.3 and state != St.WALL and state != St.REST:
		facing = 1 if ix > 0.0 else -1
	if state == St.GROUND and carrier != null and is_instance_valid(carrier):
		var d: Vector2 = carrier.platform_delta()
		if not world.box_solid(pos + d, HALF):
			pos += d
	var was_in := in_water
	in_water = world.water_px(pos)
	at_surface = in_water and not world.water_px(pos - Vector2(0, 5))
	if in_water and state != St.SWIM and state != St.REST:
		if not was_in and vel.y > 120.0:
			splashed.emit(clampf(vel.y / 400.0, 0.2, 1.0))
		state = St.SWIM
		vel *= 0.4
		release_kite()
	match state:
		St.GROUND, St.AIR:
			_step_normal(dt, ix, iy)
		St.POLE_V:
			_step_pole_v(dt, ix, iy)
		St.POLE_H:
			_step_pole_h(dt, ix, iy)
		St.WALL:
			_step_wall(dt, ix, iy)
		St.SWIM:
			_step_swim(dt, ix, iy)
		St.REST:
			_step_rest(dt, ix, iy)
	_actions()
	_animate(dt)
	position = pos
	queue_redraw()


func _touching(side: int) -> bool:
	return world.box_solid(pos + Vector2(side * 1.5, 0), HALF - Vector2(0, 2.5))


func _climbable(side: int) -> bool:
	var x := pos.x + side * (HALF.x + 2.0)
	return world.climbable_px(Vector2(x, pos.y - 3.0)) or world.climbable_px(Vector2(x, pos.y + 3.0))


func _is_climb_tile(p: Vector2) -> bool:
	return world.flag_px(p, World.F_POLE_V | World.F_VINE)


func _on_oneway() -> bool:
	var below := pos + Vector2(0, HALF.y + 2.0)
	var t := world.tile_of(below)
	if world.is_solid(t.x, t.y):
		return false
	return world.has_flag(t.x, t.y, World.F_GRATE | World.F_POLE_H) or carrier != null


func _try_grab_poles(ix: float, iy: float) -> bool:
	if regrab > 0.0:
		return false
	var wants_v := iy < -0.5 or (state == St.AIR and iy > 0.5)
	if wants_v and _is_climb_tile(pos):
		var t := world.tile_of(pos)
		var cx := t.x * T + T * 0.5
		if not world.box_solid(Vector2(cx, pos.y), HALF):
			pos.x = cx
			vel = Vector2.ZERO
			state = St.POLE_V
			release_kite()
			grabbed.emit("pole")
			return true
	if state == St.AIR and iy < 0.5:
		var hand := pos - Vector2(0, 5)
		var t := world.tile_of(hand)
		if world.has_flag(t.x, t.y, World.F_POLE_H):
			var line := t.y * T + T * 0.5
			var rising_through := vel.y < 0.0 and hand.y < line + 3.0
			var reach := iy < -0.5 and absf(hand.y - line) < 5.0
			if rising_through or reach:
				var np := Vector2(pos.x, line + 7.0)
				if not world.box_solid(np, HALF):
					pos = np
					hang_y = line
					vel = Vector2.ZERO
					state = St.POLE_H
					release_kite()
					grabbed.emit("pole")
					return true
	return false


func _step_normal(dt: float, ix: float, iy: float) -> void:
	var on_ground := state == St.GROUND
	var glide := kite != null and not on_ground
	if _try_grab_poles(ix, iy):
		return
	var target := ix * RUN
	if glide:
		target = ix * 165.0
	if stun > 0.0:
		target = 0.0
	var accel := 1500.0 if on_ground else 950.0
	if wall_lock > 0.0:
		accel *= 0.3
	if on_ground and absf(target) < 1.0:
		accel = 1900.0
	vel.x = move_toward(vel.x, target, accel * dt)
	var g := GRAV
	if vel.y < 0.0:
		if not inp["jump"] and not glide:
			g *= 2.3
		elif absf(vel.y) < 60.0:
			g *= 0.55
	else:
		g *= 1.1
	vel.y += g * dt
	if glide and vel.y > 42.0:
		vel.y = move_toward(vel.y, 42.0, 1800.0 * dt)
	if world.flag_px(pos, World.F_DRAFT):
		var cap := -300.0 if kite != null else -215.0
		vel.y = maxf(vel.y - (2700.0 if kite != null else 1900.0) * dt, cap)
		on_ground = false
		state = St.AIR
	vel.y = minf(vel.y, MAX_FALL)
	# jumping, dropping through one-way floors
	if jump_buf > 0.0 and (on_ground or coyote > 0.0) and stun <= 0.0:
		jump_buf = 0.0
		if on_ground and iy > 0.5 and _on_oneway():
			drop_timer = 0.25
		else:
			vel.y = -JUMP_V
			coyote = 0.0
			state = St.AIR
			on_ground = false
			carrier = null
			squash = 1.25
			jumped.emit()
	elif on_ground and iy > 0.5 and _on_oneway() and drop_timer < -0.35 and not (game and game._nest_near(pos, 18.0) != null):
		drop_timer = 0.25
	# standing at a rough wall, W starts the climb
	if on_ground and iy < -0.5 and regrab <= 0.0 and kite == null:
		for side in [facing, -facing]:
			var near: bool = world.box_solid(pos + Vector2(side * 4.0, 0), HALF - Vector2(0, 2.5))
			if near and _climbable(side) and ix * side > -0.3:
				var r: Dictionary = world.move_box(pos, HALF, Vector2(side * 4.0, 0))
				pos = r["pos"]
				state = St.WALL
				wall_side = side
				facing = side
				vel = Vector2.ZERO
				grabbed.emit("wall")
				return
	# walls
	if not on_ground:
		var side := 0
		if _touching(1):
			side = 1
		elif _touching(-1):
			side = -1
		if side != 0:
			if jump_buf > 0.0 and coyote <= 0.0:
				vel = Vector2(-side * 200.0, -350.0)
				wall_lock = 0.16
				jump_buf = 0.0
				facing = -side
				squash = 1.2
				jumped.emit()
			elif ix * side > 0.5 and regrab <= 0.0 and _climbable(side) and kite == null:
				state = St.WALL
				wall_side = side
				facing = side
				vel = Vector2.ZERO
				grabbed.emit("wall")
				return
			elif ix * side > 0.5 and vel.y > 70.0:
				vel.y = move_toward(vel.y, 70.0, 2500.0 * dt)
	var old_vy := vel.y
	var res: Dictionary = world.move_box(pos, HALF, vel * dt, drop_timer > 0.0)
	var old := pos
	pos = res["pos"]
	var hx: int = res["hit_x"]
	var hy: int = res["hit_y"]
	if hx != 0:
		if (on_ground or vel.y >= 0.0) and absf(ix) > 0.3 and signf(ix) == float(hx) and _try_step_up(hx):
			pass
		else:
			vel.x = 0.0
	if hy == 1:
		if state == St.AIR:
			_land(vel.y)
		vel.y = 0.0
		state = St.GROUND
		coyote = 0.1
		carrier = res["carrier"]
	elif hy == -1:
		# clipped a ceiling corner on the way up: slide round it instead of stopping
		if old_vy < -120.0 and _round_corner(ix):
			vel.y = old_vy
		else:
			vel.y = 0.0
	elif on_ground:
		state = St.AIR
		coyote = 0.1
		carrier = null
	if state == St.GROUND and absf(vel.x) > 10.0:
		step_acc += absf(pos.x - old.x)
		if step_acc > 13.0:
			step_acc = 0.0
			stepped.emit()


func _round_corner(ix: float) -> bool:
	var first := 1 if ix >= 0.0 else -1
	for d in range(1, 7):
		for s in [first, -first]:
			var np := pos + Vector2(s * d, 0)
			if not world.box_solid(np, HALF) and not world.box_solid(np + Vector2(0, -3), HALF):
				vis_off += pos - np
				pos = np
				return true
	return false


func _try_step_up(side: int) -> bool:
	# scramble up a ledge about one tile high
	var up := pos - Vector2(0, T + 0.5)
	if world.box_solid(up, HALF):
		return false
	var over := up + Vector2(side * 3.0, 0)
	if world.box_solid(over, HALF):
		return false
	vis_off += pos - over
	pos = over
	return true


func _land(speed: float) -> void:
	if speed > 200.0:
		squash = clampf(1.0 - speed / 900.0, 0.55, 0.9)
	if speed > 560.0 - 1.0:
		stun = 0.16
	landed.emit(speed)


func _step_pole_v(dt: float, ix: float, iy: float) -> void:
	var t := world.tile_of(pos)
	pos.x = move_toward(pos.x, t.x * T + T * 0.5, 240.0 * dt)
	vel = Vector2.ZERO
	if jump_buf > 0.0:
		jump_buf = 0.0
		if absf(ix) > 0.3:
			vel = Vector2(signf(ix) * 175.0, -320.0)
		else:
			vel = Vector2(0, -330.0)
		state = St.AIR
		regrab = 0.25
		squash = 1.2
		jumped.emit()
		return
	if absf(ix) > 0.5 and absf(iy) < 0.3:
		# a horizontal pole crossing here?
		if world.flag_px(pos - Vector2(0, 5), World.F_POLE_H):
			var line := world.tile_of(pos - Vector2(0, 5)).y * T + T * 0.5
			hang_y = line
			pos.y = line + 7.0
			state = St.POLE_H
			return
		state = St.AIR
		vel = Vector2(signf(ix) * 70.0, 0)
		regrab = 0.2
		return
	if absf(iy) < 0.2:
		return
	var speed := 105.0 if iy < 0.0 else 150.0
	var ny := pos.y + iy * speed * dt
	var np := Vector2(pos.x, ny)
	if _is_climb_tile(np) and not world.box_solid(np, HALF):
		pos = np
		climb_t += absf(ny - pos.y) + speed * dt
		top_hold = 0.0
	elif iy < 0.0:
		top_hold += dt
		if top_hold > 0.12:
			top_hold = 0.0
			vel = Vector2(ix * 90.0, -300.0)
			state = St.AIR
			regrab = 0.22
			jumped.emit()
	else:
		if world.on_floor(pos, HALF):
			state = St.GROUND
		else:
			state = St.AIR
			regrab = 0.2


func _step_pole_h(dt: float, ix: float, iy: float) -> void:
	vel = Vector2.ZERO
	pos.y = hang_y + 7.0
	if jump_buf > 0.0:
		jump_buf = 0.0
		vel = Vector2(ix * 150.0, -300.0 if absf(ix) > 0.3 else -345.0)
		state = St.AIR
		regrab = 0.2
		jumped.emit()
		return
	if iy < -0.5:
		if _is_climb_tile(pos - Vector2(0, 5)):
			state = St.POLE_V
			return
		var top := Vector2(pos.x, hang_y - HALF.y - 0.5)
		if not world.box_solid(top, HALF):
			vis_off += pos - top
			pos = top
			state = St.GROUND
			regrab = 0.25
			return
	elif iy > 0.5:
		if _is_climb_tile(pos):
			state = St.POLE_V
			return
		state = St.AIR
		regrab = 0.3
		return
	if absf(ix) > 0.2:
		var nx := pos.x + ix * 85.0 * dt
		var hand := Vector2(nx + signf(ix) * 3.0, hang_y)
		if world.flag_px(hand, World.F_POLE_H) and not world.box_solid(Vector2(nx, pos.y), HALF):
			pos.x = nx
			climb_t += 85.0 * dt


func _step_wall(dt: float, ix: float, iy: float) -> void:
	vel = Vector2.ZERO
	facing = wall_side
	if jump_buf > 0.0:
		jump_buf = 0.0
		vel = Vector2(-wall_side * 200.0, -350.0)
		wall_lock = 0.16
		state = St.AIR
		facing = -wall_side
		regrab = 0.12
		squash = 1.2
		jumped.emit()
		return
	if ix * wall_side < -0.5:
		state = St.AIR
		vel.x = -wall_side * 70.0
		regrab = 0.15
		return
	if absf(iy) > 0.2:
		var speed := 62.0 if iy < 0.0 else 95.0
		var np := pos + Vector2(0, iy * speed * dt)
		if not world.box_solid(np, HALF):
			var old := pos
			pos = np
			if not _touching(wall_side) or not _climbable(wall_side):
				if iy < 0.0:
					_mantle()
					return
				pos = old
				state = St.AIR
				return
			climb_t += speed * dt
		elif iy > 0.0:
			state = St.GROUND
	if not _touching(wall_side):
		state = St.AIR


func _mantle() -> void:
	for k in [6.0, 10.0, 14.0]:
		var np := pos + Vector2(wall_side * 9.0, -k)
		if not world.box_solid(np, HALF):
			vis_off += pos - np
			pos = np
			state = St.AIR
			vel = Vector2(wall_side * 60.0, -80.0)
			return
	state = St.AIR


func _step_swim(dt: float, ix: float, iy: float) -> void:
	var acc := Vector2(ix, iy)
	if acc.length() > 1.0:
		acc = acc.normalized()
	vel += acc * 560.0 * dt
	vel *= 1.0 - 2.6 * dt
	if acc == Vector2.ZERO:
		vel.y += 25.0 * dt
	if at_surface and iy <= 0.2:
		var sy := world.water_surface_y(pos)
		if sy < INF:
			vel.y = move_toward(vel.y, (sy + 3.0 - pos.y) * 5.0, 500.0 * dt)
	var cap := 175.0 if swim_dash <= 0.15 else 320.0
	if vel.length() > cap:
		vel = vel.normalized() * move_toward(vel.length(), cap, 900.0 * dt)
	if jump_buf > 0.0:
		if at_surface:
			jump_buf = 0.0
			vel = Vector2(ix * 140.0, -360.0)
			state = St.AIR
			splashed.emit(0.35)
			jumped.emit()
		elif swim_dash <= 0.0:
			jump_buf = 0.0
			var dir := acc if acc != Vector2.ZERO else Vector2(facing, 0)
			vel = dir.normalized() * 300.0
			swim_dash = 0.45
	var res: Dictionary = world.move_box(pos, HALF, vel * dt, true)
	pos = res["pos"]
	if int(res["hit_x"]) != 0:
		vel.x = 0.0
	if int(res["hit_y"]) != 0:
		vel.y = 0.0
	if not world.water_px(pos):
		state = St.AIR


func _step_rest(dt: float, ix: float, iy: float) -> void:
	rest_t += dt
	vel = Vector2.ZERO
	if absf(ix) > 0.3 or iy < -0.3 or inp["jump_p"] or inp["grab_p"]:
		wake()


func rest() -> void:
	state = St.REST
	rest_t = 0.0
	release_kite()


func wake() -> void:
	if state == St.REST:
		state = St.GROUND
		squash = 1.2
		if game:
			game.on_wake()


func is_resting() -> bool:
	return state == St.REST


# ------------------------------------------------------------------ actions

func _actions() -> void:
	if state == St.REST:
		return
	if inp["grab_p"]:
		var used := false
		if game:
			used = game.interact(self)
		if not used and kite != null:
			release_kite()
	if inp["call_p"] and game:
		game.call_out(self)
	if inp["throw_p"] and seeds > 0 and state != St.REST:
		var v := Vector2(facing * 240.0, -175.0)
		var iy: float = inp["y"]
		if aim_mouse:
			var d := get_global_mouse_position() - pos
			v = d.normalized() * 330.0 if d.length() > 1.0 else v
		elif iy < -0.5:
			v = Vector2(facing * 60.0, -420.0)
		elif iy > 0.5:
			v = Vector2(facing * 50.0, 120.0)
		seeds -= 1
		if game:
			game.throw_seed(pos + Vector2(facing * 5.0, -4.0), v + Vector2(vel.x * 0.4, minf(vel.y, 0.0) * 0.3))


func take_kite(k: Node) -> void:
	kite = k
	if state == St.GROUND:
		pass
	grabbed.emit("kite")


func release_kite() -> void:
	if kite != null and is_instance_valid(kite):
		kite.let_go()
	kite = null


# ------------------------------------------------------------------ animation

func _animate(dt: float) -> void:
	squash_v += (1.0 - squash) * 260.0 * dt
	squash_v *= 1.0 - 14.0 * dt
	squash += squash_v * dt
	vis_off = vis_off.lerp(Vector2.ZERO, 1.0 - exp(-dt * 14.0))
	if state == St.GROUND:
		walk_t += absf(vel.x) * dt * 0.11
	blink -= dt
	if blink < -0.12:
		blink = randf_range(2.0, 5.0)
	# tail: verlet chain hanging from the rear of the body
	var root := pos + _frame_pt(Vector2(-6.0, 0.5))
	var grav := Vector2(0, 260.0 if state != St.SWIM else 20.0)
	tail[0] = root
	for i in range(1, tail.size()):
		var cur := tail[i]
		var v := (cur - tail_prev[i]) * (0.9 if state != St.SWIM else 0.82)
		tail_prev[i] = cur
		var wave := Vector2.ZERO
		if state == St.SWIM:
			wave = Vector2(0, sin(Time.get_ticks_msec() * 0.012 - i * 0.9) * 22.0)
		tail[i] = cur + v + (grav + wave) * dt * dt
	for k in 3:
		for i in range(1, tail.size()):
			var d := tail[i] - tail[i - 1]
			var l := d.length()
			var seg := 3.3 - i * 0.12
			if l > 0.0001:
				tail[i] = tail[i - 1] + d / l * seg
	# antenna tips spring towards a rest pose
	for i in 2:
		var base := pos + _frame_pt(Vector2(4.2 - i * 1.2, 6.3))
		var rest := base + _frame_dir(Vector2(-3.5 - i * 1.5, 7.5 + i))
		if state == St.REST:
			rest = base + Vector2(-facing * 6.0, -2.0)
		var acc: Vector2 = (rest - tips[i]) * 320.0 - tips_v[i] * 16.0
		tips_v[i] += acc * dt
		tips[i] += tips_v[i] * dt
		var d: Vector2 = tips[i] - base
		if d.length() > 12.0:
			tips[i] = base + d.normalized() * 12.0


## Body frame: x along the long axis (head forward), y along the back (up).
func _frame_axes() -> Array:
	var f := float(facing)
	match state:
		St.POLE_V, St.POLE_H:
			return [Vector2(0, -1), Vector2(-f, 0)]
		St.WALL:
			return [Vector2(0, -1), Vector2(-float(wall_side), 0)]
		St.SWIM:
			var dir := vel.normalized() if vel.length() > 40.0 else Vector2(f, 0)
			if dir.x * f < -0.2:
				dir = Vector2(f, dir.y).normalized()
			var up := Vector2(dir.y, -dir.x) if f > 0.0 else Vector2(-dir.y, dir.x)
			return [dir, up]
	var lean := clampf(vel.y / 900.0, -0.3, 0.3) * f
	var l := Vector2(f, 0).rotated(lean)
	return [l, Vector2(0, -1).rotated(lean)]


func _frame_pt(p: Vector2) -> Vector2:
	var ax := _frame_axes()
	var sx := 1.0 / sqrt(maxf(squash, 0.3))
	var sy := squash
	return (ax[0] as Vector2) * p.x * sx + (ax[1] as Vector2) * p.y * sy


func _frame_dir(p: Vector2) -> Vector2:
	var ax := _frame_axes()
	return (ax[0] as Vector2) * p.x + (ax[1] as Vector2) * p.y


func _draw() -> void:
	var o := vis_off
	var ax := _frame_axes()
	var L: Vector2 = ax[0]
	var N: Vector2 = ax[1]
	var sx := 1.0 / sqrt(maxf(squash, 0.3))
	var sy := squash
	var body_c := BODY
	var belly := BELLY
	if in_water:
		body_c = body_c.lerp(Color(0.6, 0.8, 0.85), 0.15)
	var fp := func(p: Vector2) -> Vector2:
		return o + L * p.x * sx + N * p.y * sy
	if state == St.REST:
		_draw_rest(o)
		return
	# far leg, tail
	var feet := _feet()
	draw_line(fp.call(Vector2(-1.5, -2.5)), o + feet[1], belly.darkened(0.25), 2.0, true)
	var tpts := PackedVector2Array()
	for p in tail:
		tpts.append(p - pos + o)
	for i in tpts.size() - 1:
		var w := lerpf(3.6, 1.0, float(i) / (tpts.size() - 1))
		draw_line(tpts[i], tpts[i + 1], body_c.lerp(belly, float(i) / tpts.size()), w, true)
	# body: belly shade then body
	_ellipse(fp.call(Vector2(0, -1.0)), L * 7.4 * sx, N * 5.4 * sy, belly)
	_ellipse(fp.call(Vector2(-0.3, 0.4)), L * 7.0 * sx, N * 5.0 * sy, body_c)
	# head
	var head: Vector2 = fp.call(Vector2(4.8, 2.6))
	draw_circle(head, 4.4, body_c, true, -1.0, true)
	draw_circle(head + L * 1.2 - N * 1.6, 3.0, body_c.darkened(0.04), true, -1.0, true)
	var eye: Vector2 = head + L * 2.0 + N * 0.6
	if blink > 0.0:
		draw_circle(eye, 1.25, Color(0.08, 0.08, 0.1), true, -1.0, true)
		draw_circle(eye + Vector2(-0.4, -0.5), 0.45, Color(1, 1, 1, 0.9), true, -1.0, true)
	else:
		draw_line(eye - L * 1.2, eye + L * 1.2, Color(0.1, 0.1, 0.12), 1.0, true)
	# near leg
	draw_line(fp.call(Vector2(-2.5, -2.5)), o + feet[0], belly.darkened(0.05), 2.2, true)
	draw_circle(o + feet[0], 1.2, belly, true, -1.0, true)
	# arms when holding something
	if state == St.POLE_V or state == St.POLE_H or state == St.WALL:
		var c := sin(climb_t * 0.25)
		var hand_a := Vector2.ZERO
		var hand_b := Vector2.ZERO
		if state == St.POLE_H:
			hand_a = Vector2(-2.5, hang_y - pos.y) + o
			hand_b = Vector2(2.5, hang_y - pos.y) + o
		elif state == St.POLE_V:
			hand_a = Vector2(0, -6.0 + c * 2.0) + o
			hand_b = Vector2(0, -3.0 - c * 2.0) + o
		else:
			hand_a = Vector2(wall_side * 6.0, -6.0 + c * 2.0) + o
			hand_b = Vector2(wall_side * 6.0, -1.0 - c * 2.0) + o
		var sh: Vector2 = fp.call(Vector2(3.0, -1.0))
		draw_line(sh, hand_a, body_c.darkened(0.1), 1.8, true)
		draw_line(sh, hand_b, body_c.darkened(0.2), 1.8, true)
	# a seed carried in the mouth
	if seeds > 0:
		draw_circle(head + L * 4.2 - N * 1.2, 1.7, Color(0.55, 1.6, 1.2), true, -1.0, true)
	# antennae
	for i in 2:
		var base: Vector2 = fp.call(Vector2(4.2 - i * 1.2, 6.3))
		var tip: Vector2 = tips[i] - pos + o
		var mid := base.lerp(tip, 0.5) + N * 2.5 - L * 1.0
		var pts := PackedVector2Array()
		for k in 6:
			var t := k / 5.0
			pts.append(base.lerp(mid, t).lerp(mid.lerp(tip, t), t))
		draw_polyline(pts, body_c.darkened(0.15 * i), 1.1, true)
		draw_circle(tip, 2.6, Color(1.0, 0.8, 0.5, 0.16), true, -1.0, true)
		draw_circle(tip, 1.4, GLOW, true, -1.0, true)


func _feet() -> Array:
	var f := float(facing)
	match state:
		St.GROUND:
			var spd := clampf(absf(vel.x) / RUN, 0.0, 1.0)
			var a := Vector2(f * (sin(walk_t) * 4.0 * spd - 1.5), 6.0 - maxf(0.0, cos(walk_t)) * 2.5 * spd)
			var b := Vector2(f * (sin(walk_t + PI) * 4.0 * spd + 1.5), 6.0 - maxf(0.0, cos(walk_t + PI)) * 2.5 * spd)
			return [a, b]
		St.AIR:
			if vel.y < 0.0:
				return [Vector2(-f * 3.0, 4.5), Vector2(-f * 0.5, 5.0)]
			return [Vector2(-f * 1.5, 7.5), Vector2(f * 1.0, 7.0)]
		St.POLE_V:
			var c := sin(climb_t * 0.25)
			return [Vector2(0, 6.0 - c * 2.0), Vector2(0, 4.0 + c * 2.0)]
		St.POLE_H:
			return [Vector2(-f * 1.0, 8.5), Vector2(f * 1.5, 8.0)]
		St.WALL:
			var c := sin(climb_t * 0.25)
			return [Vector2(wall_side * 6.0, 5.0 + c * 2.0), Vector2(wall_side * 6.0, 2.0 - c * 2.0)]
		St.SWIM:
			var k := sin(Time.get_ticks_msec() * 0.01) * 2.0
			return [_frame_dir(Vector2(-5.0, -3.0 + k)), _frame_dir(Vector2(-4.0, -3.5 - k))]
	return [Vector2(-2, 6), Vector2(2, 6)]


func _draw_rest(o: Vector2) -> void:
	var breathe := 1.0 + sin(rest_t * 1.6) * 0.04
	var c := o + Vector2(0, 1.5)
	var pts := PackedVector2Array()
	for k in 14:
		var a := PI * 0.15 + k / 13.0 * PI * 1.5
		pts.append(c + Vector2(cos(a) * -facing, sin(a)) * 8.0)
	draw_polyline(pts, BELLY, 3.0, true)
	_ellipse(c, Vector2(6.8 * breathe, 0), Vector2(0, -5.2 * breathe), BODY)
	draw_circle(c + Vector2(facing * 4.5, 1.0), 3.8, BODY, true, -1.0, true)
	draw_line(c + Vector2(facing * 5.0, 1.2), c + Vector2(facing * 6.6, 1.2), Color(0.1, 0.1, 0.12), 1.0, true)
	for i in 2:
		var tip: Vector2 = tips[i] - pos + o
		draw_line(c + Vector2(facing * 3.0, -2.5), tip, BODY.darkened(0.15), 1.0, true)
		draw_circle(tip, 2.8, Color(GLOW.r, GLOW.g, GLOW.b, 0.15), true, -1.0, true)
		draw_circle(tip, 1.4, GLOW * 0.8, true, -1.0, true)


func _ellipse(c: Vector2, ax: Vector2, ay: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 18:
		var a := TAU * k / 18.0
		pts.append(c + ax * cos(a) + ay * sin(a))
	draw_colored_polygon(pts, col)
