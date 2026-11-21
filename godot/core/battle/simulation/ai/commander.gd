extends RefCounted
## Army commander, stage 1g parts 1–2 (DESIGN.md 4.2, decisions 49–57 and 66–71, #266, #267): the "commander" AI profile next to the
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
## Plans (DESIGN.md 4.2.3), scored from the strength ratio R, the outshot F, the position P (0 until part 8), the
## patience T and whether the enemy comes:
## - attack (part 1): the infantry line marches at AI_INFANTRY_ADVANCE_SPEED while out of reach of the enemy shooters and
##   at AI_CMD_UNDER_FIRE_SPEED_SHARE of its own mean speed within their reach (or while the side loses men to
##   missiles), and charges the nearest squad at AI_INFANTRY_CHARGE_DISTANCE, with no timer; the archers follow and
##   stand at AI_CMD_ARCHER_RANGE_SHARE of their range from the nearest enemy squad, at most AI_CMD_ARCHER_LINE_GAP
##   behind their own line; the cavalry flanks as the reference brain does (part 4, #269, changes that);
## - defence (part 2): the line holds where it stands (its deployment line at the start), the archers behind it, the
##   cavalry in reserve on its deployment flank; the cavalry counter-charges once the enemy is bound by the line or rides
##   within its charge distance;
## - waiting (part 2): the own shooters are stronger; the line walks up only until its archers, behind it, reach the
##   nearest enemy squad, and stands; the cavalry in reserve.
## The plan is kept AI_CMD_PLAN_HOLD_SECONDS and gives way only to one scored AI_CMD_SWITCH_MARGIN higher; a side with a
## group bound by the fight does not leave the attack. Patience grows while the side holds or waits and the enemy does
## not come; it weakens both and raises the attack of a side not weaker than AI_CMD_PATIENCE_RATIO. Leaving the attack
## calls off the charge of every group not yet bound by the fight: it re-forms where its men stand (the stage K call-off,
## generalised). The retreat comes with part 3 (#268).
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
const PLAN_DEFENCE := "defence"
const PLAN_WAITING := "waiting"
const PLANS: Array[String] = [PLAN_ATTACK, PLAN_DEFENCE, PLAN_WAITING]
const DECISION_WAIT := Tactics.DECISION_WAIT
const DECISION_ADVANCE := Tactics.DECISION_ADVANCE
const DECISION_STAND := Tactics.DECISION_STAND
const DECISION_CHARGE := Tactics.DECISION_CHARGE
const DECISION_FLANK := Tactics.DECISION_FLANK
const DECISION_STAND_DOWN := "stand_down" # A charging group not bound by the fight re-forms: the plan changed.
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
const REASON_STRONGER := "stronger" # Plan reason: the side is stronger.
const REASON_PATIENCE := "patience" # Plan reason: patience ran out, the attack outweighs standing.
const REASON_NOT_STRONGER := "not_stronger" # Plan reason: defence, the side is not stronger and not outshot.
const REASON_ENEMY_COMING := "enemy_coming" # Plan reason: defence, the enemy walks in himself.
const REASON_OUTSHOOTING := "outshooting" # Plan reason: waiting, the own shooters are stronger.
const REASON_ENGAGED := "engaged" # Plan reason: a better plan waits, a group is bound by the fight.
const REASON_PLAN_KEPT := "plan_kept" # Plan reason: a better plan waits, the plan is too young or not better enough.
const REASON_PLAN_CHANGED := "plan_changed" # Group: the charge is called off, the plan changed.
const REASON_HOLD_LINE := "hold_line" # Group: holds its place in the defence.
const REASON_ARCHERS_REACH := "archers_reach" # Infantry: waits where its archers reach the enemy.
const REASON_RESERVE := "reserve" # Cavalry: in reserve on the flank.
const REASON_COUNTER := "counter" # Cavalry: counter-charge, the enemy is bound by the own line.

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
	var scores := {} # Plan code -> score at the latest decision.
	var reasons := {} # Plan code -> why it scored so.
	var position := 0.0 # Position P at the latest decision: 0 until part 8 (#273).
	var waited := 0.0 # Seconds of holding or waiting with the enemy not coming: the patience T, times AI_CMD_PATIENCE_SECONDS.
	var advancing := false # The enemy centre closed in faster than AI_CMD_ADVANCING_SPEED between the latest two assessments.
	var engaged := false # A group of the side is bound by the fight (field assessment).
	var homes := PackedVector2Array() # Group centres at the first decision: where the army deployed.
	var anchors := PackedVector2Array() # Where the groups stand in the defence and waiting plans.
	var _decided_at := -1.0
	var _foe_center := Vector2.INF
	var _foe_serial := -1
	var _reserve_sizes := PackedInt32Array([-1, -1])
	var _reserve_strength := PackedFloat64Array([0.0, 0.0])

	func _init() -> void:
		for kind in Config.GROUP_KINDS:
			tasks.append(Task.new())
		homes.resize(Config.GROUP_KINDS)
		anchors.resize(Config.GROUP_KINDS)

	## Patience T: 0..1.
	func patience() -> float:
		return minf(waited / Config.AI_CMD_PATIENCE_SECONDS, 1.0)

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
	var groups: Array = battle.groups[command]
	if mind.plan == PLAN_DEPLOY:
		for kind in Config.GROUP_KINDS:
			mind.homes[kind] = groups[kind].center
	_observe(battle, side, mind, elapsed)
	_score(battle, side, mind)
	var plan := _choose(mind, elapsed)
	var foe_groups: Array = battle.foe_groups(command)
	mind.squads = Tactics._has_squads(foe_groups)
	if plan != mind.plan:
		mind.plan = plan
		mind.plan_since = elapsed
		if plan != PLAN_ATTACK:
			_hold_ground(battle, command, mind, foe, foe_groups)
	match mind.plan:
		PLAN_DEFENCE: _defend(battle, command, mind, foe, foe_groups)
		PLAN_WAITING: _wait(battle, command, mind, foe, foe_groups)
		_: _attack(battle, command, mind, foe, foe_groups, elapsed)
	var trace := _trace(battle, command)
	if trace != null:
		trace.set_plan(side, mind.plan, {"best": mind.best.duplicate(true), "reason": mind.reason, "ratio": mind.ratio,
			"outshot": mind.outshot, "patience": mind.patience(), "advancing": mind.advancing, "engaged": mind.engaged,
			"since": mind.plan_since, "decisions": mind.decisions})

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

