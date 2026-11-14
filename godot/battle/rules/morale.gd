extends RefCounted
const Unit = preload("res://battle/model/unit.gd")

const State = preload("res://battle/model/state.gd")
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")

static func tick(battle: State) -> void:
	var active := [0, 0]
	for unit: Unit in battle.units:
		if not unit.dead and not unit.gone and not unit.fleeing:
			active[unit.side] += 1
	battle.active_counts = active.duplicate()
	for unit: Unit in battle.units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero or unit.companion or unit.morale_immune:
			continue
		var friends: int = active[unit.side]
		var enemies: float = maxf(Config.MORALE_OPPONENT_FLOOR, active[1 - unit.side])
		var odds: float = friends / enemies
		if odds < Config.MORALE_BAD_ODDS:
			unit.morale -= Config.MORALE_BAD_ODDS_LOSS
		if odds < Config.MORALE_VERY_BAD_ODDS:
			unit.morale -= Config.MORALE_VERY_BAD_ODDS_LOSS
		var recovery: float = Config.MORALE_STRONG_RECOVERY if odds > Config.MORALE_STRONG_ODDS else (Config.MORALE_EVEN_RECOVERY if odds > Config.MORALE_EVEN_ODDS else Config.MORALE_WEAK_RECOVERY)
		unit.morale = minf(unit.base_morale, unit.morale + recovery)
		if not unit.wavering and unit.morale < Config.MORALE_WAVER_THRESHOLD:
			unit.wavering = true
			battle.record_unit_notice(Event.Kind.WAVERED, unit)
		var collapse: bool = friends <= battle.starting_units[unit.side] * Config.MORALE_FORCE_FLEE_START_SHARE and friends < enemies * Config.MORALE_FORCE_FLEE_ENEMY_SHARE and not unit.leader and battle.starting_units[unit.side] > Config.MORALE_FORCE_FLEE_MIN_START
		if unit.morale <= 0.0 or collapse:
			unit.fleeing = true
			battle.record_unit_notice(Event.Kind.FLED, unit)

static func advance(battle: State, dt: float) -> bool:
	if dt <= 0.0:
		return false
	battle.morale_timer -= dt
	var checked := false
	while battle.morale_timer <= 0.0:
		tick(battle)
		checked = true
		battle.morale_timer += Config.MORALE_TICK_SECONDS
	return checked
