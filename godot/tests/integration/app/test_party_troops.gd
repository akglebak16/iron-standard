extends SceneTree
## «Отряд» (party_window.gd, #207): troops ready for promotion always come first, then those short of gold, then the
## highest tier; one click promotes one man (or all the purse allows in «всех»), and rows stay compact at 1280×720.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const Economy = preload("res://core/campaign/economy/party_economy.gd")

func _rows(window, group: String) -> Array:
	var card: Node = window.body.find_child("TroopGroup_" + group, true, false)
	if card == null:
		return []
	var ids: Array = []
	for c in card.find_child("Table", true, false).get_children():
		if c.name.begins_with("Troop_"):
			ids.append(String(c.name).trim_prefix("Troop_"))
	return ids

func _stack(state, type: String) -> int:
	for s in state.player.troops:
		if s.type == type:
			return int(s.n)
	return 0

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var e1: Dictionary = state.roster.catalog.get_troop("e1")
	var e2: Dictionary = state.roster.catalog.get_troop("e2")
	p.troops = [{"type": "e3", "n": 5}, {"type": "e1", "n": 3}, {"type": "e2", "n": 2}, {"type": "e2a", "n": 6}, {"type": "e3c", "n": 1}]
	p.gold = Economy.upgrade_cost(e2, fx)
	var window := PartyWindow.new()
	root.add_child(window)
	await process_frame
	window.open_for(state, "troops")
	for i in 4: await process_frame
	assert(_rows(window, "ready") == ["e2a", "e2", "e1"], "ready first, higher tier and bigger stack first: %s" % [_rows(window, "ready")])
	assert(_rows(window, "poor").is_empty())
	assert(_rows(window, "top") == ["e3", "e3c"], "the highest tier goes last: %s" % [_rows(window, "top")])
	var groups: Array = window.body.get_children().filter(func(c): return String(c.name).begins_with("TroopGroup_"))
	assert(groups.map(func(c): return String(c.name)) == ["TroopGroup_ready", "TroopGroup_top"], "only groups with troops: %s" % [groups.map(func(c): return String(c.name))])
	# one click promotes exactly one man and the next ready stacks keep the top of the list
	var b := window.body.find_child("Promote_e1_e2a", true, false) as Button
	assert(b != null and not b.disabled)
	b.pressed.emit()
	assert(_stack(state, "e1") == 2 and _stack(state, "e2a") == 7, "one man per click")
	assert(p.gold == Economy.upgrade_cost(e2, fx) - Economy.upgrade_cost(e1, fx))
	assert(window.sub_label.text.contains("Повышен: Рекрут → Арбалетчик ×1"), window.sub_label.text)
	await process_frame
	assert(_rows(window, "ready") == ["e1"], "what can still be promoted moves to the top: %s" % [_rows(window, "ready")])
	assert(_rows(window, "poor") == ["e2a", "e2"], "the rest wait for gold: %s" % [_rows(window, "poor")])
	var poor := window.body.find_child("Promote_e2_e3", true, false) as Button
	assert(poor.disabled and poor.tooltip_text.contains("Нужно"), "a promotion without gold says why")
	# «всех»: one click promotes as many as the purse allows
	p.gold = Economy.upgrade_cost(e1, fx) * 5
	window._promote_mode = "all"
	window.render()
	b = window.body.find_child("Promote_e1_e2", true, false) as Button
	assert(b.text.contains("×2"), b.text)
	b.pressed.emit()
	assert(_stack(state, "e1") == 0 and _stack(state, "e2") == 4)
	await process_frame
	# compact rows that stay inside the window at 1280×720
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	for c in window.body.find_children("Troop_*", "", true, false):
		assert((c as Control).size.y <= 52, "compact row: %s %s" % [c.name, (c as Control).size])
	for c in window.body.find_children("Actions_*", "", true, false):
		assert((c as Control).get_global_rect().end.x <= panel.end.x, "actions stay in the window: %s" % c.name)
	assert(window.close_button.get_global_rect().end.y <= root.size.y, "close remains available: %s %s" % [window.close_button.get_global_rect(), root.size])
	# nobody to show: the empty state, no tables
	p.troops = []
	window.render()
	assert(window.body.find_child("TroopGroup_*", true, false) == null)
	window.free()
	print("Party troops tests passed")
	quit()
