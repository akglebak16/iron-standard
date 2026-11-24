extends RefCounted
## Army commander, stage 1g parts 1, 2, 4 and 5 (DESIGN.md 4.2, decisions 49–57, 66–71, 72–77 and 86–91, #266, #267, #269, #270): the "commander" AI profile next to the
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
##   behind their own line; the cavalry hunts the enemy shooters or rides round the weak edge of his line (part 4);
## - defence (part 2): the line holds where it stands (its deployment line at the start), the archers behind it, the
##   cavalry in reserve behind its deployment flank; the cavalry counter-charges once the enemy is bound by the line or rides
##   within its charge distance;
## - waiting (part 2): the own shooters are stronger; the line walks up only until its archers, behind it, reach the
##   nearest enemy squad, and stands; the cavalry in reserve.
## Cavalry roles (part 4, DESIGN.md 4.2.4), chosen on every decision and kept in Mind.role:
## - flank: round the weak edge of the enemy line (no enemy cavalry near it, room to the field edge, a short ride),
##   keeping AI_CMD_FLANK_CLEARANCE in front of the line while it crosses, then out and past the edge; the way is
##   worked out again on every decision, so it follows the enemy; the charge comes at the end of the way or once an
##   enemy fighter is within AI_CAVALRY_CHARGE_DISTANCE;
## - hunt: the enemy shooters are strong, the side is outshot or losing men to missiles, and the enemy cavalry near
##   the shooters is weak or bound by the fight: the same way round the weak edge, then in behind the shooters; the
##   charge comes once the shooters are within AI_CAVALRY_CHARGE_DISTANCE, whatever else is nearer;
## - counter: an enemy group threatens the own infantry or archers from a flank or the rear (field assessment
##   sectors) by more than AI_CMD_COUNTER_THREAT of their strength: the cavalry rides at it and charges it in reach;
## - reserve: in the defence and the waiting plans, AI_CMD_RESERVE_BEHIND behind the edge of the own line on the side it
##   deployed (part 2 kept it where it deployed); it counter-charges as in part 2 or takes the counter role.
## Shield wall (part 5, DESIGN.md 4.2.4), decided with the infantry task in every plan: an infantry group with at least
## AI_CMD_WALL_SHIELD_SHARE shield bearers raises a wall (Group.wall) under fire: closer slots, and its shields hold arrows
## better (block.gd); it marches as fast as without one. The wall stays in a charge while the line is formed and comes
## down once it goes loose or the group has been out of fire AI_CMD_WALL_CLEAR_SECONDS.
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
const REASON_WAYPOINT_REACHED := Tactics.REASON_WAYPOINT_REACHED
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
# Cavalry roles (part 4): Mind.role, the trace decision of the role and its reasons.
const ROLE_RESERVE := "reserve"
const ROLE_FLANK := "flank"
const ROLE_HUNT := "hunt"
const ROLE_COUNTER := "counter"
const DECISION_HUNT := "hunt" # Cavalry rides at the enemy shooters.
const DECISION_COUNTER := "counter" # Cavalry rides at an enemy group threatening the own flank or rear.
const REASON_WEAK_EDGE := "weak_edge" # Flank: round the edge of the enemy line where his cavalry is not.
const REASON_SHOOTERS_BARE := "shooters_bare" # Hunt: the enemy shooters are strong and their cover is weak.
const REASON_FLANK_THREAT := "flank_threat" # Counter: an enemy group threatens a flank or the rear of the own line.
const REASON_SHOOTERS_CLOSE := "shooters_close" # Charge: the hunted shooters are within reach.
const REASON_TARGET_CLOSE := "target_close" # Charge: the group the cavalry rides at is within reach.
# Shield wall (part 5): the trace decisions when the wall goes up or comes down, and their reasons.
const DECISION_WALL_UP := "wall_up"
const DECISION_WALL_DOWN := "wall_down"
const REASON_SHIELD_WALL := "shield_wall" # Infantry: marches or stands in a shield wall under fire.
const REASON_WALL_OUT_OF_FIRE := "wall_out_of_fire" # Wall down: out of fire long enough.
const REASON_WALL_CHARGE := "wall_charge" # Wall down: the charging line went loose.

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
	var target: Group = null # Also charges once this enemy squad (its sampled men) is within charge_within.

	func clear() -> void:
		active = false
		point = Vector2.INF
		on_waypoint = false
		speed = 0.0
		face = Vector2.INF
		charge_within = INF
		fighters = false
		arrival = -1.0
		target = null

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
	var role := "" # The cavalry role of the latest decision (ROLE_*); "" without cavalry or while it charges.
	var fire_at := -INF # The decision time the infantry was last under fire (the shield wall, part 5).
	var edge := 0 # The edge of the enemy line the cavalry rides round: +1 or -1 along Front.lateral, 0 not chosen yet.
	var way := Vector2.INF # The latest way point given to the cavalry (before the terrain doctrine moves it).
	var _decided_at := -1.0
	var _foe_center := Vector2.INF
	var _foe_serial := -1
	var _foe_seen_at := -1.0 # The decision time the latest assessment was first seen at.
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

