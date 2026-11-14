extends SceneTree
## Keep the feature boundary enforceable as more screens and rules are added.
func _initialize() -> void:
	var external_layers := ["res://app/", "res://campaign/"]
	var scene_and_files := ["FileAccess", "Input.", "get_tree("]
	var catalogs := ["res://troops/data/", "res://equipment/data/", "res://characters/data/"]
	var adapters := ["res://battle/application/", "res://battle/presentation/", "res://battle/data/"]
	_check_tree("res://battle/presentation", external_layers + ["res://battle/model/", "res://battle/rules/", "res://battle/data/", "res://troops/", "res://equipment/", "res://characters/", "FileAccess", "RandomNumberGenerator"])
	_check_tree("res://battle/model", external_layers + adapters + catalogs + scene_and_files + ["res://equipment/rules/"])
	_check_tree("res://battle/rules", external_layers + adapters + catalogs + scene_and_files)
	_check_tree("res://battle/application", external_layers + scene_and_files + ["res://battle/presentation/"])
	_check_tree("res://battle/data", external_layers + scene_and_files + ["res://battle/application/", "res://battle/presentation/"])
	var campaign_forbidden := ["res://app/", "res://battle/"]
	_check_file("res://campaign/config.gd", campaign_forbidden)
	_check_tree("res://campaign/data", campaign_forbidden)
	_check_tree("res://campaign/rules", campaign_forbidden + scene_and_files)
	_check_tree("res://campaign/economy", campaign_forbidden + scene_and_files)
	# These legacy content identifiers belong to definitions and compatibility adapters.
	var legacy_content := ['"undead"', '"skel"', '"zombie"', "UNDEAD_FACTION", "undead_kind"]
	_check_tree("res://battle/model", legacy_content)
	_check_tree("res://battle/rules", legacy_content)
	_check_tree("res://battle/data", ["SHIELD_ARROW_BONUS.get"])
	var content_modules := ["res://equipment/", "res://troops/", "res://characters/"]
	for module in content_modules:
		var forbidden := external_layers + ["res://battle/"]
		for other in content_modules:
			if other != module:
				forbidden.append(other)
		_check_file(module + "config.gd", forbidden)
		_check_tree(module + "data", forbidden)
		if DirAccess.dir_exists_absolute(module + "rules"):
			_check_tree(module + "rules", forbidden + scene_and_files)
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
