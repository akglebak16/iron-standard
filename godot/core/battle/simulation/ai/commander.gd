extends RefCounted
## Army commander, stage 1g part 1 (DESIGN.md 4.2, decisions 49–57, issue #266): the "commander" AI profile next to the
## frozen "reference" brain (rules/tactics.gd). The brain contract of profiles.gd: enemy_step(battle, command, elapsed,
## dt) for a field battle; siege_step is the reference siege brain until stage 1d.
##
## Decision and execution are apart (decision 50):
## - a decision, on the command's own tick of the decision schedule (every AI_COMMANDER_PERIOD_SECONDS, from
##   AI_GROUP_ADVANCE_DELAY_SECONDS on), scores the plans, keeps the best and gives every group a task: the point its
##   centre marches to, the speed, the point it faces and how close the enemy must be for it to charge;
## - the execution, every tick and O(groups), moves the group centre towards its task point and starts the charge
##   once the enemy is that close. So the battle does not depend on the decisions being rare (decision 10).
## Inputs are summaries only (decision 51): the field assessment the morale check keeps in State (at most 1 s old), the
## squad picture of the reference brain (stage K scan every AI_SQUAD_SCAN_SECONDS, sampled), the constant summary of a
## group (its range and mean speed, Group.enlist) and the waiting reserve. No pass over the fighters, no RNG.
##
## Part 1 has one plan, the attack (DESIGN.md 4.2.3): the infantry line marches at AI_INFANTRY_ADVANCE_SPEED while out of
## reach of the enemy shooters and at AI_CMD_UNDER_FIRE_SPEED_SHARE of its own mean speed within their reach (or while
## the side loses men to missiles), and charges the nearest squad at AI_INFANTRY_CHARGE_DISTANCE, with no timer; the
## archers follow and stand at AI_CMD_ARCHER_RANGE_SHARE of their range from the nearest enemy squad, at most
## AI_CMD_ARCHER_LINE_GAP behind their own line; the cavalry flanks as the reference brain does (part 4, #269, changes
## that). The defence, waiting and retreat plans, the plan switch and patience come with part 2 (#267).
##
## The command decides for itself which side it is on (State.side_of): the same code leads either side (4.2.9).
## Trace codes (ADR-022) are written only while State.ai_trace is set and are translated by presentation; the codes
## shared with the reference brain keep its values.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const DecisionSchedule = preload("res://core/battle/simulation/ai/decision_schedule.gd")
const DecisionTrace = preload("res://core/battle/simulation/ai/decision_trace.gd")

const PLAN_DEPLOY := Tactics.PLAN_DEPLOY
const PLAN_ATTACK := "attack"
const DECISION_WAIT := Tactics.DECISION_WAIT
const DECISION_ADVANCE := Tactics.DECISION_ADVANCE
const DECISION_STAND := Tactics.DECISION_STAND
const DECISION_CHARGE := Tactics.DECISION_CHARGE
const DECISION_FLANK := Tactics.DECISION_FLANK
const REASON_DEPLOYING := Tactics.REASON_DEPLOYING
const REASON_SQUAD_IN_REACH := Tactics.REASON_SQUAD_IN_REACH
const REASON_FIGHTER_IN_REACH := Tactics.REASON_FIGHTER_IN_REACH
const REASON_CONTACT_AFTER_CALL_OFF := Tactics.REASON_CONTACT_AFTER_CALL_OFF
const REASON_ENEMY_CLOSE := Tactics.REASON_ENEMY_CLOSE
const REASON_NO_INFANTRY := Tactics.REASON_NO_INFANTRY
const REASON_IN_RANGE := Tactics.REASON_IN_RANGE
const REASON_FLANK_TIMER := Tactics.REASON_FLANK_TIMER
const REASON_WAYPOINT_REACHED := Tactics.REASON_WAYPOINT_REACHED
const REASON_ON_FLANK_WAY := "on_flank_way" # Cavalry rides to its flank waypoint.
const REASON_OUT_OF_FIRE := "out_of_fire" # The line marches in formation, out of reach of the enemy shooters.
const REASON_UNDER_FIRE := "under_fire" # The line hurries through the reach of the enemy shooters.
const REASON_TO_RANGE := "to_range" # Archers walk up to their shooting distance.
const REASON_WITH_LINE := "with_line" # Archers keep up with their own line.
const REASON_OUTSHOT := "outshot" # Plan reason: the enemy shooters are stronger, walking in beats standing.
const REASON_STRONGER := "stronger" # Plan reason: the side is clearly stronger.
const REASON_ONLY_PLAN := "only_plan" # Plan reason: no other plan in this part (defence and waiting come with part 2).