## The enemy line the cavalry rides round (part 4), from the squad picture: his infantry squad (else his largest squad on
## foot), its centre, the way from it towards the own side and the lateral extent of its sampled men across that way.
class Front:
	var center := Vector2.INF # INF: no enemy line.
	var forward := Vector2.RIGHT # From the enemy line towards the own side.
	var lateral := Vector2.DOWN
	var low := 0.0 # Lateral coordinates of the line's edges: edge(-1) and edge(+1).
	var high := 0.0

	func valid() -> bool:
		return center.is_finite()

	func edge(side: int) -> float:
		return high if side > 0 else low

	## Along the way towards the own side (positive: in front of the line).
	func ahead(point: Vector2) -> float:
		return (point - center).dot(forward)

	func across(point: Vector2) -> float:
		return (point - center).dot(lateral)

	func at(ahead_of: float, across_of: float) -> Vector2:
		return center + forward * ahead_of + lateral * across_of

	## The lane of riders going round edge `side`: AI_CMD_FLANK_OUTWARD out of it.
	func lane(side: int) -> float:
		return edge(side) + side * Config.AI_CMD_FLANK_OUTWARD

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
	var infantry: Group = groups[Config.GROUP_INFANTRY]
	if infantry.has_active_units():
		shield_wall(battle, command, mind, infantry, under_fire(battle, side, infantry.center, foe_groups), elapsed)
	match mind.plan:
		PLAN_DEFENCE: _defend(battle, command, mind, foe, foe_groups, elapsed)
		PLAN_WAITING: _wait(battle, command, mind, foe, foe_groups, elapsed)
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
## centre closing in faster than AI_CMD_ADVANCING_SPEED between the latest two assessments, timed by the decision clock:
## the commander reads the result of the morale check, not its numbers, ADR-026), and the patience: the time it held or
## waited since the previous decision, the enemy not coming and nothing bound by the fight.
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
			var seconds := elapsed - mind._foe_seen_at
			if mind._foe_serial >= 0 and seconds > 0.0 and mind._foe_center.is_finite() and center.is_finite() and own.is_finite() and own != center:
				mind.advancing = (center - mind._foe_center).dot((own - center).normalized()) / seconds > Config.AI_CMD_ADVANCING_SPEED
			mind._foe_center = center
			mind._foe_serial = battle.assessment_serial
			mind._foe_seen_at = elapsed
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
			var reason := REASON_SHIELD_WALL if infantry.wall and fire else REASON_UNDER_FIRE if fire else REASON_OUT_OF_FIRE
			trace.record(side, Config.GROUP_INFANTRY, DECISION_ADVANCE, reason,
				{"speed": task.speed, "focus_kind": infantry.focus_kind, "wall": infantry.wall})
	_archers_to_range(battle, command, mind, foe, foe_groups, objective)
	_cavalry_attack(battle, command, mind, foe_groups, elapsed)

