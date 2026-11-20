extends SceneTree
## Army commander, stage 1g part 1 (DESIGN.md 4.2, #266): the "commander" profile, decisions on its own tick of the
## schedule and execution every tick, the attack plan (march speed by the enemy shooters' reach, no charge timer,
## archers behind their line), the same code for both sides, the field assessment kept by the morale check, the plan
## scores in the trace, and a battle that the trace does not change.
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

func _initialize() -> void:
	_test_profile()
	_test_schedule_and_execution()
	_test_march_speed()
	_test_no_charge_timer()
	_test_charge_in_reach()
	_test_archers()
	_test_both_sides()
	_test_assessment_and_plan()
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	_test_session(catalog)
	print("Commander tests passed")
	quit(0)

## A synthetic field: the AI `command` on the right half (mirrored: on the left), its enemy near the other edge.
## Own: infantry (6) at x 1700, archers (4, range ARCHER_REACH) at 1800, three riders at 1850. Enemy: infantry (6) at
## 500, archers (4, range FOE_REACH) at 400, three riders at 300. All men alike (tier 1, full health): equal strength.
func _field(command: int, own_infantry_x := 1700.0, own_archers := 4, foe_archers := 4, own_infantry := 6) -> State:
	var battle := State.new()
	battle.setup_groups()
	var side := State.side_of(command)
	var mirror := side == 0
	for i in own_infantry: _add(battle, side, Config.GROUP_INFANTRY, _at(battle, own_infantry_x, 800 + i * 20, mirror))
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

func _add(battle: State, side: int, kind: int, at: Vector2, speed := FOOT_SPEED, reach := 0.0) -> Unit:
	var unit := Unit.new(battle.units.size(), side, at, 100, 0, 1)
	unit.speed = speed
	unit.attack_range = reach
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

func _test_profile() -> void:
	assert(Profiles.is_known(Config.AI_PROFILE_COMMANDER) and Profiles.brain(Config.AI_PROFILE_COMMANDER) == Commander)
	assert(Profiles.brain(Config.AI_PROFILE_REFERENCE) == Tactics, "The reference brain stays as it was")
	var setup := Setup.new()
	setup.enemy_ai_profile = Config.AI_PROFILE_COMMANDER
	assert(Profiles.valid(setup))
	assert(Setup.new().enemy_ai_profile == Config.AI_PROFILE_REFERENCE, "The game keeps the reference brain until part 7 (#272)")

## Nothing moves while the army deploys; then one decision on the command's own schedule tick and the march every tick.
func _test_schedule_and_execution() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
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
	assert(details.best.size() == 1 and details.best[0].plan == Commander.PLAN_ATTACK and details.has("reason"))

## Out of reach of the enemy shooters the line keeps AI_INFANTRY_ADVANCE_SPEED; within it, or losing men to missiles,
## AI_CMD_UNDER_FIRE_SPEED_SHARE of its own mean speed.
func _test_march_speed() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, Config.AI_INFANTRY_ADVANCE_SPEED), "Out of reach: formation pace")
	assert(is_equal_approx(battle.groups[1][Config.GROUP_INFANTRY].mean_speed(), FOOT_SPEED))
	battle.missile_losses[1] = Config.AI_MISSILE_PRESSURE_LOSSES + 1.0 # The scan decays it a little.
	mind = _decide(battle, Config.COMMAND_ENEMY)
	var hurried := Config.AI_CMD_UNDER_FIRE_SPEED_SHARE * FOOT_SPEED
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, hurried), "Losing men to missiles: quick march")
	battle = _field(Config.COMMAND_ENEMY, 850.0) # 450 from the enemy archers (range 500), 350 from their infantry.
	mind = _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.tasks[Config.GROUP_INFANTRY].speed, hurried), "Within reach of the enemy shooters: quick march")
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD)
	assert(Commander.march_speed(battle.groups[1][Config.GROUP_INFANTRY], true, 80.0) == 80.0, "Never slower than out of fire")

## No "charge after 80 s": far from the enemy the line keeps marching; the reference brain charges by its timer.
func _test_no_charge_timer() -> void:
	var elapsed := Config.AI_INFANTRY_FORCE_CHARGE_SECONDS + 20.0
	var battle := _field(Config.COMMAND_ENEMY)
	_decide(battle, Config.COMMAND_ENEMY, elapsed)
	for i in 30:
		Commander.execute(battle, Config.COMMAND_ENEMY, DT)
	assert(battle.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_HOLD, "The commander has no charge timer")
	var reference := _field(Config.COMMAND_ENEMY)
	Tactics.enemy_step(reference, Config.COMMAND_ENEMY, elapsed, DT)
	assert(reference.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE, "The reference brain charges by its timer")

