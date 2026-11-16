extends SceneTree
## ADR-022: the AI profile in BattleSetup and the AI debug snapshot. Turning the decision trace on and off
## must not change a battle; the snapshot is detached; the worker publishes the same snapshot as the
## synchronous path; the profile field selects the brain and rejects unknown values.
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Simulation = preload("res://core/battle/api/battle_simulation.gd")
const Worker = preload("res://adapters/godot/battle_worker.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Config = preload("res://core/battle/config.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const DecisionTrace = preload("res://core/battle/simulation/ai/decision_trace.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const TICKS := 900

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	_test_trace_keeps_battle(catalog, false)
	_test_trace_keeps_battle(catalog, true)
	_test_worker(catalog)
	_test_profiles(catalog)
	_test_reasons()
	print("AI debug snapshot tests passed")
	quit(0)

func _setup(siege: bool) -> Setup:
	var setup: Setup = load("res://content/scenarios/demo_siege.tres" if siege else "res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	if not siege:
		setup.player_army.assign([{"type": "n1", "n": 24}, {"type": "n2a", "n": 12}, {"type": "n3c", "n": 8}])
		setup.enemy_army.assign([{"type": "e1", "n": 24}, {"type": "e2a", "n": 12}, {"type": "e3c", "n": 8}])
	return setup

func _session(catalog: Catalog, setup: Setup):
	return Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), Columns.create())

## Three runs of one battle: no trace, trace from the start, trace toggled with snapshots taken and mutated.
func _test_trace_keeps_battle(catalog: Catalog, siege: bool) -> void:
	var started := Time.get_ticks_msec()
	var plain = _session(catalog, _setup(siege))
	var traced = _session(catalog, _setup(siege))
	var toggled = _session(catalog, _setup(siege))
	traced.set_ai_debug(true)
	assert(traced.ai_debug_enabled() and not plain.ai_debug_enabled())
	assert(plain.ai_debug_snapshot().is_empty(), "No snapshot while debugging is off")
	for session in [plain, traced, toggled]:
		session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	var records_seen := false
	# Sieges are shorter: a siege tick costs much more than a field tick of the same size (contacts with the wall).
	var ticks := TICKS if not siege else TICKS / 2
	for tick in ticks:
		if tick % 97 == 0:
			toggled.set_ai_debug(not toggled.ai_debug_enabled())
		for session in [plain, traced, toggled]:
			session.step()
		if tick % 30 == 0:
			var debug: Dictionary = traced.ai_debug_snapshot()
			_check_shape(debug)
			records_seen = records_seen or debug.records > 0
			debug.sides[1].groups[0].order = "nonsense"
			debug.units.positions.clear()
			var other: Dictionary = toggled.ai_debug_snapshot()
			if not other.is_empty():
				other.sides[0].groups.clear()
		if tick % 60 == 0:
			var expected := var_to_str(plain.snapshot())
			assert(var_to_str(traced.snapshot()) == expected, "Trace changed the battle at tick %d" % tick)
			assert(var_to_str(toggled.snapshot()) == expected, "Toggling the trace changed the battle at tick %d" % tick)
		var events := var_to_str(plain.take_events())
		assert(var_to_str(traced.take_events()) == events and var_to_str(toggled.take_events()) == events)
	assert(var_to_str(traced.result()) == var_to_str(plain.result()))
	# The garrison only decides at the sortie timer (45 s); its plan label is there from the first tick.
	assert(records_seen or siege, "The reference brain records its decisions")
	var final: Dictionary = traced.ai_debug_snapshot()
	assert(final.sides[1].plan == (Tactics.PLAN_HOLD_WALLS if siege else Tactics.PLAN_ENGAGE), "The defender side reports a plan label")
	assert(final.sides[1].groups[0].order == traced._state.groups[1][0].order, "Mutating an old snapshot changed nothing")
	print("%s (%d ms): trace on/off identical over %d ticks, %d records, plan %s" % ["siege" if siege else "field", Time.get_ticks_msec() - started, ticks, final.records, final.sides[1].plan])

func _check_shape(debug: Dictionary) -> void:
	assert(debug.sides.size() == 2 and debug.assessment_tick >= 0)
	for side in 2:
		var entry: Dictionary = debug.sides[side]
		assert(entry.groups.size() == Config.GROUP_KINDS and entry.has("assessment"))
		for group in entry.groups:
			assert(group.has("order") and group.has("last") and group.assessment.has("morale"))
	var units: Dictionary = debug.units
	assert(units.positions.size() == units.modes.size() and units.modes.size() == units.sides.size())
	for mode in units.modes:
		assert(mode >= 0 and mode < units.mode_names.size())

## The worker joins before reading and publishes the same debug snapshot as the synchronous simulation.
func _test_worker(catalog: Catalog) -> void:
	var reference := Simulation.new(_session(catalog, _setup(false)))
	var worker := Worker.new(_session(catalog, _setup(false)))
	assert(worker.supports_async())
	reference.set_ai_debug(true)
	worker.set_ai_debug(true)
	for batch in 120:
		var count := batch % 4 + 1
		worker.start_batch(count)
		for tick in count: reference.step()
		if batch % 7 == 0:
			assert(var_to_str(worker.ai_debug_snapshot()) == var_to_str(reference.ai_debug_snapshot()), "Getter joins the running batch")
		assert(worker.finish_batch() == count)
		assert(var_to_str(worker.ai_debug_snapshot()) == var_to_str(reference.ai_debug_snapshot()))
		assert(worker.take_events() == reference.take_events())
	worker.set_ai_debug(false)
	assert(worker.ai_debug_snapshot().is_empty())
	worker.dispose()
	assert(worker.ai_debug_snapshot().is_empty(), "A disposed worker returns nothing")