## What the side sees between two decisions: whether a group of it is bound by the fight, whether the enemy comes (his
## centre closing in faster than AI_CMD_ADVANCING_SPEED between the latest two assessments, which are
## MORALE_TICK_SECONDS apart), and the patience: the time it held or waited since the previous decision, the enemy not
## coming and nothing bound by the fight.
static func _observe(battle: State, side: int, mind: Mind, elapsed: float) -> void:
	var since := elapsed - mind._decided_at if mind._decided_at >= 0.0 else 0.0
	mind._decided_at = elapsed
	var sides: Array = battle.assessment.get("sides", [])
	mind.engaged = false
	if sides.size() >= 2:
		for group: Dictionary in sides[side].groups:
			if group.engaged:
				mind.engaged = true
		if battle.assessment_serial != mind._foe_serial:
			var center: Vector2 = sides[1 - side].center
			var own: Vector2 = sides[side].center
			if mind._foe_serial >= 0 and mind._foe_center.is_finite() and center.is_finite() and own.is_finite() and own != center:
				var seconds := (battle.assessment_serial - mind._foe_serial) * Config.MORALE_TICK_SECONDS
				mind.advancing = (center - mind._foe_center).dot((own - center).normalized()) / seconds > Config.AI_CMD_ADVANCING_SPEED
			mind._foe_center = center
			mind._foe_serial = battle.assessment_serial
	if (mind.plan == PLAN_DEFENCE or mind.plan == PLAN_WAITING) and not mind.advancing and not mind.engaged:
		mind.waited += since