## A group's task from the latest decision, executed every tick.
class Task:
	var active := false # False: the group is left alone (charging, no men, or before the first decision).
	var point := Vector2.INF # Where the centre marches; INF: it stays.
	var on_waypoint := false # March on Group.waypoint instead (the terrain doctrine may move it between decisions).
	var speed := 0.0
	var face := Vector2.INF # What the group faces; INF: the way it marches.
	var charge_within := INF # Charges once the enemy is closer than this...
	var fighters := false # ...measured to the nearest fighter (true) or to the nearest squad (the reference measure).
	var arrival := -1.0 # Also charges within this of its point (the cavalry at its flank waypoint).

	func clear() -> void:
		active = false
		point = Vector2.INF
		on_waypoint = false
		speed = 0.0
		face = Vector2.INF
		charge_within = INF
		fighters = false
		arrival = -1.0

## The commander's state for one command, kept in State.commanders.
class Mind:
	var schedule := DecisionSchedule.new()
	var steps := -1 # enemy_step calls so far: the commander's own tick count for the schedule.
	var plan := PLAN_DEPLOY
	var plan_since := 0.0
	var decisions := 0
	var best: Array[Dictionary] = [] # The two best plans of the latest decision: {"plan", "score"}.
	var reason := ""
	var ratio := 1.0 # Strength ratio R at the latest decision.
	var outshot := 0.0 # Outshot F at the latest decision.
	var squads := false # The enemy has squads (stage K): charges are measured to squads, not to single fighters.
	var tasks: Array[Task] = []
	var _reserve_sizes := PackedInt32Array([-1, -1])
	var _reserve_strength := PackedFloat64Array([0.0, 0.0])

	func _init() -> void:
		for kind in Config.GROUP_KINDS:
			tasks.append(Task.new())

	## Strength of the figures still waiting off the field: weight 1, full health, by tier (FieldAssessment), counted
	## again only when a wave has taken some of them.
	func reserve_strength(battle: State, side: int) -> float:
		var waiting: Array = battle.reserve[side]
		if waiting.size() != _reserve_sizes[side]:
			var total := 0.0
			for troop_id in waiting:
				var troop: Dictionary = battle.reserve_definitions.get(troop_id, {})
				total += 1.0 + Config.AI_FIELD_TIER_POWER * int(troop.get("tier", 0))
			_reserve_sizes[side] = waiting.size()
			_reserve_strength[side] = total
		return _reserve_strength[side]

static func mind_of(battle: State, command: int) -> Mind:
	var mind: Mind = battle.commanders[command]
	if mind == null:
		mind = Mind.new()
		battle.commanders[command] = mind
	return mind

static func enemy_step(battle: State, command: int, elapsed: float, dt: float) -> void:
	var mind := mind_of(battle, command)
	mind.steps += 1
	battle.ai_scan_timers[command] -= dt
	if battle.ai_scan_timers[command] <= 0.0:
		battle.ai_scan_timers[command] = Config.AI_SQUAD_SCAN_SECONDS
		Tactics._scan(battle, command) # The reference brain's squad picture and kite check (stage K), shared.
	if elapsed <= Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
		var trace := _trace(battle, command)
		if trace != null:
			var side := State.side_of(command)
			trace.set_plan(side, PLAN_DEPLOY)
			for kind in Config.GROUP_KINDS:
				trace.record(side, kind, DECISION_WAIT, REASON_DEPLOYING)
		return
	if mind.decisions == 0 or mind.schedule.commander_due(command, mind.steps):
		decide(battle, command, elapsed)
	execute(battle, command, dt)

