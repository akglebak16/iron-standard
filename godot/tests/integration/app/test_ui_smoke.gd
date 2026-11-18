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
	# Two sides: the player's cargo (only what he has) and the merchant (only what is in stock).
	var m: Dictionary = state.market.market_of(home, state.clock.day)
	var in_stock: Array = state.market.goods.keys().filter(func(id): return int(m.stock.get(id, 0)) > 0)
	var owned: Array = state.market.goods.keys().filter(func(id): return int(state.player.inv.get(id, 0)) > 0)
	var shop: GridContainer = table.find_child("MerchantGoods", true, false).find_child("Table", true, false)
	var cargo: GridContainer = table.find_child("CargoGoods", true, false).find_child("Table", true, false)
	assert(shop.get_child_count() == shop.columns * in_stock.size(), "one merchant line per good in stock")
	assert(cargo.get_child_count() == cargo.columns * owned.size(), "one cargo line per good the player has")
	for icon in table.find_children("", "TextureRect", true, false):
		assert((icon as TextureRect).texture != null, "every good has an icon")
	var buy_buttons := shop.find_children("", "Button", true, false).filter(func(b): return b.text == "+1")
	assert(buy_buttons.size() == in_stock.size(), "every good in stock can be bought")
	# Something bought appears on the cargo side, with its sale buttons.
	state.player.gold = 100000
	var cheap: String = in_stock[0]
	state.market.buy(state.player, state.player_effects(), home, state.clock.day, cheap, 1, 10)
	town.render()
	cargo = town.body.find_child("CargoGoods", true, false).find_child("Table", true, false)
	assert(cargo.find_children("", "Button", true, false).filter(func(b): return b.text == "−1").size() >= 1, "the cargo side sells")
	assert(town.body.find_child("CargoGoods", true, false).find_child("Empty", true, false) == null, "a cargo with goods is not called empty")
	town._market_view = "gear"
	town.render()
	assert(town.body.find_child("GoodsTable", true, false) == null and town.body.find_child("MarketSwitch", true, false) != null, "the gear sub-tab hides goods")
	var gear_table: Node = town.body.find_child("GearTable", true, false)
	assert(gear_table != null and gear_table.find_child("CargoGear", true, false) != null and gear_table.find_child("MerchantGear", true, false) != null, "gear has both sides")
	for icon in gear_table.find_children("", "TextureRect", true, false):
		assert((icon as TextureRect).texture != null, "every item has a picture")
	# A trophy in the cargo: listed on the left with a comparison to the worn item, and "sell all" sells it.
	var trophy: String = state.market.gear.keys()[3]
	state.player.inv[trophy] = 1
	town.render()
	var sell_all: Button = town.body.find_child("SellAllGear", true, false)
	assert(sell_all != null and town.body.find_child("CargoGear", true, false).find_child("Compare", true, false) != null, "a trophy shows ▲/▼ and can be sold")
	sell_all.pressed.emit()
	assert(int(state.player.inv.get(trophy, 0)) == 0, "sell all empties the trophies")
	assert(town.sub_label.text.contains("продано трофеев"), "the deal is reported under the title")
	town._market_view = "goods"
	for tab in ["troops", "hero", "journal"]:
		party.open_for(state, tab)
		party.current_tab = tab
		party.render()
		await process_frame
		assert(party.body.get_child_count() > 0, tab)
	hud.refresh(state, home)
	print("UI smoke tests passed")
	quit(0)
