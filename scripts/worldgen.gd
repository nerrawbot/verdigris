extends RefCounted
## Generates the Verdigris world. A 10x8 grid of cells each holds a room (cave,
## hall, shaft, canopy) or part of the open sky valley; rooms are joined by
## tunnels and shafts along a spanning tree plus extra loops. A movement model
## (walk, jump, climb rock, poles, swim) then checks the whole map and adds
## poles until every reachable place can also be left again.

const World = preload("res://scripts/world.gd")
const WorldData = preload("res://scripts/world_data.gd")

const CW := 44
const CH := 32
const COLS := 10
const ROWS := 8
const W := CW * COLS
const H := CH * ROWS
const WATER_ROW := 6 * CH + 12
const JUMP_H := 4
const SPIRE_X0 := 208
const SPIRE_X1 := 232
const SPIRE_TOP := 8
const SPIRE_GROUND := 54

const AIR := World.AIR
const ROCK := World.ROCK
const CONC := World.CONC
const METAL := World.METAL

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()

var solid := PackedByteArray()
var fixed := PackedByteArray()
var back := PackedByteArray()
var flags := PackedByteArray()
var region := PackedByteArray()
var owner := PackedInt32Array()
var depth := PackedByteArray()
var rooms: Array = []
var cell_node := {}
var sky_id := -1
var spire_id := -1
var objects: Array = []
var start := Vector2i()
var report := PackedStringArray()

# movement graph
var adj := PackedInt32Array()
var adj_start := PackedInt32Array()
var fwd := PackedByteArray()
var bwd := PackedByteArray()


func generate(seed_value: int) -> Resource:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	noise2.seed = seed_value + 17
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.012
	noise2.fractal_octaves = 2
	var n := W * H
	solid.resize(n)
	solid.fill(ROCK)
	fixed.resize(n)
	fixed.fill(0)
	back.resize(n)
	back.fill(1)
	flags.resize(n)
	flags.fill(0)
	region.resize(n)
	owner.resize(n)
	owner.fill(-1)
	depth.resize(n)
	_assign_regions()
	_make_rooms()
	_carve_rooms()
	_smooth_organic()
	_grow_roots()
	_connect_rooms()
	_build_spire()
	_ruins()
	_find_start()
	_remove_pockets()
	_materials()
	_flood()
	_pools()
	var total := 0
	for round in 30:
		var placed := _fix_connectivity()
		total += placed
		print("  round %d: %d poles" % [round, placed])
		if placed == 0:
			break
	report.append("poles added by connectivity fixer: %d" % total)
	_build_graph()
	_reach()
	_report_reach()
	_back_layer()
	_place_objects()
	return _pack()


# ---------------------------------------------------------------- helpers

func idx(x: int, y: int) -> int:
	return y * W + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func is_air(x: int, y: int) -> bool:
	return inb(x, y) and solid[y * W + x] == AIR


func mat(x: int, y: int) -> int:
	if not inb(x, y):
		return CONC
	return solid[y * W + x]


func _air(x: int, y: int, id: int) -> void:
	if x < 1 or y < 1 or x >= W - 1 or y >= H - 1:
		return
	var i := y * W + x
	solid[i] = AIR
	fixed[i] = 0
	owner[i] = id
	flags[i] &= ~World.F_GRATE


func _set_solid(x: int, y: int, m: int) -> void:
	if not inb(x, y):
		return
	var i := y * W + x
	solid[i] = m
	fixed[i] = 1
	flags[i] = 0


func _flag(x: int, y: int, f: int) -> void:
	if inb(x, y):
		flags[y * W + x] |= f


func cell_region(c: Vector2i) -> int:
	if c.y >= 6:
		return World.R_SUNKEN
	if c.x <= 2:
		return World.R_PIPEWORKS
	if c.x >= 7:
		return World.R_CANOPY
	if c.y <= 1:
		return World.R_SPIRE
	return World.R_HOLLOWS


func _add_room(type: String, rect: Rect2i, reg: int, cell: Vector2i) -> int:
	var id := rooms.size()
	rooms.append({"id": id, "type": type, "rect": rect, "region": reg, "cell": cell, "levels": [], "built": type == "hall" or type == "shaft"})
	return id


func sky_surface(x: int) -> int:
	var x0 := 3 * CW
	var x1 := 7 * CW
	var base := 52.0 + noise.get_noise_1d(x * 0.7) * 5.0
	var el := clampf(1.0 - (x - x0) / 36.0, 0.0, 1.0)
	var er := clampf(1.0 - (x1 - 1 - x) / 36.0, 0.0, 1.0)
	base -= 17.0 * (el * el + er * er)
	var sp := clampf((absf(x - 220.0) - 20.0) / 12.0, 0.0, 1.0)
	base = lerpf(float(SPIRE_GROUND), base, sp)
	return int(round(base))


# ---------------------------------------------------------------- layout

func _assign_regions() -> void:
	for y in H:
		for x in W:
			region[y * W + x] = cell_region(Vector2i(x / CW, y / CH))


