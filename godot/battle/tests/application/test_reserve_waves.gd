extends SceneTree
## src/03_battle.js fill() / battleWaves() / kill() / finishBattle(): undead and quick battles keep extra figures in reserve.
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const ArmyBuilder = preload("res://battle/data/army_builder.gd")
const Reinforcements = preload("res://battle/data/reinforcements.gd")
const BattleResult = preload("res://battle/rules/result.gd")
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
const Feedback = preload("res://battle/presentation/combat_feedback.gd")

var _catalog := Catalog.new()

func _initialize() -> void:
	assert(_catalog.load_data())
	_check_reserve_instead_of_merging()
	_check_wave_release()
	_check_bonded_leader_scatters_reserve()
	_check_result_counts_reserve()
	_check_quick_battle_and_living_armies()
	_check_journal_and_snapshot()
	print("Reserve wave tests passed")
	quit(0)

func _state() -> State:
	var state := State.new()
	state.setup_groups()
	state.side_factions = ["nord", "undead"]
	return state

func _check_reserve_instead_of_merging() -> void:
	var state := _state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert(ArmyBuilder.spawn(state, 1, [{"type": "z1", "n": 30}, {"type": "s1", "n": 20}], "undead", _catalog, rng, 12, "", 0.0, true))
	assert(state.units.size() == 12)
	for unit: Unit in state.units:
		assert(unit.weight == 1.0, "Reserve armies are not merged into heavier figures")
	assert(state.reserve[1].size() == 38)
	assert(state.reserve_caps[1] == 12)
	var mix := {}
	for id in state.reserve[1]:
		mix[id] = true
	for unit: Unit in state.units:
		mix[unit.troop_id] = true
	assert(mix.has("z1") and mix.has("s1"), "The shuffle draws figures of both types")
	# Without waves the same army merges, as for living armies in a regular battle.
	var merged := _state()
	assert(ArmyBuilder.spawn(merged, 1, [{"type": "z1", "n": 30}, {"type": "s1", "n": 20}], "undead", _catalog, rng, 12))
	assert(merged.reserve[1].is_empty())
	var weight := 0.0
	for unit: Unit in merged.units:
		weight += unit.weight
	assert(is_equal_approx(weight, 50.0))

func _check_wave_release() -> void:
	var state := _state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	assert(ArmyBuilder.spawn(state, 1, [{"type": "z1", "n": 40}], "undead", _catalog, rng, 12, "", 0.0, true))
	state.take_events()
	# Waves wait while there is no room for a full third of the cap.
	Reinforcements.release(state, [0, 12], rng, state.side_factions)
	assert(state.units.size() == 12)
	Reinforcements.release(state, [0, 9], rng, state.side_factions)
	assert(state.units.size() == 12, "Room 3 < wave 4")
	var active := [0, 8]
	Reinforcements.release(state, active, rng, state.side_factions)
	assert(state.units.size() == 16 and state.reserve[1].size() == 24)
	assert(active[1] == 12)
	for i in range(12, 16):
		var unit: Unit = state.units[i]
		assert(unit.position.x > state.arena_size.x - Config.RESERVE_EDGE_OFFSET - Config.RESERVE_SPAWN_X_JITTER - 0.01)
		assert(absf(unit.position.y - state.arena_size.y / 2.0) <= Config.RESERVE_SPAWN_Y_SPREAD)
		assert(unit.morale_immune and unit.base_morale == 999.0, "Undead traits apply to wave units")
		assert(unit in state.groups[1][unit.group_kind].units)
	var events := state.take_events()
	assert(events.size() == 1 and events[0].kind == Event.Kind.RESERVE_WAVE)
	assert(events[0].count == 4 and events[0].remaining == 24 and events[0].side == 1)
	assert("undead" in events[0].troop_factions)
	# An empty side receives the whole room, limited by one wave.
	Reinforcements.release(state, [0, 0], rng, state.side_factions)
	assert(state.reserve[1].size() == 20)

func _check_bonded_leader_scatters_reserve() -> void:
	var state := _state()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert(ArmyBuilder.spawn(state, 1, [{"type": "z1", "n": 20}, {"type": "s3", "n": 1}], "undead", _catalog, rng, 6, "Некромант", 0.0, true))
	var leader: Unit = null
	for unit: Unit in state.units:
		if unit.leader:
			leader = unit
	if leader == null:
		# The shuffle may leave the highest tier in reserve; promote one figure as the browser leader would.
		leader = state.units[0]
		leader.leader = true
	var before: int = state.reserve[1].size()
	state.kill(leader, null, rng)
	var lost := roundi(before * Config.LEADER_BOND_RESERVE_LOSS)
	assert(state.reserve[1].size() == before - lost)
	assert(state.reserve_lost[1] == lost)
	var down := state.take_events().filter(func(e): return e.kind == Event.Kind.DOWN and e.target_id == leader.id)
	assert(down.size() == 1 and down[0].target_bonded)

func _check_result_counts_reserve() -> void:
	var state := _state()
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 3)
	hero.hero = true
	state.add_unit(hero)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert(ArmyBuilder.spawn(state, 1, [{"type": "z1", "n": 20}], "undead", _catalog, rng, 6, "", 0.0, true))
	state.reserve_lost[1] = 4
	state.reserve[1].resize(10)
	state.reserve[1].fill("z1")
	var result := BattleResult.build(state, hero, rng, 10.0, false)
	assert(result.enemyLeft.z1 == 16, "6 on the field + 10 waiting")
	assert(result.enemyDead == 4)
	assert(result.enemyTotal == 20)

func _check_quick_battle_and_living_armies() -> void:
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.player_army = [{"type": "n1", "n": 400}]
	setup.enemy_army = [{"type": "e1", "n": 400}]
	setup.companion_profiles = []
	setup.hero_profile = {}
	assert(not setup.uses_reserve_waves("emp"))
	assert(setup.uses_reserve_waves("undead"))
	var regular := Factory.create(setup, _catalog)
	assert(regular != null and regular.snapshot().reserve == [0, 0])
	setup.quick = true
	var quick := Factory.create(setup, _catalog)
	assert(quick.snapshot().reserve == [100, 100])

func _check_journal_and_snapshot() -> void:
	var feedback := Feedback.new()
	feedback.set_seed(1)
	feedback.advance(0.0, [
		{"kind": Event.Kind.RESERVE_WAVE, "side": 1, "count": 200, "remaining": 50, "troop_factions": ["undead"]},
		{"kind": Event.Kind.RESERVE_WAVE, "side": 0, "count": 30, "remaining": 0, "troop_factions": ["nord"]},
		{"kind": Event.Kind.DOWN, "target_hero": false, "target_companion": false, "target_leader": true, "target_bonded": true, "target_name": "Некромант", "source_hero": false},
	])
	var text := feedback.journal()
	assert(text.contains("Из-за холма выходят ещё 200 мертвецов (в запасе 50)."))
	assert(text.contains("К нам подходит подкрепление: 30 — последняя волна."))
	assert(text.contains("Некромант пал — мертвецы рассыпаются в прах!"))
	var rout := Feedback.new()
	rout.set_seed(2)
	var logged := 0
	for i in 40:
		rout.advance(0.0, [{"kind": Event.Kind.FLED, "target_name": "Ополченец %d" % i}])
		if rout.journal().ends_with("Ополченец %d бежит с поля боя." % i):
			logged += 1
	assert(logged > 8 and logged < 32, "About half of routs reach the journal")
