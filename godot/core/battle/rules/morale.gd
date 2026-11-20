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
# Cell of the local grids for pursuit and panic: not smaller than MORALE_PURSUIT_RADIUS and MORALE_PANIC_RADIUS, so the
# 3 x 3 cells around a point hold everyone within either radius. A rout of a dense block must not query every neighbour.
const CELL := 150.0

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
	# Odds of each side, as before stage 1b: the same for every fighter of the side.
	var bad := [false, false]
	var very_bad := [false, false]
	var recoveries := [0.0, 0.0]
	for side in 2:
		var odds: float = active[side] / maxf(Config.MORALE_OPPONENT_FLOOR, active[1 - side])
		bad[side] = odds < Config.MORALE_BAD_ODDS
		very_bad[side] = odds < Config.MORALE_VERY_BAD_ODDS
		recoveries[side] = Config.MORALE_STRONG_RECOVERY if odds > Config.MORALE_STRONG_ODDS else (Config.MORALE_EVEN_RECOVERY if odds > Config.MORALE_EVEN_ODDS else Config.MORALE_WEAK_RECOVERY)
	var grouped := battle.groups.size() >= 2
	var pursuers: Array = [] # Lazily: per side, a grid of its live fighters (Morale._pursued).
	var routed: Array[Unit] = []
	var rallied := {}
	# Flags from the columns, not Unit getters: this runs over every fighter once a second.
	var units := battle.active_units
	for row in count:
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var unit: Unit = units[row]
		if unit.morale_immune or not unit.companion_id.is_empty():
			continue
		var side: int = flags[I.SIDE * capacity + row]
		var kind: int = flags[I.GROUP_KIND * capacity + row]
		var slot := side * Config.GROUP_KINDS + kind if grouped and kind >= 0 and kind < Config.GROUP_KINDS else -1
		if flags[I.FLEEING * capacity + row]:
			if _rout_step(battle, unit, leaders[side], collapsed[side], slot >= 0, pursuers) and slot >= 0:
				rallied[battle.groups[flags[I.COMMAND * capacity + row]][kind]] = true
			continue
		if bad[side]:
			unit.morale -= Config.MORALE_BAD_ODDS_LOSS
		if very_bad[side]:
			unit.morale -= Config.MORALE_VERY_BAD_ODDS_LOSS
		if slot >= 0:
			unit.morale -= group_loss[slot]
		var base: float = unit.base_morale
		var morale: float = minf(base, unit.morale + recoveries[side])
		unit.morale = morale
		var wavering_at: int = I.WAVERING * capacity + row
		if flags[wavering_at]:
			if morale >= base * Config.MORALE_STEADY_SHARE:
				flags[wavering_at] = 0
		elif morale < base * Config.MORALE_WAVER_SHARE:
			flags[wavering_at] = 1
			if not unit.waver_noticed:
				unit.waver_noticed = true
				battle.record_unit_notice(Event.Kind.WAVERED, unit)
		var collapse: bool = collapsed[side] and not flags[I.LEADER * capacity + row]
		if morale <= 0.0 or collapse:
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
## The player's allies (#243) share the pressure of the player's group of their kind: they stand on the same side.
static func _group_losses(battle: State) -> PackedFloat64Array:
	var losses := PackedFloat64Array()
	losses.resize(2 * Config.GROUP_KINDS)
	if battle.groups.size() < 2:
		return losses
	battle.assessment = FieldAssessment.assess(battle) # Kept for the commanders (stage 1g): no pass of their own.
	battle.assessment_serial += 1
	var sides: Array = battle.assessment.sides
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

