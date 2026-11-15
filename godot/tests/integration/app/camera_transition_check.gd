extends RefCounted
## Shared by debug tests and exported release smoke; checks never rely on assert.
const WorldScene = preload("res://apps/godot/composition/world_demo.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")

static func run(tree: SceneTree, capture_dir: String = "") -> String:
	Options.seed_value = 4242
	Options.continue_game = false
	var original_size := tree.root.size
	var world = WorldScene.instantiate()
	tree.root.add_child(world)
	await tree.process_frame
	await tree.process_frame
	var error := "Campaign did not initialize"
	if world._ready_to_play:
		world.set_process(false)
		world.state.clock.paused = true
		error = await _check(tree, world, capture_dir)
	world.queue_free()
	await tree.process_frame
	# Audio stop/free commands are consumed by the mixer, not by process_frame.
	# Fast headless runs can otherwise quit before the final playback is released.
	await tree.create_timer(0.1).timeout
	tree.root.size = original_size
	return error

static func _check(tree: SceneTree, world: Node, capture_dir: String) -> String:
	for size in [Vector2i(1280, 720), Vector2i(2560, 1440)]:
		tree.root.size = size
		world.camera.position = Vector2(4000, 2800)
		world.camera.force_update_scroll()
		if tree.root.get_camera_2d() != world.camera:
			return "Campaign camera not current before battle"
		var opponent: Dictionary = world.state.roster.make_party("bandit", "bandit", "Camera test", world.state.player.x + 5, world.state.player.y, [{"type": "b1", "n": 19}])
		world._start_battle(opponent)
		var battle = world._battle
		if battle == null:
			return "Campaign battle did not initialize"
		battle.set_process(false)
		await tree.process_frame
		if tree.root.get_camera_2d() != battle.camera:
			return "Battle did not take ownership of the viewport camera"
		if world.camera.enabled or world.map_view.visible or world.hud.visible:
			return "Campaign presentation remains active during battle"
		var hero: Vector2 = battle.get_battle_snapshot().hero_position
		var screen: Vector2 = tree.root.canvas_transform * hero
		if not tree.root.get_visible_rect().has_point(screen):
			return "Hero outside viewport after campaign transition"
		if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := capture_dir.path_join("camera-transition-%dx%d.png" % [size.x, size.y])
			if tree.root.get_texture().get_image().save_png(path) != OK:
				return "Cannot save camera transition screenshot"
		var before: Transform2D = tree.root.canvas_transform
		var events: Array[Dictionary] = []
		battle.camera.advance(1.0, hero + Vector2(400, 0), false, Vector2(size) * 0.5, events)
		if tree.root.canvas_transform == before:
			return "Battle camera does not move the viewport"
		battle._request_retreat()
		for tick in 180:
			battle._process(1.0 / 60.0)
			if world._waiting_return: break
		if not world._waiting_return:
			return "Retreat did not complete the encounter"
		world._return_to_map()
		await tree.process_frame
		if tree.root.get_camera_2d() != world.camera or not world.camera.enabled:
			return "Campaign camera not restored after battle"
		if not world.map_view.visible or not world.hud.visible:
			return "Campaign presentation not restored"
	return ""
