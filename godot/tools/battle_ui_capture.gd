extends SceneTree
## Capture the actual native battle and menu at a chosen viewport/biome, without stepping simulation.
## --out= --size=1366x768 --biome=grass [--menu]
const MainScene = preload("res://app/main.tscn")
var _out := "user://battle.png"
var _size := Vector2i(1366, 768)
var _biome := "grass"
var _menu := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.substr(6)
		elif arg.begins_with("--size="):
			var dims := arg.substr(7).split("x")
			_size = Vector2i(int(dims[0]), int(dims[1]))
		elif arg.begins_with("--biome="): _biome = arg.substr(8)
		elif arg == "--menu": _menu = true
	call_deferred("_capture")

func _capture() -> void:
	root.size = _size
	var scene := MainScene.instantiate()
	scene.battle_setup = scene.battle_setup.duplicate(true)
	scene.battle_setup.biome = _biome
	root.add_child(scene)
	var view = scene.get_node("Battle")
	view.frame_driven = false
	view._audio.enabled = false
	view._music.enabled = false
	if _menu: view._controls._menu.pressed.emit()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out)
	scene.free()
	for i in 3: await process_frame
	quit()
