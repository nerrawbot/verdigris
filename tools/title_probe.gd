extends SceneTree
## Starts the game like a player would, presses a key on the title, reports what happened.
## tools\godot.cmd --script res://tools/title_probe.gd


func _init() -> void:
	var scene: PackedScene = load("res://scenes/game.tscn")
	var game := scene.instantiate()
	root.add_child(game)
	for k in 40:
		await process_frame
	print("before: started=%s title_a=%.2f fade_a=%.2f frozen=%s" % [game.started, game.hud.title_box.modulate.a, game.hud.fade.color.a, game.player.frozen])
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_D
	ev.keycode = KEY_D
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	for k in 150:
		await process_frame
	print("after: started=%s title_a=%.2f fade_a=%.2f frozen=%s focus=%s" % [game.started, game.hud.title_box.modulate.a, game.hud.fade.color.a, game.player.frozen, str(root.gui_get_focus_owner())])
	root.get_viewport().get_texture().get_image().save_png("res://shots/probe_title.png")
	quit()