## Plan scores (DESIGN.md 4.2.3) from the field assessment of the latest morale check, with ramp(x; a, b) below:
##   attack = ramp(R; AI_CMD_ATTACK_RATIO) x (1 - AI_CMD_ATTACK_POSITION x max(P, 0)), raised under fire (F above the
##     first AI_CMD_OUTSHOT value, R at least AI_CMD_OUTSHOT_MIN_RATIO) to AI_CMD_OUTSHOT_FLOOR x ramp(F; AI_CMD_OUTSHOT),
##     plus AI_CMD_PATIENCE_ATTACK x T for R of at least AI_CMD_PATIENCE_RATIO;
##   defence = ramp(R; AI_CMD_DEFENCE_RATIO) x (1 - ramp(F; AI_CMD_OUTSHOT)) x (AI_CMD_DEFENCE_FLOOR + the rest x
##     max(P, 0)), times (1 - AI_CMD_PATIENCE_DEFENCE x T) while the enemy does not come;
##   waiting = ramp(-F; AI_CMD_WAIT_OUTSHOOT) x (1 - T).
## The position P is 0 until part 8 (#273); the retreat comes with part 3 (#268).
static func _score(battle: State, side: int, mind: Mind) -> void:
	mind.ratio = strength_ratio(battle, side, mind)
	mind.outshot = outshot(battle.assessment, side)
	var patience := mind.patience()
	var good_ground := maxf(mind.position, 0.0)
	var attack := ramp(mind.ratio, Config.AI_CMD_ATTACK_RATIO[0], Config.AI_CMD_ATTACK_RATIO[1]) * (1.0 - Config.AI_CMD_ATTACK_POSITION * good_ground)
	var attack_reason := REASON_STRONGER
	if mind.outshot > Config.AI_CMD_OUTSHOT[0] and mind.ratio >= Config.AI_CMD_OUTSHOT_MIN_RATIO:
		var floor_value: float = Config.AI_CMD_OUTSHOT_FLOOR * ramp(mind.outshot, Config.AI_CMD_OUTSHOT[0], Config.AI_CMD_OUTSHOT[1])
		if floor_value > attack:
			attack = floor_value
			attack_reason = REASON_OUTSHOT
	var eager := 0.0
	if mind.ratio >= Config.AI_CMD_PATIENCE_RATIO:
		eager = Config.AI_CMD_PATIENCE_ATTACK * patience
	var outshot_share := ramp(mind.outshot, Config.AI_CMD_OUTSHOT[0], Config.AI_CMD_OUTSHOT[1])
	var steady_defence := ramp(mind.ratio, Config.AI_CMD_DEFENCE_RATIO[0], Config.AI_CMD_DEFENCE_RATIO[1]) * (1.0 - outshot_share) \
		* (Config.AI_CMD_DEFENCE_FLOOR + (1.0 - Config.AI_CMD_DEFENCE_FLOOR) * good_ground)
	var defence := steady_defence
	if not mind.advancing:
		defence *= 1.0 - Config.AI_CMD_PATIENCE_DEFENCE * patience
	var steady_waiting := ramp(-mind.outshot, Config.AI_CMD_WAIT_OUTSHOOT[0], Config.AI_CMD_WAIT_OUTSHOOT[1])
	var waiting := steady_waiting * (1.0 - patience)
	mind.scores = {PLAN_ATTACK: attack + eager, PLAN_DEFENCE: defence, PLAN_WAITING: waiting}
	# Patience is the reason of an attack that would lose to standing without it.
	if patience > 0.0 and attack < maxf(steady_defence, steady_waiting):
		attack_reason = REASON_PATIENCE
	mind.reasons = {PLAN_ATTACK: attack_reason, PLAN_DEFENCE: REASON_ENEMY_COMING if mind.advancing else REASON_NOT_STRONGER,
		PLAN_WAITING: REASON_OUTSHOOTING}
	var scores: Array[Dictionary] = []
	for plan in PLANS:
		scores.append({"plan": plan, "score": mind.scores[plan]})
	# Ties go to the earlier plan of PLANS (the sort is not stable by itself).
	scores.sort_custom(func(a: Dictionary, b: Dictionary): return a.score > b.score or a.score == b.score and PLANS.find(a.plan) < PLANS.find(b.plan))
	mind.best.assign(scores.slice(0, 2))

