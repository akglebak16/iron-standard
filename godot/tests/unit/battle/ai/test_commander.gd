extends SceneTree
## Army commander, stage 1g parts 1, 2, 4 and 5 (DESIGN.md 4.2, #266, #267, #269, #270): the "commander" profile, decisions on its
## own tick of the schedule and execution every tick, the attack plan (march speed by the enemy shooters' reach, no charge
## timer, archers behind their line), the defence and waiting plans, the plan switch with hysteresis and patience, the
## call-off of a charge when the plan changes, the cavalry roles (the way round the weak edge, the hunt for shooters, the
## counter-strike), the shield wall under fire, the same code for both sides, the field assessment kept by the morale check, the plan scores and the
## cavalry role in the trace, and a battle that the trace does not change.
const Commander = preload("res://core/battle/simulation/ai/commander.gd")
const Profiles = preload("res://core/battle/simulation/ai/profiles.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Morale = preload("res://core/battle/rules/morale.gd")
const DecisionTrace = preload("res://core/battle/simulation/ai/decision_trace.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const DT := 1.0 / 60.0
const FOOT_SPEED := 60.0
const ARCHER_REACH := 400.0
const FOE_REACH := 500.0
const SHIELD := 0.18

func _initialize() -> void:
	_test_profile()
	_test_schedule_and_execution()
	_test_march_speed()
	_test_no_charge_timer()
	_test_charge_in_reach()
	_test_archers()
	_test_both_sides()
	_test_assessment_and_plan()
	_test_plan_scores()
	_test_defence()
	_test_counter_charge()
	_test_waiting()
	_test_hysteresis()
	_test_stand_down()
	_test_patience()
	_test_weak_edge()
	_test_hunt()
	_test_counter_strike()
	_test_shield_wall()
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	_test_session(catalog)
	print("Commander tests passed")
	quit(0)

## A synthetic field: the AI `command` on the right half (mirrored: on the left), its enemy near the other edge.
## Own: infantry (6) at x 1700, archers (4, range ARCHER_REACH) at 1800, three riders at 1850. Enemy: infantry (6) at
## 500, archers (4, range FOE_REACH) at 400, three riders at 300. All men alike (tier 1, full health): equal strength.
## `own_shields`: so many of the own infantry bear shields (shield_block SHIELD, the shield wall of part 5).
func _field(command: int, own_infantry_x := 1700.0, own_archers := 4, foe_archers := 4, own_infantry := 6, own_shields := 0) -> State:
	var battle := State.new()
	battle.setup_groups()
	var side := State.side_of(command)
	var mirror := side == 0
	for i in own_infantry: _add(battle, side, Config.GROUP_INFANTRY, _at(battle, own_infantry_x, 800 + i * 20, mirror), FOOT_SPEED, 0.0, SHIELD if i < own_shields else 0.0)
	for i in own_archers: _add(battle, side, Config.GROUP_ARCHERS, _at(battle, 1800, 810 + i * 20, mirror), 50.0, ARCHER_REACH)
	for i in 3:
		var rider := _add(battle, side, Config.GROUP_CAVALRY, _at(battle, 1850, 1200 + i * 20, mirror), 100.0)
		rider.mounted = true
	for i in 6: _add(battle, 1 - side, Config.GROUP_INFANTRY, _at(battle, 500, 800 + i * 20, mirror))
	for i in foe_archers: _add(battle, 1 - side, Config.GROUP_ARCHERS, _at(battle, 400, 810 + i * 20, mirror), 50.0, FOE_REACH)
	for i in 3:
		var foe_rider := _add(battle, 1 - side, Config.GROUP_CAVALRY, _at(battle, 300, 830 + i * 20, mirror), 100.0)
		foe_rider.mounted = true
	_place(battle, command, Config.GROUP_INFANTRY, _at(battle, own_infantry_x, 850, mirror))
	_place(battle, command, Config.GROUP_ARCHERS, _at(battle, 1800, 840, mirror))
	_place(battle, command, Config.GROUP_CAVALRY, _at(battle, 1850, 1220, mirror))
	return battle

func _at(battle: State, x: float, y: float, mirror: bool) -> Vector2:
	return Vector2(battle.arena_size.x - x if mirror else x, y)

func _add(battle: State, side: int, kind: int, at: Vector2, speed := FOOT_SPEED, reach := 0.0, shield := 0.0) -> Unit:
	var unit := Unit.new(battle.units.size(), side, at, 100, 0, 1)
	unit.speed = speed
	unit.attack_range = reach
	unit.shield_block = shield
	battle.add_grouped_unit(unit, kind)
	return unit

func _place(battle: State, command: int, kind: int, center: Vector2) -> void:
	battle.groups[command][kind].center = center

## Moves the group's men and centre by `shift` (the squad picture is sampled from the men).
func _shift(battle: State, command: int, kind: int, shift: Vector2) -> void:
	var group: Group = battle.groups[command][kind]
	for unit: Unit in group.units:
		unit.position += shift
	group.center += shift

func _decide(battle: State, command: int, elapsed := 10.0) -> Commander.Mind:
	Tactics._scan(battle, command)
	Commander.decide(battle, command, elapsed)
	return Commander.mind_of(battle, command)

## Makes the commander's side stronger without moving a man: `figures` waiting reserve figures of tier 1 (half weight),
## then the morale check keeps the assessment. With the default 20 figures R = (13 + 10) / 13: the attack plan.
func _eager(battle: State, command: int, figures := 20) -> State:
	battle.reserve_definitions["zz_reserve"] = {"tier": 1}
	var waiting: Array = []
	for i in figures: waiting.append("zz_reserve")
	battle.reserve[State.side_of(command)].assign(waiting)
	Morale.tick(battle)
	return battle

func _test_profile() -> void:
	assert(Profiles.is_known(Config.AI_PROFILE_COMMANDER) and Profiles.brain(Config.AI_PROFILE_COMMANDER) == Commander)
	assert(Profiles.brain(Config.AI_PROFILE_REFERENCE) == Tactics, "The reference brain stays as it was")
	var setup := Setup.new()
	setup.enemy_ai_profile = Config.AI_PROFILE_COMMANDER
	assert(Profiles.valid(setup))
	assert(Setup.new().enemy_ai_profile == Config.AI_PROFILE_REFERENCE, "The game keeps the reference brain until part 7 (#272)")

## Nothing moves while the army deploys; then one decision on the command's own schedule tick and the march every tick.
func _test_schedule_and_execution() -> void:
	var battle := _eager(_field(Config.COMMAND_ENEMY), Config.COMMAND_ENEMY)
	battle.ai_trace = DecisionTrace.new()
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	var start := infantry.center
	var mind: Commander.Mind = null
	var first := -1
	var expected := 0
	for step in 600:
		var elapsed := (step + 1) * DT
		var before := infantry.center
		var decisions := mind.decisions if mind != null else 0
		battle.ai_trace.begin_tick(step, elapsed)
		Commander.enemy_step(battle, Config.COMMAND_ENEMY, elapsed, DT)
		mind = Commander.mind_of(battle, Config.COMMAND_ENEMY)
		if elapsed <= Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
			assert(mind.decisions == 0 and infantry.center == start, "The army deploys first")
			assert(battle.ai_trace.plans[1] == Commander.PLAN_DEPLOY)
			continue
		if first < 0:
			first = step
			expected = 1
		elif mind.schedule.commander_due(Config.COMMAND_ENEMY, step):
			expected += 1
		if mind.decisions > decisions:
			assert(step == first or mind.schedule.commander_due(Config.COMMAND_ENEMY, step), "Decisions only on the command's schedule tick")
		var task: Commander.Task = mind.tasks[Config.GROUP_INFANTRY]
		# Vector2 is single precision.
		assert(absf(before.distance_to(infantry.center) - task.speed * DT) < 1e-3, "The centre marches every tick, not only on decisions")
	assert(mind.decisions == expected and expected >= 15, "Two decisions a second after deploying: %d" % mind.decisions)
	assert(infantry.order == Config.ORDER_HOLD and battle.ai_trace.plans[1] == Commander.PLAN_ATTACK)
	assert(infantry.center.x < start.x - 250.0, "The line marches on the enemy")
	var details: Dictionary = battle.ai_trace.plan_details[1]
	assert(details.best.size() == 2 and details.best[0].plan == Commander.PLAN_ATTACK and details.reason == Commander.REASON_STRONGER)
	assert(details.has("patience") and details.has("advancing") and details.has("engaged"))

## Out of reach of the enemy shooters the line keeps AI_INFANTRY_ADVANCE_SPEED; within it, or losing men to missiles,
## AI_CMD_UNDER_FIRE_SPEED_SHARE of its own mean speed.
func _test_march_speed() -> void:
	var battle := _eager(_field(Config.COMMAND_ENEMY), Config.COMMAND_ENEMY)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, Config.AI_INFANTRY_ADVANCE_SPEED), "Out of reach: formation pace")
	assert(is_equal_approx(battle.groups[1][Config.GROUP_INFANTRY].mean_speed(), FOOT_SPEED))
	battle.missile_losses[1] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0 # The scan decays it a little.
	mind = _decide(battle, Config.COMMAND_ENEMY)
	var hurried := Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * FOOT_SPEED
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, hurried), "Losing men to missiles: quick march")
	battle = _eager(_field(Config.COMMAND_ENEMY, 850.0), Config.COMMAND_ENEMY) # 450 from the enemy archers (range 500), 350 from their infantry.
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.plan == Commander.PLAN_ATTACK)
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, hurried), "Within reach of the enemy shooters: quick march")
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD)
	assert(Commander.march_speed(battle.groups[1][Config.GROUP_INFANTRY], true, 80.0) == 80.0, "Never slower than out of fire")

