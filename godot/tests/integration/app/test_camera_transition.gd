extends SceneTree
const Check = preload("res://tests/integration/app/camera_transition_check.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	var error := await Check.run(self, capture_dir)
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	print("Campaign battle camera transition tests passed")
	quit(0)