## Cavalry in the attack (part 4): a counter-strike on a group threatening the own flank or rear, else the hunt for the
## enemy shooters, else the way round the weak edge of the enemy line; a hunt already close to its shooters goes on.
static func _cavalry_attack(battle: State, command: int, mind: Mind, foe_groups: Array, elapsed: float) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
	var task: Task = mind.tasks[Config.GROUP_CAVALRY]
	task.clear()
	mind.role = ""
	if cavalry.order == Config.ORDER_CHARGE or not cavalry.has_active_units():
		return
	if elapsed <= Config.AI_CAVALRY_FLANK_DELAY_SECONDS:
		if trace != null:
			trace.record(side, Config.GROUP_CAVALRY, DECISION_WAIT, REASON_DEPLOYING)
		return
	var riders := own_riders(battle, side, cavalry)
	var shooters := hunted_shooters(battle, side, mind, foe_groups, riders)
	var threat := counter_target(battle, side, foe_groups)
	if threat != null and not (shooters != null and squad_gap(cavalry.center, shooters) < 2.0 * Config.AI_CAVALRY_CHARGE_DISTANCE):
		_counter(battle, command, mind, threat)
		return
	var front := front_of(battle, side, foe_groups)
	if not front.valid():
		_counter(battle, command, mind, _nearest_squad(foe_groups, cavalry.center))
		return
	choose_edge(battle, mind, front, cavalry.center, foe_groups, riders)
	var past := front.ahead(cavalry.center) <= -0.5 * Config.AI_CMD_FLANK_BEHIND # Behind the enemy front already.
	var outside := mind.edge * front.across(cavalry.center) >= mind.edge * front.edge(mind.edge) + 0.5 * Config.AI_CMD_FLANK_OUTWARD
	var point := front.at(-Config.AI_CMD_FLANK_BEHIND, front.lane(mind.edge))
	if not (past or outside):
		point = front.at(maxf(front.ahead(cavalry.center), Config.AI_CMD_FLANK_CLEARANCE), front.lane(mind.edge)) # Cross out of reach.
	task.active = true
	task.on_waypoint = true
	task.speed = Config.AI_CAVALRY_FLANK_SPEED
	task.charge_within = Config.AI_CAVALRY_CHARGE_DISTANCE
	if shooters != null:
		mind.role = ROLE_HUNT
		task.target = shooters
		if past:
			var away := shooters.scan_center - front.center
			away = away.normalized() if away.length_squared() > 1.0 else -front.forward
			point = shooters.scan_center + away * Config.AI_CMD_HUNT_BEHIND
			task.arrival = Config.AI_CAVALRY_WAYPOINT_ARRIVAL
	else:
		mind.role = ROLE_FLANK
		task.fighters = true
		if past or outside:
			task.arrival = Config.AI_CAVALRY_WAYPOINT_ARRIVAL
	_send_cavalry(battle, mind, cavalry, point)
	if trace != null:
		trace.record(side, Config.GROUP_CAVALRY, DECISION_HUNT if shooters != null else DECISION_FLANK,
			REASON_SHOOTERS_BARE if shooters != null else REASON_WEAK_EDGE, {"edge": mind.edge, "waypoint": cavalry.waypoint})

## The cavalry rides at `target` and charges it within AI_CAVALRY_CHARGE_DISTANCE (a counter-strike); nothing to do
## without a target.
static func _counter(battle: State, command: int, mind: Mind, target: Group) -> void:
	var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
	var task: Task = mind.tasks[Config.GROUP_CAVALRY]
	task.clear()
	mind.role = ""
	if target == null:
		return
	mind.role = ROLE_COUNTER
	task.active = true
	task.on_waypoint = true
	task.speed = Config.AI_CAVALRY_FLANK_SPEED
	task.charge_within = Config.AI_CAVALRY_CHARGE_DISTANCE
	task.target = target
	_send_cavalry(battle, mind, cavalry, nearest_squad_point([target], cavalry.center))
	var trace := _trace(battle, command)
	if trace != null:
		trace.record(State.side_of(command), Config.GROUP_CAVALRY, DECISION_COUNTER, REASON_FLANK_THREAT, {"target_kind": target.kind, "waypoint": cavalry.waypoint})

