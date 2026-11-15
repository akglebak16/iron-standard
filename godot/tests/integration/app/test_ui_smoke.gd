extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const WorldHud = preload("res://apps/godot/presentation/campaign/world_hud.gd")

func _initialize() -> void:
	var menu = (load("res://apps/godot/composition/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(3, data, "nord", ContentLoader.registry())
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
	town.current_tab = "goods"
	town.render()
	assert(town.body.get_child_count() > 10, "goods tab lists goods")
	for tab in ["troops", "hero", "journal"]:
		party.open_for(state, tab)
		party.current_tab = tab
		party.render()
		await process_frame
		assert(party.body.get_child_count() > 0, tab)
	hud.refresh(state, home)
	print("UI smoke tests passed")
	quit(0)
