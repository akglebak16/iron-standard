extends RefCounted

const Config = preload("res://battle/config.gd")

static func tick(battle: RefCounted) -> void:
	var active := [0, 0]
	for unit in battle.units:
		if not unit.dead and not unit.gone and not unit.fleeing:
			active[unit.side] += 1
	for unit in battle.units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero or unit.companion or unit.faction == "undead":
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
		var collapse: bool = friends <= battle.starting_units[unit.side] * Config.MORALE_FORCE_FLEE_START_SHARE and friends < enemies * Config.MORALE_FORCE_FLEE_ENEMY_SHARE and not unit.leader and battle.starting_units[unit.side] > Config.MORALE_FORCE_FLEE_MIN_START
		if unit.morale <= 0.0 or collapse:
			unit.fleeing = true
