extends SceneTree
const Game = preload("res://apps/godot/composition/game.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	Options.seed_value = 4242
	Options.continue_game = false
	var game := Game.instantiate()
	root.add_child(game)
	for siege in [false, true]:
		game._mode.demo_requested.emit(siege)
		game._mode.demo_requested.emit(siege)
		for frame in 3: await process_frame
		assert(game.get_child_count() == 1 and game._mode.has_node("Battle"))
		var view = game._mode.get_node("Battle")
		var session_ref: WeakRef = weakref(view._session)
		assert(game._mode.battle_setup.siege == siege)
		view.set_menu_open(true)
		var tick: int = view._frame.tick
		for frame in 3: await process_frame
		assert(view._paused and view._frame.tick == tick)
		game._mode.title_requested.emit()
		view = null
		for frame in 3: await process_frame
		assert(game.get_child_count() == 1 and game._mode.has_signal("demo_requested"))
		assert(session_ref.get_ref() == null)
	game._mode.quick_battle_requested.emit({"me":"khan", "foe":"bandit", "size":50})
	game._mode.quick_battle_requested.emit({"me":"emp", "foe":"nord", "size":200})
	for frame in 3: await process_frame
	assert(game.get_child_count() == 1 and game._mode.has_node("Battle"))
	assert(game._mode.battle_setup.quick and game._mode.battle_setup.enemy_faction == "bandit")
	assert(game._mode.battle_setup.hero_profile.eq.horse == "horse_riding")
	game._mode.title_requested.emit()
	for frame in 3: await process_frame
	for iteration in 2:
		game._mode.campaign_requested.emit()
		# Duplicate requests within the same frame must not create a second context.
		game._mode.campaign_requested.emit()
		await process_frame
		await process_frame
		await process_frame
		assert(game.get_child_count() == 1 and game._mode._ready_to_play)
		var world_ref: WeakRef = weakref(game._mode.state)
		var wars_ref: WeakRef = weakref(game._mode.state.wars)
		game._mode.title_requested.emit()
		await process_frame
		await process_frame
		assert(game.get_child_count() == 1 and game._mode.has_signal("campaign_requested"))
		assert(world_ref.get_ref() == null and wars_ref.get_ref() == null)
	game.queue_free()
	await process_frame
	print("Mode lifecycle tests passed")
	quit(0)
