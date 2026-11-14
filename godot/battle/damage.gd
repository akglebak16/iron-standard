extends RefCounted
## Mirrors hurt() in src/03_battle.js. Other combat modifiers are applied upstream.

static func after_armor(damage: float, armor: float, pierce: float = 0.0) -> int:
	var effective_armor := armor * (1.0 - pierce)
	return maxi(1, floori(damage * (1.0 - effective_armor / (effective_armor + 55.0)) + 0.5))
