extends SceneTree
const WorldMotion = preload("res://apps/godot/presentation/campaign/world_motion.gd")
const WorldClock = preload("res://core/campaign/world/world_clock.gd")
const PauseMenu = preload("res://apps/godot/composition/pause_menu.gd")
const Preferences = preload("res://apps/godot/composition/presentation_preferences.gd")
const FpsOverlay = preload("res://apps/godot/composition/fps_overlay.gd")

func _initialize() -> void:
	# rpos: a figure slides between its previous and current step position
	var m := WorldMotion.new()
	assert(m.at(1, Vector2(100, 100)) == Vector2(100, 100), "First sight is drawn where it is")
	m.tick(0.016, true, 0.0, 1)
	assert(m.at(1, Vector2(110, 100)) == Vector2(100, 100), "Right after a step the figure is still at the old point")
	m.tick(WorldMotion.STEP_SECONDS * 0.5, true, 0.5, 1)
	assert(m.at(1, Vector2(110, 100)).is_equal_approx(Vector2(105, 100)), "Half a step drawn halfway")
	m.tick(0.016, false, 0.5, 1)
	m.tick(1.0, false, 0.5, 1)
	assert(m.alpha == 1.0 and m.at(1, Vector2(110, 100)) == Vector2(110, 100), "A stopped world settles on the last step")
	m.tick(0.016, true, 0.1, 1)
	assert(m.at(1, Vector2(400, 100)) == Vector2(400, 100), "A long jump is not slid across the map")
	# the clock reports how far the next step has come
	var clock := WorldClock.new()
	clock.advance(0.5 * WorldClock.STEP / 1.2, func(_dh): pass, func(): pass)
	assert(is_equal_approx(clock.step_fraction(), 0.5))
	# the FPS counter is off by default and switched in the pause menu
	var prefs := Preferences.new("user://test_fps_prefs.cfg")
	assert(not prefs.read_fps())
	if FpsOverlay.instance == null:
		root.add_child(FpsOverlay.new())
	await process_frame
	var overlay = FpsOverlay.instance
	overlay.visible = false
	var menu := PauseMenu.new()
	root.add_child(menu)
	await process_frame
	menu.open_menu(prefs)
	var toggle: Button = null
	for b in menu.body.find_children("", "Button", true, false):
		if b.text.begins_with("Счётчик FPS"):
			toggle = b
	assert(toggle != null and toggle.text == "Счётчик FPS: выключен")
	toggle.pressed.emit()
	assert(prefs.read_fps() and overlay.visible, "The switch shows the counter and remembers it")
	await process_frame
	await process_frame
	assert(overlay.text().begins_with("FPS "))
	for b in menu.body.find_children("", "Button", true, false):
		if b.text.begins_with("Счётчик FPS"):
			toggle = b
	assert(toggle.text == "Счётчик FPS: включён")
	toggle.pressed.emit()
	assert(not prefs.read_fps() and not overlay.visible)
	print("Map motion and FPS tests passed")
	quit(0)
