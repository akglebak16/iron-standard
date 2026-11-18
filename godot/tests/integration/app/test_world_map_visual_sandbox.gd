extends SceneTree
const Region = preload("res://apps/godot/presentation/campaign/sandbox/WorldMapVisualSandbox.tscn")
func _initialize() -> void:
	call_deferred("_check")
func _check() -> void:
	var region := Region.instantiate()
	root.add_child(region)
	await process_frame
	var road: Curve2D = region.route
	assert(road.get_baked_length() > 900)
	assert(road.sample_baked(0).distance_to(region.get_node("Landmarks/Belmont").position) < 0.01)
	assert(road.sample_baked(road.get_baked_length()).distance_to(region.get_node("Landmarks/Ventum").position) < 0.01)
	var army: Sprite2D = region.get_node("Traffic/Army")
	var caravan: Sprite2D = region.get_node("Traffic/Caravan")
	assert(army.texture != null and caravan.texture != null)
	var start := army.position
	var cart_start := caravan.position
	region._process(1.0)
	assert(start.distance_to(army.position) > 10 and cart_start.distance_to(caravan.position) > 5)
	assert(road.get_closest_point(army.position).distance_to(army.position) < 0.1)
	region._toggle()
	start = army.position
	region._process(1.0)
	assert(start == army.position)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(arg.trim_prefix("--capture=")) == OK)
	print("World map visual sandbox tests passed")
	quit()