## The reference siege brain until stage 1d.
static func siege_step(battle: State, elapsed: float, dt: float = 0.0) -> void:
	Tactics.siege_step(battle, elapsed, dt)

## One decision: plan scores, the best plan and the tasks of the groups.
static func decide(battle: State, command: int, elapsed: float) -> void:
	var mind := mind_of(battle, command)
	var side := State.side_of(command)
	var foe := battle.centroid(1 - side)
	if foe == Vector2.INF:
		return
	mind.decisions += 1
	_score(battle, side, mind)
	var plan: String = mind.best[0].plan
	if plan != mind.plan:
		mind.plan = plan
		mind.plan_since = elapsed
	var foe_groups: Array = battle.foe_groups(command)
	mind.squads = Tactics._has_squads(foe_groups)
	_attack(battle, command, mind, foe, foe_groups, elapsed)
	var trace := _trace(battle, command)
	if trace != null:
		trace.set_plan(side, mind.plan, {"best": mind.best.duplicate(true), "reason": mind.reason, "ratio": mind.ratio,
			"outshot": mind.outshot, "since": mind.plan_since, "decisions": mind.decisions})

## Every tick, O(groups): the centres march on their task points, a group charges once the enemy is close enough.
static func execute(battle: State, command: int, dt: float) -> void:
	var mind := mind_of(battle, command)
	for kind in Config.GROUP_KINDS:
		var task: Task = mind.tasks[kind]
		if not task.active:
			continue
		var group: Group = battle.groups[command][kind]
		if group.order == Config.ORDER_CHARGE:
			task.active = false
			continue
		var point := group.waypoint if task.on_waypoint else task.point
		if point.is_finite():
			var offset := point - group.center
			var remaining := offset.length()
			var stride := task.speed * dt
			if remaining <= stride:
				group.center = point
			elif remaining > 0.0:
				group.center += offset / remaining * stride
		var face := task.face if task.face.is_finite() else point
		if face.is_finite() and face != group.center:
			group.direction = (face - group.center).angle()
		var reason := _charge_reason(battle, command, group, task, point, mind.squads)
		if not reason.is_empty():
			_charge(battle, command, group, reason)
			task.active = false

## Plan scores (DESIGN.md 4.2.3) from the field assessment of the latest morale check. Part 1 has only the attack:
##   attack = ramp(R; AI_CMD_ATTACK_RATIO), raised under fire (F above the first AI_CMD_OUTSHOT value, R at least
##   AI_CMD_OUTSHOT_MIN_RATIO) to AI_CMD_OUTSHOT_FLOOR x ramp(F; AI_CMD_OUTSHOT).
## The position P is 0 until part 8 (#273), the patience T comes with part 2.
static func _score(battle: State, side: int, mind: Mind) -> void:
	mind.ratio = strength_ratio(battle, side, mind)
	mind.outshot = outshot(battle.assessment, side)
	var by_ratio := ramp(mind.ratio, Config.AI_CMD_ATTACK_RATIO[0], Config.AI_CMD_ATTACK_RATIO[1])
	var attack := by_ratio
	mind.reason = REASON_ONLY_PLAN
	if mind.outshot > Config.AI_CMD_OUTSHOT[0] and mind.ratio >= Config.AI_CMD_OUTSHOT_MIN_RATIO:
		var floor_value: float = Config.AI_CMD_OUTSHOT_FLOOR * ramp(mind.outshot, Config.AI_CMD_OUTSHOT[0], Config.AI_CMD_OUTSHOT[1])
		if floor_value > attack:
			attack = floor_value
			mind.reason = REASON_OUTSHOT
	if mind.reason == REASON_ONLY_PLAN and by_ratio >= 1.0:
		mind.reason = REASON_STRONGER
	var scores: Array[Dictionary] = [{"plan": PLAN_ATTACK, "score": attack}]
	scores.sort_custom(func(a: Dictionary, b: Dictionary): return a.score > b.score)
	mind.best.assign(scores.slice(0, 2))

