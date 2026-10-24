extends Node
## One spring per 8 px column of the world. Splashes push the springs; the
## heights go to the water shader as a 1-row float texture.

const World = preload("res://scripts/world.gd")

var cols := 0
var h := PackedFloat32Array()
var v := PackedFloat32Array()
var surf := PackedInt32Array()   # surface row of each column's top water body (-1 none)
var img: Image
var tex: ImageTexture
var world: World
var rain := 0.0
var rng := RandomNumberGenerator.new()


func setup(w: World) -> void:
	world = w
	cols = w.w * 2
	h.resize(cols)
	v.resize(cols)
	surf.resize(cols)
	for c in cols:
		var x := c / 2
		surf[c] = -1
		for y in w.h:
			if w.has_flag(x, y, World.F_WATER):
				surf[c] = y
				break
	img = Image.create(cols, 1, false, Image.FORMAT_RF)
	tex = ImageTexture.create_from_image(img)


func splash(x_px: float, force: float, width := 3) -> void:
	var c := int(x_px / 8.0)
	for k in range(-width, width + 1):
		var cc := c + k
		if cc >= 0 and cc < cols:
			v[cc] += force * (1.0 - absf(k) / (width + 1.0))


func surface_at(x_px: float) -> int:
	var c := clampi(int(x_px / 8.0), 0, cols - 1)
	return surf[c]


func _physics_process(dt: float) -> void:
	if cols == 0:
		return
	var k := 60.0
	var damp := 2.2
	for i in cols:
		v[i] += (-k * h[i] - damp * v[i]) * dt
	for pass_i in 2:
		for i in range(1, cols - 1):
			if surf[i] < 0:
				continue
			if surf[i - 1] == surf[i]:
				var d := (h[i - 1] - h[i]) * 9.0 * dt
				v[i] += d * 6.0
				v[i - 1] -= d * 6.0
	if rain > 0.05:
		for n in int(rain * 6.0):
			var c := rng.randi_range(0, cols - 1)
			if surf[c] >= 0 and world.sky[surf[c] * world.w + c / 2] > 0:
				v[c] += rng.randf_range(-12.0, 12.0) * rain
	for i in cols:
		h[i] += v[i] * dt
		h[i] = clampf(h[i], -10.0, 10.0)
		img.set_pixel(i, 0, Color(h[i], 0, 0))
	tex.update(img)
