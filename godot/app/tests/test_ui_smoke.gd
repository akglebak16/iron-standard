extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const TownWindow = preload("res://campaign/presentation/town_window.gd")
const PartyWindow = preload("res://campaign/presentation/party_window.gd")
const WorldHud = preload("res://campaign/presentation/world_hud.gd")

func _initialize() -> void:
	var menu = (load("res://app/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	var data := EuropeData.new()
	assert(data.load_data())
	var state := WorldState.create(3, data, "nord")
	var town := TownWindow.new()
	var party := PartyWindow.new()
	var hud := WorldHud.new()
	root.add_child(town)
	root.add_child(party)
	root.add_child(hud)
	await process_frame
	var home: Dictionary = state.settlement_near(state.player.x, state.player.y, 80.0)
	town.open_for(state, home)
	assert(town.visible and town.body.get_child_count() > 2, "recruit tab lists recruits")
	town.current_tab = "market"
	town.render()
	assert(town.body.get_child_count() > 5, "market lists food and gear")
	for tab in ["troops", "hero", "journal"]:
		party.open_for(state, tab)
		party.current_tab = tab
		party.render()
		await process_frame
		assert(party.body.get_child_count() > 0, tab)
	hud.refresh(state, home)
	print("UI smoke tests passed")
	quit(0)
