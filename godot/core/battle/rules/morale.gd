extends RefCounted
## Morale check, once per MORALE_TICK_SECONDS (DESIGN.md 4.5). The causes from before stage 1b stay: odds of the sides,
## the collapse of a side, and the losses in State.hurt/kill (damage, deaths of neighbours, leaders, hero, companions,
## the bond of the undead to their necromancer). Stage 1b adds, the same for both sides and for player orders:
## - steps of a fighter: steady -> wavering -> fleeing -> rallied (wavering again); a wavering fighter fights worse
##   (combat.gd, block.gd, charge.gd) and does not charge far (ai_decision.gd, movement_kernel.hpp);
## - threat to a group from its flanks and rear (and an overwhelming front), read from the field assessment
##   (simulation/ai/field_assessment.gd), where terrain will join it later (TERRAIN.md 7);
## - panic: a new flight shakes the friends around, and a group loses heart by its share of fleeing men;
## - rally: a fleeing fighter nobody pursues recovers, faster near an own leader or the hero, and turns back.
## Blows from the flank and rear and cavalry charges are weighed where they land (State.hit_morale_multiplier).
const Unit = preload("res://core/battle/model/unit.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")

static func tick(battle: State) -> void:
	var motion := battle.motion
	var capacity := motion.capacity
	var flags := motion.integer_fields
	var positions := motion.positions
	var I = MotionStore.I
	var count := battle.active_units.size()
	var active := [0, 0]
	var leaders: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]
	for row in count:
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row]:
			continue
		var side: int = flags[I.SIDE * capacity + row]
		active[side] += 1
		if flags[I.LEADER * capacity + row] or flags[I.HERO * capacity + row]:
			leaders[side].append(positions[row])
	battle.active_counts = active.duplicate()
	var collapsed := [false, false]
	for side in 2:
		var friends: int = active[side]
		var enemies: float = maxf(Config.MORALE_OPPONENT_FLOOR, active[1 - side])
		collapsed[side] = friends <= battle.starting_units[side] * Config.MORALE_FORCE_FLEE_START_SHARE and friends < enemies * Config.MORALE_FORCE_FLEE_ENEMY_SHARE and battle.starting_units[side] > Config.MORALE_FORCE_FLEE_MIN_START
	var group_loss := _group_losses(battle)
	var routed: Array[Unit] = []
	var rallied := {}
	for unit: Unit in battle.active_units:
		if unit.dead or unit.gone or unit.hero or unit.companion or unit.morale_immune:
			continue
		if unit.fleeing:
			if _rout_step(battle, unit, leaders[unit.side], collapsed[unit.side]):
				rallied[battle.groups[unit.side][unit.group_kind]] = true
			continue
		var friends: int = active[unit.side]
		var enemies: float = maxf(Config.MORALE_OPPONENT_FLOOR, active[1 - unit.side])
		var odds: float = friends / enemies
		if odds < Config.MORALE_BAD_ODDS:
			unit.morale -= Config.MORALE_BAD_ODDS_LOSS
		if odds < Config.MORALE_VERY_BAD_ODDS:
			unit.morale -= Config.MORALE_VERY_BAD_ODDS_LOSS
		var slot := _slot(battle, unit)
		if slot >= 0:
			unit.morale -= group_loss[slot]
		var recovery: float = Config.MORALE_STRONG_RECOVERY if odds > Config.MORALE_STRONG_ODDS else (Config.MORALE_EVEN_RECOVERY if odds > Config.MORALE_EVEN_ODDS else Config.MORALE_WEAK_RECOVERY)
		unit.morale = minf(unit.base_morale, unit.morale + recovery)
		if unit.wavering:
			if unit.morale >= unit.base_morale * Config.MORALE_STEADY_SHARE:
				unit.wavering = false
		elif unit.morale < unit.base_morale * Config.MORALE_WAVER_SHARE:
			unit.wavering = true
			if not unit.waver_noticed:
				unit.waver_noticed = true
				battle.record_unit_notice(Event.Kind.WAVERED, unit)
		var collapse: bool = collapsed[unit.side] and not unit.leader
		if unit.morale <= 0.0 or collapse:
			unit.fleeing = true
			unit.wavering = false
			# The flight starts from nothing; a deep rout (a heavy blow) takes longer to recover from, up to a limit.
			unit.morale = clampf(unit.morale, -unit.base_morale * Config.MORALE_RALLY_SHARE, 0.0)
			battle.record_unit_notice(Event.Kind.FLED, unit)
			routed.append(unit)
	_panic(battle, routed)
	for group: Group in rallied:
		group.layout()

