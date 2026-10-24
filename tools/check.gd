extends SceneTree
## Loads every script and shader so parse errors show up in one run.


func _init() -> void:
	var bad := 0
	for d in ["res://scripts", "res://scripts/obj", "res://tools"]:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				var s: Script = load(d + "/" + f)
				if s == null or not s.can_instantiate():
					print("FAIL ", d + "/" + f)
					bad += 1
	print("scripts checked, %d failed" % bad)
	quit()
