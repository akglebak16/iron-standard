extends SceneTree
const CommandGhost = preload("res://apps/godot/presentation/battle/hud/command_ghost.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	var groups := [
		{"kind": Config.GROUP_INFANTRY, "order": Config.ORDER_HOLD, "backing": false, "center": Vector2(500, 500), "direction": 0.0, "centroid": Vector2(300, 500)},
		{"kind": Config.GROUP_ARCHERS, "order": Config.ORDER_CHARGE, "backing": false, "center": Vector2(500, 600), "direction": 0.0, "centroid": Vector2(500, 600)},
		{"kind": Config.GROUP_CAVALRY, "order": Config.ORDER_HOLD, "backing": true, "center": Vector2(500, 700), "direction": 0.0, "centroid": Vector2(500, 700)},
	]
	# commandDraw: only selected groups that hold and are not backing off get a ghost
	assert(CommandGhost.ghosts(groups, Config.ALL_GROUPS).size() == 1)
	assert(CommandGhost.ghosts(groups, Config.GROUP_INFANTRY).size() == 1)
	assert(CommandGhost.ghosts(groups, Config.GROUP_ARCHERS).is_empty())
	assert(CommandGhost.ghosts(groups, Config.GROUP_CAVALRY).is_empty())
	print("Command ghost tests passed")
	quit(0)
