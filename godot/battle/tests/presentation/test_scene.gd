extends SceneTree
const Session = preload("res://battle/application/session.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var packed: PackedScene = load("res://app/main.tscn")
	assert(packed != null)
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var view = scene.get_node("Battle")
	var frame: Dictionary = view.get_battle_snapshot()
	assert(frame.units.size() == 52)
	assert(frame.counts == [26, 26])
	assert(frame.outcome == Session.Outcome.RUNNING)
	assert(view.get_node("Hud/Status").text.contains("Свои"))
	frame.units.clear()
	assert(view.get_battle_snapshot().units.size() == 52)
	await physics_frame
	await process_frame
	assert(view.get_battle_snapshot().tick > 0)
	assert(view.get_node("Camera").position == view.get_battle_snapshot().hero_position)
	print("Scene tests passed")
	quit(0)