## No "charge after 80 s": far from the enemy the line keeps marching; the reference brain charges by its timer.
func _test_no_charge_timer() -> void:
	var elapsed := Config.AI_INFANTRY_FORCE_CHARGE_SECONDS + 20.0
	var battle := _eager(_field(Config.COMMAND_ENEMY), Config.COMMAND_ENEMY)
	_decide(battle, Config.COMMAND_ENEMY, elapsed)
	for i in 30:
		Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD, "The commander has no charge timer")
	var reference := _field(Config.COMMAND_ENEMY)
	Tactics.enemy_step(reference, Config.COMMAND_ENEMY, elapsed, DT)
	assert(reference.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE, "The reference brain charges by its timer")

## Within AI_INFANTRY_CHARGE_DISTANCE of an enemy squad the line charges at once, with the reason and the notice.
func _test_charge_in_reach() -> void:
	var battle := _eager(_field(Config.COMMAND_ENEMY, 500.0 + Config.AI_INFANTRY_CHARGE_DISTANCE - 20.0), Config.COMMAND_ENEMY)
	battle.ai_trace = DecisionTrace.new()
	_decide(battle, Config.COMMAND_ENEMY)
	Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)
	var last := battle.ai_trace.last(1, Config.GROUP_INFANTRY)
	assert(last.decision == Commander.DECISION_CHARGE and last.reason == Commander.REASON_SQUAD_IN_REACH)
	var notices := battle.take_events().filter(func(event: Dictionary): return event.kind == Event.Kind.ENEMY_CHARGE)
	assert(notices.size() == 1, "The player hears the enemy charge")
	assert(not Commander.mind_of(battle, Config.COMMAND_ENEMY).tasks[Config.GROUP_INFANTRY].active, "A charging group has no march task")