## Sets the cavalry way point, kept within AI_CAVALRY_FLANK_EDGE of the field edge. A point within
## AI_CAVALRY_WAYPOINT_ARRIVAL of the latest one leaves the waypoint as it is, so the terrain doctrine (stage Р3, decision
## 45) does not have to move it to open ground again on every decision.
static func _send_cavalry(battle: State, mind: Mind, cavalry: Group, point: Vector2) -> void:
	var margin := Vector2.ONE * Config.AI_CAVALRY_FLANK_EDGE
	point = point.clamp(margin, battle.arena_size - margin)
	cavalry.tactic_state = Config.AI_TACTIC_FLANK
	if not mind.way.is_finite() or mind.way.distance_to(point) >= Config.AI_CAVALRY_WAYPOINT_ARRIVAL:
		mind.way = point
		cavalry.waypoint = point

## The enemy line (Front) from the squad picture; not valid without an enemy squad on foot.
static func front_of(battle: State, side: int, foe_groups: Array) -> Front:
	var front := Front.new()
	var line: Group = null
	for foe: Group in foe_groups:
		if not Tactics._is_squad(foe) or foe.kind == Config.GROUP_CAVALRY:
			continue
		var infantry := foe.kind == Config.GROUP_INFANTRY
		var line_infantry := line != null and line.kind == Config.GROUP_INFANTRY
		if line == null or (infantry and not line_infantry) or (infantry == line_infantry and foe.scan_count > line.scan_count):
			line = foe
	if line == null:
		return front
	var own := battle.centroid(side)
	if not own.is_finite() or own.distance_squared_to(line.scan_center) < 1.0:
		return front
	front.center = line.scan_center
	front.forward = (own - line.scan_center).normalized()
	front.lateral = Vector2(-front.forward.y, front.forward.x)
	front.low = INF
	front.high = -INF
	for point in line.scan_points:
		var across := front.across(point)
		front.low = minf(front.low, across)
		front.high = maxf(front.high, across)
	return front

## Picks the edge of the enemy line to ride round from `from`, keeping the chosen one unless the other is scored
## AI_CMD_FLANK_EDGE_MARGIN higher (DESIGN.md 4.2.4).
static func choose_edge(battle: State, mind: Mind, front: Front, from: Vector2, foe_groups: Array, riders: float) -> void:
	var low := edge_score(battle, front, -1, from, foe_groups, riders)
	var high := edge_score(battle, front, 1, from, foe_groups, riders)
	var best := 1 if high > low else -1
	var kept := high if mind.edge == 1 else low
	if mind.edge == 0 or maxf(low, high) > kept + Config.AI_CMD_FLANK_EDGE_MARGIN:
		mind.edge = best

