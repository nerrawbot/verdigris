extends SceneTree
## Generates the world and bakes it to res://assets/world/world.res.
## tools\godot.cmd --headless --script res://tools/gen_world.gd [-- seed=N]

const WorldGen = preload("res://scripts/worldgen.gd")
const World = preload("res://scripts/world.gd")


func _init() -> void:
	var seed_value := 1207
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_value = int(a.substr(5))
	var t0 := Time.get_ticks_msec()
	var gen := WorldGen.new()
	var data: Resource = gen.generate(seed_value)
	for line in gen.report:
		print(line)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/world"))
	var err := ResourceSaver.save(data, "res://assets/world/world.res")
	print("saved world.res (err %d) in %d ms, start %s" % [err, Time.get_ticks_msec() - t0, str(data.start)])
	_debug_png(data, gen)
	quit()


func _debug_png(d: Resource, gen: RefCounted) -> void:
	var img := Image.create(d.w, d.h, false, Image.FORMAT_RGB8)
	var reg_air := [Color(0.55, 0.62, 0.55), Color(0.62, 0.55, 0.45), Color(0.5, 0.68, 0.45), Color(0.45, 0.55, 0.65), Color(0.78, 0.78, 0.85)]
	for y in d.h:
		for x in d.w:
			var i: int = y * d.w + x
			var m: int = d.solid[i]
			var c := Color.BLACK
			if m == World.ROCK:
				c = Color(0.22, 0.2, 0.17)
			elif m == World.CONC:
				c = Color(0.32, 0.32, 0.34)
			elif m == World.METAL:
				c = Color(0.4, 0.25, 0.18)
			else:
				c = reg_air[d.region[i]]
				if d.back[i] == 0:
					c = c.lightened(0.35)
				var f: int = d.flags[i]
				if f & World.F_WATER:
					c = Color(0.2, 0.35, 0.6)
				if f & World.F_GRATE:
					c = Color(0.1, 0.1, 0.1)
				if f & World.F_POLE_V:
					c = Color(0.95, 0.85, 0.2)
				if f & World.F_POLE_H:
					c = Color(0.95, 0.6, 0.2)
				if f & World.F_DRAFT:
					c = c.lerp(Color.WHITE, 0.4)
				if not gen.strong(x, y):
					c = c.lerp(Color(1, 0, 0), 0.5)
			img.set_pixel(x, y, c)
	var cols := {"nest": Color(0.3, 1, 1), "lantern": Color(1, 1, 1), "plant": Color(0.2, 1, 0.3), "kite": Color(1, 0.4, 1), "trundler": Color(0.6, 0.3, 1), "glimmers": Color(0, 1, 1), "vent": Color(1, 1, 1)}
	for o in d.objects:
		var c: Color = cols.get(o["t"], Color.WHITE)
		var rr := 2 if o["t"] in ["lantern", "nest"] else 0
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var px: int = o["x"] + dx
				var py: int = o["y"] + dy
				if px >= 0 and py >= 0 and px < d.w and py < d.h:
					img.set_pixel(px, py, c)
	img.resize(d.w * 3, d.h * 3, Image.INTERPOLATE_NEAREST)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png("res://shots/world_map.png")
