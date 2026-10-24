extends Node2D
## Builds the drawn world in 512 px chunks: back wall, poles and chains, the play
## layer, foliage and water. All static; only shader uniforms change at runtime.

const World = preload("res://scripts/world.gd")
const Palette = preload("res://scripts/palette.gd")
const MB = preload("res://scripts/mesh_builder.gd")

const CHUNK := 32
const Z_BACK := -50
const Z_MID := -40
const Z_FRONT := 10
const Z_FOLIAGE := 12
const Z_WATER := 20

var world: World
var mat_back: ShaderMaterial
var mat_front: ShaderMaterial
var mat_water: ShaderMaterial
var mat_sway: ShaderMaterial
var mat_plain: ShaderMaterial
var rng := RandomNumberGenerator.new()


func build(w: World, waves_tex: Texture2D) -> void:
	world = w
	mat_back = _terrain_mat("res://shaders/terrain_back.gdshader")
	mat_front = _terrain_mat("res://shaders/terrain_front.gdshader")
	mat_water = _terrain_mat("res://shaders/water.gdshader")
	mat_water.set_shader_parameter("waves", waves_tex)
	mat_water.set_shader_parameter("wave_cols", float(w.w * 2))
	mat_sway = ShaderMaterial.new()
	mat_sway.shader = load("res://shaders/sway.gdshader")
	mat_plain = mat_sway
	var cs := CHUNK * World.TILE
	for cy in ceili(float(w.h) / CHUNK):
		for cx in ceili(float(w.w) / CHUNK):
			var has_solid := false
			var has_back := false
			var has_water := false
			for y in range(cy * CHUNK, mini((cy + 1) * CHUNK, w.h)):
				for x in range(cx * CHUNK, mini((cx + 1) * CHUNK, w.w)):
					var i := y * w.w + x
					if w.solid[i] != World.AIR:
						has_solid = true
					elif w.back[i] != 0:
						has_back = true
					if w.flags[i] & World.F_WATER:
						has_water = true
			var pos := Vector2(cx, cy) * cs
			if has_back:
				_rect(pos, cs, mat_back, Z_BACK)
			if has_solid:
				_rect(pos, cs, mat_front, Z_FRONT)
			if has_water:
				_rect(pos, cs, mat_water, Z_WATER)
			rng.seed = hash(Vector2i(cx, cy))
			_mid_mesh(cx, cy)
			_foliage_mesh(cx, cy)


func _terrain_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	m.set_shader_parameter("map_a", world.tex_a)
	m.set_shader_parameter("map_b", world.tex_b)
	m.set_shader_parameter("map_c", world.tex_c)
	m.set_shader_parameter("reg_a", world.reg_a)
	m.set_shader_parameter("reg_b", world.reg_b)
	m.set_shader_parameter("map_size", Vector2(world.w, world.h))
	m.set_shader_parameter("tile", World.TILE)
	m.set_shader_parameter("sun_map", world.tex_sun)
	m.set_shader_parameter("sun_dir", World.SUN_DIR)
	Palette.apply(m)
	return m


func set_atmosphere(sky_tint: Color, fog_amount: float, ambient: Color, wind: float, glow: float, sun: Color, sun_strength: float) -> void:
	var st := Vector3(sky_tint.r, sky_tint.g, sky_tint.b)
	for m in [mat_back, mat_front]:
		m.set_shader_parameter("sky_tint", st)
		m.set_shader_parameter("sun_col", Vector3(sun.r, sun.g, sun.b))
		m.set_shader_parameter("sun_strength", sun_strength)
	mat_back.set_shader_parameter("fog_amount", fog_amount)
	mat_water.set_shader_parameter("ambient", Vector3(ambient.r, ambient.g, ambient.b))
	mat_sway.set_shader_parameter("wind", wind)
	mat_sway.set_shader_parameter("glow", glow)


func _rect(pos: Vector2, size: float, m: Material, z: int) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = Vector2(size, size)
	r.material = m
	r.z_index = z
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)


func _mesh_node(mb: MB, z: int, light := true) -> void:
	if mb.is_empty():
		return
	var mi := MeshInstance2D.new()
	mi.mesh = mb.build()
	mi.material = mat_sway
	mi.z_index = z
	if not light:
		mi.light_mask = 0
	add_child(mi)


