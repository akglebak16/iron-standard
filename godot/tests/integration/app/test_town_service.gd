extends SceneTree
## «Служба» (town_window.gd, #214): the faction card with the relations, the oath with ✓/✗ requirements and a disabled
## «Присягнуть» that says why, the service card (pay, no-shows, leaving with a second click) and the balance of power
## with a row per living faction and its enemies' crests.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")

func _needs(window) -> Array:
	return window.body.find_child("OathCard", true, false).find_children("Need*", "Label", true, false).map(func(l): return l.text)

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var p = state.player
	var town: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.fac == "emp":
			town = s
			break
	p.liege = ""
	p.hero.lvl = 1
	p.rel["emp"] = 5.0
	var window := TownWindow.new()
	root.add_child(window)
	await process_frame
	window.open_for(state, town)
	window.current_tab = "oath"
	window.render()
	await process_frame
	assert((window.body.find_child("Relation", true, false) as Label).text.begins_with("Отношения: 5"))
	var needs := _needs(window)
	assert(needs[0].begins_with("✗") and needs[1].begins_with("✗"), "level and relations not met: %s" % [needs])
	var swear := window.body.find_child("Swear", true, false) as Button
	assert(swear.disabled and swear.tooltip_text == state.clans.oath_why("emp"), swear.tooltip_text)
	p.hero.lvl = 5
	p.rel["emp"] = 40.0
	window.render()
	needs = _needs(window)
	assert(needs[0].begins_with("✓") and needs[1].begins_with("✓"), "%s" % [needs])
	# serving: pay, no-shows, and leaving needs a second click
	if not state.wars.wars.is_empty():
		(window.body.find_child("Swear", true, false) as Button).pressed.emit()
		assert(p.liege == "emp", "the oath is sworn")
	else:
		p.liege = "emp"
		window.render()
	assert(window.body.find_child("ServiceCard", true, false) != null and window.body.find_child("OathCard", true, false) == null)
	p.strikes = 2
	window.render()
	assert((window.body.find_child("Strikes", true, false) as Label).text.contains("2 из 3"))
	var leave := window.body.find_child("Leave", true, false) as Button
	leave.pressed.emit()
	assert(p.liege == "emp", "the first click only asks")
	leave = window.body.find_child("Leave", true, false) as Button
	assert(leave.text.begins_with("Точно уйти"))
	leave.pressed.emit()
	assert(p.liege == "", "the second click leaves the service")
	# the balance of power: a row per living faction, enemies as in the war table
	for x in state.wars.factions_alive():
		assert(window.body.find_child("Power_" + x, true, false) != null, "row for %s" % x)
		var foes := window.body.find_child("Foes_" + x, true, false)
		var expected := 0
		for k in state.wars.wars:
			if x in String(k).split("|"):
				expected += 1
		assert(foes.find_children("Foe_*", "", true, false).size() == expected, "enemies of %s" % x)
	# 1280×720: inside the window
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	for b in window.body.find_children("*", "Button", true, false):
		assert((b as Control).get_global_rect().end.x <= panel.end.x)
	window.free()
	print("Town service tests passed")
	quit()