## A fleeing fighter: recovers unless pursued and turns back once he has recovered enough (only into a group). True when
## he rallied.
static func _rout_step(battle: State, unit: Unit, leaders: PackedVector2Array, collapsed: bool, grouped: bool, pursuers: Array) -> bool:
	if unit.rallies >= Config.MORALE_RALLY_LIMIT:
		return false
	var at := unit.position
	if pursuers.is_empty():
		pursuers.append_array(_side_grids(battle))
	if _pursued(battle, pursuers[1 - unit.side], at):
		return false
	var recovery := Config.MORALE_ROUT_RECOVERY
	for leader in leaders:
		if leader.distance_to(at) < Config.MORALE_RALLY_LEADER_RADIUS:
			recovery += Config.MORALE_RALLY_LEADER_BONUS
			break
	unit.morale = minf(unit.base_morale, unit.morale + recovery)
	if unit.morale < unit.base_morale * Config.MORALE_RALLY_SHARE or collapsed or not grouped:
		return false
	if at.x < Config.MORALE_RALLY_EDGE or at.x > battle.arena_size.x - Config.MORALE_RALLY_EDGE:
		return false
	unit.fleeing = false
	unit.wavering = true
	unit.rallies += 1
	battle.record_unit_notice(Event.Kind.RALLIED, unit)
	return true

static func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))

static func _put(grid: Dictionary, cell: Vector2i, value) -> void:
	var bucket = grid.get(cell)
	if bucket == null:
		grid[cell] = [value]
	else:
		bucket.append(value)

## Rows of the live fighters (not dead or gone) of each side by cell; whether one is ready is read when asked.
static func _side_grids(battle: State) -> Array:
	var flags := battle.motion.integer_fields
	var capacity := battle.motion.capacity
	var positions := battle.motion.positions
	var I = MotionStore.I
	var grids := [{}, {}]
	for row in battle.active_units.size():
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row]:
			continue
		_put(grids[flags[I.SIDE * capacity + row]], _cell(positions[row]), row)
	return grids

## A ready enemy (not fleeing) within MORALE_PURSUIT_RADIUS; `enemies` is the grid of the other side.
static func _pursued(battle: State, enemies: Dictionary, at: Vector2) -> bool:
	var flags := battle.motion.integer_fields
	var capacity := battle.motion.capacity
	var positions := battle.motion.positions
	var fleeing: int = MotionStore.I.FLEEING * capacity
	var center := _cell(at)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var bucket = enemies.get(center + Vector2i(dx, dy))
			if bucket == null:
				continue
			for row: int in bucket:
				if not flags[fleeing + row] and positions[row].distance_to(at) < Config.MORALE_PURSUIT_RADIUS:
					return true
	return false

## Every new flight costs the ready friends within MORALE_PANIC_RADIUS MORALE_PANIC_LOSS, at most MORALE_PANIC_CAP
## per fighter and check; their own flight, if it comes, waits for the next check. Counted per friend near a flight
## (cells next to a fugitive's cell), with the same subtractions as one fugitive after another.
static func _panic(battle: State, routed: Array[Unit]) -> void:
	if routed.is_empty():
		return
	var flags := battle.motion.integer_fields
	var capacity := battle.motion.capacity
	var positions := battle.motion.positions
	var I = MotionStore.I
	var routers := [{}, {}]
	var near := [{}, {}] # Cells within one cell of a fugitive's cell.
	for router in routed:
		var at := router.position
		var cell := _cell(at)
		_put(routers[router.side], cell, at)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				near[router.side][cell + Vector2i(dx, dy)] = true
	var units := battle.active_units
	for row in units.size():
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var side: int = flags[I.SIDE * capacity + row]
		var at := positions[row]
		var center := _cell(at)
		if not near[side].has(center):
			continue
		var unit: Unit = units[row]
		if unit.morale_immune or not unit.companion_id.is_empty():
			continue
		var taken := 0.0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var bucket = routers[side].get(center + Vector2i(dx, dy))
				if bucket == null:
					continue
				for from: Vector2 in bucket:
					if taken >= Config.MORALE_PANIC_CAP:
						break
					if at.distance_to(from) > Config.MORALE_PANIC_RADIUS:
						continue
					var loss := minf(Config.MORALE_PANIC_LOSS, Config.MORALE_PANIC_CAP - taken)
					taken += loss
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