## Score of riding round edge `edge` (+1 or -1) of the enemy line from `from`: minus the enemy riders within
## AI_CMD_FLANK_CAVALRY_RADIUS of the edge over the own `riders`, minus 1 with the field edge closer than
## AI_CMD_FLANK_FIELD_EDGE, minus AI_CMD_FLANK_PATH_WEIGHT per AI_CMD_FLANK_PATH_UNIT of the ride.
static func edge_score(battle: State, front: Front, edge: int, from: Vector2, foe_groups: Array, riders: float) -> float:
	var corner := front.at(0.0, front.edge(edge))
	var score := 0.0
	for foe: Group in foe_groups:
		if foe.kind == Config.GROUP_CAVALRY and Tactics._is_squad(foe):
			var near := 1.0 - foe.scan_center.distance_to(corner) / Config.AI_CMD_FLANK_CAVALRY_RADIUS
			if near > 0.0:
				score -= near * foe.scan_count / maxf(riders, 1.0)
	var room := minf(minf(corner.x, battle.arena_size.x - corner.x), minf(corner.y, battle.arena_size.y - corner.y))
	if room < Config.AI_CMD_FLANK_FIELD_EDGE:
		score -= 1.0
	var end := front.at(-Config.AI_CMD_FLANK_BEHIND, front.lane(edge))
	var cross := front.at(maxf(front.ahead(from), Config.AI_CMD_FLANK_CLEARANCE), front.lane(edge))
	var ride := from.distance_to(cross) + cross.distance_to(end)
	return score - Config.AI_CMD_FLANK_PATH_WEIGHT * ride / Config.AI_CMD_FLANK_PATH_UNIT

## The enemy shooters worth a hunt (DESIGN.md 4.2.4), or null: their strength is at least AI_CMD_HUNT_RANGED_SHARE of
## the enemy's, the side is outshot or losing men to missiles, and the enemy riders near them and not bound by the
## fight are fewer than AI_CMD_HUNT_ESCORT_SHARE of the own `riders`.
static func hunted_shooters(battle: State, side: int, mind: Mind, foe_groups: Array, riders: float) -> Group:
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() < 2 or foe_groups.size() <= Config.GROUP_ARCHERS:
		return null
	var shooters: Group = foe_groups[Config.GROUP_ARCHERS]
	var enemy: Dictionary = sides[1 - side]
	if not Tactics._is_squad(shooters) or enemy.strength <= 0.0 or _shooters(enemy) < Config.AI_CMD_HUNT_RANGED_SHARE * enemy.strength:
		return null
	if mind.outshot <= 0.0 and battle.missile_losses[side] < Config.AI_MISSILE_PRESSURE_LOSSES:
		return null
	var escort := 0.0
	for foe: Group in foe_groups:
		if foe.kind != Config.GROUP_CAVALRY or not Tactics._is_squad(foe) or foe.scan_center.distance_to(shooters.scan_center) >= Config.AI_CMD_HUNT_ESCORT_RADIUS:
			continue
		if enemy.groups[Config.GROUP_CAVALRY].engaged:
			continue
		escort += foe.scan_count
	return shooters if escort < Config.AI_CMD_HUNT_ESCORT_SHARE * riders else null

## The enemy squad that threatens the own infantry or archers most from a flank or the rear (field assessment: its
## strength against theirs, fading to nothing at AI_FIELD_THREAT_RADIUS, the sectors of 4.1), when that threat is more
## than AI_CMD_COUNTER_THREAT of their strength; null otherwise or without an assessment.
static func counter_target(battle: State, side: int, foe_groups: Array) -> Group:
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() < 2:
		return null
	var best := Config.AI_CMD_COUNTER_THREAT
	var target: Group = null
	for own_kind in [Config.GROUP_INFANTRY, Config.GROUP_ARCHERS]:
		var own: Dictionary = sides[side].groups[own_kind]
		if own.count == 0 or own.strength <= 0.0:
			continue
		for foe_kind in mini(Config.GROUP_KINDS, foe_groups.size()):
			var foe: Dictionary = sides[1 - side].groups[foe_kind]
			if foe.count == 0 or not Tactics._is_squad(foe_groups[foe_kind]):
				continue
			var offset: Vector2 = foe.center - own.center
			var distance := offset.length()
			if distance >= Config.AI_FIELD_THREAT_RADIUS or distance <= 0.0:
				continue
			if absf(wrapf(offset.angle() - float(own.frame), -PI, PI)) <= Config.AI_FIELD_FRONT_ARC:
				continue
			var share: float = foe.matchup[own_kind] * (1.0 - distance / Config.AI_FIELD_THREAT_RADIUS) / own.strength
			if share > best:
				best = share
				target = foe_groups[foe_kind]
	return target

