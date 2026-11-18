extends SceneTree
## The settlement window (town_window.gd, #211): it is as tall as its tab (no empty space under a short one), a long tab
## stops at the screen edge and scrolls, the top stays put between tabs, and «Подождать здесь» sits in the bottom left
## corner next to «Покинуть …» on every tab.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var town: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.fac == "emp":
			town = s
			break
	var window := TownWindow.new()
	root.add_child(window)
	await process_frame
	var waited: Array = []
	window.wait_requested.connect(func(s): waited.append(s.id))
	town.recruits = [{"type": "e1", "n": 2}]
	window.open_for(state, town)
	root.size = Vector2i(1280, 720)
	await _frames(6)
	var panel: Rect2 = window._panel.get_global_rect()
	var top := panel.position.y
	assert(panel.size.y < 600, "a short tab gives a short window: %s" % panel)
	var scroll: ScrollContainer = window._scroll
	assert(absf(scroll.size.y - window.body.get_combined_minimum_size().y) < 2.0, "no empty space under the content")
	var wait := window.footer_left.find_child("Wait", true, false) as Button
	assert(wait != null and wait.text == "Подождать здесь")
	assert(window.body.find_child("Wait", true, false) == null, "the wait card left «Рекруты»")
	var at := wait.get_global_rect()
	var close := window.close_button.get_global_rect()
	assert(at.position.x - panel.position.x < 60 and absf(at.get_center().y - close.get_center().y) < 2.0, "bottom left, in line with «Покинуть»")
	assert(close.end.x <= panel.end.x and close.end.y <= root.size.y)
	# a long tab: the window stops at the screen and the body scrolls, the top does not move
	window.current_tab = "oath"
	window.render()
	await _frames(6)
	panel = window._panel.get_global_rect()
	assert(absf(panel.position.y - top) < 1.0, "the top stays put")
	assert(panel.end.y <= root.size.y, "never taller than the screen: %s" % panel)
	assert(window.body.get_combined_minimum_size().y > scroll.size.y, "the long tab scrolls")
	assert(window.close_button.get_global_rect().end.y <= root.size.y)
	assert(window.footer_left.find_child("Wait", true, false) != null, "the wait button is on every tab")
	wait.pressed.emit()
	assert(waited == [town.id] and not window.visible, "waiting closes the window")
	window.free()
	print("Town window layout tests passed")
	quit()
