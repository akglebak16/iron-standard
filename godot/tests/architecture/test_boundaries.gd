extends SceneTree
## Keep the feature boundary enforceable as more screens and rules are added.
func _initialize() -> void:
	# The visual library has actual consumers in both campaign and battle, and owns no game rules.
	_check_tree("res://apps/godot/visuals", ["res://apps/godot/composition/", "res://core/campaign/", "res://core/battle/", "res://core/troops/", "res://core/equipment/", "res://core/characters/"])
	var external_layers := ["res://apps/godot/composition/", "res://core/campaign/"]
	var scene_and_files := ["FileAccess", "Input.", "get_tree("]
	var catalogs := ["res://core/troops/data/", "res://core/equipment/data/", "res://core/characters/data/"]
	var adapters := ["res://core/battle/application/", "res://apps/godot/presentation/battle/", "res://core/battle/data/"]
	# Presentation may create its own RNG for effects. Access to simulation internals stays forbidden.
	_check_tree("res://apps/godot/presentation/battle", external_layers + ["res://core/battle/model/", "res://core/battle/rules/", "res://core/battle/data/", "res://core/troops/", "res://core/equipment/", "res://core/characters/", "FileAccess", "._rng", "._state"])
	_check_tree("res://core/battle/model", external_layers + adapters + catalogs + scene_and_files + ["res://core/equipment/rules/"])
	_check_tree("res://core/battle/rules", external_layers + adapters + catalogs + scene_and_files)
	_check_tree("res://core/battle/application", external_layers + scene_and_files + ["res://apps/godot/presentation/battle/"])
	_check_tree("res://core/battle/data", external_layers + scene_and_files + ["res://core/battle/application/", "res://apps/godot/presentation/battle/"])
	var campaign_forbidden := ["res://apps/godot/composition/", "res://core/battle/"]
	_check_file("res://core/campaign/config.gd", campaign_forbidden)
	_check_tree("res://core/campaign/data", campaign_forbidden)
	_check_tree("res://core/campaign/rules", campaign_forbidden + scene_and_files)
	_check_tree("res://core/campaign/economy", campaign_forbidden + scene_and_files)
	# World generation is pure simulation: no scenes, no files, no input. Its picture lives in core/campaign/presentation.
	_check_tree("res://core/campaign/world", campaign_forbidden + scene_and_files)
	_check_tree("res://apps/godot/presentation/campaign", campaign_forbidden + ["FileAccess", "._rng"])
	# These legacy content identifiers belong to definitions and compatibility adapters.
	var legacy_content := ['"undead"', '"skel"', '"zombie"', "UNDEAD_FACTION", "undead_kind"]
	_check_tree("res://core/battle/model", legacy_content)
	_check_tree("res://core/battle/rules", legacy_content)
	_check_tree("res://core/battle/data", ["SHIELD_ARROW_BONUS.get"])
	var content_modules := ["res://core/equipment/", "res://core/troops/", "res://core/characters/"]
	for module in content_modules:
		var forbidden := external_layers + ["res://core/battle/"]
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
		# Scenes and resources are code too: a .tscn may not reach across a boundary either.
		if not (filename.ends_with(".gd") or filename.ends_with(".tscn") or filename.ends_with(".tres")):
			continue
		_check_file(path + "/" + filename, forbidden)
	for child in DirAccess.get_directories_at(path):
		_check_tree(path + "/" + child, forbidden)

func _check_file(path: String, forbidden: Array) -> void:
	var source := FileAccess.get_file_as_string(path)
	for dependency in forbidden:
		assert(not source.contains(dependency), path + " must not depend on " + dependency)