func _test_profiles(catalog: Catalog) -> void:
	var defaults := _setup(false)
	assert(defaults.player_ai_profile == Config.AI_PROFILE_PLAYER and defaults.enemy_ai_profile == Config.AI_PROFILE_REFERENCE)
	var copy: Setup = defaults.duplicate()
	copy.enemy_ai_profile = "zz_unknown"
	assert(defaults.enemy_ai_profile == Config.AI_PROFILE_REFERENCE, "Setup copies own the profile")
	assert(_session(catalog, copy) == null, "Unknown profile is rejected")
	var siege := _setup(true)
	siege.enemy_ai_profile = Config.AI_PROFILE_PLAYER
	assert(_session(catalog, siege) == null, "Siege defenders need a brain")
	# The field selects the brain: a passive enemy never charges, an AI player side moves by itself.
	var passive_setup := _setup(false)
	passive_setup.enemy_ai_profile = Config.AI_PROFILE_PLAYER
	passive_setup.player_ai_profile = Config.AI_PROFILE_REFERENCE
	var passive = _session(catalog, passive_setup)
	var normal = _session(catalog, _setup(false))
	assert(passive.ai_profiles() == [Config.AI_PROFILE_REFERENCE, Config.AI_PROFILE_PLAYER])
	var start: Vector2 = passive._state.groups[0][Config.GROUP_INFANTRY].center
	var held: Vector2 = normal._state.groups[0][Config.GROUP_INFANTRY].center
	for tick in 600:
		passive.step()
		normal.step()
	for group in passive._state.groups[1]:
		assert(group.order == Config.ORDER_HOLD, "Without a brain the enemy only follows orders")
	assert(passive._state.groups[0][Config.GROUP_INFANTRY].center.distance_to(start) > 100.0, "The AI player side advances")
	assert(normal._state.groups[0][Config.GROUP_INFANTRY].center == held, "The player's side waits for orders")
	assert(normal._state.groups[1][Config.GROUP_INFANTRY].center.x < 2600 - Config.FRONT_X, "The reference enemy advances")

## Codes of the reference brain for a forced kite and for a squad charge (DESIGN.md 1.4).
func _test_reasons() -> void:
	var battle := State.new()
	battle.setup_groups()
	battle.ai_trace = DecisionTrace.new()
	for i in Config.AI_SQUAD_MIN_UNITS:
		battle.add_grouped_unit(Unit.new(battle.units.size(), 0, Vector2(300, 400 + i * 20), 100, 0, 1), Config.GROUP_INFANTRY)
	var hero := Unit.new(battle.units.size(), 0, Vector2(1000, 800), 100, 0, 1)
	battle.add_unit(hero)
	hero.hero = true
	hero.speed = 160.0
	for i in 4:
		var unit := Unit.new(battle.units.size(), 1, Vector2(1200, 790 + i * 5), 100, 0, 1)
		battle.add_grouped_unit(unit, Config.GROUP_INFANTRY)
		unit.speed = 60.0
		unit.target_handle = hero.unit_handle
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	infantry.order = Config.ORDER_CHARGE
	infantry.center = Vector2(1500, 800)
	var dt := Config.AI_SQUAD_SCAN_SECONDS
	for i in roundi(Config.AI_KITE_SECONDS / dt) + 1:
		battle.ai_trace.begin_tick(i, 3.0 + i * dt)
		Tactics.enemy_step(battle, 1, 3.0 + i * dt, dt)
	var recent: Array = battle.ai_trace.snapshot().recent
	var call_off: Array = recent.filter(func(entry): return entry.decision == Tactics.DECISION_CALL_OFF)
	assert(call_off.size() == 1 and call_off[0].reason == Tactics.REASON_HOPELESS_CHASE and call_off[0].group == Config.GROUP_INFANTRY)
	assert(call_off[0].values.focus_kind == Config.GROUP_INFANTRY)
	var last := battle.ai_trace.last(1, Config.GROUP_INFANTRY)
	assert(last.decision == Tactics.DECISION_ADVANCE and last.reason == Tactics.REASON_ON_FOCUS, "After calling off, the line marches on its focus")
	for unit in battle.groups[0][Config.GROUP_INFANTRY].units:
		unit.position = infantry.center + Vector2(-40, 0)
	for i in 2:
		Tactics.enemy_step(battle, 1, 10.0 + i * dt, dt)
	last = battle.ai_trace.last(1, Config.GROUP_INFANTRY)
	assert(last.decision == Tactics.DECISION_CHARGE and last.reason == Tactics.REASON_CONTACT_AFTER_CALL_OFF)
	var count := battle.ai_trace.record_count()
	Tactics.enemy_step(battle, 1, 11.0, dt)
	assert(battle.ai_trace.record_count() <= count + 2, "A decision still in force is not recorded again")
