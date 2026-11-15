extends RefCounted
const ArmyBuilder = preload("res://core/battle/data/army_builder.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Session = preload("res://core/battle/application/session.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroStats = preload("res://core/battle/data/hero_stats.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const PerkEffects = preload("res://core/characters/rules/perk_effects.gd")
const Config = preload("res://core/battle/config.gd")
const CharacterConfig = preload("res://core/characters/config.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const CompanionProfile = preload("res://core/characters/rules/companion_profile.gd")
const CompanionBuilder = preload("res://core/battle/data/companion_builder.gd")
const SiegeSetup = preload("res://core/battle/data/siege_setup.gd")
const VegetationSetup = preload("res://core/battle/data/vegetation_setup.gd")

static func create(setup: Setup, catalog: Catalog, gear_catalog: GearCatalog = null, perk_catalog: PerkCatalog = null, companion_catalog: CompanionCatalog = null, contact_solver := Callable()) -> Session:
	if setup == null or catalog == null or not setup.hero_position.is_finite():
		return null
	var troop: Dictionary = catalog.get_troop(setup.hero_troop)
	if troop.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = setup.seed
	var state := State.new()
	state.contact_solver = contact_solver
	state.setup_groups()
	var player_cap := setup.unit_cap(setup.player_faction, setup.player_unit_cap)
	var enemy_cap := setup.unit_cap(setup.enemy_faction, setup.enemy_unit_cap)
	state.side_factions = [setup.player_faction, setup.enemy_faction]
	if not ArmyBuilder.spawn(state, 0, setup.player_army, setup.player_faction, catalog, rng, player_cap, "", 0.0, setup.uses_reserve_waves(setup.player_faction)):
		return null
	var party := _resolve_companions(setup, companion_catalog)
	if party.is_empty():
		return null
	if setup.siege:
		SiegeSetup.apply(state, party.siege_skill, setup.wall_damage, setup.wall_defense)
	state.set_plants(VegetationSetup.create(state.arena_size, setup.seed, setup.biome, state.wall.x if state.wall != null else INF))
	var defender_morale := roundf(Config.SIEGE_DEFENDER_MORALE * (1.0 - state.siege_skill)) if setup.siege else 0.0
	if not ArmyBuilder.spawn(state, 1, setup.enemy_army, setup.enemy_faction, catalog, rng, enemy_cap, setup.enemy_leader_name, defender_morale, setup.uses_reserve_waves(setup.enemy_faction)):
		return null
	var dialogue: Variant = _spawn_companions(state, party.fit, gear_catalog, perk_catalog, rng)
	if dialogue == null:
		return null
	state.place_units()
	var hero := _create_hero(setup, troop, state, gear_catalog, perk_catalog)
	if hero == null:
		return null
	state.add_unit(hero)
	return Session.new(state, hero, rng, gear_catalog, setup.hero_profile, party.survival, dialogue)

## Checks the saved companion roster. Returns the fit companions and the party effects
## they add up to, or an empty dictionary when a profile is unknown or repeated.
static func _resolve_companions(setup: Setup, companion_catalog: CompanionCatalog) -> Dictionary:
	var survival := 0.0
	var siege_skill := 0.0
	var seen := {}
	var fit: Array[Dictionary] = []
	for saved in setup.companion_profiles:
		var resolved := CompanionProfile.resolve(saved, companion_catalog)
		if resolved.is_empty() or seen.has(resolved.profile.id):
			return {}
		seen[resolved.profile.id] = true
		survival += float(resolved.party_effects.get(CharacterConfig.SURVIVAL_EFFECT, 0.0))
		siege_skill += float(resolved.party_effects.get(CharacterConfig.SIEGE_EFFECT, 0.0))
		if resolved.fit:
			fit.append(resolved)
	return {"fit": fit, "survival": survival, "siege_skill": siege_skill}

## Creates the fit companions as allied fighters. Returns their dialogue by unit id,
## or null when a companion cannot be equipped.
static func _spawn_companions(state: State, fit: Array[Dictionary], gear_catalog: GearCatalog, perk_catalog: PerkCatalog, rng: RandomNumberGenerator) -> Variant:
	var dialogue := {}
	for companion in fit:
		var profile: Dictionary = companion.profile
		var gear := HeroGear.resolve(profile, gear_catalog)
		if gear.is_empty() or perk_catalog == null:
			return null
		var effects := PerkEffects.own(profile, perk_catalog)
		if effects.is_empty():
			return null
		var unit := CompanionBuilder.spawn(state, profile, gear, effects, rng)
		if unit == null:
			return null
		if not companion.voice.is_empty():
			dialogue[unit.id] = {"name": unit.name, "companion_id": unit.companion_id, "lines": companion.voice}
	return dialogue

## Builds the player's hero from the preview troop and, when a profile is set, applies its
## gear, perks and the morale and damage bonus it gives to allies. Returns null when invalid.
static func _create_hero(setup: Setup, troop: Dictionary, state: State, gear_catalog: GearCatalog, perk_catalog: PerkCatalog) -> Unit:
	var hero := Unit.new(state.units.size(), 0, setup.hero_position, float(troop.hp), float(troop.arm), int(troop.tier))
	hero.hero = true
	hero.appearance = troop.get("look", {}).duplicate(true)
	# The preview hero's troop definition provides art but does not equip a mount.
	hero.appearance.erase("horse")
	hero.troop_id = setup.hero_troop
	hero.speed = float(troop.spd)
	hero.damage = float(troop.dmg)
	hero.attack_interval = float(troop.cd)
	hero.block_chance = float(troop.block)
	hero.shield_block = float(troop.get("shb", 0))
	if setup.hero_profile.is_empty():
		return hero
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
	return hero
