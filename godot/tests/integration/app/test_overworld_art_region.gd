extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://apps/godot/presentation/overworld/art_region.tscn").instantiate() as Node2D
	root.add_child(scene)
	await process_frame
	var renderer := scene.get_node("WorldMap") as IronWorldMapRenderer
	for frame in 180:
		if not scene.get_node("Loading").visible:
			break
		await process_frame
	assert(not scene.get_node("Loading").visible)
	assert(scene.surface.get_shader_parameter("terrain") is ImageTexture)
	assert(scene.bridge_art.visible)
	scene.get_node("%Bridge").button_pressed = false
	assert(not scene.bridge_art.visible)
	scene.get_node("%Bridge").button_pressed = true
	assert(renderer.trial_status().bridge)
	scene.set_process(false)
	var initial_x: float = renderer.trial_status().company_x
	var day: Vector3 = scene.surface.get_shader_parameter("sunlight")
	scene.set_hour(22)
	assert(scene.ink.get_shader_parameter("night") > .9)
	assert(scene.surface.get_shader_parameter("sunlight") != day)
	assert(renderer.trial_status().company_x == initial_x)
	scene.set_hour(12)
	assert(scene.surface.get_shader_parameter("sunlight") == day)
	scene.free()
	print("Overworld art region tests passed")
	quit()
