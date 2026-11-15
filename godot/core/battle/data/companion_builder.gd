extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const HeroStats = preload("res://core/battle/data/hero_stats.gd")

static func spawn(state: State, profile: Dictionary, gear: Dictionary, effects: Dictionary, rng: RandomNumberGenerator) -> Unit:
	var unit := Unit.new(state.allocate_unit_id(), 0, Vector2.ZERO, 0.0, 0.0, Config.COMPANION_TIER)
	unit.companion_id = profile.id
	unit.troop_id = Config.COMPANION_TROOP_PREFIX + unit.companion_id
	unit.name = profile.name
	unit.perk_effects = effects
	if not HeroStats.apply(unit, profile, gear):
		return null
	unit.melee_reach = Config.DEFAULT_MELEE_REACH + Config.HERO_WEAPON_BASE_REACH + float(gear.weapon.get("reach", 0.0))
	unit.attack_cooldown = rng.randf_range(0.0, Config.AI_INITIAL_ATTACK_COOLDOWN_MAX)
	unit.target_timer = rng.randf_range(0.0, Config.RETARGET_INITIAL_MAX_SECONDS)
	unit.base_morale = Config.COMPANION_BASE_MORALE
	unit.morale = unit.base_morale
	var group := Config.GROUP_INFANTRY
	if unit.mounted:
		group = Config.GROUP_CAVALRY
	elif unit.attack_range > 0.0:
		group = Config.GROUP_ARCHERS
	state.add_grouped_unit(unit, group)
	return unit