## R: own strength over the enemy's (field assessment: weight x health x tier), each with AI_CMD_RESERVE_WEIGHT of its
## waiting reserve; 1 before the first assessment.
static func strength_ratio(battle: State, side: int, mind: Mind) -> float:
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() < 2:
		return 1.0
	var own: float = sides[side].strength + Config.AI_CMD_RESERVE_WEIGHT * mind.reserve_strength(battle, side)
	var enemy: float = sides[1 - side].strength + Config.AI_CMD_RESERVE_WEIGHT * mind.reserve_strength(battle, 1 - side)
	if enemy <= 0.0:
		return INF if own > 0.0 else 1.0
	return own / enemy

## F: (enemy shooters' strength - own) / the larger of the two, from -1 to 1; above 0 the side is outshot.
static func outshot(assessment: Dictionary, side: int) -> float:
	var sides: Array = assessment.get("sides", [])
	if sides.size() < 2:
		return 0.0
	var own := _shooters(sides[side])
	var enemy := _shooters(sides[1 - side])
	var larger := maxf(own, enemy)
	return (enemy - own) / larger if larger > 0.0 else 0.0

static func _shooters(side_summary: Dictionary) -> float:
	var total := 0.0
	for group: Dictionary in side_summary.groups:
		var strength: PackedFloat64Array = group.class_strength
		total += strength[Config.AI_CLASS_ARCHER] + strength[Config.AI_CLASS_HORSE_ARCHER]
	return total

## 0 at `from`, 1 at `to`, linear in between and clipped; `from` may be above `to` (a falling ramp).
static func ramp(value: float, from: float, to: float) -> float:
	if from == to:
		return 1.0 if value >= to else 0.0
	return clampf((value - from) / (to - from), 0.0, 1.0)

