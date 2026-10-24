extends RefCounted
## Runtime world: tile data, collision queries and the textures the terrain shaders sample.

const TILE := 16.0
const SUN_SLOPE := 0.45                       # sun rays move this many cells right per cell down
const SUN_RES := 4                            # sun map cells per tile
const SUN_DIR := Vector2(0.41, 0.912)         # normalised direction the light travels

const AIR := 0
const ROCK := 1
const CONC := 2
const METAL := 3

const F_POLE_V := 1
const F_POLE_H := 2
const F_VINE := 4
const F_DRAFT := 8
const F_GRATE := 16
const F_WATER := 32

const R_HOLLOWS := 0
const R_PIPEWORKS := 1
const R_CANOPY := 2
const R_SUNKEN := 3
const R_SPIRE := 4
const REGION_NAMES := ["The Hollows", "The Pipeworks", "The Canopy", "The Sunken Galleries", "The Spire"]
const REGION_SUBS := [
	"moss remembers the shape of everything",
	"the old pumps still breathe, a little",
	"roots have been patient longer than stone",
	"the water keeps what the works let go",
	"from up here the ruin looks almost whole",
]

var w := 0
var h := 0
var solid: PackedByteArray
var back: PackedByteArray
var flags: PackedByteArray
var region: PackedByteArray
var depth: PackedByteArray
var air_dist: PackedByteArray
var water_depth: PackedByteArray
var moss: PackedByteArray
var sky: PackedByteArray
var sun: PackedByteArray
var start := Vector2i()
var objects: Array = []
var vine_claims := PackedByteArray()
var platforms: Array = []   # nodes with platform_rect() -> Rect2

var tex_a: ImageTexture
var tex_b: ImageTexture
var tex_c: ImageTexture
var tex_sun: ImageTexture
var reg_a: ImageTexture
var reg_b: ImageTexture


func load_data(d: Resource) -> void:
	w = d.w
	h = d.h
	solid = d.solid
	back = d.back
	flags = d.flags.duplicate()
	region = d.region
	depth = d.depth
	air_dist = d.air_dist
	water_depth = d.water_depth
	moss = d.moss
	sky = d.sky
	sun = d.sun
	start = d.start
	objects = d.objects
	vine_claims.resize(w * h)
	vine_claims.fill(0)