## Within AI_INFANTRY_CHARGE_DISTANCE of an enemy squad the line charges at once, with the reason and the notice.
func _test_charge_in_reach() -> void:
	var battle := _field(Config.COMMAND_ENEMY, 500.0 + Config.AI_INFANTRY_CHARGE_DISTANCE - 20.0)
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
	var battle := _field(Config.COMMAND_ENEMY, 1000.0)
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	var task: Commander.Task = mind.tasks[Config.GROUP_ARCHERS]
	var archers: Group = battle.groups[1][Config.GROUP_ARCHERS]
	# In range of the nearest squad (x 500) at x 500 + 0.85 x 400 = 840, ahead of the line (x 1000): 105 behind it.
	assert(task.active and task.point.is_finite())
	assert(absf(task.point.x - (1000.0 + Config.ARCHER_REAR_OFFSET)) < 1.0, "Not ahead of the own line: %s" % task.point)
	battle = _field(Config.COMMAND_ENEMY, 1700.0)
	mind = _decide(battle, Config.COMMAND_ENEMY)
	task = mind.tasks[Config.GROUP_ARCHERS]
	assert(not task.point.is_finite(), "Right behind their line the archers stand; they do not step back")
	battle = _field(Config.COMMAND_ENEMY, 1000.0)
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

## One code for both sides: the mirrored field gives mirrored tasks.
func _test_both_sides() -> void:
	for own_x in [1700.0, 1000.0, 850.0]:
		var right := _field(Config.COMMAND_ENEMY, own_x)
		var left := _field(Config.COMMAND_PLAYER, own_x)
		var a := _decide(right, Config.COMMAND_ENEMY)
		var b := _decide(left, Config.COMMAND_PLAYER)
		assert(a.plan == b.plan and a.reason == b.reason and is_equal_approx(a.ratio, b.ratio))
		for kind in Config.GROUP_KINDS:
			var one: Commander.Task = a.tasks[kind]
			var other: Commander.Task = b.tasks[kind]
			assert(one.active == other.active and is_equal_approx(one.speed, other.speed) and one.charge_within == other.charge_within)
			assert(one.point.is_finite() == other.point.is_finite())
			if one.point.is_finite():
				assert(absf(one.point.x - (right.arena_size.x - other.point.x)) < 1e-3 and absf(one.point.y - other.point.y) < 1e-3, "Mirrored task of group %d" % kind)
	for kind in Config.GROUP_KINDS:
		assert(Commander.task_point(State.new(), Config.COMMAND_ENEMY, kind) == Vector2.INF, "No commander, no march point")

## The morale check keeps the field assessment in State; the commander reads it for the plan score.
func _test_assessment_and_plan() -> void:
	var battle := _field(Config.COMMAND_ENEMY)
	assert(battle.assessment.is_empty() and battle.assessment_serial == 0)
	Morale.tick(battle)
	assert(battle.assessment.sides.size() == 2 and battle.assessment_serial == 1, "The morale check keeps its assessment")
	var mind := _decide(battle, Config.COMMAND_ENEMY)
	assert(is_equal_approx(mind.ratio, 1.0) and mind.outshot == 0.0 and mind.reason == Commander.REASON_ONLY_PLAN)
	assert(is_equal_approx(mind.best[0].score, Commander.ramp(1.0, Config.AI_CMD_ATTACK_RATIO[0], Config.AI_CMD_ATTACK_RATIO[1])))
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

## A real battle with the commander on both sides: the trace does not change it, a seed repeats it, and the commander
## attacks (no charge timer: the first charge comes from the distance).
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
		for tick in 1200:
			session.step()
			if charged_at < 0 and session._state.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE:
				charged_at = tick
			if traced and tick == 600:
				var debug: Dictionary = session.ai_debug_snapshot()
				assert(debug.sides[1].plan == Commander.PLAN_ATTACK and not debug.sides[1].plan_details.is_empty())
				assert(debug.sides[1].profile == Config.AI_PROFILE_COMMANDER)
		assert(charged_at > 0, "The commander's infantry charges within 20 s")
		runs.append(var_to_str(session.snapshot()))
	assert(runs[0] == runs[1], "The trace does not change the battle")
	assert(runs[0] == runs[2], "A seed repeats its battle")
