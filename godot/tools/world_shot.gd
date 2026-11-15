extends SceneTree
## One screenshot of the world demo: godot --path godot --script res://tools/world_shot.gd -- --out=/tmp/w.png [--frames=60] [--seed=N] [--focus=x,y,zoom]
var _frames := 90
var _out := "user://world.png"
var _n := 0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	root.add_child((load("res://app/world_demo.tscn") as PackedScene).instantiate())
func _process(_d: float) -> bool:
	_n += 1
	if _n >= _frames:
		root.get_texture().get_image().save_png(_out)
		quit()
		return true
	return false
