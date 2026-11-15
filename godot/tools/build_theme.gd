extends SceneTree
func _initialize() -> void:
	var theme = preload("res://apps/godot/visuals/game_theme.gd").build()
	assert(ResourceSaver.save(theme, "res://apps/godot/visuals/game_theme.tres") == OK)
	quit()
