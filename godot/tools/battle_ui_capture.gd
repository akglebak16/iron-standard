extends SceneTree
## Capture the actual native battle and menu at a chosen viewport/biome, without stepping simulation.
## --out= --size=1366x768 --biome=grass [--menu]
const MainScene = preload("res://apps/godot/composition/main.tscn")
var _out := "user://battle.png"
var _size := Vector2i(1366, 768)
var _biome := ""
var _menu := false
var _attack := false
var _quick_options := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.substr(6)
		elif arg.begins_with("--size="):
			var dims := arg.substr(7).split("x")
			_size = Vector2i(int(dims[0]), int(dims[1]))
		elif arg.begins_with("--biome="): _biome = arg.substr(8)
		elif arg == "--menu": _menu = true
		elif arg == "--attack": _attack = true
		elif arg.begins_with("--banner="): preload("res://apps/godot/composition/game_options.gd").banner = int(arg.substr(9))
		elif arg.begins_with("--quick="):
			var fields := arg.substr(8).split(",")
			_quick_options = {"me":fields[0], "foe":fields[1], "size":int(fields[2])}
	call_deferred("_capture")

func _capture() -> void:
	root.size = _size
	var scene := MainScene.instantiate()
	if not _quick_options.is_empty(): scene.battle_setup = preload("res://apps/godot/composition/quick_battle_setup.gd").build(_quick_options, 4017)
	scene.battle_setup = scene.battle_setup.duplicate(true)
	if not _biome.is_empty(): scene.battle_setup.biome = _biome
	root.add_child(scene)
	var view = scene.get_node("Battle")
	view.set_process(false)
	view._audio.enabled = false
	view._music.enabled = false
	if _attack:
		var input := preload("res://core/battle/application/hero_input.gd").new()
		input.attack = true
		input.face = 0.3
		view._session.set_hero_input(input)
		for i in 5: view._session.advance(1.0 / 60.0)
		view._post_step(5.0 / 60.0, view._session.take_events(), 5.0 / 60.0)
	if _menu: view._controls._menu.pressed.emit()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out)
	scene.free()
	for i in 3: await process_frame
	quit()