## Archers walk up to AI_CMD_ARCHER_RANGE_SHARE of their range, but stay behind their own line: at most
## AI_CMD_ARCHER_LINE_GAP and at least ARCHER_REAR_OFFSET behind it, never stepping back for it.
func _test_archers() -> void:
	var battle := _eager(_field(Config.COMMAND_ENEMY, 1000.0), Config.COMMAND_ENEMY)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	var task: Commander.Task = mind.tasks[Config.GROUP_ARCHERS]
	var archers: Group = battle.groups[1][Config.GROUP_ARCHERS]
	# In range of the nearest squad (x 500) at x 500 + 0.85 x 400 = 840, ahead of the line (x 1000): 105 behind it.
	assert(task.active and task.point.is_finite())
	assert(absf(task.point.x - (1000.0 + Config.ARCHER_REAR_OFFSET)) < 1.0, "Not ahead of the own line: %s" % task.point)
	battle = _eager(_field(Config.COMMAND_ENEMY, 1700.0), Config.COMMAND_ENEMY)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	task = mind.tasks[Config.GROUP_ARCHERS]
	assert(not task.point.is_finite(), "Right behind their line the archers stand; they do not step back")
	battle = _eager(_field(Config.COMMAND_ENEMY, 1000.0), Config.COMMAND_ENEMY)
	archers = battle.groups[1][Config.GROUP_ARCHERS]
	archers.reach = 1000.0
	mind = _decide(battle, Config.COMMAND_ENEMY)
	task = mind.tasks[Config.GROUP_ARCHERS]
	# Range 1000: 850 from x 500 is x 1350, 350 behind the line; they close up to AI_CMD_ARCHER_LINE_GAP.
	assert(absf(task.point.x - (1000.0 + Config.AI_CMD_ARCHER_LINE_GAP)) < 1.0, "Not far behind the own line: %s" % task.point)
	for i in 1200:
		Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(archers.center.is_equal_approx(task.point), "The archers stop at their point")
	assert(is_equal_approx(task.speed, Config.AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED), "Out of fire they walk with the infantry")

## One code for both sides: the mirrored field gives mirrored tasks, in the attack, the defence and the waiting plan.
## A case: own line x, own reserve figures (20: the attack), enemy archers (2 against 4 with 4 own infantry: waiting).
func _test_both_sides() -> void:
	for case in [[1700.0, 20, 4], [1000.0, 20, 4], [850.0, 20, 4], [1700.0, 0, 4], [1000.0, 0, 2]]:
		var own_x: float = case[0]
		var own_infantry := 6 if case[2] == 4 else 4
		var right := _eager(_field(Config.COMMAND_ENEMY, own_x, 4, case[2], own_infantry), Config.COMMAND_ENEMY, case[1])
		var left := _eager(_field(Config.COMMAND_PLAYER, own_x, 4, case[2], own_infantry), Config.COMMAND_PLAYER, case[1])
		var a := _decide(right, Config.COMMAND_ENEMY)
		var b := _decide(left, Config.COMMAND_PLAYER)
		assert(a.plan == b.plan and a.reason == b.reason and is_equal_approx(a.ratio, b.ratio))
		var expected := Commander.PLAN_ATTACK if case[1] > 0 else (Commander.PLAN_DEFENCE if case[2] == 4 else Commander.PLAN_WAITING)
		assert(a.plan == expected, "Plan %s for %s" % [a.plan, str(case)])
		assert(a.role == b.role)
		for kind in Config.GROUP_KINDS:
			var one: Commander.Task = a.tasks[kind]
			var other: Commander.Task = b.tasks[kind]
			assert(one.active == other.active and is_equal_approx(one.speed, other.speed) and one.charge_within == other.charge_within)
			assert(one.point.is_finite() == other.point.is_finite() and one.on_waypoint == other.on_waypoint)
			if one.point.is_finite():
				assert(absf(one.point.x - (right.arena_size.x - other.point.x)) < 1e-3 and absf(one.point.y - other.point.y) < 1e-3, "Mirrored task of group %d" % kind)
			if one.on_waypoint:
				var way: Vector2 = right.groups[Config.COMMAND_ENEMY][kind].waypoint
				var mirrored: Vector2 = left.groups[Config.COMMAND_PLAYER][kind].waypoint
				assert(absf(way.x - (right.arena_size.x - mirrored.x)) < 1e-2 and absf(way.y - mirrored.y) < 1e-2, "Mirrored way %s and %s" % [way, mirrored])
	for kind in Config.GROUP_KINDS:
		assert(Commander.task_point(State.new(), Config.COMMAND_ENEMY, kind) == Vector2.INF, "No commander, no march point")

## The morale check keeps the field assessment in State; the commander reads it for the plan score.
func _test_assessment_and_plan() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	assert(battle.assessment.is_empty() and battle.assessment_serial == 0)
	Morale.tick(battle)
	assert(battle.assessment.sides.size() == 2 and battle.assessment_serial == 1, "The morale check keeps its assessment")
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.ratio, 1.0) and mind.outshot == 0.0)
	assert(is_equal_approx(mind.scores[Commander.PLAN_ATTACK], Commander.ramp(1.0, Config.AI_CMD_ATTACK_RATIO[0], Config.AI_CMD_ATTACK_RATIO[1])))
	# Outshot: one archer against four, strength ratio 10/13: the attack is raised to the floor under fire.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 1, 4)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.outshot, 0.75) and is_equal_approx(mind.ratio, 10.0 / 13.0))
	assert(mind.reason == Commander.REASON_OUTSHOT and is_equal_approx(mind.best[0].score, Config.AI_CMD_OUTSHOT_FLOOR))
	# Twice the infantry: clearly stronger.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 4, 4, 12)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.ratio >= Config.AI_CMD_ATTACK_RATIO[1] and mind.reason == Commander.REASON_STRONGER and mind.best[0].score == 1.0)
	# Waiting reserve counts for half: four figures of tier 1.
	battle = _field(Config.COMMAND_ENEMY)
	battle.reserve_definitions["zz_reserve"] = {"tier": 1}
	battle.reserve[1].assign(["zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve"])
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	var strength_per_man := 1.0 + Config.AI_FIELD_TIER_POWER
	assert(is_equal_approx(mind.ratio, (13.0 + 0.5 * 4.0) * strength_per_man / (13.0 * strength_per_man)), "Reserve at half weight: %f" % mind.ratio)
	assert(Commander.ramp(2.0, 1.4, 0.9) == 0.0 and Commander.ramp(0.9, 1.4, 0.9) == 1.0, "A falling ramp")

