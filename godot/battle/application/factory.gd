extends RefCounted
const ArmyBuilder = preload("res://battle/data/army_builder.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")

static func create(setup: Setup, catalog: Catalog) -> Session:
	if setup == null or catalog == null or not setup.hero_position.is_finite():
		return null
	var troop: Dictionary = catalog.get_troop(setup.hero_troop)
	if troop.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = setup.seed
	var state := State.new()
	state.setup_groups()
	if not ArmyBuilder.spawn(state, 0, setup.player_army, setup.player_faction, catalog, rng) or not ArmyBuilder.spawn(state, 1, setup.enemy_army, setup.enemy_faction, catalog, rng):
		return null
	state.place_units()
	var hero := Unit.new(state.units.size(), 0, setup.hero_position, float(troop.hp), float(troop.arm), int(troop.tier))
	hero.hero = true
	hero.troop_id = setup.hero_troop
	hero.speed = float(troop.spd)
	hero.damage = float(troop.dmg)
	hero.attack_interval = float(troop.cd)
	hero.block_chance = float(troop.block)
	state.add_unit(hero)
	for group in state.groups[1]:
		group.order = Config.ORDER_CHARGE
	return Session.new(state, hero, rng)
