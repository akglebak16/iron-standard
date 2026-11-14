extends RefCounted
const Config = preload("res://battle/config.gd")
## Mirrors hurt() in src/03_battle.js. Other combat modifiers are applied upstream.

static func after_armor(damage: float, armor: float, pierce: float = 0.0) -> int:
	var effective_armor := armor * (1.0 - pierce)
	return maxi(Config.MIN_HIT_DAMAGE, floori(damage * (1.0 - effective_armor / (effective_armor + Config.ARMOR_SCALE)) + 0.5))
