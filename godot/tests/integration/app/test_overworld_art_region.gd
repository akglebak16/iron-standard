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
	var fields := {}
	var routes := {}
	var passes := {}
	for seed_value in [188,19,47,103,271]:
		var field := IronWorldMapRenderer.bake_region_terrain(seed_value, Vector3.ONE)
		assert(field.size() == 320*200*4)
		_check_habitat(field)
		var fingerprint := hash(field)
		assert(not fields.has(fingerprint))
		fields[fingerprint] = true
		renderer.set_region_profile(seed_value,Vector3.ONE)
		var status := renderer.trial_status()
		var alignment := Vector2(status.west_detour,status.east_detour)
		routes[alignment] = true
		passes[status.pass_x] = true
		renderer.reload_trial()
		var reloaded := renderer.trial_status()
		assert(reloaded.pass_x == status.pass_x and reloaded.west_detour == alignment.x and reloaded.east_detour == alignment.y)
		assert(field == IronWorldMapRenderer.bake_region_terrain(seed_value, Vector3.ONE))
	assert(routes.size() > 1 and passes.size() == 5)
	scene.free()
	print("Overworld art region tests passed")
	quit()

# Sample the land at 32 world-unit intervals, away from the narrow shoreline.
# Coverage catches empty/solid worlds; neighbour agreement catches scattered
# cells with the same coverage but no forest interiors.
func _check_habitat(field: PackedByteArray) -> void:
	var land := 0
	var woods := 0
	var neighbours := 0
	var basin_core := 0
	var min_height := 255
	var max_height := 0
	for y in range(4,196,4):
		for x in range(4,316,4):
			var i := (320*y+x)*4
			if field[i+2] < 138:
				continue
			land += 1
			min_height = mini(min_height,field[i])
			max_height = maxi(max_height,field[i])
			if field[i+1] > 150:
				woods += 1
				if x >= 50 and x <= 105 and y >= 26 and y <= 62:
					basin_core += 1
				for offset in [-16,16,-5120,5120]:
					if field[i+offset+1] > 150:
						neighbours += 1
	var coverage := float(woods)/maxi(land,1)
	assert(coverage > .06 and coverage < .65)
	assert(neighbours > woods*2)
	assert(basin_core >= 24)
	assert(max_height-min_height > 88)