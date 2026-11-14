extends RefCounted
## Consumes a finished battle once and returns detached campaign data to its owner.
const Session = preload("res://battle/application/session.gd")
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")
const Rewards = preload("res://campaign/data/encounter_rewards.gd")
const Aftermath = preload("res://campaign/rules/battle_aftermath.gd")
const Loot = preload("res://campaign/economy/battle_loot.gd")
const EncounterWorld = preload("res://campaign/rules/encounter_world.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")

var _session: Session

func _init(session: Session) -> void:
	_session = session

func resolve(party: Dictionary, opponent: Dictionary, mounted_hero: bool, troops: Troops, gear: Gear, goods: Goods, rng: RandomNumberGenerator, companions: CompanionCatalog, perks: PerkCatalog, world: Dictionary = {}) -> Dictionary:
	if _session == null or gear == null or goods == null or companions == null or perks == null or not party.get("hero") is Dictionary:
		return {}
	var result := _session.result()
	if result.is_empty():
		return {}
	var encounter := Rewards.from_opponent(opponent)
	var effects := CompanionProfile.party_effects(party.hero, party.get("comps", []), companions, perks)
	var aftermath := Aftermath.resolve(party, result, encounter, effects, troops, rng, companions, perks)
	if aftermath.is_empty():
		return {}
	aftermath.world = EncounterWorld.apply(world, aftermath.party, opponent, result, aftermath.summary, float(effects.get("quest", 0.0)))
	aftermath.summary.drops = []
	if result.win:
		var reward_effects := CompanionProfile.party_effects(aftermath.party.hero, aftermath.party.get("comps", []), companions, perks)
		aftermath.summary.drops = Loot.collect(aftermath.party, encounter, reward_effects, mounted_hero, troops, gear, goods, rng)
	_session = null
	return aftermath
