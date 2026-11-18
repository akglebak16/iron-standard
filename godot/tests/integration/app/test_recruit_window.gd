extends SceneTree
## «Рекруты» in a settlement (town_window.gd, #208): one compact table sorted by tier, «Нанять» / «×5» / «Всех» that
## respect stock, purse and room, disabled buttons that say why, and the time until new recruits from `rt`.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const Economy = preload("res://core/campaign/economy/party_economy.gd")

func _stack(list: Array, type: String) -> int:
	for s in list:
		if s.type == type:
			return int(s.n)
	return 0

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var town: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.fac == "emp":
			town = s
			break
	town.recruits = [{"type": "e1", "n": 8}, {"type": "e3c", "n": 1}, {"type": "e2a", "n": 2}]
	town.rt = 50
	p.troops = [{"type": "e1", "n": 10}]
	var e1: Dictionary = state.roster.catalog.get_troop("e1")
	var e3c: Dictionary = state.roster.catalog.get_troop("e3c")
	var cost := Economy.hire_cost(e1, fx)
	p.gold = cost * 7
	var window := TownWindow.new()
	root.add_child(window)
	await process_frame
	window.open_for(state, town)
	for i in 3: await process_frame
	var table: Node = window.body.find_child("RecruitTable", true, false)
	assert(table != null)
	var order: Array = table.find_child("Table", true, false).get_children().filter(func(c): return String(c.name).begins_with("Troop_")).map(func(c): return String(c.name).trim_prefix("Troop_"))
	assert(order == ["e3c", "e2a", "e1"], "higher tier first: %s" % [order])
	var summary: Node = window.body.find_child("RecruitSummary", true, false)
	assert(summary != null and summary.find_children("*", "Label", true, false).any(func(l): return l.text == "Новые люди через 22 ч"), "the next recruits come from rt")
	# too expensive: disabled and the hint says why
	p.gold = cost * 7
	var knight := window.body.find_child("Hire_e3c", true, false) as Button
	assert(knight.disabled == (p.gold < Economy.hire_cost(e3c, fx)) and knight.tooltip_text.contains("Не хватает золота"), knight.tooltip_text)
	# «Нанять» takes one, «×5» five, «Всех» the rest the purse allows
	(window.body.find_child("Hire_e1", true, false) as Button).pressed.emit()
	assert(_stack(p.troops, "e1") == 11 and _stack(town.recruits, "e1") == 7)
	assert(window.sub_label.text.contains("нанято: Рекрут ×1"), window.sub_label.text)
	(window.body.find_child("Hire5_e1", true, false) as Button).pressed.emit()
	assert(_stack(p.troops, "e1") == 16 and p.gold == cost)
	var all := window.body.find_child("HireAll_e1", true, false) as Button
	assert(not all.disabled and all.text == "Всех", "one more affordable: %s" % all.text)
	all.pressed.emit()
	assert(_stack(p.troops, "e1") == 17 and p.gold == 0)
	# a full party: buttons disabled, the hint names the limit
	p.gold = 10000
	p.troops = [{"type": "e1", "n": Economy.size_cap(p.hero, fx)}]
	window.render()
	var full := window.body.find_child("HireAll_e1", true, false) as Button
	assert(full.disabled and full.tooltip_text.begins_with("Отряд полон"), full.tooltip_text)
	# nobody left: the empty card with the time of the next recruits, waiting still works
	town.recruits = []
	window.render()
	assert(window.body.find_child("RecruitTable", true, false) == null and window.body.find_child("RecruitEmpty", true, false) != null)
	assert(window.body.find_child("Wait", true, false) != null)
	# 1280×720: the table stays inside the window
	town.recruits = [{"type": "e1", "n": 8}, {"type": "e3c", "n": 1}, {"type": "e2a", "n": 2}]
	p.troops = [{"type": "e1", "n": 10}]
	window.render()
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	for c in window.body.find_children("Actions_*", "", true, false):
		assert((c as Control).get_global_rect().end.x <= panel.end.x, "actions stay in the window: %s" % c.name)
	for c in window.body.find_children("Troop_*", "", true, false):
		assert((c as Control).size.y <= 52, "compact row: %s %s" % [c.name, (c as Control).size])
	window.free()
	print("Recruit window tests passed")
	quit()
