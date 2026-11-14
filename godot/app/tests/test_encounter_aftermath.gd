extends SceneTree
const Aftermath = preload("res://app/encounter_aftermath.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Config = preload("res://battle/config.gd")
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")
const TICK := 1.0 / 60.0

func _initialize() -> void:
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
	assert(bridge.resolve(party, opponent, {}, false, troops, gear, goods, rng).is_empty())
	assert(rng.state == initial_rng)
	session._state.kill(session._state.units[0], session._hero)
	session.advance(TICK)
	session.advance(TICK + Config.BATTLE_END_DELAY_SECONDS)
	var applied := bridge.resolve(party, opponent, {}, false, troops, gear, goods, rng)
	assert(applied.summary.win and applied.summary.loot > 0 and not applied.summary.drops.is_empty())
	assert(applied.party.gold == 25 + applied.summary.loot)
	assert(party.gold == 25 and not party.has("inv"))
	var final_rng := rng.state
	assert(bridge.resolve(applied.party, opponent, {}, false, troops, gear, goods, rng).is_empty())
	assert(rng.state == final_rng)
	print("Encounter aftermath integration tests passed")
	quit(0)