## The plan scores of DESIGN.md 4.2.3: even forces hold their ground (defence over attack), stronger own shooters wait,
## a weak side holds, ties go to the earlier plan.
func _test_plan_scores() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	Morale.tick(battle)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	var even_defence: float = Commander.ramp(1.0, Config.AI_CMD_DEFENCE_RATIO[0], Config.AI_CMD_DEFENCE_RATIO[1]) * Config.AI_CMD_DEFENCE_FLOOR
	assert(mind.plan == Commander.PLAN_DEFENCE and mind.reason == Commander.REASON_NOT_STRONGER)
	assert(is_equal_approx(mind.scores[Commander.PLAN_DEFENCE], even_defence) and mind.scores[Commander.PLAN_WAITING] == 0.0)
	assert(mind.best[0].plan == Commander.PLAN_DEFENCE and mind.best[1].plan == Commander.PLAN_ATTACK)
	# Four own archers against two, four own infantry: equal strength, F = -0.5: waiting.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 4, 2, 4)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.ratio, 1.0) and is_equal_approx(mind.outshot, -0.5))
	assert(mind.plan == Commander.PLAN_WAITING and mind.reason == Commander.REASON_OUTSHOOTING and mind.scores[Commander.PLAN_WAITING] == 1.0)
	# Outshot: the attack floor, the defence gone.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 1, 4)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.plan == Commander.PLAN_ATTACK and mind.scores[Commander.PLAN_DEFENCE] == 0.0)
	# Weak (R = 9/13): only the defence.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 4, 4, 2)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.plan == Commander.PLAN_DEFENCE and mind.scores[Commander.PLAN_ATTACK] == 0.0 and is_equal_approx(mind.scores[Commander.PLAN_DEFENCE], Config.AI_CMD_DEFENCE_FLOOR))
	# A tie: four own archers against one, R = 13/10 (attack 1) and F = -0.75 (waiting 1): the attack comes first.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 4, 1)
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.scores[Commander.PLAN_ATTACK] == 1.0 and mind.scores[Commander.PLAN_WAITING] == 1.0 and mind.plan == Commander.PLAN_ATTACK)

## The defence: the line and the archers hold where the army deployed, the cavalry stands in reserve AI_CMD_RESERVE_BEHIND
## behind the edge of the line on its own flank; the line has no charge of its own (it fights by the "hold" rule), the
## cavalry charges a rider within AI_CAVALRY_CHARGE_DISTANCE.
func _test_defence() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	battle.ai_trace = DecisionTrace.new()
	Morale.tick(battle)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.plan == Commander.PLAN_DEFENCE)
	var homes := []
	for kind in Config.GROUP_KINDS:
		assert(mind.homes[kind] == battle.groups[1][kind].center and mind.tasks[kind].active)
		homes.append(mind.tasks[kind].point)
		if kind != Config.GROUP_CAVALRY:
			assert(homes[kind] == battle.groups[1][kind].center, "Group %d holds" % kind)
	# The reserve: the line stands at x 1700 (men y 800..900) facing -x, the riders deployed below it (y 1220).
	var reserve: Vector2 = homes[Config.GROUP_CAVALRY]
	var edge := 850.0 + 0.5 * float(battle.assessment.sides[1].groups[Config.GROUP_INFANTRY].front_width)
	assert(reserve.distance_to(Vector2(1700.0 + Config.AI_CMD_RESERVE_BEHIND, edge)) < 2.0, "Reserve at %s" % reserve) # The enemy centre is a little off the axis.
	assert(Commander.role_of(battle, Config.COMMAND_ENEMY) == Commander.ROLE_RESERVE)
	assert(mind.tasks[Config.GROUP_INFANTRY].charge_within == INF, "The line does not charge by itself")
	assert(mind.tasks[Config.GROUP_CAVALRY].charge_within == Config.AI_CAVALRY_CHARGE_DISTANCE and mind.tasks[Config.GROUP_CAVALRY].fighters)
	for i in 600:
		Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	for kind in Config.GROUP_KINDS:
		assert(battle.groups[1][kind].center == homes[kind] and battle.groups[1][kind].order == Config.ORDER_HOLD)
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	assert(absf(wrapf(infantry.direction - PI, -PI, PI)) < 0.3, "The line faces the enemy")
	assert(battle.ai_trace.last(1, Config.GROUP_INFANTRY).reason == Commander.REASON_HOLD_LINE)
	assert(battle.ai_trace.last(1, Config.GROUP_CAVALRY).reason == Commander.REASON_RESERVE)
	assert(battle.ai_trace.plans[1] == Commander.PLAN_DEFENCE)
	# An enemy rider comes within the charge distance of the reserve: it charges.
	_shift(battle, Config.COMMAND_PLAYER, Config.GROUP_CAVALRY, reserve + Vector2(-Config.AI_CAVALRY_CHARGE_DISTANCE + 30.0, 0.0) - Vector2(300.0, 850.0))
	Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(battle.groups[1][Config.GROUP_CAVALRY].order == Config.ORDER_CHARGE)
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD)

## The counter-charge: once the own line is bound by the fight, the reserve cavalry charges.
func _test_counter_charge() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	battle.ai_trace = DecisionTrace.new()
	Morale.tick(battle)
	_decide(battle, Config.COMMAND_ENEMY)
	assert(battle.groups[1][Config.GROUP_CAVALRY].order == Config.ORDER_HOLD)
	battle.assessment.sides[1].groups[Config.GROUP_INFANTRY].engaged = true
	_decide(battle, Config.COMMAND_ENEMY, 10.5)
	assert(battle.groups[1][Config.GROUP_CAVALRY].order == Config.ORDER_CHARGE, "Counter-charge")
	assert(battle.ai_trace.last(1, Config.GROUP_CAVALRY).reason == Commander.REASON_COUNTER)
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD, "The line keeps holding")