## The plan to follow (hysteresis, DESIGN.md 4.2.3): the best one at the first decision; later a plan is kept at least
## AI_CMD_PLAN_HOLD_SECONDS and gives way only to one scored AI_CMD_SWITCH_MARGIN higher, and the attack is not left
## while a group is bound by the fight. Sets the reason of the decision.
static func _choose(mind: Mind, elapsed: float) -> String:
	var best: String = mind.best[0].plan
	if mind.plan == PLAN_DEPLOY or best == mind.plan:
		mind.reason = mind.reasons[best]
		return best
	if mind.plan == PLAN_ATTACK and mind.engaged:
		mind.reason = REASON_ENGAGED
		return mind.plan
	if elapsed - mind.plan_since < Config.AI_CMD_PLAN_HOLD_SECONDS or mind.scores[best] < mind.scores[mind.plan] + Config.AI_CMD_SWITCH_MARGIN:
		mind.reason = REASON_PLAN_KEPT
		return mind.plan
	mind.reason = mind.reasons[best]
	return best

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
	_archers_to_range(battle, command, mind, foe, foe_groups, objective)
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

## Archers (attack and waiting): up to AI_CMD_ARCHER_RANGE_SHARE of their range from the nearest enemy squad, not far
## behind their line: at most AI_CMD_ARCHER_LINE_GAP and, while the line has not charged, at least ARCHER_REAR_OFFSET
## (where they deploy), never stepping back for it.
static func _archers_to_range(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array, objective: Vector2) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
	var archers: Group = battle.groups[command][Config.GROUP_ARCHERS]
	var has_infantry := infantry.has_active_units()
	var task: Task = mind.tasks[Config.GROUP_ARCHERS]
	task.clear()
	if archers.order == Config.ORDER_CHARGE or not archers.has_active_units():
		return
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

## Leaving the attack (DESIGN.md 4.2.3, the stage K call-off generalised): every charging group not bound by the fight
## re-forms where its men stand; the groups then hold or wait from where they are (the infantry and the archers) or
## from their deployment place (the cavalry, a reserve on its flank). A cavalry not yet charging leaves its flank way.
static func _hold_ground(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array) -> void:
	var side := State.side_of(command)
	var sides: Array = battle.assessment.get("sides", [])
	var groups: Array = battle.groups[command]
	for kind in Config.GROUP_KINDS:
		var group: Group = groups[kind]
		if group.order == Config.ORDER_CHARGE:
			var bound: bool = sides.size() >= 2 and sides[side].groups[kind].engaged
			if not bound and group.has_active_units():
				_stand_down(battle, command, group, foe, foe_groups)
		mind.anchors[kind] = group.center
	var cavalry: Group = groups[Config.GROUP_CAVALRY]
	mind.anchors[Config.GROUP_CAVALRY] = mind.homes[Config.GROUP_CAVALRY]
	if cavalry.order != Config.ORDER_CHARGE:
		cavalry.tactic_state = Config.AI_TACTIC_WAIT

## A charge called off by the plan: back into formation where the men stand, facing the enemy squad to fight.
static func _stand_down(battle: State, command: int, group: Group, foe: Vector2, foe_groups: Array) -> void:
	group.order = Config.ORDER_HOLD
	group.kite_seconds = 0.0
	group.kite_gap = INF
	group.center = group.centroid()
	if group.kind == Config.GROUP_CAVALRY:
		group.tactic_state = Config.AI_TACTIC_WAIT
	var aim := Tactics._objective(group, foe_groups, foe)
	if aim.is_finite() and aim != group.center:
		group.direction = (aim - group.center).angle()
	group.squad_distance = Tactics._squad_distance(group.center, foe_groups)
	group.layout()
	var trace := _trace(battle, command)
	if trace != null:
		trace.record(State.side_of(command), group.kind, DECISION_STAND_DOWN, REASON_PLAN_CHANGED)

