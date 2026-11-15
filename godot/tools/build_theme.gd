extends SceneTree
func _initialize() -> void:
	var theme = preload("res://ui/game_theme.gd").build()
	assert(ResourceSaver.save(theme, "res://ui/game_theme.tres") == OK)
	quit()
