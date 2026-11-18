extends SceneTree
## «Таверна» (town_window.gd, #212): a card per wandering companion with portrait, story, skill, attributes and price;
## «Нанять» takes the gold and the companion, a disabled button says why; an empty tavern shows its card; the rumour
## marks the wanderer's town on the map.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")

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
	var comps = state.companions
	comps.ensure(p)
	for id in comps.pos.keys():
		if comps.pos[id] == town.id:
			comps.pos[id] = -1
	comps.pos["ingrid"] = town.id
	comps.pos["geoffroi"] = town.id
	var ingrid: Dictionary = state.companion_catalog.get_companion("ingrid")
	var knight: Dictionary = state.companion_catalog.get_companion("geoffroi")
	p.gold = int(ingrid.price) + 10
	var window := TownWindow.new()
	root.add_child(window)
	await process_frame
	var marks: Array = []
	window.map_target.connect(func(x: float, y: float): marks.append(Vector2(x, y)))
	window.open_for(state, town)
	window.current_tab = "tavern"
	window.render()
	await process_frame
	var card: Node = window.body.find_child("Companion_ingrid", true, false)
	assert(card != null and window.body.find_child("Companion_geoffroi", true, false) != null, "a card per companion in the tavern")
	assert(card.find_child("Portrait", true, false) is TextureRect and (card.find_child("Portrait", true, false) as TextureRect).texture != null)
	assert((card.find_child("Story", true, false) as Label).text.contains(String(ingrid.story).left(20)))
	assert(card.find_child("Skill", true, false) != null and card.find_child("Attributes", true, false).get_child_count() >= 5)
	var too_dear := window.body.find_child("Hire_geoffroi", true, false) as Button
	assert(too_dear.disabled and too_dear.tooltip_text.contains("Не хватает %d золота" % (int(knight.price) - p.gold)), too_dear.tooltip_text)
	# hire: gold goes, the companion joins and leaves the tavern
	(window.body.find_child("Hire_ingrid", true, false) as Button).pressed.emit()
	assert(p.comps.size() == 1 and p.comps[0].id == "ingrid" and p.gold == 10)
	assert(window.sub_label.text.contains("нанят спутник: Ингрид"), window.sub_label.text)
	assert(window.body.find_child("Companion_ingrid", true, false) == null)
	# a full company: the button says so
	p.gold = 100000
	while p.comps.size() < comps.COMP_MAX:
		p.comps.append(comps.new_profile("halvdan"))
	window.render()
	var full := window.body.find_child("Hire_geoffroi", true, false) as Button
	assert(full.disabled and full.tooltip_text.begins_with("Отряд спутников полон"))
	# empty tavern: the card, and the rumour still points somewhere on the map
	comps.pos["geoffroi"] = -1
	window.render()
	assert(window.body.find_child("TavernEmpty", true, false) != null, "the empty tavern card")
	var rumor := window.body.find_child("RumorMap", true, false) as Button
	if rumor != null:
		rumor.pressed.emit()
		assert(marks.size() == 1 and not window.visible, "the rumour marks the town on the map and closes the window")
	# 1280×720: cards stay inside the window
	window.open_for(state, town)
	comps.pos["geoffroi"] = town.id
	window.current_tab = "tavern"
	window.render()
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	for b in window.body.find_children("Hire_*", "Button", true, false):
		assert((b as Control).get_global_rect().end.x <= panel.end.x)
	window.free()
	print("Tavern window tests passed")
	quit()