func _built(x: int, y: int) -> bool:
	var m := world.mat(x, y)
	return m == World.CONC or m == World.METAL


func _reg(x: int, y: int) -> int:
	if not world.inb(x, y):
		return 0
	return world.region[y * world.w + x]


# ------------------------------------------------------------ poles, grates, chains

func _mid_mesh(cx: int, cy: int) -> void:
	var mb := MB.new()
	var T := World.TILE
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	var x1 := mini(x0 + CHUNK, world.w)
	var y1 := mini(y0 + CHUNK, world.h)
	var pole_c := Color(0.36, 0.35, 0.33)
	var pole_hi := Color(0.55, 0.53, 0.5)
	# vertical pole runs (start inside this chunk)
	for x in range(x0, x1):
		var y := y0
		while y < y1:
			if not world.has_flag(x, y, World.F_POLE_V) or world.is_solid(x, y):
				y += 1
				continue
			if world.has_flag(x, y - 1, World.F_POLE_V) and y > y0 and not world.is_solid(x, y - 1):
				y += 1
				continue
			var ys := y
			while world.has_flag(x, y, World.F_POLE_V) and not world.is_solid(x, y):
				y += 1
			var top := ys * T - (4.0 if world.is_solid(x, ys - 1) else -3.0)
			var bot := y * T + (4.0 if world.is_solid(x, y) else -3.0)
			var cxp := x * T + T * 0.5
			mb.rect(Rect2(cxp - 1.5, top, 3.0, bot - top), pole_c)
			mb.rect(Rect2(cxp - 1.0, top, 1.0, bot - top), pole_hi)
			for k in range(ys, y, 4):
				mb.rect(Rect2(cxp - 2.5, k * T + 6.0, 5.0, 2.0), pole_c.darkened(0.3))
			mb.rect(Rect2(cxp - 3.5, top, 7.0, 3.0), pole_c.darkened(0.2))
			mb.rect(Rect2(cxp - 3.5, bot - 3.0, 7.0, 3.0), pole_c.darkened(0.2))
	# horizontal poles
	for y in range(y0, y1):
		var x := x0
		while x < x1:
			if not world.has_flag(x, y, World.F_POLE_H) or world.is_solid(x, y):
				x += 1
				continue
			var xs := x
			while x < x1 and world.has_flag(x, y, World.F_POLE_H) and not world.is_solid(x, y):
				x += 1
			var cyp := y * T + T * 0.5
			var l := xs * T - (4.0 if world.is_solid(xs - 1, y) else 0.0)
			var r := x * T + (4.0 if world.is_solid(x, y) else 0.0)
			mb.rect(Rect2(l, cyp - 1.5, r - l, 3.0), pole_c)
			mb.rect(Rect2(l, cyp - 1.5, r - l, 1.0), pole_hi)
	# grates
	var grate_c := Color(0.28, 0.27, 0.26)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if not world.has_flag(x, y, World.F_GRATE):
				continue
			var px := x * T
			var py := y * T
			mb.rect(Rect2(px, py, T, 2.5), grate_c.lightened(0.15))
			mb.rect(Rect2(px, py + 6.0, T, 1.5), grate_c)
			for k in 4:
				mb.rect(Rect2(px + k * 4.0 + 1.0, py + 2.0, 1.5, 5.0), grate_c)
	# chains and cables under built ceilings
	for y in range(y0, y1):
		for x in range(x0, x1):
			if not _built(x, y) or world.is_solid(x, y + 1):
				continue
			var roll := rng.randf()
			if roll < 0.035:
				var n := 0
				while n < 10 and not world.is_solid(x, y + 1 + n) and not world.has_flag(x, y + 1 + n, World.F_WATER):
					n += 1
				var length := rng.randi_range(2, maxi(2, n - 2)) * T
				var cxp := x * T + rng.randf_range(3, 13)
				var c := Color(0.2, 0.19, 0.18)
				var yy := (y + 1) * T - 2.0
				var link := 0
				while yy < (y + 1) * T + length:
					var s := (yy - (y + 1) * T) / 120.0
					if link % 2 == 0:
						mb.ellipse(Vector2(cxp, yy + 3), Vector2(2.2, 3.4), c, s, 0.0, 6)
						mb.ellipse(Vector2(cxp, yy + 3), Vector2(1.0, 2.0), c.darkened(0.6), s, 0.0, 6)
					else:
						mb.rect(Rect2(cxp - 0.6, yy, 1.2, 6.0), c, s)
					yy += 5.0
					link += 1
				if rng.randf() < 0.4:
					mb.rect(Rect2(cxp - 3, yy, 6, 5), c.darkened(0.2), (yy - (y + 1) * T) / 120.0)
			elif roll < 0.06:
				var span := rng.randi_range(3, 7)
				var ok := true
				for k in span + 1:
					if not _built(x + k, y) or world.is_solid(x + k, y + 1):
						ok = false
						break
				if not ok:
					continue
				var a := Vector2(x * T + 8, (y + 1) * T)
				var b := Vector2((x + span) * T + 8, (y + 1) * T)
				var sag := rng.randf_range(10, 34)
				var pts := PackedVector2Array()
				for k in 13:
					var t := k / 12.0
					pts.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
				mb.polyline(pts, 1.6, 1.6, Color(0.12, 0.11, 0.11), Color(0.12, 0.11, 0.11), 0.0, 0.0)
	_mesh_node(mb, Z_MID)


