extends SceneTree
## Keep the feature boundary enforceable as more screens and rules are added.
func _initialize() -> void:
	_check_tree("res://battle/presentation", ["battle/model/", "battle/rules/", "battle/data/", "troops/data/", "equipment/data/", "equipment/rules/", "FileAccess", "RandomNumberGenerator"])
	_check_tree("res://battle/model", ["battle/application/", "battle/presentation/", "battle/data/", "troops/data/", "equipment/data/", "equipment/rules/", "FileAccess", "Input.", "get_tree("])
	_check_tree("res://battle/rules", ["battle/application/", "battle/presentation/", "battle/data/", "troops/data/", "equipment/data/", "FileAccess", "Input.", "get_tree("])
	_check_tree("res://battle/application", ["battle/presentation/", "FileAccess", "Input.", "get_tree("])
	_check_tree("res://equipment/data", ["res://battle/", "res://troops/", "res://campaign/"])
	_check_tree("res://equipment/rules", ["res://battle/", "res://troops/", "res://campaign/", "FileAccess", "Input.", "get_tree("])
	_check_tree("res://troops/data", ["res://battle/", "res://equipment/", "res://campaign/"])
	_check_tree("res://characters/data", ["res://battle/", "res://equipment/", "res://troops/", "res://campaign/"])
	_check_tree("res://characters/rules", ["res://battle/", "res://equipment/", "res://troops/", "res://campaign/", "FileAccess", "Input.", "get_tree("])
	_check_file("res://equipment/config.gd", ["res://battle/", "res://troops/"])
	_check_file("res://troops/config.gd", ["res://battle/", "res://equipment/"])
	print("Architecture boundary tests passed")
	quit(0)

func _check_tree(path: String, forbidden: Array) -> void:
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".gd"):
			continue
		_check_file(path + "/" + filename, forbidden)
	for child in DirAccess.get_directories_at(path):
		_check_tree(path + "/" + child, forbidden)

func _check_file(path: String, forbidden: Array) -> void:
	var source := FileAccess.get_file_as_string(path)
	for dependency in forbidden:
		assert(not source.contains(dependency), path + " must not depend on " + dependency)
