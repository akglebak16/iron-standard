extends SceneTree
## Render a real screen, without changing player saves. --scene= --out= [--create]
var _out := "user://preview.png"
var _frames := 0
var _create := false
var _scene: Node
func _initialize() -> void:
	var path := "res://apps/godot/composition/main_menu.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="): path = arg.substr(8)
		elif arg.begins_with("--out="): _out = arg.substr(6)
		elif arg == "--create": _create = true
	_scene = (load(path) as PackedScene).instantiate()
	root.add_child(_scene)
func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 10 and _create:
		_scene._create()
	if _frames >= 60:
		root.get_texture().get_image().save_png(_out)
		quit()
	return false
