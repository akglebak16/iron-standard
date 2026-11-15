extends SceneTree
## Render a real screen, without changing player saves. --scene= --out= [--create]
var _out := "user://preview.png"
var _frames := 0
var _create := false
var _quick := false
var _layout_out := ""
var _scene: Node
func _initialize() -> void:
	var path := "res://apps/godot/composition/main_menu.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="): path = arg.substr(8)
		elif arg.begins_with("--out="): _out = arg.substr(6)
		elif arg == "--create": _create = true
		elif arg == "--quick": _quick = true
		elif arg.begins_with("--layout-out="): _layout_out = arg.substr(13)
		elif arg.begins_with("--banner="): preload("res://apps/godot/composition/game_options.gd").banner = int(arg.substr(9))
	_scene = (load(path) as PackedScene).instantiate()
	root.add_child(_scene)
func _process(_dt: float) -> bool:
	_frames += 1
	if _frames == 10 and _create:
		_scene._create()
	if _frames == 10 and _quick:
		_scene._quick()
	if _frames >= 60:
		root.get_texture().get_image().save_png(_out)
		if not _layout_out.is_empty(): _save_layout()
		quit()
	return false

func _save_layout() -> void:
	var d = _scene._dialog
	var column = d._panel.get_child(0)
	var controls := {"window": d._panel, "header":column.get_child(0), "body":d._scroll, "footer":column.get_child(column.get_child_count()-2)}
	if is_instance_valid(_scene._name): controls.input = _scene._name
	var values := {}
	for key in controls:
		var rect: Rect2 = controls[key].get_global_rect()
		values[key] = {"x":rect.position.x, "y":rect.position.y, "w":rect.size.x, "h":rect.size.y}
	FileAccess.open(_layout_out, FileAccess.WRITE).store_string(JSON.stringify(values, "  "))
