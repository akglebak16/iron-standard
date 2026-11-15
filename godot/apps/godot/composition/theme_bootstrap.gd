extends Node
## The project theme starts without imported dependencies, so a clean editor import
## can finish before loading fonts/textures. Runtime (including script tests) installs
## the original theme before any game scene creates controls.
func _enter_tree() -> void:
	ThemeDB.get_project_theme().merge_with(load("res://apps/godot/visuals/game_theme.tres"))