## The attack plan: tasks of the three groups.
static func _attack(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array, elapsed: float) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var groups: Array = battle.groups[command]
	var infantry: Group = groups[Config.GROUP_INFANTRY]
	var archers: Group = groups[Config.GROUP_ARCHERS]
	var cavalry: Group = groups[Config.GROUP_CAVALRY]
	var has_infantry := infantry.has_active_units()
	var objective := Tactics._objective(infantry, foe_groups, foe)
	# Infantry: a line on the nearest squad (or its focus after a hopeless chase), quick under fire, charging in reach.
	var task: Task = mind.tasks[Config.GROUP_INFANTRY]
	task.clear()
	if has_infantry and infantry.order != Config.ORDER_CHARGE:
		var fire := under_fire(battle, side, infantry.center, foe_groups)
		task.active = true
		task.point = objective
		task.face = objective
		task.speed = march_speed(infantry, fire, Config.AI_INFANTRY_ADVANCE_SPEED)
		task.charge_within = Config.AI_KITE_RECHARGE_DISTANCE if infantry.kited else Config.AI_INFANTRY_CHARGE_DISTANCE
		if trace != null:
			trace.record(side, Config.GROUP_INFANTRY, DECISION_ADVANCE, REASON_UNDER_FIRE if fire else REASON_OUT_OF_FIRE,
				{"speed": task.speed, "focus_kind": infantry.focus_kind})
	# Archers: up to their shooting distance from the nearest enemy squad, not far behind their line.
	task = mind.tasks[Config.GROUP_ARCHERS]
	task.clear()
	if archers.order != Config.ORDER_CHARGE and archers.has_active_units():
		task.active = true
		task.charge_within = Config.AI_ARCHER_CHARGE_DISTANCE if has_infantry else Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE
		var near := nearest_squad_point(foe_groups, archers.center)
		var aim := near if near.is_finite() else foe
		var reach := archers.reach if archers.reach > 0.0 else Config.AI_ARCHER_ADVANCE_DISTANCE
		var gap := archers.center.distance_to(aim)
		var point := archers.center
		var reason := REASON_IN_RANGE
		if gap > reach * Config.AI_CMD_ARCHER_RANGE_SHARE:
			point += (aim - archers.center) / gap * (gap - reach * Config.AI_CMD_ARCHER_RANGE_SHARE)
			reason = REASON_TO_RANGE
		if has_infantry:
			# Behind the line: at most AI_CMD_ARCHER_LINE_GAP and, while the line has not charged, at least
			# ARCHER_REAR_OFFSET (where they deploy), never stepping back for it.
			var line := _line_center(battle, side, infantry)
			var forward := (objective - line).normalized() if objective.is_finite() and objective != line else Vector2.ZERO
			var behind := (line - point).dot(forward)
			if behind > Config.AI_CMD_ARCHER_LINE_GAP and infantry.order != Config.ORDER_CHARGE:
				point += forward * (behind - Config.AI_CMD_ARCHER_LINE_GAP)
				reason = REASON_WITH_LINE
			elif behind < Config.ARCHER_REAR_OFFSET and infantry.order != Config.ORDER_CHARGE and point != archers.center:
				point -= forward * (Config.ARCHER_REAR_OFFSET - behind)
				if (point - archers.center).dot(forward) <= 0.0:
					point = archers.center
				reason = REASON_WITH_LINE
		# Stage Р3: archers on the high ground or a forest edge the doctrine chose stay there while in range.
		if archers.post.is_finite() and archers.center == archers.post and gap <= reach:
			point = archers.center
			reason = REASON_IN_RANGE
		var fire := under_fire(battle, side, archers.center, foe_groups)
		task.point = point if point != archers.center else Vector2.INF
		task.face = aim
		task.speed = march_speed(archers, fire, Config.AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED if has_infantry else Config.AI_ARCHER_ADVANCE_ALONE_SPEED)
		if trace != null:
			trace.record(side, Config.GROUP_ARCHERS, DECISION_ADVANCE if task.point.is_finite() else DECISION_STAND, reason,
				{"distance": gap, "speed": task.speed})
	# Cavalry: the reference flank (part 4, #269, chooses the weak edge, hunts shooters and keeps a reserve).
	task = mind.tasks[Config.GROUP_CAVALRY]
	task.clear()
	if cavalry.order == Config.ORDER_CHARGE or not cavalry.has_active_units():
		return
	if cavalry.tactic_state == Config.AI_TACTIC_WAIT:
		if elapsed <= Config.AI_CAVALRY_FLANK_DELAY_SECONDS:
			if trace != null:
				trace.record(side, Config.GROUP_CAVALRY, DECISION_WAIT, REASON_DEPLOYING)
			return
		var own := battle.centroid(side)
		if own == Vector2.INF:
			return
		cavalry.tactic_state = Config.AI_TACTIC_FLANK
		var flank_side := 1.0 if cavalry.center.y >= battle.arena_size.y * 0.5 else -1.0
		cavalry.waypoint = Vector2(lerpf(own.x, foe.x, Config.AI_CAVALRY_FLANK_PROGRESS), clampf(foe.y + flank_side * Config.AI_CAVALRY_FLANK_OFFSET, Config.AI_CAVALRY_FLANK_EDGE, battle.arena_size.y - Config.AI_CAVALRY_FLANK_EDGE))
		if trace != null:
			trace.record(side, Config.GROUP_CAVALRY, DECISION_FLANK, REASON_FLANK_TIMER, {"waypoint": cavalry.waypoint, "flank_side": flank_side})
	elif trace != null:
		trace.record(side, Config.GROUP_CAVALRY, DECISION_FLANK, REASON_ON_FLANK_WAY, {"waypoint": cavalry.waypoint})
	task.active = true
	task.on_waypoint = true
	task.speed = Config.AI_CAVALRY_FLANK_SPEED
	task.charge_within = Config.AI_CAVALRY_CHARGE_DISTANCE
	task.fighters = true
	task.arrival = Config.AI_CAVALRY_WAYPOINT_ARRIVAL

