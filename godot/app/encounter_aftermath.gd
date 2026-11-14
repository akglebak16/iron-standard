extends RefCounted
## Consumes a finished battle once and returns detached campaign data to its owner.
const Session = preload("res://battle/application/session.gd")
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")
const Rewards = preload("res://campaign/data/encounter_rewards.gd")
const Aftermath = preload("res://campaign/rules/battle_aftermath.gd")
const Loot = preload("res://campaign/economy/battle_loot.gd")

var _session: Session

func _init(session: Session) -> void:
	_session = session

func resolve(party: Dictionary, opponent: Dictionary, effects: Dictionary, mounted_hero: bool, troops: Troops, gear: Gear, goods: Goods, rng: RandomNumberGenerator) -> Dictionary:
	if _session == null or gear == null or goods == null:
		return {}
	var result := _session.result()
	if result.is_empty():
		return {}
	var encounter := Rewards.from_opponent(opponent)
	var aftermath := Aftermath.resolve(party, result, encounter, effects, troops, rng)
	if aftermath.is_empty():
		return {}
	aftermath.summary.drops = Loot.collect(aftermath.party, encounter, effects, mounted_hero, troops, gear, goods, rng) if result.win else []
	_session = null
	return aftermath