## Every morale check: per group (side * GROUP_KINDS + kind) the morale every ready fighter loses this check to the
## threat around it and to the flight of its own men; also writes the group's morale summary for the debug overlay.
static func _group_losses(battle: State) -> PackedFloat64Array:
	var losses := PackedFloat64Array()
	losses.resize(2 * Config.GROUP_KINDS)
	if battle.groups.size() != 2:
		return losses
	var sides: Array = FieldAssessment.assess(battle).sides
	for side in 2:
		for kind in mini(Config.GROUP_KINDS, battle.groups[side].size()):
			var summary: Dictionary = sides[side].groups[kind]
			var group: Group = battle.groups[side][kind]
			var ready: int = summary.count
			var fleeing: int = summary.fleeing
			var total := ready + fleeing
			var pressure := 0.0
			if ready > 0:
				var strength: float = maxf(summary.strength, Config.MORALE_THREAT_STRENGTH_FLOOR)
				pressure = (summary.threat_flank + summary.threat_rear * Config.MORALE_THREAT_REAR_WEIGHT) / strength + maxf(0.0, summary.threat_front / strength - Config.MORALE_THREAT_FRONT_FREE) * Config.MORALE_THREAT_FRONT_WEIGHT
			var share := float(fleeing) / total if total > 0 else 0.0
			group.morale_pressure = pressure
			group.morale_fleeing_share = share
			if share >= Config.MORALE_GROUP_ROUTED_SHARE:
				group.morale_state = Config.MORALE_GROUP_ROUTED
			elif total > 0 and summary.wavering + fleeing >= total * Config.MORALE_GROUP_WAVERING_SHARE:
				group.morale_state = Config.MORALE_GROUP_WAVERING
			else:
				group.morale_state = Config.MORALE_GROUP_STEADY
			losses[side * Config.GROUP_KINDS + kind] = Config.MORALE_THREAT_LOSS * clampf(pressure - Config.MORALE_THREAT_FREE, 0.0, Config.MORALE_THREAT_CAP) + Config.MORALE_PANIC_SHARE_LOSS * share
	return losses

static func _slot(battle: State, unit: Unit) -> int:
	if battle.groups.size() != 2 or unit.group_kind < 0 or unit.group_kind >= mini(Config.GROUP_KINDS, battle.groups[unit.side].size()):
		return -1
	return unit.side * Config.GROUP_KINDS + unit.group_kind

## A fleeing fighter: recovers unless pursued and turns back once he has recovered enough. True when he rallied.
static func _rout_step(battle: State, unit: Unit, leaders: PackedVector2Array, collapsed: bool) -> bool:
	if unit.rallies >= Config.MORALE_RALLY_LIMIT:
		return false
	var at := unit.position
	if _pursued(battle, unit.side, at):
		return false
	var recovery := Config.MORALE_ROUT_RECOVERY
	for leader in leaders:
		if leader.distance_to(at) < Config.MORALE_RALLY_LEADER_RADIUS:
			recovery += Config.MORALE_RALLY_LEADER_BONUS
			break
	unit.morale = minf(unit.base_morale, unit.morale + recovery)
	if unit.morale < unit.base_morale * Config.MORALE_RALLY_SHARE or collapsed or _slot(battle, unit) < 0:
		return false
	if at.x < Config.MORALE_RALLY_EDGE or at.x > battle.arena_size.x - Config.MORALE_RALLY_EDGE:
		return false
	unit.fleeing = false
	unit.wavering = true
	unit.rallies += 1
	battle.record_unit_notice(Event.Kind.RALLIED, unit)
	return true

## A ready enemy (not fleeing) within MORALE_PURSUIT_RADIUS.
static func _pursued(battle: State, side: int, at: Vector2) -> bool:
	var motion := battle.motion
	var capacity := motion.capacity
	var flags := motion.integer_fields
	var positions := motion.positions
	var I = MotionStore.I
	var candidates: PackedInt32Array = battle.column_backend.nearby(motion, at, Config.MORALE_PURSUIT_RADIUS) if battle.column_backend != null else PackedInt32Array(range(battle.active_units.size()))
	for row in candidates:
		if flags[I.SIDE * capacity + row] == side or flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row]:
			continue
		if positions[row].distance_to(at) < Config.MORALE_PURSUIT_RADIUS:
			return true
	return false

## Every new flight costs the ready friends within MORALE_PANIC_RADIUS MORALE_PANIC_LOSS, at most MORALE_PANIC_CAP
## per fighter and check; their own flight, if it comes, waits for the next check.
static func _panic(battle: State, routed: Array[Unit]) -> void:
	if routed.is_empty():
		return
	var motion := battle.motion
	var positions := motion.positions
	var taken := PackedFloat64Array()
	taken.resize(battle.active_units.size())
	for router in routed:
		var at := router.position
		var candidates: PackedInt32Array = battle.column_backend.nearby(motion, at, Config.MORALE_PANIC_RADIUS) if battle.column_backend != null else PackedInt32Array(range(battle.active_units.size()))
		for row in candidates:
			var unit: Unit = battle.active_units[row]
			if unit.side != router.side or unit.dead or unit.gone or unit.fleeing or unit.hero or unit.companion or unit.morale_immune:
				continue
			if positions[row].distance_to(at) > Config.MORALE_PANIC_RADIUS:
				continue
			var loss := minf(Config.MORALE_PANIC_LOSS, Config.MORALE_PANIC_CAP - taken[row])
			if loss <= 0.0:
				continue
			taken[row] += loss
			unit.morale -= loss

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