func _make_rooms() -> void:
	for cy in ROWS:
		for cx in COLS:
			var c := Vector2i(cx, cy)
			var reg := cell_region(c)
			if reg == World.R_SPIRE:
				if sky_id < 0:
					sky_id = _add_room("sky", Rect2i(3 * CW, 1, 4 * CW, 2 * CH), reg, c)
				cell_node[c] = sky_id
				continue
			var type := "cave"
			match reg:
				World.R_PIPEWORKS:
					type = "shaft" if rng.randf() < 0.3 else "hall"
				World.R_HOLLOWS:
					type = "hall" if rng.randf() < 0.22 else "cave"
				World.R_CANOPY:
					type = "canopy"
				World.R_SUNKEN:
					type = "hall" if rng.randf() < 0.5 else "cave"
			if c == Vector2i(4, 3) or c == Vector2i(5, 3):
				type = "cave"
			var x0 := cx * CW
			var y0 := cy * CH
			var r := Rect2i()
			match type:
				"cave":
					# sizes vary a lot: snug pockets, wide galleries, tall wells
					var shape := rng.randi_range(0, 3)
					var mx := rng.randi_range(2, 10) if shape != 1 else rng.randi_range(2, 4)
					var my := rng.randi_range(2, 7) if shape != 2 else rng.randi_range(2, 3)
					if shape == 1:
						my = rng.randi_range(6, 9)
					if shape == 2:
						mx = rng.randi_range(9, 13)
					var a := x0 + mx + rng.randi_range(-1, 1)
					var b := y0 + my
					r = Rect2i(a, b, CW - 2 * mx, CH - my - rng.randi_range(2, 7))
				"canopy":
					var a := x0 + rng.randi_range(1, 3)
					var b := y0 + rng.randi_range(1, 3)
					r = Rect2i(a, b, x0 + CW - rng.randi_range(1, 3) - a, y0 + CH - rng.randi_range(1, 3) - b)
				"hall":
					var rw := rng.randi_range(24, 38)
					var rh := rng.randi_range(18, 27)
					r = Rect2i(x0 + rng.randi_range(2, CW - 2 - rw), y0 + rng.randi_range(2, CH - 2 - rh), rw, rh)
				"shaft":
					var rw := rng.randi_range(8, 12)
					r = Rect2i(x0 + rng.randi_range(3, CW - 3 - rw), y0 + 2, rw, CH - 4)
			cell_node[c] = _add_room(type, r, reg, c)


func _carve_rooms() -> void:
	for room in rooms:
		match room["type"]:
			"cave":
				_carve_blob(room, 0.9, 0.6)
			"canopy":
				_carve_blob(room, 1.05, 0.55)
			"hall":
				_carve_hall(room)
			"shaft":
				_carve_shaft(room)
			"sky":
				_carve_sky(room)


func _carve_blob(room: Dictionary, thresh: float, amp: float) -> void:
	var r: Rect2i = room["rect"]
	var id: int = room["id"]
	var c := Vector2(r.position) + Vector2(r.size) * 0.5
	var hx := r.size.x * 0.5
	var hy := r.size.y * 0.5
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var nx := (x + 0.5 - c.x) / hx
			var ny := (y + 0.5 - c.y) / hy
			# superellipse: rounded-box caverns rather than diamonds
			var d := pow(pow(absf(nx), 3.0) + pow(absf(ny), 3.0), 1.0 / 3.0)
			if d + noise.get_noise_2d(x, y) * amp < thresh:
				_air(x, y, id)
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			_air(int(c.x) + dx, int(c.y) + dy, id)


