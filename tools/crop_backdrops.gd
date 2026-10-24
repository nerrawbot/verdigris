extends SceneTree
## Crops the empty sky off the Blender backdrop renders (run after art_src/backdrops.py).


func _init() -> void:
	for n in ["far", "mid", "near"]:
		var path := ProjectSettings.globalize_path("res://assets/backdrop/%s.png" % n)
		var img := Image.load_from_file(path)
		if img == null:
			continue
		var used := img.get_used_rect()
		var top := maxi(used.position.y - 8, 0)
		var out := img.get_region(Rect2i(0, top, img.get_width(), img.get_height() - top))
		out.save_png(path)
		print("%s: %dx%d -> %dx%d" % [n, img.get_width(), img.get_height(), out.get_width(), out.get_height()])
	quit()