## Within reach of an enemy squad's shooters (its sampled fighters, the group's longest range), or losing men to missiles.
static func under_fire(battle: State, side: int, at: Vector2, foe_groups: Array) -> bool:
	if battle.missile_losses[side] >= Config.AI_MISSILE_PRESSURE_LOSSES:
		return true
	for foe: Group in foe_groups:
		if foe.reach <= 0.0 or foe.scan_count < Config.AI_SQUAD_MIN_UNITS:
			continue
		var reach_squared := foe.reach * foe.reach
		for point in foe.scan_points:
			if at.distance_squared_to(point) <= reach_squared:
				return true
	return false

## Marching speed of a group: `calm` out of fire, AI_CMD_UNDER_FIRE_SPEED_SHARE of its mean speed under fire (never slower).
static func march_speed(group: Group, fire: bool, calm: float) -> float:
	return maxf(calm, Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * group.mean_speed()) if fire else calm

## The enemy squads' sampled fighter nearest to `point` (stage K squad picture); INF without squads.
static func nearest_squad_point(foe_groups: Array, point: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for foe: Group in foe_groups:
		if foe.scan_count < Config.AI_SQUAD_MIN_UNITS:
			continue
		for at in foe.scan_points:
			var distance := point.distance_squared_to(at)
			if distance < best_distance:
				best_distance = distance
				best = at
	return best

## Where the own infantry line stands: its men's mean position at the latest assessment, its centre without one.
static func _line_center(battle: State, side: int, infantry: Group) -> Vector2:
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() > side and infantry.side == side:
		var summary: Dictionary = sides[side].groups[Config.GROUP_INFANTRY]
		if summary.count > 0 and Vector2(summary.center).is_finite():
			return summary.center
	return infantry.center

## The trace code of the charge that starts now, or "" while the enemy is not close enough.
static func _charge_reason(battle: State, command: int, group: Group, task: Task, point: Vector2, squads: bool) -> String:
	if task.arrival >= 0.0 and point.is_finite() and group.center.distance_to(point) < task.arrival:
		return REASON_WAYPOINT_REACHED
	if task.charge_within == INF:
		return ""
	var side := State.side_of(command)
	var distance: float
	if task.fighters:
		distance = Tactics._nearest_foe_distance(battle, group.center, 1 - side)
	else:
		distance = Tactics._charge_distance(battle, group, side, squads)
	if distance >= task.charge_within:
		return ""
	match group.kind:
		Config.GROUP_INFANTRY:
			return REASON_CONTACT_AFTER_CALL_OFF if group.kited else (REASON_SQUAD_IN_REACH if squads else REASON_FIGHTER_IN_REACH)
		Config.GROUP_ARCHERS:
			return REASON_ENEMY_CLOSE if distance < Config.AI_ARCHER_CHARGE_DISTANCE else REASON_NO_INFANTRY
	return REASON_ENEMY_CLOSE

static func _charge(battle: State, command: int, group: Group, reason: String) -> void:
	group.order = Config.ORDER_CHARGE
	if group.kind == Config.GROUP_INFANTRY and command == Config.COMMAND_ENEMY:
		battle.record_notice(Event.Kind.ENEMY_CHARGE)
	var trace := _trace(battle, command)
	if trace != null:
		trace.record(State.side_of(command), group.kind, DECISION_CHARGE, reason, {"distance": group.squad_distance})

## Where the commander of `command` sends the group of `kind` now (the debug overlay); INF without a commander or a task.
static func task_point(battle: State, command: int, kind: int) -> Vector2:
	var mind: Mind = battle.commanders[command] if command < battle.commanders.size() else null
	if mind == null or not mind.tasks[kind].active:
		return Vector2.INF
	var task: Task = mind.tasks[kind]
	return battle.groups[command][kind].waypoint if task.on_waypoint else task.point

## The debug trace is kept per side; the allies (#243) are not traced, as with the reference brain.
static func _trace(battle: State, command: int) -> DecisionTrace:
	return battle.ai_trace if command != Config.COMMAND_ALLY else null