## Waiting: the line walks up until its archers, behind it, reach the nearest enemy squad, and stands; no charge.
func _test_waiting() -> void:
	var battle := _field(Config.COMMAND_ENEMY, 1000.0, 4, 2, 4)
	battle.ai_trace = DecisionTrace.new()
	Morale.tick(battle)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(mind.plan == Commander.PLAN_WAITING)
	var task: Commander.Task = mind.tasks[Config.GROUP_INFANTRY]
	var wanted := maxf(ARCHER_REACH * Config.AI_CMD_ARCHER_RANGE_SHARE - Config.ARCHER_REAR_OFFSET, Config.AI_INFANTRY_CHARGE_DISTANCE)
	# The nearest enemy squad stands at x 500; the line's men (y 800..860) and the centre (y 850) differ a little.
	assert(task.active and task.charge_within == INF and absf(task.point.x - (500.0 + wanted)) < 15.0, "Waiting line at %s" % task.point)
	assert(battle.ai_trace.last(1, Config.GROUP_INFANTRY).reason == Commander.REASON_ARCHERS_REACH)
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	for step in 1200: # 20 s: walking 265 at 40, then standing; the patience has not run out yet.
		if step % 30 == 0:
			for unit: Unit in infantry.units:
				unit.position = infantry.formation_point(unit.slot_offset, infantry.center, battle.arena_size) # The men keep up.
			_decide(battle, Config.COMMAND_ENEMY, 10.0 + step * DT)
		Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(mind.plan == Commander.PLAN_WAITING and infantry.order == Config.ORDER_HOLD and absf(infantry.center.x - (500.0 + wanted)) < 15.0, "Stands at %s" % infantry.center)
	var archers: Group = battle.groups[1][Config.GROUP_ARCHERS]
	assert(archers.order == Config.ORDER_HOLD and archers.center.x > infantry.center.x, "The archers stay behind the line")

## Hysteresis: a plan is kept AI_CMD_PLAN_HOLD_SECONDS and gives way only to one scored AI_CMD_SWITCH_MARGIN higher; the
## attack is not left while a group is bound by the fight.
func _test_hysteresis() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	Morale.tick(battle)
	var mind := _decide(battle, Config.COMMAND_ENEMY, 10.0)
	assert(mind.plan == Commander.PLAN_DEFENCE)
	# One reserve figure: the attack is best, but by less than the margin (5 s of patience add a little to it).
	_eager(battle, Config.COMMAND_ENEMY, 1)
	mind = _decide(battle, Config.COMMAND_ENEMY, 15.0)
	assert(mind.best[0].plan == Commander.PLAN_ATTACK and mind.scores[Commander.PLAN_ATTACK] - mind.scores[Commander.PLAN_DEFENCE] < Config.AI_CMD_SWITCH_MARGIN)
	assert(mind.plan == Commander.PLAN_DEFENCE and mind.reason == Commander.REASON_PLAN_KEPT)
	# Six: better by more than the margin, but the plan is young.
	battle = _field(Config.COMMAND_ENEMY)
	Morale.tick(battle)
	_decide(battle, Config.COMMAND_ENEMY, 10.0)
	_eager(battle, Config.COMMAND_ENEMY, 6)
	mind = _decide(battle, Config.COMMAND_ENEMY, 10.0 + Config.AI_CMD_PLAN_HOLD_SECONDS - 0.5)
	assert(mind.plan == Commander.PLAN_DEFENCE and mind.reason == Commander.REASON_PLAN_KEPT, "Too early to switch")
	mind = _decide(battle, Config.COMMAND_ENEMY, 10.0 + Config.AI_CMD_PLAN_HOLD_SECONDS)
	assert(mind.plan == Commander.PLAN_ATTACK and mind.reason == Commander.REASON_STRONGER and mind.plan_since == 10.0 + Config.AI_CMD_PLAN_HOLD_SECONDS)
	# Weak again, but the infantry is bound by the fight: the attack is kept.
	battle.reserve[1].clear()
	battle.reserve[0].assign(["zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve"])
	Morale.tick(battle)
	battle.assessment.sides[1].groups[Config.GROUP_INFANTRY].engaged = true
	mind = _decide(battle, Config.COMMAND_ENEMY, 30.0)
	assert(mind.best[0].plan == Commander.PLAN_DEFENCE and mind.plan == Commander.PLAN_ATTACK and mind.reason == Commander.REASON_ENGAGED and mind.engaged)
	battle.assessment.sides[1].groups[Config.GROUP_INFANTRY].engaged = false
	mind = _decide(battle, Config.COMMAND_ENEMY, 30.5)
	assert(mind.plan == Commander.PLAN_DEFENCE, "Not bound any more: the defence")

## Leaving the attack: a charging group not bound by the fight re-forms where its men stand (order "hold", centre at its
## men, facing the enemy), with the trace record; the flanking cavalry gives up its way and goes back to the reserve behind its flank.
func _test_stand_down() -> void:
	var battle := _eager(_field(Config.COMMAND_ENEMY, 1000.0), Config.COMMAND_ENEMY)
	battle.ai_trace = DecisionTrace.new()
	var mind := _decide(battle, Config.COMMAND_ENEMY, 10.0)
	assert(mind.plan == Commander.PLAN_ATTACK)
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	var cavalry: Group = battle.groups[1][Config.GROUP_CAVALRY]
	assert(cavalry.tactic_state == Config.AI_TACTIC_FLANK)
	infantry.order = Config.ORDER_CHARGE
	infantry.center = Vector2(700, 900) # A charge moves the centre away from the men (at x 1000).
	cavalry.center += Vector2(-200, 0)
	battle.reserve[1].clear()
	battle.reserve[0].assign(["zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve"]) # Weaker now.
	Morale.tick(battle)
	mind = _decide(battle, Config.COMMAND_ENEMY, 10.0 + Config.AI_CMD_PLAN_HOLD_SECONDS)
	assert(mind.plan == Commander.PLAN_DEFENCE)
	assert(infantry.order == Config.ORDER_HOLD and infantry.center.distance_to(infantry.centroid()) < 1e-3, "Re-formed where the men stand")
	assert(absf(wrapf(infantry.direction - PI, -PI, PI)) < 0.3, "Facing the enemy")
	var last := battle.ai_trace.last(1, Config.GROUP_INFANTRY)
	assert(battle.ai_trace.snapshot().recent.any(func(entry: Dictionary): return entry.group == Config.GROUP_INFANTRY and entry.decision == Commander.DECISION_STAND_DOWN and entry.reason == Commander.REASON_PLAN_CHANGED))
	assert(last.reason == Commander.REASON_HOLD_LINE)
	assert(mind.tasks[Config.GROUP_INFANTRY].point.distance_to(infantry.center) < 1e-3, "The line holds where it re-formed")
	var reserve := Commander.reserve_point(battle, Config.COMMAND_ENEMY, mind, battle.centroid(0))
	assert(cavalry.tactic_state == Config.AI_TACTIC_WAIT and mind.tasks[Config.GROUP_CAVALRY].point == reserve, "The cavalry goes back to the reserve")
	assert(reserve.y > infantry.center.y, "On its own flank")
	# A charging group bound by the fight keeps charging: the plan does not change while the side is engaged.
	battle = _eager(_field(Config.COMMAND_ENEMY, 1000.0), Config.COMMAND_ENEMY)
	_decide(battle, Config.COMMAND_ENEMY, 10.0)
	infantry = battle.groups[1][Config.GROUP_INFANTRY]
	infantry.order = Config.ORDER_CHARGE
	battle.reserve[1].clear()
	battle.reserve[0].assign(["zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve", "zz_reserve"])
	Morale.tick(battle)
	battle.assessment.sides[1].groups[Config.GROUP_INFANTRY].engaged = true
	mind = _decide(battle, Config.COMMAND_ENEMY, 20.0)
	assert(mind.plan == Commander.PLAN_ATTACK and infantry.order == Config.ORDER_CHARGE)

