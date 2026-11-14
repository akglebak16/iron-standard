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
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const PerkEffects = preload("res://characters/rules/perk_effects.gd")
const Config = preload("res://battle/config.gd")
const CharacterConfig = preload("res://characters/config.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")
const CompanionBuilder = preload("res://battle/data/companion_builder.gd")
const SiegeSetup = preload("res://battle/data/siege_setup.gd")

static func create(setup: Setup, catalog: Catalog, gear_catalog: GearCatalog = null, perk_catalog: PerkCatalog = null, companion_catalog: CompanionCatalog = null) -> Session:
	if setup == null or catalog == null or not setup.hero_position.is_finite():
		return null
	var troop: Dictionary = catalog.get_troop(setup.hero_troop)
	if troop.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = setup.seed
	var state := State.new()
	state.setup_groups()
	var player_cap := setup.unit_cap(setup.player_faction, setup.player_unit_cap)
	var enemy_cap := setup.unit_cap(setup.enemy_faction, setup.enemy_unit_cap)
	if not ArmyBuilder.spawn(state, 0, setup.player_army, setup.player_faction, catalog, rng, player_cap):
		return null
	var companion_survival := 0.0
	var siege_skill := 0.0
	var companion_ids := {}
	var fit_companions: Array[Dictionary] = []
	for saved in setup.companion_profiles:
		var resolved := CompanionProfile.resolve(saved, companion_catalog)
		if resolved.is_empty() or companion_ids.has(resolved.profile.id):
			return null
		companion_ids[resolved.profile.id] = true
		companion_survival += float(resolved.party_effects.get(CharacterConfig.SURVIVAL_EFFECT, 0.0))
		siege_skill += float(resolved.party_effects.get(CharacterConfig.SIEGE_EFFECT, 0.0))
		if not resolved.fit:
			continue
		fit_companions.append(resolved.profile)
	if setup.siege:
		SiegeSetup.apply(state, siege_skill)
	var defender_morale := roundf(Config.SIEGE_DEFENDER_MORALE * (1.0 - state.siege_skill)) if setup.siege else 0.0
	if not ArmyBuilder.spawn(state, 1, setup.enemy_army, setup.enemy_faction, catalog, rng, enemy_cap, setup.enemy_leader_name, defender_morale):
		return null
	for profile in fit_companions:
		var gear := HeroGear.resolve(profile, gear_catalog)
		if gear.is_empty() or perk_catalog == null:
			return null
		var effects := PerkEffects.own(profile, perk_catalog)
		if effects.is_empty() or not CompanionBuilder.spawn(state, profile, gear, effects, rng):
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
		var selected_perks: Variant = setup.hero_profile.get("perks", [])
		if not selected_perks is Array or not selected_perks.is_empty() and perk_catalog == null:
			return null
		if perk_catalog != null:
			hero.perk_effects = PerkEffects.own(setup.hero_profile, perk_catalog)
			if hero.perk_effects.is_empty():
				return null
		var gear: Dictionary = HeroGear.resolve(setup.hero_profile, gear_catalog)
		if gear.is_empty() or not HeroStats.apply(hero, setup.hero_profile, gear):
			return null
		var charisma: float = float(setup.hero_profile.get("cha", 0.0))
		if charisma == 0.0:
			charisma = float(setup.hero_profile.get("lead", 0.0))
		var morale_bonus: float = charisma * Config.HERO_ALLY_MORALE_PER_CHARISMA + float(hero.perk_effects.get("morale", 0.0))
		var damage_bonus: float = float(hero.perk_effects.get("ally", 0.0))
		for ally: Unit in state.units:
			if ally.side == hero.side:
				ally.base_morale += morale_bonus
				ally.morale = ally.base_morale
				ally.damage *= 1.0 + damage_bonus
	state.add_unit(hero)
	return Session.new(state, hero, rng, gear_catalog, setup.hero_profile, companion_survival)
