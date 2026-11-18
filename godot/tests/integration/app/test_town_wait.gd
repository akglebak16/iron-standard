extends SceneTree
## «Подождать здесь» in a settlement (town_window.gd, footer), clicked with the mouse in the map scene with the world
## simulation thread (ADR-024): the window closes, the party stays waiting by the walls and time goes on. The button
## fires on release and closes its window, so the same release used to reach the map camera as a click on the map: the
## wait was cancelled at once and the party rode to the point under the button. A click on the map itself still moves.
const World = preload("res://apps/godot/composition/world_demo.tscn")

func _button(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var found := _button(c, text)
		if found != null:
			return found
	return null

func _click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		root.push_input(e)
		await process_frame

func _initialize() -> void:
	Engine.max_fps = 0
	var world = World.instantiate()
	world.sim_thread = true  # as in the game: the world steps on the worker thread
	root.add_child(world)
	while not world._ready_to_play:
		await process_frame
	assert(world._sim != null, "the scene runs the world on the simulation thread")
	var s = world.state
	var home: Dictionary = s.map.settlement_by_id(s.home_id)
	s.player.stop()
	s.player.x = home.x
	s.player.y = home.y + 20
	s.enter(home)
	for i in 3:
		await process_frame
	assert(world._town.visible, "entering the home town opens its window")
	assert(world.state.clock.paused, "the world stands while the window is open")
	var wait := _button(world._town.footer_left, "Подождать здесь")
	assert(wait != null, "«Подождать здесь» sits in the footer of the town window (#211)")
	# a window of a real size (headless is 64×64): the button is in the bottom left corner, no scrolling needed
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	var panel: Rect2 = world._town._panel.get_global_rect()
	var at := wait.get_global_rect()
	assert(at.position.x - panel.position.x < 60 and panel.end.y - at.end.y < 60, "bottom left corner: %s in %s" % [at, panel])
	await _click(wait.get_global_rect().get_center())
	assert(not world._town.visible, "waiting closes the window")
	assert(world.state.waiting and not world.state.player.has_route(), "the click on the button does not reach the map: the party waits")
	var hour0: int = world.state.hours_passed
	var frames := 0
	while world.state.hours_passed < hour0 + 2 and frames < 4000:
		frames += 1
		await process_frame
	assert(world.state.waiting, "the party is still waiting")
	assert(not world.state.clock.paused, "the clock runs")
	assert(world.state.hours_passed >= hour0 + 2, "time goes on while the party waits by the walls: %d frames, %d hours" % [frames, world.state.hours_passed - hour0])
	# a click on the map itself ends the wait and sets the party on its way
	await _click(Vector2(400, 300))
	assert(not world.state.waiting and world.state.player.has_route(), "a click on the map still moves the party")
	world.queue_free()
	await process_frame
	print("Town wait tests passed")
	quit(0)
