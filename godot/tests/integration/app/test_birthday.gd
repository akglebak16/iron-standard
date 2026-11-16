extends SceneTree
const Menu = preload("res://apps/godot/composition/main_menu.tscn")
const Preferences = preload("res://apps/godot/composition/presentation_preferences.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	root.size = Vector2i(1366, 768)
	var prefs := Preferences.new("user://birthday-test.cfg")
	assert(prefs.save(true, true) == OK)
	var menu := Menu.instantiate()
	menu._preferences = prefs
	root.add_child(menu)
	for i in 5: await process_frame
	var birthday = menu.find_child("VikentyBirthday", true, false)
	assert(birthday != null and birthday._portrait != null)
	assert(birthday._friends.keys().size() == 2 and birthday._friends.has("glebio") and birthday._friends.has("zahariy"))
	assert("Викентий Де Будетон" in birthday._greeting.text)
	assert(birthday._song.playing and not birthday._song.stream_paused)
	assert(not menu._music.enabled and not menu._music.is_processing(), "ordinary menu music must not overlap the birthday melody")
	assert(birthday._song.stream.get_length() > 10)
	assert(birthday.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	# Real button input toggles the saved preference, including while the scene exists.
	_click(birthday._mute)
	assert(not prefs.read().music and birthday._song.stream_paused)
	_click(birthday._mute)
	assert(prefs.read().music and not birthday._song.stream_paused)
	assert(prefs.save(false, true) == OK)
	birthday._sync_music()
	assert(birthday._song.stream_paused, "global sound off must also silence the greeting")
	assert(prefs.save(true, true) == OK)
	birthday._sync_music()
	for dims in [Vector2i(1366,768), Vector2i(960,650), Vector2i(480,800)]:
		root.size = dims
		for i in 5: await process_frame
		for button in menu._menu.get_children():
			var rect: Rect2 = button.get_global_rect()
			assert(rect.position.x >= 0 and rect.position.y >= 0)
			assert(rect.end.x <= dims.x + 1 and rect.end.y <= dims.y + 1, "menu actions must remain reachable")
	_click(menu._menu.get_child(0))
	for i in 10: await process_frame
	assert(is_instance_valid(menu._dialog) and menu._dialog.visible, "confetti must not intercept New Game")
	var song: WeakRef = weakref(birthday._song)
	menu.queue_free()
	for i in 3: await process_frame
	assert(song.get_ref() == null, "leaving the menu must release the birthday player")
	print("Birthday tests passed")
	quit()

func _click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