## Ready riders of the own cavalry: the latest assessment, all its men without one.
static func own_riders(battle: State, side: int, cavalry: Group) -> float:
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() >= 2:
		return float(sides[side].groups[Config.GROUP_CAVALRY].count)
	return float(cavalry.units.size())

## From `point` to the nearest sampled man of the squad; INF when it is no squad.
static func squad_gap(point: Vector2, squad: Group) -> float:
	if not Tactics._is_squad(squad):
		return INF
	var best := INF
	for at in squad.scan_points:
		best = minf(best, point.distance_squared_to(at))
	return sqrt(best)

static func _nearest_squad(foe_groups: Array, point: Vector2) -> Group:
	var best: Group = null
	var best_gap := INF
	for foe: Group in foe_groups:
		var gap := squad_gap(point, foe)
		if gap < best_gap:
			best_gap = gap
			best = foe
	return best

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
static func _defend(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array, elapsed: float) -> void:
	var side := State.side_of(command)
	var trace := _trace(battle, command)
	var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
	var archers: Group = battle.groups[command][Config.GROUP_ARCHERS]
	var has_infantry := infantry.has_active_units()
	var task: Task = mind.tasks[Config.GROUP_INFANTRY]
	task.clear()
	if has_infantry and infantry.order != Config.ORDER_CHARGE:
		var objective := Tactics._objective(infantry, foe_groups, foe)
		var fire := under_fire(battle, side, infantry.center, foe_groups)
		task.active = true
		task.point = mind.anchors[Config.GROUP_INFANTRY]
		task.face = objective
		task.speed = march_speed(infantry, fire, Config.AI_INFANTRY_ADVANCE_SPEED)
		if trace != null:
			trace.record(side, Config.GROUP_INFANTRY, DECISION_STAND, REASON_SHIELD_WALL if infantry.wall and fire else REASON_HOLD_LINE, {"wall": infantry.wall})
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
static func _wait(battle: State, command: int, mind: Mind, foe: Vector2, foe_groups: Array, elapsed: float) -> void:
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
		var fire := under_fire(battle, side, infantry.center, foe_groups)
		task.active = true
		task.point = anchor
		task.face = objective
		task.speed = march_speed(infantry, fire, Config.AI_INFANTRY_ADVANCE_SPEED)
		if trace != null:
			trace.record(side, Config.GROUP_INFANTRY, DECISION_ADVANCE if infantry.center.distance_to(anchor) > 1.0 else DECISION_STAND,
				REASON_SHIELD_WALL if infantry.wall and fire else REASON_ARCHERS_REACH, {"distance": gap, "wall": infantry.wall})
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
	mind.role = ""
	if sides.size() >= 2 and (sides[side].groups[Config.GROUP_INFANTRY].engaged or sides[side].groups[Config.GROUP_ARCHERS].engaged):
		_charge(battle, command, cavalry, REASON_COUNTER)
		return
	var threat := counter_target(battle, side, foe_groups)
	if threat != null:
		_counter(battle, command, mind, threat)
		return
	cavalry.tactic_state = Config.AI_TACTIC_WAIT
	mind.role = ROLE_RESERVE
	var near := nearest_squad_point(foe_groups, cavalry.center)
	task.active = true
	task.point = reserve_point(battle, command, mind, foe)
	task.face = near if near.is_finite() else foe
	task.speed = Config.AI_CAVALRY_FLANK_SPEED
	task.charge_within = Config.AI_CAVALRY_CHARGE_DISTANCE
	task.fighters = true
	if trace != null:
		trace.record(side, Config.GROUP_CAVALRY, DECISION_STAND, REASON_RESERVE)