## Patience: holding with the enemy not coming, an even side attacks once T outweighs the defence by the margin; a weak
## one keeps holding; while the enemy comes the patience does not run.
func _test_patience() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	Morale.tick(battle)
	var mind: Commander.Mind = null
	var switched := -1.0
	var elapsed := 10.0
	while elapsed < 100.0:
		mind = _decide(battle, Config.COMMAND_ENEMY, elapsed)
		if mind.plan == Commander.PLAN_ATTACK:
			switched = elapsed
			break
		elapsed += Config.AI_COMMANDER_PERIOD_SECONDS
	# attack 0.4 + 0.3 T against defence 0.48 (1 - 0.5 T) + the margin: T from 0.426, after 19.2 s of holding.
	var t := (0.48 + Config.AI_CMD_SWITCH_MARGIN - 0.4) / (Config.AI_CMD_PATIENCE_ATTACK + 0.48 * Config.AI_CMD_PATIENCE_DEFENCE)
	assert(switched > 0.0 and mind.reason == Commander.REASON_PATIENCE, "Patience: %s" % str(switched))
	assert(absf(switched - 10.0 - t * Config.AI_CMD_PATIENCE_SECONDS) <= Config.AI_COMMANDER_PERIOD_SECONDS + 1e-6, "Switch after %.1f s" % (switched - 10.0))
	# Weak: holds for good.
	battle = _field(Config.COMMAND_ENEMY, 1700.0, 4, 4, 2)
	Morale.tick(battle)
	for step in 300:
		mind = _decide(battle, Config.COMMAND_ENEMY, 10.0 + step * Config.AI_COMMANDER_PERIOD_SECONDS)
	assert(mind.plan == Commander.PLAN_DEFENCE and mind.patience() == 1.0, "A weak side keeps holding")
	# The enemy comes (his men 30 closer per assessment, one a second): no patience runs, the reason says so.
	battle = _field(Config.COMMAND_ENEMY)
	Morale.tick(battle)
	elapsed = 10.0
	var waited := 0.0
	for second in 40:
		for kind in Config.GROUP_KINDS:
			_shift(battle, Config.COMMAND_PLAYER, kind, Vector2(30.0, 0.0) if second < 20 else Vector2.ZERO)
		Morale.tick(battle)
		for half in 2:
			mind = _decide(battle, Config.COMMAND_ENEMY, elapsed)
			elapsed += Config.AI_COMMANDER_PERIOD_SECONDS
		if second == 0:
			waited = mind.waited # Half a second held before the first sight of the enemy moving.
		elif second < 20:
			assert(mind.advancing and mind.waited == waited and mind.reason == Commander.REASON_ENEMY_COMING, "Second %d" % second)
	assert(not mind.advancing and mind.waited > waited, "The enemy stopped: patience runs again")

## Spreads the enemy infantry of `command`'s foe across y 600..1100 (a wide line: its edges are 500 apart) and puts his
## riders from `riders` down (field coordinates of the right side, mirrored for the left); then the morale check.
func _wide_line(battle: State, command: int, riders: Vector2) -> void:
	var mirror := State.side_of(command) == 0
	var foe := 1 - command
	var infantry: Group = battle.groups[foe][Config.GROUP_INFANTRY]
	for i in infantry.units.size():
		infantry.units[i].position = _at(battle, 500, 600 + i * 100, mirror)
	var cavalry: Group = battle.groups[foe][Config.GROUP_CAVALRY]
	for i in cavalry.units.size():
		cavalry.units[i].position = _at(battle, riders.x, riders.y + i * 20, mirror)
	cavalry.center = _at(battle, riders.x, riders.y + 20, mirror)
	Morale.tick(battle)

## Part 4: in the attack the cavalry rides round the edge of the enemy line away from his riders, crossing
## AI_CMD_FLANK_CLEARANCE or more in front of the line, then on the lane AI_CMD_FLANK_OUTWARD out of the edge to
## AI_CMD_FLANK_BEHIND past his front, charging at its end; when the enemy riders move to that edge, the way follows.
func _test_weak_edge() -> void:
	for command in [Config.COMMAND_ENEMY, Config.COMMAND_PLAYER]:
		var mirror := State.side_of(command) == 0
		var battle := _eager(_field(command), command)
		battle.ai_trace = DecisionTrace.new()
		_wide_line(battle, command, Vector2(450, 1230)) # Off the high edge (y 1100).
		var mind := _decide(battle, command)
		var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
		var task: Commander.Task = mind.tasks[Config.GROUP_CAVALRY]
		assert(mind.plan == Commander.PLAN_ATTACK and mind.role == Commander.ROLE_FLANK and task.active and task.on_waypoint)
		var way := _at(battle, cavalry.waypoint.x, cavalry.waypoint.y, mirror) # Back to right-side coordinates.
		assert(way.y < 600.0 - 0.5 * Config.AI_CMD_FLANK_OUTWARD and way.x >= 500.0 + Config.AI_CMD_FLANK_CLEARANCE, "Crosses to the low edge in front of the line: %s" % way)
		assert(task.arrival < 0.0 and task.fighters, "No charge on the crossing point, but at an enemy in reach")
		var last := battle.ai_trace.last(State.side_of(command), Config.GROUP_CAVALRY)
		assert(last.decision == Commander.DECISION_FLANK and last.reason == Commander.REASON_WEAK_EDGE)
		# Out of the edge: on along the lane to past the enemy front, charging at its end.
		cavalry.center = cavalry.waypoint
		mind = _decide(battle, command, 10.5)
		way = _at(battle, cavalry.waypoint.x, cavalry.waypoint.y, mirror)
		assert(way.x < 500.0 and way.y < 600.0 - 0.5 * Config.AI_CMD_FLANK_OUTWARD, "Past the low edge: %s" % way)
		assert(task.arrival == Config.AI_CAVALRY_WAYPOINT_ARRIVAL)
		# The enemy riders go to the low edge: the way turns to the high one.
		cavalry.center = _at(battle, 1850, 1220, mirror)
		_wide_line(battle, command, Vector2(450, 380))
		mind = _decide(battle, command, 11.0)
		way = _at(battle, cavalry.waypoint.x, cavalry.waypoint.y, mirror)
		assert(way.y > 1100.0 + 0.5 * Config.AI_CMD_FLANK_OUTWARD, "The way follows the enemy: %s" % way)

