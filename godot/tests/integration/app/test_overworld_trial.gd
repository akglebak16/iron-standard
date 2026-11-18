extends SceneTree

const TRIAL := preload("res://apps/godot/presentation/overworld/overworld_trial.tscn")
const CROSSING := Rect2(800, 580, 950, 430)
const WEST := Rect2(160, 130, 450, 410)


func _initialize() -> void:
	call_deferred("_run")


func _settle(renderer: IronWorldMapRenderer, view: Rect2) -> void:
	for frame in 180:
		renderer.update_trial(view, 0)
		if not renderer.trial_status().busy:
			return
		await process_frame
	assert(false, "Chunk queue did not drain")


func _run() -> void:
	var scene := TRIAL.instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var renderer := scene.get_node("WorldMap") as IronWorldMapRenderer
	var bridge := scene.get_node("%Bridge") as CheckButton
	await _settle(renderer, CROSSING)
	for tick in 440:
		renderer.update_trial(CROSSING, 1.0 / 60)
	assert(is_equal_approx(renderer.trial_status().company_x, 1238.0), "A closed crossing blocks movement")

	var uploads := int(renderer.trial_status().uploaded)
	bridge.button_pressed = true
	await _settle(renderer, CROSSING)
	assert(int(renderer.trial_status().uploaded) - uploads == 2, "Only the two bridge chunks are rebuilt")
	for tick in 50:
		renderer.update_trial(CROSSING, 1.0 / 60)
	assert(renderer.trial_status().company_x > 1322, "The company should cross the deck")
	bridge.button_pressed = false
	await _settle(renderer, CROSSING)
	assert(not renderer.trial_status().bridge)

	var evictions := int(renderer.trial_status().evicted)
	await _settle(renderer, WEST)
	assert(renderer.trial_status().evicted > evictions)
	renderer.update_trial(CROSSING, 0)
	renderer.reload_trial()
	await _settle(renderer, CROSSING)
	assert(renderer.trial_status().discarded > 0, "A job from the previous world must be discarded")
	assert(is_equal_approx(renderer.trial_status().company_x, 600.0))
	scene.free()
	print("Overworld trial tests passed")
	quit()