## The defence plan: the line holds its anchor facing the nearest squad and fights there by the "hold" rule (no charge
## of its own), the archers stand behind it and shoot, the cavalry waits in reserve.
static func _defend(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
	var archers: Group = battle.groups[command][Config.GROUP_ARCHERS]
	var has_infantry := infantry.has_active_units()
	var task: Task = mind.tasks[Config.GROUP_INFANTRY]
	task.clear()
	if has_infantry and infantry.order != Config.ORDER_CHARGE:
		var objective := Tactics._objective(infantry, foe_groups, foe)
		task.active = true
		task.point = mind.anchors[Config.GROUP_INFANTRY]
		task.face = objective
		task.speed = march_speed(infantry, under_fire(battle, side, infantry.center, foe_groups), Config.AI_INFANTRY_ADVANCE_SPEED)
		if trace != null:
			trace.record(side, Config.GROUP_INFANTRY, DECISION_STAND, REASON_HOLD_LINE)
	task = mind.tasks[Config.GROUP_ARCHERS]
	task.clear()
	if archers.order != Config.ORDER_CHARGE and archers.has_active_units():
		var near := nearest_squad_point(foe_groups, archers.center)
		task.active = true
		task.point = mind.anchors[Config.GROUP_ARCHERS]
		# Stage Р3: archers on the high ground or a forest edge the doctrine chose stay there.
		if archers.post.is_finite() and archers.center == archers.post:
			task.point = Vector2.INF
		task.face = near if near.is_finite() else foe
		task.speed = march_speed(archers, under_fire(battle, side, archers.center, foe_groups), Config.AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED)
		task.charge_within = Config.AI_ARCHER_CHARGE_DISTANCE if has_infantry else Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE
		if trace != null:
			trace.record(side, Config.GROUP_ARCHERS, DECISION_STAND, REASON_HOLD_LINE)
	_reserve(battle, command, mind, foe, foe_groups)

## The waiting plan: the own shooters are stronger. The line walks up (never back) until its archers, standing
## ARCHER_REAR_OFFSET behind it, are AI_CMD_ARCHER_RANGE_SHARE of their range from the nearest enemy squad, and holds
## there; the archers keep to the attack rule behind it; the cavalry waits in reserve.
static func _wait(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
	var archers: Group = battle.groups[command][Config.GROUP_ARCHERS]
	var objective := Tactics._objective(infantry, foe_groups, foe)
	var task: Task = mind.tasks[Config.GROUP_INFANTRY]
	task.clear()
	if infantry.has_active_units() and infantry.order != Config.ORDER_CHARGE:
		# Measured from the centre, not from the men's mean of the assessment: that one is up to a second old.
		var near := nearest_squad_point(foe_groups, infantry.center)
		var aim := near if near.is_finite() else objective
		var reach := archers.reach if archers.reach > 0.0 else Config.AI_ARCHER_ADVANCE_DISTANCE
		var wanted := maxf(reach * Config.AI_CMD_ARCHER_RANGE_SHARE - Config.ARCHER_REAR_OFFSET, Config.AI_INFANTRY_CHARGE_DISTANCE)
		var gap := infantry.center.distance_to(aim)
		var anchor := mind.anchors[Config.GROUP_INFANTRY]
		if gap > wanted and aim.is_finite():
			anchor = infantry.center + (aim - infantry.center) / gap * (gap - wanted)
			mind.anchors[Config.GROUP_INFANTRY] = anchor
		task.active = true
		task.point = anchor
		task.face = objective
		task.speed = march_speed(infantry, under_fire(battle, side, infantry.center, foe_groups), Config.AI_INFANTRY_ADVANCE_SPEED)
		if trace != null:
			trace.record(side, Config.GROUP_INFANTRY, DECISION_ADVANCE if infantry.center.distance_to(anchor) > 1.0 else DECISION_STAND,
				REASON_ARCHERS_REACH, {"distance": gap})
	_archers_to_range(battle, command, mind, foe, foe_groups, objective)
	_reserve(battle, command, mind, foe, foe_groups)

## Cavalry in reserve (defence and waiting): back to its deployment place on the flank, facing the nearest squad; it
## charges once an enemy fighter comes within AI_CAVALRY_CHARGE_DISTANCE or, as a counter-charge, once the own infantry
## or archers are bound by the fight.
static func _reserve(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
	var task: Task = mind.tasks[Config.GROUP_CAVALRY]
	task.clear()
	if cavalry.order == Config.ORDER_CHARGE or not cavalry.has_active_units():
		return
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() >= 2 and (sides[side].groups[Config.GROUP_INFANTRY].engaged or sides[side].groups[Config.GROUP_ARCHERS].engaged):
		_charge(battle, command, cavalry, REASON_COUNTER)
		return
	var near := nearest_squad_point(foe_groups, cavalry.center)
	task.active = true
	task.point = mind.anchors[Config.GROUP_CAVALRY]
	task.face = near if near.is_finite() else foe
	task.speed = Config.AI_CAVALRY_FLANK_SPEED
	task.charge_within = Config.AI_CAVALRY_CHARGE_DISTANCE
	task.fighters = true
	if trace != null:
		trace.record(side, Config.GROUP_CAVALRY, DECISION_STAND, REASON_RESERVE)

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