## Part 4: the hunt. Strong enemy shooters, the side outshot, no enemy riders near the shooters: the cavalry rides round
## the weak edge and in behind the shooters, and charges once they are within AI_CAVALRY_CHARGE_DISTANCE, though the
## enemy infantry is nearer; riders close to the shooters cover them, and the cavalry rides round the edge instead.
func _test_hunt() -> void:
	for command in [Config.COMMAND_ENEMY, Config.COMMAND_PLAYER]:
		var side := State.side_of(command)
		var mirror := side == 0
		var battle := _field(command, 1700.0, 1, 4) # One own archer against four: outshot, the attack.
		battle.ai_trace = DecisionTrace.new()
		Morale.tick(battle)
		var mind := _decide(battle, command)
		assert(mind.plan == Commander.PLAN_ATTACK and mind.outshot > 0.0)
		assert(mind.role == Commander.ROLE_FLANK, "The enemy riders stand by his shooters: no hunt")
		_shift(battle, 1 - command, Config.GROUP_CAVALRY, Vector2(0, 700))
		Morale.tick(battle)
		mind = _decide(battle, command, 10.5)
		var task: Commander.Task = mind.tasks[Config.GROUP_CAVALRY]
		var shooters: Group = battle.groups[1 - command][Config.GROUP_ARCHERS]
		assert(mind.role == Commander.ROLE_HUNT and task.target == shooters and not task.fighters, "Hunt")
		assert(battle.ai_trace.last(side, Config.GROUP_CAVALRY).reason == Commander.REASON_SHOOTERS_BARE)
		# Behind the enemy front: in behind the shooters, away from their infantry.
		var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
		cavalry.center = _at(battle, 150, 500, mirror)
		mind = _decide(battle, command, 11.0)
		var foot: Group = battle.groups[1 - command][Config.GROUP_INFANTRY]
		var away := (shooters.scan_center - foot.scan_center).normalized()
		assert(cavalry.waypoint.distance_to(shooters.scan_center + away * Config.AI_CMD_HUNT_BEHIND) < 1.0, "Behind the shooters: %s" % cavalry.waypoint)
		assert(task.arrival == Config.AI_CAVALRY_WAYPOINT_ARRIVAL)
		# The enemy infantry is in reach, the shooters are not: no charge yet.
		cavalry.center = _at(battle, 680, 1000, mirror) # 309 from the lowest shooter, 206 from the lowest foot.
		Commander.execute(battle, command, DT)
		assert(cavalry.order == Config.ORDER_HOLD, "Infantry in reach does not start the hunt's charge")
		cavalry.center = _at(battle, 450, 1050, mirror) # 187 from the lowest shooter.
		Commander.execute(battle, command, DT)
		assert(cavalry.order == Config.ORDER_CHARGE and battle.ai_trace.last(side, Config.GROUP_CAVALRY).reason == Commander.REASON_SHOOTERS_CLOSE)

