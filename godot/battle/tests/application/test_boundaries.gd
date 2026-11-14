extends SceneTree
## Keep the feature boundary enforceable as more screens and rules are added.
const ROOT := "res://battle/"

func _initialize() -> void:
	_check_scripts("presentation", ["battle/model/", "battle/rules/", "battle/data/", "FileAccess", "RandomNumberGenerator"])
	_check_scripts("model", ["battle/application/", "battle/presentation/", "battle/data/", "FileAccess", "Input.", "get_tree("])
	_check_scripts("rules", ["battle/application/", "battle/presentation/", "battle/data/", "FileAccess", "Input.", "get_tree("])
	_check_scripts("application", ["battle/presentation/", "FileAccess", "Input.", "get_tree("])
	print("Architecture boundary tests passed")
	quit(0)

func _check_scripts(role: String, forbidden: Array) -> void:
	var path := ROOT + role
	for filename in DirAccess.get_files_at(path):
		if not filename.ends_with(".gd"):
			continue
		var source := FileAccess.get_file_as_string(path + "/" + filename)
		for dependency in forbidden:
			assert(not source.contains(dependency), path + "/" + filename + " must not depend on " + dependency)
	for child in DirAccess.get_directories_at(path):
		_check_scripts(role + "/" + child, forbidden)
