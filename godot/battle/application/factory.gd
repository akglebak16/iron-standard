extends RefCounted
const ArmyBuilder = preload("res://battle/data/army_builder.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Session = preload("res://battle/application/session.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const HeroStats = preload("res://battle/data/hero_stats.gd")

static func create(setup: Setup, catalog: Catalog, gear_catalog: GearCatalog = null) -> Session:
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
	hero.shield_block = float(troop.get("shb", 0))
	if not setup.hero_profile.is_empty():
		var gear: Dictionary = HeroGear.resolve(setup.hero_profile, gear_catalog)
		if gear.is_empty() or not HeroStats.apply(hero, setup.hero_profile, gear):
			return null
	state.add_unit(hero)
	return Session.new(state, hero, rng, gear_catalog, setup.hero_profile)
