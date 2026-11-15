extends SceneTree
const Game = preload("res://app/game.tscn")
const Options = preload("res://app/game_options.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	Options.seed_value = 4242
	Options.continue_game = false
	var game := Game.instantiate()
	root.add_child(game)
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
