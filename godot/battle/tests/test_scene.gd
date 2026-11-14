extends SceneTree

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var packed: PackedScene = load("res://app/main.tscn")
	assert(packed != null)
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var view = scene.get_node("Battle")
	assert(view.battle.units.size() > 0)
	assert(view.hero != null)
	assert(view.outcome == "")
	print("Scene tests passed")
	quit(0)
