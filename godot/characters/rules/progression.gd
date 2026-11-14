extends RefCounted

const BASE_LEVEL_XP := 100
const LEVEL_XP_STEP := 80
const XP_PER_EXTRA_INTELLIGENCE := 0.03
const HERO_ATTRIBUTE_POINTS := 2
const HERO_PERK_POINTS := 1

static func xp_multiplier(profile: Dictionary, xp_bonus: float) -> float:
	var intelligence := float(profile.get("int", 1))
	if intelligence == 0:
		intelligence = 1
	return 1.0 + (intelligence - 1.0) * XP_PER_EXTRA_INTELLIGENCE + xp_bonus

## Updates a caller-owned profile and returns the number of levels gained.
static func gain_hero_xp(profile: Dictionary, amount: int) -> int:
	profile.xp = int(profile.get("xp", 0)) + amount
	profile.lvl = int(profile.get("lvl", 1))
	var gained := 0
	while profile.xp >= _level_cost(profile.lvl):
		profile.xp -= _level_cost(profile.lvl)
		profile.lvl += 1
		gained += 1
	profile.pts = int(profile.get("pts", 0)) + gained * HERO_ATTRIBUTE_POINTS
	profile.pp = int(profile.get("pp", 0)) + gained * HERO_PERK_POINTS
	return gained

static func _level_cost(level: int) -> int:
	return BASE_LEVEL_XP + level * LEVEL_XP_STEP