# ------------------------------------------------------------ foliage

func _foliage_mesh(cx: int, cy: int) -> void:
	var mb := MB.new()
	var T := World.TILE
	var x0 := cx * CHUNK
	var y0 := cy * CHUNK
	for y in range(y0, mini(y0 + CHUNK, world.h)):
		for x in range(x0, mini(x0 + CHUNK, world.w)):
			if not world.is_solid(x, y):
				continue
			var i := y * world.w + x
			var reg := world.region[i]
			var moss := world.moss[i] / 255.0
			var above_air := world.inb(x, y - 1) and not world.is_solid(x, y - 1)
			var below_air := world.inb(x, y + 1) and not world.is_solid(x, y + 1)
			var wet_above := world.has_flag(x, y - 1, World.F_WATER)
			var mc: Color = Palette.MOSS[reg]
			if above_air and moss > 0.2:
				var n := int(moss * 6.0)
				if reg == World.R_CANOPY:
					n += 2
				for k in n:
					var bx := x * T + rng.randf() * T
					var by := y * T + 3.0
					var hgt := rng.randf_range(4.0, 11.0) * (0.5 + moss)
					if wet_above:
						hgt *= 1.6
					var lean := rng.randf_range(-3.0, 3.0)
					var c := mc * rng.randf_range(0.7, 1.15)
					c.a = 1.0
					mb.tri(Vector2(bx - 1.3, by), Vector2(bx + 1.3, by), Vector2(bx + lean, by - hgt), c.darkened(0.45), c.darkened(0.45), c, 0.0, 0.0, hgt / 12.0)
				# small pale flowers among the moss
				if (reg == World.R_HOLLOWS or reg == World.R_CANOPY or reg == World.R_SPIRE) and rng.randf() < 0.07 and not wet_above:
					_flowers(mb, Vector2(x * T + rng.randf_range(2, 14), y * T + 3), reg)
				# canopy ferns, hollows mushrooms
				if reg == World.R_CANOPY and rng.randf() < 0.12:
					_fern(mb, Vector2(x * T + 8, y * T + 3), mc)
				elif (reg == World.R_HOLLOWS or reg == World.R_SUNKEN) and rng.randf() < 0.07 and not wet_above:
					_mushrooms(mb, Vector2(x * T + rng.randf_range(3, 13), y * T + 3), reg)
			if below_air and not world.has_flag(x, y + 1, World.F_WATER) and world.mat(x, y) == World.ROCK:
				var p := 0.3 if reg != World.R_PIPEWORKS else 0.08
				if reg == World.R_CANOPY:
					p = 0.5
				if rng.randf() < p:
					_strand(mb, Vector2(x * T + rng.randf_range(2, 14), (y + 1) * T - 3.0), reg, x, y)
	_mesh_node(mb, Z_FOLIAGE)


