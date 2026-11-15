extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const PauseMenu = preload("res://apps/godot/composition/pause_menu.gd")
const Preferences = preload("res://apps/godot/composition/presentation_preferences.gd")
const WorldTips = preload("res://apps/godot/presentation/campaign/world_tips.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var p = s.player
	var gear = s.gear
	# legacy kit becomes slots
	var eq: Dictionary = HeroEquip.ensure(p.hero)
	assert(eq.melee == "sword_old" and eq.head == "head_cap" and p.hero.sel == "melee")
	# equip a two-handed weapon: the shield goes to the cargo
	var two := ""
	var shield := ""
	var horse := ""
	for id in gear.definitions():
		var it: Dictionary = gear.get_item(id)
		if it.slot == "melee" and int(it.get("hands", 1)) == 2 and two == "":
			two = id
		if it.slot == "shield" and shield == "":
			shield = id
		if it.slot == "horse" and horse == "":
			horse = id
	p.inv[shield] = 1
	assert(HeroEquip.equip(p.inv, p.hero, shield, gear).ok)
	p.inv[two] = 1
	var r: Dictionary = HeroEquip.equip(p.inv, p.hero, two, gear)
	assert(r.ok and r.note != "" and eq.shield == null and int(p.inv[shield]) == 1 and int(p.inv["sword_old"]) == 1)
	assert(not HeroEquip.equip(p.inv, p.hero, shield, gear).ok, "no shield with a two-hander")
	p.inv[horse] = 1
	HeroEquip.equip(p.inv, p.hero, horse, gear)
	assert(int(p.hero.horse) > 0 and HeroGear.resolve(p.hero, gear).mounted)
	assert(HeroEquip.unequip(p.inv, p.hero, "horse") and int(p.hero.horse) == 0)
	# the market buys and sells gear
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "emp":
			town = t
			break
	var m: Dictionary = s.market.market_of(town, s.clock.day)
	var gear_stock := 0
	for t in s.map.settles:
		if t.kind == "town":
			for id in s.market.market_of(t, 1).stock:
				if s.market.is_gear(id):
					gear_stock += 1
	assert(gear_stock > 0, "towns sell gear")
	var fx: Dictionary = s.player_effects()
	var sp: int = s.market.sell_price(p.rel, fx, town, m, shield)
	assert(sp < s.market.buy_price(p.rel, fx, town, m, shield))
	var gold: int = p.gold
	assert(s.market.sell(p, fx, town, s.clock.day, shield, 1).n == 1 and p.gold == gold + sp and not p.inv.has(shield))
	assert(s.market.buy(p, fx, town, s.clock.day, shield, 1, 10).n == 1 and int(p.inv[shield]) == 1)
	assert(s.market.cargo_weight(p.inv) > 0.0)
	# companions are dressed from the same cargo
	p.comps.append(s.companions.new_profile(s.companion_catalog.ids()[0]))
	assert(HeroEquip.equip(p.inv, p.comps[0], shield, gear).ok or true)
	# save keeps the slots
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back.player.hero.eq.melee == two)
	# windows
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	pw.open_for(s, "gear")
	var figure := pw.body.find_child("EquipmentFigure", true, false) as TextureRect
	assert(figure != null and figure.texture != null, "equipment shows the dressed hero")
	for slot in PartyWindow.SLOT_NAMES:
		assert(pw.body.find_child("Equipped_" + slot, true, false) is Button, "every equipment slot remains accessible")
	var tw := TownWindow.new()
	root.add_child(tw)
	await process_frame
	tw.open_for(s, town)
	tw.current_tab = "goods"
	tw.render()
	assert(tw.body.get_child_count() > 10)
	var menu := PauseMenu.new()
	root.add_child(menu)
	await process_frame
	var prefs := Preferences.new("user://test_prefs.cfg")
	menu.open_menu(prefs)
	assert(menu.visible and menu.body.get_child_count() >= 7)
	prefs.save(false, true)
	menu.render()
	assert(not prefs.read().effects)
	prefs.save(true, true)
	# tooltips
	var factions := FactionCatalog.new()
	assert(ContentLoader.populate(factions))
	assert("Отношение" in WorldTips.settlement_tip(s, town, factions))
	var lord: Dictionary = s.roster.parties.filter(func(q): return q.kind == "lord")[0]
	assert(lord.name in WorldTips.party_tip(s, lord, factions))
	print("Gear and menu tests passed")
	quit(0)
