extends RefCounted
## Port of src/03_battle.js blocked(): chances are data, RNG is caller-owned.
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")

static func chance(target: Unit, arrow: bool) -> float:
	var base: float = target.block_chance
	var shield: float = target.shield_block
	if target.hero:
		if target.blocking:
			return minf(Config.HERO_MAX_BLOCK_CHANCE, base + Config.HERO_ACTIVE_BLOCK_BONUS + (shield * Config.HERO_SHIELD_ACTIVE_ARROW_MULTIPLIER if arrow else 0.0))
		return base * Config.HERO_IDLE_BLOCK_MULTIPLIER + (shield * Config.HERO_SHIELD_IDLE_ARROW_MULTIPLIER if arrow else 0.0)
	if arrow:
		return minf(Config.SHIELD_ARROW_MAX_BLOCK, base * Config.SHIELD_ARROW_BONUS_MULTIPLIER + shield) if shield > 0.0 else base * Config.UNSHIELDED_ARROW_BLOCK_MULTIPLIER
	return base

static func check(target: Unit, incoming: float, arrow: bool, rng: RandomNumberGenerator) -> bool:
	var probability := chance(target, arrow)
	if probability <= 0.0 or absf(wrapf(incoming - target.facing, -PI, PI)) > Config.BLOCK_ARC:
		return false
	return rng.randf() < probability
