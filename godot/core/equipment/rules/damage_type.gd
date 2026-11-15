extends RefCounted
## armClass(), dtPierce() and dtMul() from src/01b_gear.js.
const Config = preload("res://core/equipment/config.gd")

static func armor_class(armor: float) -> int:
	if armor < Config.ARMOR_LIGHT_MAX:
		return 0
	return 1 if armor < Config.ARMOR_MEDIUM_MAX else 2

static func pierce(kind: String, armor: float, extra: float = 0.0) -> float:
	var table: Array = Config.DAMAGE_TYPE_ARMOR_PIERCE.get(kind, [])
	var base: float = table[armor_class(armor)] if not table.is_empty() else 0.0
	return clampf(base + extra, 0.0, Config.DAMAGE_TYPE_PIERCE_CAP)

static func multiplier(kind: String, armor: float) -> float:
	return Config.LIGHT_ARMOR_CUT_MULTIPLIER if kind == Config.DAMAGE_TYPE_CUT and armor_class(armor) == 0 else 1.0