func size_px() -> Vector2:
	return Vector2(w, h) * TILE


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func mat(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return CONC
	return solid[y * w + x]


func is_solid(x: int, y: int) -> bool:
	return mat(x, y) != AIR


func flag(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	return flags[y * w + x]


func has_flag(x: int, y: int, f: int) -> bool:
	return (flag(x, y) & f) != 0


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func solid_px(p: Vector2) -> bool:
	return is_solid(floori(p.x / TILE), floori(p.y / TILE))


func flag_px(p: Vector2, f: int) -> bool:
	return has_flag(floori(p.x / TILE), floori(p.y / TILE), f)


func water_px(p: Vector2) -> bool:
	return flag_px(p, F_WATER)


func region_px(p: Vector2) -> int:
	var t := tile_of(p)
	if not inb(t.x, t.y):
		return R_HOLLOWS
	return region[t.y * w + t.x]


func sky_px(p: Vector2) -> float:
	var t := tile_of(p)
	if not inb(t.x, t.y):
		return 0.0
	return sky[t.y * w + t.x] / 255.0


func climbable_px(p: Vector2) -> bool:
	return mat(floori(p.x / TILE), floori(p.y / TILE)) == ROCK


## Water surface y (px) of the column at p, or INF when p is not in water.
func water_surface_y(p: Vector2) -> float:
	var t := tile_of(p)
	if not has_flag(t.x, t.y, F_WATER):
		return INF
	var y := t.y
	while y > 0 and has_flag(t.x, y - 1, F_WATER):
		y -= 1
	return y * TILE


func set_vine(x: int, y: int, on: bool) -> void:
	if not inb(x, y):
		return
	var i := y * w + x
	if on:
		vine_claims[i] = mini(vine_claims[i] + 1, 255)
		flags[i] |= F_VINE
	else:
		vine_claims[i] = maxi(vine_claims[i] - 1, 0)
		if vine_claims[i] == 0:
			flags[i] &= ~F_VINE


func box_solid(pos: Vector2, half: Vector2) -> bool:
	var x0 := floori((pos.x - half.x) / TILE)
	var x1 := floori((pos.x + half.x) / TILE)
	var y0 := floori((pos.y - half.y) / TILE)
	var y1 := floori((pos.y + half.y) / TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid(x, y):
				return true
	return false


## Moves an axis-aligned box through the grid. Grates, horizontal poles and
## platforms (creature backs) only stop downward motion from above.
## Returns {pos, hit_x (-1/0/1), hit_y (1 landed, -1 ceiling), carrier}.
func move_box(pos: Vector2, half: Vector2, motion: Vector2, drop := false) -> Dictionary:
	var hit_x := 0
	var hit_y := 0
	var carrier: Object = null
	var steps := maxi(1, ceili(maxf(absf(motion.x), absf(motion.y)) / 5.0))
	var step := motion / float(steps)
	for s in steps:
		if step.x != 0.0:
			pos.x += step.x
			if box_solid(pos, half):
				if step.x > 0.0:
					pos.x = floorf((pos.x + half.x) / TILE) * TILE - half.x - 0.01
					hit_x = 1
				else:
					pos.x = (floorf((pos.x - half.x) / TILE) + 1.0) * TILE + half.x + 0.01
					hit_x = -1
				step.x = 0.0
		if step.y != 0.0:
			var prev_bottom := pos.y + half.y
			pos.y += step.y
			if box_solid(pos, half):
				if step.y > 0.0:
					pos.y = floorf((pos.y + half.y) / TILE) * TILE - half.y - 0.01
					hit_y = 1
				else:
					pos.y = (floorf((pos.y - half.y) / TILE) + 1.0) * TILE + half.y + 0.01
					hit_y = -1
				step.y = 0.0
			elif step.y > 0.0 and not drop:
				var res := _platform_hit(pos, half, prev_bottom)
				if res.size() > 0:
					pos.y = float(res[0]) - half.y - 0.01
					hit_y = 1
					carrier = res[1]
					step.y = 0.0
	return {"pos": pos, "hit_x": hit_x, "hit_y": hit_y, "carrier": carrier}


func _platform_hit(pos: Vector2, half: Vector2, prev_bottom: float) -> Array:
	var bottom := pos.y + half.y
	var x0 := floori((pos.x - half.x + 1.0) / TILE)
	var x1 := floori((pos.x + half.x - 1.0) / TILE)
	var r0 := floori(prev_bottom / TILE) - 1
	var r1 := floori(bottom / TILE)
	for ry in range(r0, r1 + 1):
		for x in range(x0, x1 + 1):
			var f := flag(x, ry)
			if f & F_GRATE:
				var line := ry * TILE
				if prev_bottom <= line + 0.5 and bottom >= line:
					return [line, null]
			if f & F_POLE_H:
				var pl := ry * TILE + TILE * 0.5
				if prev_bottom <= pl + 0.5 and bottom >= pl:
					return [pl, null]
	for p in platforms:
		if not is_instance_valid(p):
			continue
		var r: Rect2 = p.platform_rect()
		if pos.x + half.x < r.position.x or pos.x - half.x > r.end.x:
			continue
		var top := r.position.y
		if prev_bottom <= top + 2.0 and bottom >= top:
			return [top, p]
	return []


## True when the box is resting on something (solid, grate, pole or platform).
func on_floor(pos: Vector2, half: Vector2) -> bool:
	var r: Dictionary = move_box(pos, half, Vector2(0, 1.5))
	return int(r["hit_y"]) == 1


func build_textures() -> void:
	var n := w * h
	var a := PackedByteArray()
	var b := PackedByteArray()
	var c := PackedByteArray()
	a.resize(n * 4)
	b.resize(n * 4)
	c.resize(n * 4)
	for i in n:
		var m := solid[i]
		var o := i * 4
		a[o] = 255 if m == ROCK else 0
		a[o + 1] = 255 if (m == CONC or m == METAL) else 0
		a[o + 2] = [0, 128, 255][back[i]]
		a[o + 3] = moss[i]
		b[o] = mini(depth[i] * 32, 255)
		b[o + 1] = mini(air_dist[i] * 36, 255)
		b[o + 2] = mini(water_depth[i] * 20, 255) if water_depth[i] > 0 else 0
		if m != AIR:
			# solids beside water take its depth, so the field only falls off at the surface
			var best := 0
			for d in [-1, 1, -w, w]:
				var j: int = i + d
				if j >= 0 and j < n and water_depth[j] > 0:
					best = maxi(best, water_depth[j])
			if best > 0:
				b[o + 2] = mini(best * 20, 255)
		b[o + 3] = sky[i]
		c[o] = 255 if m == METAL else 0
		c[o + 1] = 255 if (flags[i] & F_GRATE) else 0
		c[o + 2] = region[i] * 50
		c[o + 3] = 255 if (flags[i] & F_WATER) or (m != AIR and b[o + 2] > 0) else 0
	tex_a = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, a))
	tex_b = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, b))
	tex_c = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, c))
	tex_sun = ImageTexture.create_from_image(Image.create_from_data(w * SUN_RES, h * SUN_RES, false, Image.FORMAT_L8, sun))
	_build_region_weights()


func _build_region_weights() -> void:
	# Low-res, blurred region weights so palettes blend over ~20 tiles.
	var s := 4
	var lw := w / s
	var lh := h / s
	var wts: Array = []
	for k in 5:
		var arr := PackedFloat32Array()
		arr.resize(lw * lh)
		wts.append(arr)
	for ly in lh:
		for lx in lw:
			var counts := [0, 0, 0, 0, 0]
			for dy in s:
				for dx in s:
					counts[region[(ly * s + dy) * w + lx * s + dx]] += 1
			for k in 5:
				wts[k][ly * lw + lx] = counts[k] / float(s * s)
	for p in 3:
		for k in 5:
			var src: PackedFloat32Array = wts[k]
			var dst := PackedFloat32Array()
			dst.resize(lw * lh)
			for ly in lh:
				for lx in lw:
					var sum := 0.0
					var cnt := 0
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var xx := lx + dx
							var yy := ly + dy
							if xx >= 0 and yy >= 0 and xx < lw and yy < lh:
								sum += src[yy * lw + xx]
								cnt += 1
					dst[ly * lw + lx] = sum / cnt
			wts[k] = dst
	var ia := PackedByteArray()
	var ib := PackedByteArray()
	ia.resize(lw * lh * 4)
	ib.resize(lw * lh * 4)
	for i in lw * lh:
		for k in 4:
			ia[i * 4 + k] = int(clampf(wts[k][i], 0.0, 1.0) * 255.0)
		ib[i * 4] = int(clampf(wts[4][i], 0.0, 1.0) * 255.0)
		ib[i * 4 + 3] = 255
	reg_a = ImageTexture.create_from_image(Image.create_from_data(lw, lh, false, Image.FORMAT_RGBA8, ia))
	reg_b = ImageTexture.create_from_image(Image.create_from_data(lw, lh, false, Image.FORMAT_RGBA8, ib))
