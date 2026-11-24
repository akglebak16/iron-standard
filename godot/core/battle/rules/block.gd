extends RefCounted
## Port of src/03_battle.js blocked(): chances are data, RNG is caller-owned.
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")

## `wall`: the target stands in a shield wall (stage 1g part 5, #270, Group.wall): a shield bearer holds an arrow
## AI_CMD_WALL_ARROW_BLOCK more often; the hero keeps his own rule.
static func chance(target: Unit, arrow: bool, wall := false) -> float:
	var base: float = target.block_chance
	var shield: float = target.shield_block
	if target.hero:
		if target.blocking:
			return minf(Config.HERO_MAX_BLOCK_CHANCE, base + Config.HERO_ACTIVE_BLOCK_BONUS + (shield * Config.HERO_SHIELD_ACTIVE_ARROW_MULTIPLIER if arrow else 0.0))
		return base * Config.HERO_IDLE_BLOCK_MULTIPLIER + (shield * Config.HERO_SHIELD_IDLE_ARROW_MULTIPLIER if arrow else 0.0)
	if arrow:
		if shield <= 0.0:
			return base * Config.UNSHIELDED_ARROW_BLOCK_MULTIPLIER
		if wall:
			shield += Config.AI_CMD_WALL_ARROW_BLOCK
		return minf(Config.SHIELD_ARROW_MAX_BLOCK, base * Config.SHIELD_ARROW_BONUS_MULTIPLIER + shield)
	return base

static func check(target: Unit, incoming: float, arrow: bool, rng: RandomNumberGenerator, wall := false) -> bool:
	var probability := chance(target, arrow, wall)
	if target.wavering:
		probability *= Config.MORALE_WAVER_BLOCK_MULTIPLIER
	if probability <= 0.0 or absf(wrapf(incoming - target.facing, -PI, PI)) > Config.BLOCK_ARC:
		return false
	return rng.randf() < probability
