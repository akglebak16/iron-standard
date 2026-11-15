extends RefCounted
## Consumes a finished battle once and returns detached campaign data to its owner.
const Troops = preload("res://core/troops/data/catalog.gd")
const Gear = preload("res://core/equipment/data/gear_catalog.gd")
const Goods = preload("res://core/campaign/data/goods_catalog.gd")
const Rewards = preload("res://core/campaign/data/encounter_rewards.gd")
const Aftermath = preload("res://core/campaign/rules/battle_aftermath.gd")
const Loot = preload("res://core/campaign/economy/battle_loot.gd")
const EncounterWorld = preload("res://core/campaign/rules/encounter_world.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const CompanionProfile = preload("res://core/characters/rules/companion_profile.gd")

var _result_query: Callable

func _init(result_query: Callable) -> void:
	_result_query = result_query

func resolve(party: Dictionary, opponent: Dictionary, mounted_hero: bool, troops: Troops, gear: Gear, goods: Goods, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog, world: Dictionary = {}) -> Dictionary:
	if not _result_query.is_valid() or gear == null or goods == null or companions == null or perks == null or not party.get("hero") is Dictionary:
		return {}
	var result: Dictionary = _result_query.call()
	if result.is_empty():
		return {}
	var resolved := resolve_result(result, party, opponent, mounted_hero, troops, gear, goods, rng, companions, perks, world)
	if not resolved.is_empty(): _result_query = Callable()
	return resolved

## Same rules for a result that did not come from a played session (auto-resolved battle).
static func resolve_result(result: Dictionary, party: Dictionary, opponent: Dictionary, mounted_hero: bool, troops: Troops, gear: Gear, goods: Goods, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog, world: Dictionary = {}) -> Dictionary:
	if gear == null or goods == null or companions == null or perks == null or not party.get("hero") is Dictionary or result.is_empty():
		return {}
	var encounter := Rewards.from_opponent(opponent)
	var effects := CompanionProfile.party_effects(party.hero, party.get("comps", []), companions, perks)
	var aftermath := Aftermath.resolve(party, result, encounter, effects, troops, rng, companions, perks)
	if aftermath.is_empty():
		return {}
	aftermath.world = EncounterWorld.apply(world, aftermath.party, opponent, result, aftermath.summary, float(effects.get("quest", 0.0)), troops, rng)
	aftermath.summary.drops = []
	if result.win:
		var reward_effects := CompanionProfile.party_effects(aftermath.party.hero, aftermath.party.get("comps", []), companions, perks)
		aftermath.summary.drops = Loot.collect(aftermath.party, encounter, reward_effects, mounted_hero, troops, gear, goods, rng)
	return aftermath
