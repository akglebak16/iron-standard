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
	town.current_tab = "goods"
	town.render()
	assert(town.body.get_child_count() > 3, "goods tab lists goods")
	var table: Node = town.body.find_child("GoodsTable", true, false)
	assert(table != null and town.body.find_child("TradeSummary", true, false) != null, "goods table and summary are drawn")
	var grid: GridContainer = table.get_child(0)
	assert(grid.get_child_count() == grid.columns * (state.market.goods.size() + 1), "a header and one line per good")
	for icon in grid.find_children("", "TextureRect", true, false):
		assert((icon as TextureRect).texture != null, "every good has an icon")
	var buy_buttons := grid.find_children("", "Button", true, false).filter(func(b): return b.text == "+1")
	assert(buy_buttons.size() == state.market.goods.size(), "every good can be bought")
	for tab in ["troops", "hero", "journal"]:
		party.open_for(state, tab)
		party.current_tab = tab
		party.render()
		await process_frame
		assert(party.body.get_child_count() > 0, tab)
	hud.refresh(state, home)
	print("UI smoke tests passed")
	quit(0)