## Where the reserve stands (DESIGN.md 4.2.4): AI_CMD_RESERVE_BEHIND behind the edge of the own line on the side the
## cavalry deployed, facing the enemy; its deployment place without an infantry line.
static func reserve_point(battle: State, command: int, mind: Mind, foe: Vector2) -> Vector2:
	var side := State.side_of(command)
	var home := mind.anchors[Config.GROUP_CAVALRY]
	var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
	var line := mind.anchors[Config.GROUP_INFANTRY]
	if not infantry.has_active_units() or not line.is_finite() or not foe.is_finite() or foe.distance_squared_to(line) < 1.0:
		return home
	var forward := (foe - line).normalized()
	var lateral := Vector2(-forward.y, forward.x)
	var flank := signf((home - line).dot(lateral))
	var half := 0.0
	var sides: Array = battle.assessment.get("sides", [])
	if sides.size() >= 2:
		half = 0.5 * float(sides[side].groups[Config.GROUP_INFANTRY].front_width)
	return line + lateral * flank * half - forward * Config.AI_CMD_RESERVE_BEHIND

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

## Marching speed of a group: `calm` out of fire, AI_CMD_UNDER_FIRE_SPEED_SHARE of its mean speed under fire (never slower),
## in a shield wall as well (part 5: a slower wall stood longer under the arrows and lost more men).
static func march_speed(group: Group, fire: bool, calm: float) -> float:
	return maxf(calm, Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * group.mean_speed()) if fire else calm

## The shield wall of the infantry group (part 5, DESIGN.md 4.2.4), on every decision of the plan: it goes up under fire
## when at least AI_CMD_WALL_SHIELD_SHARE of the men who joined the group bear shields, and comes down once the group has
## been out of fire AI_CMD_WALL_CLEAR_SECONDS; in a charge it stays while the line is formed (the squad doctrine) and
## comes down once the line goes loose (mingled in a long melee, in a pursuit, in the forest). The slots close up or open
## again whenever the wall changes.
static func shield_wall(battle: State, command: int, mind: Mind, infantry: Group, fire: bool, elapsed: float) -> void:
	if fire:
		mind.fire_at = elapsed
	var charging := infantry.order == Config.ORDER_CHARGE
	var reason := ""
	if not infantry.wall and fire and not charging and infantry.shield_share() >= Config.AI_CMD_WALL_SHIELD_SHARE:
		reason = REASON_SHIELD_WALL
	elif infantry.wall and elapsed - mind.fire_at >= Config.AI_CMD_WALL_CLEAR_SECONDS:
		reason = REASON_WALL_OUT_OF_FIRE
	elif infantry.wall and charging and not infantry.formed:
		reason = REASON_WALL_CHARGE
	if not reason.is_empty():
		_set_wall(battle, command, infantry, not infantry.wall, reason)

## Raises or lowers the wall of `group`: its men take closer (or wider) slots round the same centre. The centre is the
## front of the formation, not the men's mean: moving it to their mean would throw the line back by half its depth, out
## of the enemy's reach again, and the wall would go up and down on the spot.
static func _set_wall(battle: State, command: int, group: Group, raised: bool, reason: String) -> void:
	group.wall = raised
	group.layout()
	var trace := _trace(battle, command)
	if trace != null:
		trace.record(State.side_of(command), group.kind, DECISION_WALL_UP if raised else DECISION_WALL_DOWN, reason)

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
	if task.target != null:
		var gap := squad_gap(group.center, task.target)
		if gap < task.charge_within:
			return REASON_SHOOTERS_CLOSE if task.target.kind == Config.GROUP_ARCHERS and role_of(battle, command) == ROLE_HUNT else REASON_TARGET_CLOSE
		if not task.fighters:
			return ""
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

## The cavalry role the commander of `command` gave at its latest decision (ROLE_*), "" without one (the overlay).
static func role_of(battle: State, command: int) -> String:
	var mind: Mind = battle.commanders[command] if command < battle.commanders.size() else null
	return mind.role if mind != null else ""

## The debug trace is kept per side; the allies (#243) are not traced, as with the reference brain.
static func _trace(battle: State, command: int) -> DecisionTrace:
	return battle.ai_trace if command != Config.COMMAND_ALLY else null
