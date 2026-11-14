extends RefCounted
const ArmyBuilder = preload("res://battle/data/army_builder.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")
const GearCatalog = preload("res://battle/data/gear_catalog.gd")
const HeroGear = preload("res://battle/data/hero_gear.gd")

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
		if gear.is_empty() or not _apply_hero_gear(hero, setup.hero_profile, gear):
			return null
	state.add_unit(hero)
	return Session.new(state, hero, rng)

static func _apply_hero_gear(hero: Unit, profile: Dictionary, gear: Dictionary) -> bool:
	for stat in ["str", "agi", "vit", "hp"]:
		var value: Variant = profile.get(stat, 1.0 if stat == "hp" else 0.0)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0.0:
			return false
	var strength: float = float(profile.get("str", 0.0))
	var agility: float = float(profile.get("agi", 0.0))
	var vitality: float = float(profile.get("vit", 0.0))
	var weapon: Dictionary = gear.weapon
	var ranged: bool = weapon.get("slot") == "ranged"
	hero.max_hp = roundf(Config.HERO_BASE_HEALTH + vitality * Config.HERO_HEALTH_PER_VITALITY)
	hero.hp = maxf(hero.max_hp * Config.HERO_MIN_HEALTH_FRACTION, hero.max_hp * float(profile.get("hp", 1.0)))
	hero.armor = float(gear.armor)
	hero.mounted = bool(gear.mounted)
	hero.speed = float(gear.horse.v) if hero.mounted else Config.HERO_BASE_FOOT_SPEED + agility * Config.HERO_SPEED_PER_AGILITY
	hero.damage = float(weapon.dmg) + strength * (float(weapon.get("bs", 0.0)) if ranged else Config.HERO_MELEE_DAMAGE_PER_STRENGTH)
	hero.attack_interval = maxf(Config.HERO_RANGED_MIN_COOLDOWN, float(weapon.cd) * (1.0 - agility * Config.HERO_RANGED_AGILITY_COOLDOWN)) if ranged else maxf(Config.HERO_MELEE_MIN_COOLDOWN, Config.HERO_MELEE_BASE_COOLDOWN - agility * Config.HERO_MELEE_AGILITY_COOLDOWN) * float(weapon.spd)
	hero.attack_range = float(weapon.range) if ranged else 0.0
	hero.block_chance = float(gear.block)
	hero.shield_block = float(Config.SHIELD_ARROW_BONUS.get(gear.shield.get("look", ""), 0.0))
	hero.weapon_kind = str(weapon.wt)
	hero.damage_type = str(weapon.dt)
	hero.pierce = float(weapon.get("pb", 0.0))
	hero.accuracy = float(weapon.get("acc", 0.0)) * Config.HERO_GEAR_ACCURACY_MULTIPLIER
	hero.anti_cavalry = bool(weapon.get("anticav", false))
	hero.collision_radius = Config.HORSE_COLLISION_RADIUS if hero.mounted else Config.FOOT_COLLISION_RADIUS
	hero.mass = Config.HORSE_MASS if hero.mounted else Config.FOOT_MASS
	return true
