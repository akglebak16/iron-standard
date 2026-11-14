extends SceneTree
const Aftermath = preload("res://app/encounter_aftermath.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Config = preload("res://battle/config.gd")
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")
const Siege = preload("res://campaign/rules/siege_aftermath.gd")
const TICK := 1.0 / 60.0

const Companions = preload("res://characters/data/companion_catalog.gd")
const Perks = preload("res://characters/data/perk_catalog.gd")

func _initialize() -> void:
	var companions := Companions.new()
	var perks := Perks.new()
	assert(companions.load_data() and perks.load_data())
	var troops := Troops.new()
	var gear := Gear.new()
	var goods := Goods.new()
	assert(troops.load_data() and gear.load_data() and goods.load_data())
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.enemy_army = [{"type": "e1", "n": 1}]
	var session := Factory.create(setup, troops)
	var bridge := Aftermath.new(session)
	var party := {"troops": [], "hero": {"str": 2}, "gold": 25}
	var opponent := {"troops": setup.enemy_army, "kind": "caravan", "fac": "emp"}
	var rng := RandomNumberGenerator.new()
	rng.seed = 25
	var initial_rng := rng.state
	assert(bridge.resolve(party, opponent, false, troops, gear, goods, rng, companions, perks).is_empty())
	assert(rng.state == initial_rng)
	session._state.kill(session._state.units[0], session._hero)
	session.advance(TICK)
	session.advance(TICK + Config.BATTLE_END_DELAY_SECONDS)
	var applied := bridge.resolve(party, opponent, false, troops, gear, goods, rng, companions, perks)
	assert(applied.summary.win and applied.summary.loot > 0 and not applied.summary.drops.is_empty())
	assert(applied.party.gold == 25 + applied.summary.loot)
	assert(party.gold == 25 and not party.has("inv"))
	var final_rng := rng.state
	assert(bridge.resolve(applied.party, opponent, false, troops, gear, goods, rng, companions, perks).is_empty())
	assert(rng.state == final_rng)
	var settlement := {"id": 5, "kind": "town", "fac": "emp", "name": "Вентум", "gar": [{"type": "e1", "n": 1}]}
	var siege := Siege.defenders(settlement, [], troops, rng)
	setup.enemy_army.assign(siege.troops)
	var siege_session := Factory.create(setup, troops)
	siege_session._state.kill(siege_session._state.units[0], siege_session._hero)
	siege_session.advance(TICK)
	siege_session.advance(TICK + Config.BATTLE_END_DELAY_SECONDS)
	party.id = 7
	var captured := Aftermath.new(siege_session).resolve(party, siege, false, troops, gear, goods, rng, companions, perks, {"settlements": [settlement]})
	assert(captured.summary.captured == settlement.name and captured.world.settlements[0].owner == 7)
	assert(settlement.fac == "emp" and settlement.gar[0].n == 1)
	print("Encounter aftermath integration tests passed")
	quit(0)