func _carve_hall(room: Dictionary) -> void:
	var r: Rect2i = room["rect"]
	var id: int = room["id"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_air(x, y, id)
	if rng.randf() < 0.55:
		var span := rng.randi_range(7, 12)
		for x in range(r.position.x, r.end.x):
			var f := absf(sin(PI * float(x - r.position.x) / span))
			var rows := int(round((1.0 - f) * 3.0))
			for k in rows:
				_set_solid(x, r.position.y + k, CONC)
	var levels: Array = [r.end.y]
	var y := r.end.y - rng.randi_range(6, 8)
	while y > r.position.y + 5:
		levels.append(y)
		y -= rng.randi_range(6, 8)
	room["levels"] = levels
	var m := METAL if (room["region"] == World.R_PIPEWORKS and rng.randf() < 0.4) else CONC
	for li in range(1, levels.size()):
		var ly: int = levels[li]
		var below: int = levels[li - 1]
		var grate := rng.randf() < 0.3
		var gaps := {}
		for g in rng.randi_range(1, 2):
			var gw := rng.randi_range(3, 6)
			var gx := rng.randi_range(r.position.x, r.end.x - gw)
			for x in range(gx, gx + gw):
				gaps[x] = true
		var px := -1
		for tries in 30:
			var cand := rng.randi_range(r.position.x + 2, r.end.x - 3)
			if not gaps.has(cand) and not gaps.has(cand - 1) and not gaps.has(cand + 1):
				px = cand
				break
		for x in range(r.position.x, r.end.x):
			if gaps.has(x):
				continue
			if grate:
				_flag(x, ly, World.F_GRATE)
			else:
				_set_solid(x, ly, m)
		if px >= 0:
			_air(px, ly, id)
			_flag(px, ly, World.F_GRATE)
			for yy in range(ly - 1, below):
				_flag(px, yy, World.F_POLE_V)
		# stumps on the floor below this slab and beams hanging from it
		for k in rng.randi_range(0, 3):
			var sx := rng.randi_range(r.position.x + 1, r.end.x - 2)
			if absi(sx - px) <= 1:
				continue
			if rng.randf() < 0.5:
				for hh in rng.randi_range(1, 2):
					if is_air(sx, below - 1 - hh) and (flags[idx(sx, below - 1 - hh)] & World.F_POLE_V) == 0:
						_set_solid(sx, below - 1 - hh, CONC)
			elif not gaps.has(sx) and not grate:
				_set_solid(sx, ly + 1, CONC)
	# a few horizontal poles spanning the top level
	if rng.randf() < 0.6 and levels.size() > 0:
		var top: int = levels[levels.size() - 1]
		var py := r.position.y + 4
		if top - py > 4:
			for x in range(r.position.x, r.end.x):
				_flag(x, py, World.F_POLE_H)


func _carve_shaft(room: Dictionary) -> void:
	var r: Rect2i = room["rect"]
	var id: int = room["id"]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_air(x, y, id)
	var cx := r.position.x + r.size.x / 2
	for y in range(r.position.y, r.end.y):
		_flag(cx, y, World.F_POLE_V)
	var y := r.end.y - rng.randi_range(4, 6)
	var side := 1 if rng.randf() < 0.5 else -1
	while y > r.position.y + 2:
		var lw := rng.randi_range(2, maxi(2, r.size.x / 2 - 2))
		if side < 0:
			for x in range(r.position.x, mini(r.position.x + lw, cx - 1)):
				_set_solid(x, y, CONC)
		else:
			for x in range(maxi(r.end.x - lw, cx + 2), r.end.x):
				_set_solid(x, y, CONC)
		side = -side
		y -= rng.randi_range(4, 6)


func _carve_sky(room: Dictionary) -> void:
	var r: Rect2i = room["rect"]
	for x in range(r.position.x, r.end.x):
		var s := sky_surface(x)
		for y in range(1, s):
			_air(x, y, room["id"])


func _smooth_organic() -> void:
	for p in 2:
		var copy := solid.duplicate()
		for room in rooms:
			if room["type"] != "cave" and room["type"] != "canopy":
				continue
			var r: Rect2i = room["rect"].grow(1)
			for y in range(maxi(r.position.y, 1), mini(r.end.y, H - 1)):
				for x in range(maxi(r.position.x, 1), mini(r.end.x, W - 1)):
					var cnt := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if (dx != 0 or dy != 0) and copy[(y + dy) * W + x + dx] != AIR:
								cnt += 1
					var i := y * W + x
					if cnt >= 5:
						solid[i] = ROCK
					elif cnt <= 3:
						solid[i] = AIR
						owner[i] = room["id"]


func _grow_roots() -> void:
	for room in rooms:
		if room["type"] != "canopy":
			continue
		var r: Rect2i = room["rect"]
		for k in rng.randi_range(4, 8):
			var x := rng.randi_range(r.position.x + 2, r.end.x - 3)
			var y := r.position.y
			while y < r.end.y and not is_air(x, y):
				y += 1
			if y >= r.end.y - 6:
				continue
			var length := rng.randi_range(5, 14)
			var fx := float(x)
			for k2 in length:
				var yy := y + k2
				fx += noise.get_noise_2d(x * 3.0, yy * 3.0) * 0.8
				var ix := int(round(fx))
				if not is_air(ix, yy + 1) or not is_air(ix, yy + 2):
					break
				_set_solid(ix, yy, ROCK)
				if k2 < 3:
					_set_solid(ix + 1, yy, ROCK)
		if rng.randf() < 0.7:
			var by := rng.randi_range(r.position.y + 7, r.end.y - 6)
			var xc := r.get_center().x
			if is_air(xc, by):
				var xl := xc
				while xl > r.position.x and is_air(xl - 1, by):
					xl -= 1
				var xr := xc
				while xr < r.end.x and is_air(xr + 1, by):
					xr += 1
				if xr - xl > 6:
					for x in range(xl, xr + 1):
						var sag := int(round(sin(PI * (x - xl) / float(xr - xl)) * 2.0))
						_set_solid(x, by + sag, ROCK)


# ---------------------------------------------------------------- tunnels

func _connect_rooms() -> void:
	var cands: Array = []
	for cy in ROWS:
		for cx in COLS:
			var c := Vector2i(cx, cy)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb: Vector2i = c + d
				if nb.x >= COLS or nb.y >= ROWS:
					continue
				var a: int = cell_node[c]
				var b: int = cell_node[nb]
				if a == b:
					continue
				if a == sky_id or b == sky_id:
					var ok := false
					if d.x == 1 and c.y == 1 and (c.x == 2 or c.x == 6):
						ok = true
					if d.y == 1 and c.y == 1:
						ok = true
					if not ok:
						continue
				cands.append({"a": a, "b": b, "ca": c, "cb": nb, "horiz": d.x == 1, "w": rng.randf()})
	cands.sort_custom(func(p, q): return p["w"] < q["w"])
	var parent := {}
	for room in rooms:
		parent[room["id"]] = room["id"]
	var chosen: Array = []
	for e in cands:
		var ra := _find(parent, e["a"])
		var rb := _find(parent, e["b"])
		var forced: bool = (e["a"] == sky_id or e["b"] == sky_id) and (e["horiz"] or e["ca"].x == 4)
		if ra != rb:
			parent[ra] = rb
			chosen.append(e)
		else:
			var ta: String = rooms[e["a"]]["type"]
			var tb: String = rooms[e["b"]]["type"]
			var p := 0.32
			if ta == "canopy" and tb == "canopy":
				p = 0.85
			if forced or rng.randf() < p:
				chosen.append(e)
	for e in chosen:
		_carve_edge(e)
	report.append("rooms %d, connections %d of %d candidates" % [rooms.size(), chosen.size(), cands.size()])


func _find(parent: Dictionary, v: int) -> int:
	while parent[v] != v:
		parent[v] = parent[parent[v]]
		v = parent[v]
	return v


func _corridor_room(a: Dictionary, b: Dictionary, cell: Vector2i) -> int:
	var id := _add_room("corridor", Rect2i(), cell_region(cell), cell)
	rooms[id]["built"] = a["built"] or b["built"] or cell_region(cell) == World.R_PIPEWORKS
	return id


func _anchor(room: Dictionary, side: Vector2i, cell: Vector2i) -> Vector2i:
	# side: direction from this room towards the other one
	var r: Rect2i = room["rect"]
	var t: String = room["type"]
	if t == "sky":
		if side == Vector2i(-1, 0):
			return Vector2i(3 * CW + 1, sky_surface(3 * CW + 1) - 1)
		if side == Vector2i(1, 0):
			return Vector2i(7 * CW - 2, sky_surface(7 * CW - 2) - 1)
		var x := rng.randi_range(cell.x * CW + 8, cell.x * CW + CW - 9)
		if x > SPIRE_X0 - 6 and x < SPIRE_X1 + 6:
			x = SPIRE_X0 - 8 if x < 220 else SPIRE_X1 + 8
		return Vector2i(x, sky_surface(x) - 1)
	if t == "cave" or t == "canopy":
		var c := r.get_center()
		return Vector2i(c.x, c.y + rng.randi_range(-3, 3))
	if side.x != 0:
		var y := 0
		if t == "hall":
			var levels: Array = room["levels"]
			y = int(levels[rng.randi_range(0, levels.size() - 1)]) - 1
		else:
			y = rng.randi_range(r.position.y + 3, r.end.y - 2)
		return Vector2i(r.end.x - 1 if side.x > 0 else r.position.x, y)
	var x := rng.randi_range(r.position.x + 2, r.end.x - 3)
	if t == "shaft":
		x = r.position.x + 1 if rng.randf() < 0.5 else r.end.x - 2
	return Vector2i(x, r.end.y - 1 if side.y > 0 else r.position.y)


func _carve_h(x0: int, x1: int, fy: int, hgt: int, id: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		for k in hgt:
			_air(x, fy - k, id)


func _carve_rect(x: int, y: int, w: int, h: int, id: int) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_air(xx, yy, id)


func _carve_edge(e: Dictionary) -> void:
	var A: Dictionary = rooms[e["a"]]
	var B: Dictionary = rooms[e["b"]]
	var ca: Vector2i = e["ca"]
	var cb: Vector2i = e["cb"]
	var cid := _corridor_room(A, B, ca if A["type"] != "sky" else cb)
	var built: bool = rooms[cid]["built"]
	if e["horiz"]:
		var pa := _anchor(A, Vector2i(1, 0), ca)
		var pb := _anchor(B, Vector2i(-1, 0), cb)
		var hgt := rng.randi_range(2, 4)
		if built and rng.randf() < 0.3:
			hgt = 1
		elif not built and rng.randf() < 0.35:
			hgt = rng.randi_range(5, 9)   # a wide mouth, so the caves run together
		if A["type"] == "sky" or B["type"] == "sky":
			hgt = 3
		var xm := cb.x * CW + rng.randi_range(-3, 2)
		_carve_h(pa.x, xm, pa.y, hgt, cid)
		var top := mini(pa.y, pb.y) - hgt + 1
		var wv := 2 if hgt < 3 else hgt
		_carve_rect(xm, top, wv, maxi(pa.y, pb.y) - top + 1, cid)
		_carve_h(xm, pb.x, pb.y, hgt, cid)
	else:
		var pa := _anchor(A, Vector2i(0, 1), ca)
		var pb := _anchor(B, Vector2i(0, -1), cb)
		var wv := rng.randi_range(2, 3)
		var ym := cb.y * CH + rng.randi_range(-2, 1)
		if A["type"] == "sky":
			ym = maxi(ym, pa.y + 6)
		var top := mini(pa.y, ym - 2)
		_carve_rect(pa.x, top, wv, maxi(pa.y, ym) - top + 1, cid)
		_carve_h(pa.x, pb.x, ym, 3, cid)
		_carve_rect(pb.x, ym - 2, wv, maxi(pb.y - (ym - 2), 1) + 1, cid)


func _build_spire() -> void:
	spire_id = _add_room("hall", Rect2i(SPIRE_X0, SPIRE_TOP, SPIRE_X1 - SPIRE_X0, SPIRE_GROUND - SPIRE_TOP), World.R_SPIRE, Vector2i(4, 0))
	var id := spire_id
	for y in range(SPIRE_TOP, SPIRE_GROUND):
		for x in range(SPIRE_X0, SPIRE_X1):
			if x < SPIRE_X0 + 2 or x >= SPIRE_X1 - 2 or y < SPIRE_TOP + 2:
				_set_solid(x, y, CONC)
			else:
				_air(x, y, id)
	for x in range(SPIRE_X0 - 2, SPIRE_X1 + 2):
		_set_solid(x, SPIRE_GROUND, CONC)
		_set_solid(x, SPIRE_GROUND + 1, CONC)
	# doors at ground level
	for y in range(SPIRE_GROUND - 3, SPIRE_GROUND):
		for x in [SPIRE_X0, SPIRE_X0 + 1, SPIRE_X1 - 2, SPIRE_X1 - 1]:
			_air(x, y, id)
	var slabs := [47, 40, 33, 26, 19]
	var below := SPIRE_GROUND
	var left := true
	for ly in slabs:
		var px := SPIRE_X0 + 4 if left else SPIRE_X1 - 5
		for x in range(SPIRE_X0 + 2, SPIRE_X1 - 2):
			if x == px:
				_air(x, ly, id)
				_flag(x, ly, World.F_GRATE)
			else:
				_set_solid(x, ly, CONC)
		for yy in range(ly - 1, below):
			_flag(px, yy, World.F_POLE_V)
		for side in [0, 1]:
			if rng.randf() < 0.6:
				var wx: Array = [SPIRE_X0, SPIRE_X0 + 1] if side == 0 else [SPIRE_X1 - 2, SPIRE_X1 - 1]
				for x in wx:
					for yy in [ly - 4, ly - 3]:
						_air(x, yy, id)
		below = ly
		left = not left
	# roof hatch and the mast
	var hx := SPIRE_X1 - 5
	for yy in [SPIRE_TOP, SPIRE_TOP + 1]:
		_air(hx, yy, id)
	_flag(hx, SPIRE_TOP, World.F_GRATE)
	for yy in range(SPIRE_TOP - 1, below):
		_flag(hx, yy, World.F_POLE_V)
	for yy in range(2, SPIRE_TOP):
		_flag(SPIRE_X0 + 6, yy, World.F_POLE_V)
	for xx in range(SPIRE_X0 + 3, SPIRE_X0 + 10):
		_flag(xx, 4, World.F_POLE_H)
	# broken arches on the valley floor
	for k in 4:
		var ax := rng.randi_range(3 * CW + 26, 7 * CW - 36)
		if ax > SPIRE_X0 - 16 and ax < SPIRE_X1 + 4:
			continue
		var g := sky_surface(ax)
		var span := rng.randi_range(6, 10)
		var hgt := rng.randi_range(6, 10)
		for x in [ax, ax + 1, ax + span, ax + span + 1]:
			var gg := sky_surface(x)
			for y in range(g - hgt, gg + 1):
				_set_solid(x, y, CONC)
		if rng.randf() < 0.7:
			for x in range(ax, ax + span + 2 - rng.randi_range(0, 3)):
				_set_solid(x, g - hgt - 1, CONC)


func _ruins() -> void:
	for room in rooms:
		if room["type"] != "cave":
			continue
		if room["region"] != World.R_HOLLOWS and room["region"] != World.R_SUNKEN:
			continue
		var r: Rect2i = room["rect"]
		for k in rng.randi_range(1, 3):
			var x := rng.randi_range(r.position.x + 2, r.end.x - 3)
			var y := r.get_center().y
			while y < r.end.y + 4 and is_air(x, y + 1):
				y += 1
			if not is_air(x, y) or is_air(x, y + 1):
				continue
			if rng.randf() < 0.6:
				var hh := rng.randi_range(2, 3)
				for yy in range(y - hh + 1, y + 1):
					_set_solid(x, yy, CONC)
					if is_air(x + 1, yy):
						_set_solid(x + 1, yy, CONC)
			else:
				# a broken slab bridging the air above
				var sy := y - rng.randi_range(4, 7)
				for xx in range(x - rng.randi_range(2, 5), x + rng.randi_range(2, 5)):
					if is_air(xx, sy):
						_set_solid(xx, sy, CONC)


func _find_start() -> void:
	var room: Dictionary = rooms[cell_node[Vector2i(4, 3)]]
	var c: Vector2i = room["rect"].get_center()
	var y := c.y
	while is_air(c.x, y + 1):
		y += 1
	start = Vector2i(c.x, y)


func _remove_pockets() -> void:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var q := PackedInt32Array([idx(start.x, start.y)])
	seen[q[0]] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if inb(nx, ny):
				var j := ny * W + nx
				if seen[j] == 0 and solid[j] == AIR:
					seen[j] = 1
					q.append(j)
	var filled := 0
	for i in W * H:
		if solid[i] == AIR and seen[i] == 0:
			solid[i] = ROCK
			flags[i] = 0
			filled += 1
	report.append("filled %d isolated air tiles" % filled)


func _materials() -> void:
	var src := PackedInt32Array()
	src.resize(W * H)
	src.fill(-1)
	depth.fill(0)
	var q := PackedInt32Array()
	for i in W * H:
		if solid[i] == AIR:
			src[i] = owner[i]
			q.append(i)
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		var y := i / W
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if not inb(nx, ny):
				continue
			var j := ny * W + nx
			if solid[j] == AIR or depth[j] != 0:
				continue
			depth[j] = mini(depth[i] + 1, 250)
			src[j] = src[i]
			q.append(j)
			if fixed[j] == 0:
				var o := src[i]
				var built := false
				if o >= 0:
					built = rooms[o]["built"]
				var m := CONC if built else ROCK
				if built and region[j] == World.R_PIPEWORKS and noise.get_noise_2d(nx * 4.0 + 300.0, ny * 4.0) > 0.25:
					m = METAL
				solid[j] = m


func _flood() -> void:
	for y in range(WATER_ROW, H):
		for x in W:
			if solid[y * W + x] == AIR:
				flags[y * W + x] |= World.F_WATER


func _pools() -> void:
	var count := 0
	for y in range(WATER_ROW - 1, 2, -1):
		var x := 1
		while x < W - 1:
			if solid[y * W + x] != AIR or (flags[y * W + x] & World.F_WATER):
				x += 1
				continue
			var x0 := x
			while x < W - 1 and solid[y * W + x] == AIR:
				x += 1
			var x1 := x - 1
			var reg := region[y * W + x0]
			if reg == World.R_PIPEWORKS or reg == World.R_SPIRE:
				continue
			if x1 - x0 < 2 or x1 - x0 > 26:
				continue
			if solid[y * W + x0 - 1] == AIR or solid[y * W + x1 + 1] == AIR:
				continue
			var ok := true
			var deep := 0
			for xx in range(x0, x1 + 1):
				var b := (y + 1) * W + xx
				if solid[b] == AIR and (flags[b] & World.F_WATER) == 0:
					ok = false
					break
				if flags[b] & World.F_WATER:
					var d := 1
					while (flags[(y + d) * W + xx] & World.F_WATER) != 0:
						d += 1
					deep = maxi(deep, d)
			if not ok or deep >= 4:
				continue
			# hash per basin so the whole basin is kept or skipped together
			if deep == 0 and (hash(Vector2i(x0, y)) % 100) > 55:
				continue
			for xx in range(x0, x1 + 1):
				flags[y * W + xx] |= World.F_WATER
			count += 1
	report.append("pool layers %d" % count)


# ---------------------------------------------------------------- reachability

func _support(x: int, y: int) -> int:
	var i := y * W + x
	var s := 0
	var f := flags[i]
	if f & World.F_WATER:
		s |= 4
	if f & (World.F_POLE_V | World.F_VINE):
		s |= 2
	if f & World.F_POLE_H:
		s |= 16
	if y + 1 >= H:
		s |= 1
	else:
		var b := i + W
		if solid[b] != AIR or (flags[b] & (World.F_GRATE | World.F_POLE_H)) != 0:
			s |= 1
	if mat(x - 1, y) == ROCK or mat(x + 1, y) == ROCK:
		s |= 8
	return s


func _succ(x: int, y: int, out: PackedInt32Array) -> void:
	if is_air(x, y + 1):
		out.append(idx(x, y + 1))
	var s := _support(x, y)
	if s == 0:
		for dx in [-1, 1]:
			var nx: int = x + dx
			if is_air(nx, y) and is_air(nx, y + 1) and (flags[idx(nx, y + 1)] & (World.F_GRATE | World.F_POLE_H)) == 0:
				out.append(idx(nx, y + 1))
		return
	for dx in [-1, 1]:
		if is_air(x + dx, y):
			out.append(idx(x + dx, y))
	if (s & (2 | 4 | 8 | 16)) and is_air(x, y - 1):
		out.append(idx(x, y - 1))
	var in_water := (s & 4) != 0
	var surface := in_water and is_air(x, y - 1) and (flags[idx(x, y - 1)] & World.F_WATER) == 0
	var held := (s & (1 | 2 | 8 | 16)) != 0
	if not held and not surface:
		return
	var jh := JUMP_H
	if in_water and not held:
		jh = 3
	for k in range(1, jh + 1):
		var yy := y - k
		if not is_air(x, yy):
			break
		out.append(idx(x, yy))
		for dx in [-1, 1]:
			for j in range(1, 4):
				var nx: int = x + dx * j
				if not is_air(nx, yy):
					break
				out.append(idx(nx, yy))


func _build_graph() -> void:
	var n := W * H
	adj_start.resize(n + 1)
	adj = PackedInt32Array()
	var tmp := PackedInt32Array()
	for i in n:
		adj_start[i] = adj.size()
		if solid[i] != AIR:
			continue
		tmp.clear()
		_succ(i % W, i / W, tmp)
		adj.append_array(tmp)
	adj_start[n] = adj.size()


func _reach() -> void:
	var n := W * H
	fwd.resize(n)
	fwd.fill(0)
	bwd.resize(n)
	bwd.fill(0)
	var s := idx(start.x, start.y)
	var q := PackedInt32Array([s])
	fwd[s] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		for k in range(adj_start[i], adj_start[i + 1]):
			var j := adj[k]
			if fwd[j] == 0:
				fwd[j] = 1
				q.append(j)
	# reverse graph
	var indeg := PackedInt32Array()
	indeg.resize(n + 1)
	indeg.fill(0)
	for k in adj.size():
		indeg[adj[k] + 1] += 1
	for i in n:
		indeg[i + 1] += indeg[i]
	var rstart := indeg.duplicate()
	var fill := indeg.duplicate()
	var radj := PackedInt32Array()
	radj.resize(adj.size())
	for i in n:
		for k in range(adj_start[i], adj_start[i + 1]):
			var j := adj[k]
			radj[fill[j]] = i
			fill[j] += 1
	q = PackedInt32Array([s])
	bwd[s] = 1
	head = 0
	while head < q.size():
		var i := q[head]
		head += 1
		for k in range(rstart[i], rstart[i + 1]):
			var j := radj[k]
			if bwd[j] == 0:
				bwd[j] = 1
				q.append(j)


func _standing(x: int, y: int) -> bool:
	if not is_air(x, y) or (flags[idx(x, y)] & World.F_WATER):
		return false
	if not inb(x, y + 1):
		return true
	var b := idx(x, y + 1)
	return solid[b] != AIR or (flags[b] & (World.F_GRATE | World.F_POLE_H)) != 0


func _place_pole(c: int, y_top: int, y_bot: int) -> void:
	for y in range(y_top, y_bot + 1):
		if is_air(c, y):
			_flag(c, y, World.F_POLE_V)


func _fix_connectivity() -> int:
	_build_graph()
	_reach()
	var claimed := PackedByteArray()
	claimed.resize(W * H)
	claimed.fill(0)
	var placed := 0
	# traps: places you can fall into but not climb out of
	for y in range(H - 2, 0, -1):
		for x in range(1, W - 1):
			var i := y * W + x
			if fwd[i] == 0 or bwd[i] == 1 or claimed[i] == 1:
				continue
			var surface := (flags[i] & World.F_WATER) != 0 and is_air(x, y - 1) and (flags[i - W] & World.F_WATER) == 0
			if not _standing(x, y) and not surface:
				continue
			var done := false
			for c in [x, x - 1, x + 1, x - 2, x + 2]:
				if done or not is_air(c, y):
					continue
				for r in range(y - 1, maxi(y - 60, 1), -1):
					if not is_air(c, r):
						break
					var ok := false
					for side in [-1, 1]:
						var sx: int = c + side
						if is_air(sx, r) and bwd[idx(sx, r)] == 1 and _support(sx, r) != 0:
							ok = true
					if bwd[idx(c, r)] == 1 and _support(c, r) & (1 | 2 | 8) != 0:
						ok = true
					if ok:
						_place_pole(c, r, y)
						placed += 1
						done = true
						break
			if done:
				_claim(claimed, x, y, 10)
	# high ledges nothing reaches
	for y in range(H - 2, 0, -1):
		for x in range(1, W - 1):
			var i := y * W + x
			if fwd[i] == 1 or claimed[i] == 1 or not _standing(x, y):
				continue
			for c in [x - 1, x + 1]:
				if not is_air(c, y) or not is_air(c, y + 1):
					continue
				var r := y + 1
				while r < H - 1 and is_air(c, r + 1) and (flags[idx(c, r)] & World.F_WATER) == 0 and r - y < 60:
					r += 1
				if fwd[idx(c, r)] == 1:
					_place_pole(c, y, r)
					placed += 1
					_claim(claimed, x, y, 10)
					break
	return placed


func _claim(claimed: PackedByteArray, x: int, y: int, rad: int) -> void:
	for yy in range(maxi(y - rad, 0), mini(y + rad + 1, H)):
		for xx in range(maxi(x - rad, 0), mini(x + rad + 1, W)):
			claimed[yy * W + xx] = 1


func strong(x: int, y: int) -> bool:
	var i := idx(x, y)
	return fwd[i] == 1 and bwd[i] == 1


func _report_reach() -> void:
	var standing := 0
	var ok := 0
	var traps := 0
	var unreached := 0
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if not _standing(x, y):
				continue
			standing += 1
			var i := idx(x, y)
			if fwd[i] == 1 and bwd[i] == 1:
				ok += 1
			elif fwd[i] == 1:
				traps += 1
			else:
				unreached += 1
	report.append("standing tiles %d: round trip %d, traps %d, unreached %d" % [standing, ok, traps, unreached])


# ---------------------------------------------------------------- dressing

func _back_layer() -> void:
	for y in H:
		for x in W:
			var i := y * W + x
			var o := owner[i]
			var b := 1
			if o >= 0 and rooms[o]["built"]:
				b = 2
			var reg := region[i]
			if o == sky_id or (reg == World.R_SPIRE and o != spire_id and y < SPIRE_GROUND + 2):
				b = 0
			if reg == World.R_CANOPY and y < 2 * CH:
				b = 0
			# broken back panels in built rooms: whole panels missing
			if b == 2 and reg != World.R_SPIRE:
				var panel := Vector2i(int(floor(x / 6.0)), int(floor(y / 4.0)))
				if (hash(panel) % 1000) < 70:
					b = 0
			back[i] = b
	# cracks high in cave walls, so daylight slants down into the hollows
	for room in rooms:
		if room["type"] != "cave" and room["type"] != "canopy":
			continue
		var r: Rect2i = room["rect"]
		if r.position.y > WATER_ROW - 24 or rng.randf() > 0.7:
			continue
		for k in rng.randi_range(1, 2):
			var cx := rng.randi_range(r.position.x + 3, r.end.x - 4)
			var cy := r.position.y + rng.randi_range(1, maxi(2, r.size.y / 3))
			var rad := rng.randf_range(1.6, 3.4)
			for y in range(cy - 5, cy + 6):
				for x in range(cx - 7, cx + 8):
					if not inb(x, y):
						continue
					var d := Vector2((x - cx) / 1.6, y - cy).length() + noise.get_noise_2d(x * 3.0, y * 3.0) * 1.2
					if d < rad and solid[idx(x, y)] == AIR:
						back[idx(x, y)] = 0


func _farthest(cands: Array, count: int, taken: Array, min_d: float) -> Array:
	var out: Array = []
	if cands.is_empty():
		return out
	for k in count:
		var best := Vector2i(-1, -1)
		var best_d := -1.0
		for t in 400:
			var c: Vector2i = cands[rng.randi_range(0, cands.size() - 1)]
			var d := 1e9
			for p in taken + out:
				var pv: Vector2i = p
				d = minf(d, Vector2(c - pv).length())
			if d > best_d:
				best_d = d
				best = c
		if best.x >= 0 and best_d >= min_d:
			out.append(best)
	return out


func _openness(x: int, y: int, r: int) -> int:
	var cnt := 0
	for yy in range(y - r, y + r + 1, 2):
		for xx in range(x - r, x + r + 1, 2):
			if is_air(xx, yy):
				cnt += 1
	return cnt


func _place_objects() -> void:
	var stand_by_region: Array = [[], [], [], [], []]
	var water_floor: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if not strong(x, y):
				continue
			var i := idx(x, y)
			if _standing(x, y):
				stand_by_region[region[i]].append(Vector2i(x, y))
			elif (flags[i] & World.F_WATER) and not is_air(x, y + 1) and region[i] == World.R_SUNKEN:
				water_floor.append(Vector2i(x, y))
	objects.append({"t": "nest", "x": start.x, "y": start.y, "id": 0})
	var nests: Array = [start]
	var nid := 1
	for reg in [World.R_PIPEWORKS, World.R_CANOPY, World.R_SUNKEN, World.R_SPIRE, World.R_HOLLOWS]:
		var cands: Array = []
		for c in stand_by_region[reg]:
			if c.y < WATER_ROW - 1 and _standing(c.x - 1, c.y) and _standing(c.x + 1, c.y) and not is_air(c.x, c.y + 1) and not is_air(c.x - 1, c.y + 1) and not is_air(c.x + 1, c.y + 1) and (flags[idx(c.x, c.y)] & (World.F_POLE_V | World.F_DRAFT)) == 0:
				cands.append(c)
		var got := _farthest(cands, 1, nests, 30.0)
		for p in got:
			nests.append(p)
			objects.append({"t": "nest", "x": p.x, "y": p.y, "id": nid})
			nid += 1
	# lanterns
	var lanterns: Array = []
	var lid := 0
	var plan := {World.R_HOLLOWS: 2, World.R_PIPEWORKS: 2, World.R_CANOPY: 2, World.R_SUNKEN: 1}
	for reg in plan:
		var cands: Array = []
		for c in stand_by_region[reg]:
			if _standing(c.x - 1, c.y) and _standing(c.x + 1, c.y):
				cands.append(c)
		for p in _farthest(cands, plan[reg], nests + lanterns, 26.0):
			lanterns.append(p)
			objects.append({"t": "lantern", "x": p.x, "y": p.y, "id": lid, "kind": "lamp"})
			lid += 1
	var deep := _farthest(water_floor, 1, nests + lanterns, 20.0)
	for p in deep:
		lanterns.append(p)
		objects.append({"t": "lantern", "x": p.x, "y": p.y, "id": lid, "kind": "deep"})
		lid += 1
	objects.append({"t": "lantern", "x": 220, "y": SPIRE_TOP - 1, "id": lid, "kind": "beacon"})
	lanterns.append(Vector2i(220, SPIRE_TOP - 1))
	report.append("lanterns %d, nests %d" % [lanterns.size(), nests.size()])
	# seed plants
	var plants: Array = []
	var pchance := [0.05, 0.012, 0.07, 0.04, 0.03]
	for reg in 5:
		for c in stand_by_region[reg]:
			if rng.randf() > pchance[reg] or mat(c.x, c.y + 1) == AIR:
				continue
			var near := false
			for p in plants:
				if absi(p.x - c.x) < 8 and absi(p.y - c.y) < 4:
					near = true
					break
			for p in lanterns + nests:
				if absi(p.x - c.x) < 3 and absi(p.y - c.y) < 3:
					near = true
			if not near:
				plants.append(c)
	for p in plants:
		objects.append({"t": "plant", "x": p.x, "y": p.y})
	# trundlers on long flat floors
	var trund: Array = []
	for reg in [World.R_HOLLOWS, World.R_CANOPY, World.R_SPIRE, World.R_SUNKEN]:
		var cands: Array = []
		for c in stand_by_region[reg]:
			if c.y >= WATER_ROW - 1:
				continue
			var run := 0
			for dx in range(-7, 8):
				if _standing(c.x + dx, c.y) and mat(c.x + dx, c.y + 1) != AIR:
					run += 1
			if run >= 15 and is_air(c.x, c.y - 1) and is_air(c.x, c.y - 2):
				cands.append(c)
		for p in _farthest(cands, 3 if reg != World.R_SUNKEN else 2, trund + nests, 22.0):
			trund.append(p)
			objects.append({"t": "trundler", "x": p.x, "y": p.y})
	# kites in big open air
	var kites: Array = []
	var kcands: Array = []
	for y in range(3, WATER_ROW - 4, 2):
		for x in range(3, W - 3, 2):
			if not is_air(x, y):
				continue
			var reg := region[idx(x, y)]
			if reg == World.R_CANOPY or reg == World.R_SPIRE or reg == World.R_HOLLOWS:
				if _openness(x, y, 6) >= 46:
					kcands.append(Vector2i(x, y))
	for p in _farthest(kcands, 30, [], 14.0):
		kites.append(p)
		objects.append({"t": "kite", "x": p.x, "y": p.y})
	# glimmer schools
	var wc: Array = []
	for y in range(WATER_ROW + 2, H - 2, 2):
		for x in range(2, W - 2, 2):
			if (flags[idx(x, y)] & World.F_WATER) and _openness(x, y, 4) >= 22:
				wc.append(Vector2i(x, y))
	for p in _farthest(wc, 14, [], 20.0):
		objects.append({"t": "glimmers", "x": p.x, "y": p.y})
	# updrafts: steam vents in built halls, thermals beside the spire
	var vents := 0
	for room in rooms:
		if room["type"] != "hall" or room["region"] != World.R_PIPEWORKS or vents >= 8:
			continue
		var r: Rect2i = room["rect"]
		for t in 20:
			var x := rng.randi_range(r.position.x + 2, r.end.x - 4)
			var y := r.end.y - 1
			if not _standing(x, y) or not _standing(x + 1, y):
				continue
			var top := y
			while top > y - 16 and is_air(x, top - 1) and is_air(x + 1, top - 1):
				top -= 1
			if y - top < 8:
				continue
			for yy in range(top, y + 1):
				_flag(x, yy, World.F_DRAFT)
				_flag(x + 1, yy, World.F_DRAFT)
			objects.append({"t": "vent", "x": x, "y": y, "w": 2, "h": y - top + 1, "kind": "steam"})
			vents += 1
			break
	for vx in [SPIRE_X0 - 9, SPIRE_X1 + 7]:
		var g := sky_surface(vx) - 1
		var top := 6
		for yy in range(top, g + 1):
			for k in 3:
				_flag(vx + k, yy, World.F_DRAFT)
		objects.append({"t": "vent", "x": vx, "y": g, "w": 3, "h": g - top + 1, "kind": "thermal"})
	report.append("plants %d, trundlers %d, kites %d, vents %d" % [plants.size(), trund.size(), kites.size(), vents + 2])
	# echoes: glyphs carved in the back wall, read for a line of the works' story
	var ecands: Array = []
	for reg in 5:
		for c in stand_by_region[reg]:
			if back[idx(c.x, c.y - 1)] != 0 and back[idx(c.x, c.y - 2)] != 0 and is_air(c.x, c.y - 2) and flags[idx(c.x, c.y)] == 0:
				ecands.append(c)
	var echoes := _farthest(ecands, 14, nests + lanterns, 18.0)
	for k in echoes.size():
		objects.append({"t": "echo", "x": echoes[k].x, "y": echoes[k].y, "id": k})
	report.append("echoes %d" % echoes.size())


## Sunlight falls down and to the right (SUN_SLOPE tiles across per row). It
## starts wherever the air opens onto the outside (back layer missing) and
## carries on in straight parallel rays until stone stops it; water dims it.
func _sunlight() -> PackedByteArray:
	# baked at SUN_RES cells per tile so beam edges stay smooth when sampled
	var R := World.SUN_RES
	var sw := W * R
	var sh := H * R
	var slope := World.SUN_SLOPE
	var sun := PackedByteArray()
	sun.resize(sw * sh)
	sun.fill(0)
	for cy in range(R, sh):
		var shift := floori(cy * slope) - floori((cy - 1) * slope)
		var ty := cy / R
		var row := cy * sw
		var prev := row - sw
		for cx in sw:
			var ti := ty * W + cx / R
			if solid[ti] != AIR:
				continue
			var v := 0
			if back[ti] == 0 and ty < WATER_ROW:
				v = 255
			var sx := cx - shift
			if sx >= 0:
				v = maxi(v, sun[prev + sx])
			if flags[ti] & World.F_WATER:
				v = int(v * 0.965)
			sun[row + cx] = v
	return sun

func _pack() -> Resource:
	var d := WorldData.new()
	var n := W * H
	d.w = W
	d.h = H
	d.solid = solid
	d.back = back
	d.flags = flags
	d.region = region
	d.depth = depth
	d.start = start
	d.objects = objects
	# distance from air to solid
	var ad := PackedByteArray()
	ad.resize(n)
	ad.fill(0)
	var q := PackedInt32Array()
	for i in n:
		if solid[i] != AIR:
			q.append(i)
	var seen := PackedByteArray()
	seen.resize(n)
	for i in q:
		seen[i] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % W
		var y := i / W
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + dd.x
			var ny: int = y + dd.y
			if not inb(nx, ny):
				continue
			var j := ny * W + nx
			if seen[j] == 1:
				continue
			seen[j] = 1
			ad[j] = mini(ad[i] + 1, 8)
			if ad[j] < 8:
				q.append(j)
	d.air_dist = ad
	var wd := PackedByteArray()
	wd.resize(n)
	wd.fill(0)
	for x in W:
		var run := 0
		for y in H:
			var i := y * W + x
			if flags[i] & World.F_WATER:
				run += 1
				wd[i] = mini(run, 12)
			else:
				run = 0
	d.water_depth = wd
	var ms := PackedByteArray()
	ms.resize(n)
	ms.fill(0)
	var rm := [0.85, 0.25, 1.0, 0.55, 0.45]
	for y in range(1, H):
		for x in W:
			var i := y * W + x
			if solid[i] == AIR:
				continue
			var exposed := 0.0
			if is_air(x, y - 1):
				exposed = 1.0
			elif is_air(x, y - 2) and solid[i - W] != AIR:
				exposed = 0.5
			elif is_air(x - 1, y) or is_air(x + 1, y):
				exposed = 0.3
			if exposed <= 0.0:
				continue
			var m: float = rm[region[i]] * exposed * clampf(0.55 + noise.get_noise_2d(x * 2.0, y * 2.0) * 0.9, 0.0, 1.0)
			if solid[i] != ROCK:
				m *= 0.45
			if flags[i - W] & World.F_WATER:
				m *= 0.5
			ms[i] = int(m * 255.0)
	d.moss = ms
	var sk := PackedByteArray()
	sk.resize(n)
	sk.fill(0)
	for x in W:
		for y in range(1, H):
			var i := y * W + x
			if solid[i] != AIR:
				break
			sk[i] = 255
			if flags[i] & World.F_WATER:
				break
	# rain also drifts through places that open onto the far air behind
	for i in n:
		if solid[i] == AIR and back[i] == 0 and sk[i] == 0 and region[i] != World.R_SUNKEN:
			sk[i] = 150
	d.sky = sk
	d.sun = _sunlight()
	return d
