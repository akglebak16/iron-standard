extends RefCounted
## Converts browser encounter identifiers into values consumed by the reward rule.
const Config = preload("res://campaign/config.gd")
const LOW_LOOT_FACTIONS := ["undead"]
const CAMP_KIND := "camp"
const CARAVAN_KIND := "caravan"

static func from_opponent(opponent: Dictionary) -> Dictionary:
	var kind: String = opponent.get("kind", "")
	return {
		"troops": opponent.get("troops", []).duplicate(true),
		"gold": int(opponent.get("gold", 0)),
		"bonus_gold": Config.CAMP_GOLD if kind == CAMP_KIND else 0,
		"gold_multiplier": Config.LOW_LOOT_GOLD_MULTIPLIER if opponent.get("fac") in LOW_LOOT_FACTIONS else 1.0,
		"provisions": Config.CARAVAN_PROVISIONS if kind == CARAVAN_KIND else Config.BATTLE_PROVISIONS,
		"trade_goods_only": kind == CARAVAN_KIND,
		"faction": opponent.get("fac", ""),
	}
