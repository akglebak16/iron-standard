extends RefCounted

const BASE_LEVEL_XP := 100
const LEVEL_XP_STEP := 80
const XP_PER_EXTRA_INTELLIGENCE := 0.03
const HERO_ATTRIBUTE_POINTS := 2
const HERO_PERK_POINTS := 1
const FIRST_GROWTH_LEVEL := 2

static func xp_multiplier(profile: Dictionary, xp_bonus: float) -> float:
	var intelligence := float(profile.get("int", 1))
	if intelligence == 0:
		intelligence = 1
	return 1.0 + (intelligence - 1.0) * XP_PER_EXTRA_INTELLIGENCE + xp_bonus

## Updates a caller-owned profile and returns the number of levels gained.
static func gain_hero_xp(profile: Dictionary, amount: int) -> int:
	var gained := _gain_xp(profile, amount)
	profile.pts = int(profile.get("pts", 0)) + gained * HERO_ATTRIBUTE_POINTS
	profile.pp = int(profile.get("pp", 0)) + gained * HERO_PERK_POINTS
	return gained

static func gain_companion_xp(profile: Dictionary, amount: int, growth: Array) -> int:
	var previous_level := int(profile.get("lvl", 1))
	var gained := _gain_xp(profile, amount)
	for level in range(previous_level + 1, previous_level + gained + 1):
		var attribute: String = growth[(level - FIRST_GROWTH_LEVEL) % growth.size()]
		profile[attribute] = int(profile.get(attribute, 0)) + 1
	return gained

static func _gain_xp(profile: Dictionary, amount: int) -> int:
	profile.xp = int(profile.get("xp", 0)) + amount
	profile.lvl = int(profile.get("lvl", 1))
	var gained := 0
	while profile.xp >= _level_cost(profile.lvl):
		profile.xp -= _level_cost(profile.lvl)
		profile.lvl += 1
		gained += 1
	return gained

static func _level_cost(level: int) -> int:
	return BASE_LEVEL_XP + level * LEVEL_XP_STEP