## Part 4: the counter-strike. Enemy riders on the flank of the own line threaten it by more than AI_CMD_COUNTER_THREAT of
## its strength: the reserve (defence) or the cavalry in the attack rides at them and charges them in reach.
func _test_counter_strike() -> void:
	for eager in [false, true]:
		for command in [Config.COMMAND_ENEMY, Config.COMMAND_PLAYER]:
			var side := State.side_of(command)
			var mirror := side == 0
			var battle := _field(command)
			if eager:
				_eager(battle, command)
			battle.ai_trace = DecisionTrace.new()
			Morale.tick(battle)
			var mind := _decide(battle, command)
			assert(mind.plan == (Commander.PLAN_ATTACK if eager else Commander.PLAN_DEFENCE))
			assert(mind.role == (Commander.ROLE_FLANK if eager else Commander.ROLE_RESERVE))
			# Enemy riders 230 off the side of the own line, 400 from the own riders.
			var foe_riders: Group = battle.groups[1 - command][Config.GROUP_CAVALRY]
			_shift(battle, 1 - command, Config.GROUP_CAVALRY, _at(battle, 1600, 1060, mirror) - foe_riders.units[0].position)
			Morale.tick(battle)
			mind = _decide(battle, command, 10.5)
			var task: Commander.Task = mind.tasks[Config.GROUP_CAVALRY]
			assert(mind.role == Commander.ROLE_COUNTER and task.target == foe_riders, "Counter-strike (attack %s)" % eager)
			var last := battle.ai_trace.last(side, Config.GROUP_CAVALRY)
			assert(last.decision == Commander.DECISION_COUNTER and last.reason == Commander.REASON_FLANK_THREAT)
			var cavalry: Group = battle.groups[command][Config.GROUP_CAVALRY]
			for step in 180:
				Commander.execute(battle, command, DT)
				if cavalry.order == Config.ORDER_CHARGE:
					break
			assert(cavalry.order == Config.ORDER_CHARGE and battle.ai_trace.last(side, Config.GROUP_CAVALRY).reason == Commander.REASON_TARGET_CLOSE)
			assert(battle.groups[command][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD)

## A real battle with the commander on both sides: the trace does not change it, a seed repeats it, and the commander
## attacks within a minute (no charge timer: the first charge comes from the distance or from patience).
func _test_session(catalog: Catalog) -> void:
	var runs := []
	for traced in [false, true, false]:
		var setup: Setup = load("res://content/scenarios/demo_battle.tres").to_setup()
		setup.hero_profile.clear()
		setup.companion_profiles.clear()
		setup.player_army.assign([{"type": "n1", "n": 24}, {"type": "n2a", "n": 12}, {"type": "n3c", "n": 8}])
		setup.enemy_army.assign([{"type": "e1", "n": 24}, {"type": "e2a", "n": 12}, {"type": "e3c", "n": 8}])
		setup.player_ai_profile = Config.AI_PROFILE_COMMANDER
		setup.enemy_ai_profile = Config.AI_PROFILE_COMMANDER
		var session = Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), Columns.create())
		assert(session != null and session.ai_profiles() == [Config.AI_PROFILE_COMMANDER, Config.AI_PROFILE_COMMANDER])
		session._state.mark_gone(session._hero)
		session.set_ai_debug(traced)
		var charged_at := -1
		for tick in 3600:
			session.step()
			if charged_at < 0 and session._state.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE:
				charged_at = tick
			if traced and tick == 600:
				var debug: Dictionary = session.ai_debug_snapshot()
				assert(debug.sides[1].plan in Commander.PLANS and not debug.sides[1].plan_details.is_empty())
				assert(debug.sides[1].profile == Config.AI_PROFILE_COMMANDER)
				assert(debug.sides[1].groups[Config.GROUP_CAVALRY].has("role") and debug.sides[1].groups[Config.GROUP_INFANTRY].role == "")
		assert(charged_at > 0, "The commander's infantry charges within 60 s")
		runs.append(var_to_str(session.snapshot()))
	assert(runs[0] == runs[1], "The trace does not change the battle")
	assert(runs[0] == runs[2], "A seed repeats its battle")

## Part 5 (#270): an infantry group with at least AI_CMD_WALL_SHIELD_SHARE shield bearers raises a shield wall under fire:
## closer slots, the march as quick as under fire without a wall, the reason in the trace. Fewer shields, no wall; out of fire for
## AI_CMD_WALL_CLEAR_SECONDS it comes down; in a charge it stays while the line is formed and comes down once it goes loose.
## The same for both sides.
func _test_shield_wall() -> void:
	for command in [Config.COMMAND_ENEMY, Config.COMMAND_PLAYER]:
		var side := State.side_of(command)
		var battle := _eager(_field(command, 1700.0, 4, 4, 6, 3), command)
		battle.ai_trace = DecisionTrace.new()
		var infantry: Group = battle.groups[command][Config.GROUP_INFANTRY]
		assert(is_equal_approx(infantry.shield_share(), 0.5))
		var mind := _decide(battle, command)
		assert(not infantry.wall, "Out of fire, no wall")
		assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, Config.AI_INFANTRY_ADVANCE_SPEED))
		infantry.layout()
		var open_gap := _slot_gap(infantry)
		battle.missile_losses[side] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0
		mind = _decide(battle, command, 10.5)
		assert(infantry.wall, "Under fire with half shield bearers: the wall goes up (command %d)" % command)
		assert(is_equal_approx(_slot_gap(infantry), open_gap * Config.AI_CMD_WALL_SPACING), "The wall closes up its slots")
		assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * FOOT_SPEED), "The wall is no slower")
		var last := battle.ai_trace.last(side, Config.GROUP_INFANTRY)
		assert(last.decision == Commander.DECISION_ADVANCE and last.reason == Commander.REASON_SHIELD_WALL and last.values.wall)
		assert(battle.ai_trace.snapshot().recent.any(func(record: Dictionary): return record.decision == Commander.DECISION_WALL_UP), "The wall goes up in the trace")
		# Out of fire: the wall stays AI_CMD_WALL_CLEAR_SECONDS, then comes down and the slots open again.
		battle.missile_losses[side] = 0.0
		_decide(battle, command, 11.0)
		assert(infantry.wall, "Not out of fire long enough")
		_decide(battle, command, 10.5 + Config.AI_CMD_WALL_CLEAR_SECONDS)
		assert(not infantry.wall and is_equal_approx(_slot_gap(infantry), open_gap), "Out of fire: the wall comes down")
		assert(battle.ai_trace.snapshot().recent.any(func(record: Dictionary): return record.decision == Commander.DECISION_WALL_DOWN and record.reason == Commander.REASON_WALL_OUT_OF_FIRE))
		# A charge: the wall stays with a formed line under fire and comes down when the line goes loose.
		battle.missile_losses[side] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0
		_decide(battle, command, 13.0)
		assert(infantry.wall)
		infantry.order = Config.ORDER_CHARGE
		infantry.formed = true
		battle.missile_losses[side] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0
		_decide(battle, command, 13.5)
		assert(infantry.wall, "A formed line charges in its wall")
		infantry.formed = false
		battle.missile_losses[side] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0
		_decide(battle, command, 14.0)
		assert(not infantry.wall, "A loose charge drops the wall")
		assert(battle.ai_trace.last(side, Config.GROUP_INFANTRY).reason == Commander.REASON_WALL_CHARGE)
	# Fewer than half shield bearers: no wall under fire.
	var few := _eager(_field(Config.COMMAND_ENEMY, 1700.0, 4, 4, 6, 2), Config.COMMAND_ENEMY)
	few.missile_losses[1] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0
	var plain := _decide(few, Config.COMMAND_ENEMY)
	assert(not few.groups[1][Config.GROUP_INFANTRY].wall, "Too few shields for a wall")
	assert(is_equal_approx(plain.tasks[Config.GROUP_INFANTRY].speed, Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * FOOT_SPEED))

## The smallest distance between two slots of the group.
func _slot_gap(group: Group) -> float:
	var best := INF
	for a: Unit in group.units:
		for b: Unit in group.units:
			if a != b:
				best = minf(best, a.slot_offset.distance_to(b.slot_offset))
	return best