func _fern(mb: MB, base: Vector2, mc: Color) -> void:
	var fronds := rng.randi_range(3, 5)
	for f in fronds:
		var ang := lerpf(-2.4, -0.7, (f + 0.5) / fronds) + rng.randf_range(-0.15, 0.15)
		var length := rng.randf_range(12, 24)
		var pts := PackedVector2Array()
		for k in 7:
			var t := k / 6.0
			var dir := Vector2(cos(ang), sin(ang))
			pts.append(base + dir * length * t + Vector2(0, length * 0.35 * t * t))
		var c := mc.darkened(0.1)
		mb.polyline(pts, 1.6, 0.6, c.darkened(0.3), c, 0.0, length / 18.0)
		for k in range(1, 6):
			var p := pts[k]
			var s := k / 6.0 * length / 18.0
			var lw := (1.0 - k / 7.0) * 5.0
			mb.tri(p, p + Vector2(-1.5, -lw), p + Vector2(1.5, -lw * 0.6), c, c, c.lightened(0.15), s, s, s)
			mb.tri(p, p + Vector2(1.5, lw * 0.5), p + Vector2(-1.0, lw * 0.8), c.darkened(0.15), c, c, s, s, s)


func _mushrooms(mb: MB, base: Vector2, reg: int) -> void:
	var gc: Color = Palette.GLOW[reg] * 0.8
	for k in rng.randi_range(1, 3):
		var p := base + Vector2(k * 3.5 - 3.5, 0)
		var h := rng.randf_range(3, 7)
		mb.rect(Rect2(p.x - 0.6, p.y - h, 1.2, h), Color(0.75, 0.72, 0.62) * 0.6, 0.0)
		var r := rng.randf_range(1.6, 3.0)
		var cap := PackedVector2Array()
		for s in 6:
			var a := PI + PI * s / 5.0
			mb.tri(Vector2(p.x, p.y - h), Vector2(p.x, p.y - h) + Vector2(cos(a), sin(a)) * r, Vector2(p.x, p.y - h) + Vector2(cos(a + PI / 5.0), sin(a + PI / 5.0)) * r, gc, gc, gc, 0.0, 0.0, 0.0, 1.0)


func _strand(mb: MB, top: Vector2, reg: int, x: int, y: int) -> void:
	var room := 0
	while room < 6 and not world.is_solid(x, y + 1 + room):
		room += 1
	var length := rng.randf_range(6.0, minf(10.0 + room * 7.0, 46.0))
	var c: Color = Palette.MOSS[reg].darkened(0.35)
	if reg == World.R_CANOPY:
		c = Color(0.3, 0.25, 0.17)
	var pts := PackedVector2Array()
	var seg := 6
	for k in seg + 1:
		var t := float(k) / seg
		pts.append(top + Vector2(sin(t * 3.0 + x) * 1.5, length * t))
	mb.polyline(pts, 2.0, 0.7, c, c.lightened(0.1), 0.0, length / 25.0)
	if (reg == World.R_HOLLOWS or reg == World.R_SUNKEN) and rng.randf() < 0.25:
		var gc: Color = Palette.GLOW[reg]
		mb.circle(pts[seg] + Vector2(0, 1.5), 1.4, gc, length / 25.0, 1.0, 6)


func _flowers(mb: MB, base: Vector2, reg: int) -> void:
	var tones := [Color(0.95, 0.92, 0.85), Color(0.98, 0.82, 0.8), Color(0.98, 0.9, 0.6), Color(0.8, 0.82, 0.98)]
	var c: Color = tones[rng.randi_range(0, tones.size() - 1)]
	if reg == World.R_CANOPY and rng.randf() < 0.5:
		c = Color(0.98, 0.9, 0.6)
	for k in rng.randi_range(1, 3):
		var p := base + Vector2(k * 3.0 - 3.0, 0)
		var h := rng.randf_range(4.0, 9.0)
		var top := p + Vector2(rng.randf_range(-1.5, 1.5), -h)
		var stem: Color = Palette.MOSS[reg].darkened(0.3)
		mb.line(p, top, 0.8, 0.6, stem, stem, 0.0, h / 12.0)
		var r := rng.randf_range(1.2, 1.9)
		for petal in 5:
			var a := TAU * petal / 5.0 + rng.randf()
			mb.circle(top + Vector2(cos(a), sin(a)) * r, r * 0.75, c, h / 12.0, 0.0, 5)
		mb.circle(top, r * 0.5, Color(0.95, 0.75, 0.3), h / 12.0, 0.0, 5)