extends SceneTree
## src/03c_siegedef.js and the battered-wall branch of src/03_battle.js siegeSetup().
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const SiegeSetup = preload("res://battle/data/siege_setup.gd")
const Defense = preload("res://battle/model/siege_defense.gd")
const SiegeDefense = preload("res://battle/rules/siege_defense.gd")
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
const Feedback = preload("res://apps/godot/presentation/battle/combat_feedback.gd")

func _initialize() -> void:
	_check_damaged_wall()
	_check_supplies()
	_check_stones()
	_check_oil()
	_check_no_defenders()
	print("Siege defense tests passed")
	quit(0)

func _siege(damage: float = 0.0, supplies: Dictionary = {}, skill: float = 0.0) -> State:
	var state := State.new()
	state.setup_groups()
	SiegeSetup.apply(state, skill, damage, supplies)
	return state

func _add(state: State, side: int, at: Vector2) -> Unit:
	var unit := Unit.new(state.units.size(), side, at, 500, 0, 1)
	state.add_grouped_unit(unit, Config.GROUP_INFANTRY)
	return unit

func _defenders(state: State, count: int) -> void:
	for i in count:
		_add(state, 1, Vector2(state.wall.x + 60, 200 + i * 30))

func _check_damaged_wall() -> void:
	var intact := _siege()
	assert(intact.wall.gap_at(850.0) == Vector2(770, 930))
	var battered := _siege(0.5)
	assert(battered.wall.gap_at(850.0) == Vector2(740, 960), "Half-battered walls widen the gate by 30 on each side")
	assert(battered.wall.gap_at(330.0 + 1.0) == Vector2(330, 425), "Side breaches keep their size")
	var ruined := _siege(2.0)
	assert(ruined.wall.gap_at(850.0) == Vector2(710, 990), "Damage is clamped to 1")

func _check_supplies() -> void:
	var town: Defense = _siege().siege_defense
	assert(town.stones == 10)
	assert(town.cauldrons.map(func(c): return c.charges) == [2, 1, 1])
	assert(town.cauldrons.map(func(c): return c.cooldown) == [4.0, 6.0, 8.0])
	var castle: Defense = _siege(0.0, {"stones": 14, "oil": 3}).siege_defense
	assert(castle.stones == 14 and castle.cauldrons.map(func(c): return c.charges) == [3, 2, 2])
	var battered: Defense = _siege(1.0, {"stones": 14, "oil": 3}).siege_defense
	assert(battered.stones == 6 and battered.cauldrons.map(func(c): return c.charges) == [1, 1, 1])
	var poor: Defense = _siege(1.0, {"stones": 10, "oil": 2}).siege_defense
	assert(poor.cauldrons.map(func(c): return c.charges) == [1, 1, 1])
	var no_side: Defense = _siege(1.0, {"stones": 10, "oil": 1}).siege_defense
	assert(no_side.cauldrons.map(func(c): return c.charges) == [1, 0, 0], "Side cauldrons need three oil")

func _check_stones() -> void:
	var state := _siege()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	_defenders(state, 6)
	var lone := _add(state, 0, Vector2(state.wall.x - 100, 600))
	var crowd: Array[Unit] = []
	for i in 3:
		crowd.append(_add(state, 0, Vector2(state.wall.x - 200 + i * 10, 1000)))
	var far := _add(state, 0, Vector2(state.wall.x - 500, 1000))
	SiegeDefense.step(state, 4.9, rng)
	assert(state.siege_defense.stones_in_flight.is_empty(), "First stone waits five seconds")
	SiegeDefense.step(state, 0.2, rng)
	var defense: Defense = state.siege_defense
	assert(defense.stones == 9 and defense.stones_in_flight.size() == 1)
	var stone: Dictionary = defense.stones_in_flight[0]
	assert(stone.impact == crowd[0].position, "Aims at the densest group, first on ties")
	assert(stone.origin == Vector2(state.wall.x + 18, 1000))
	var cooldown_bound := 7.0 / (0.6 + 0.4 * 6.0 / 25.0)
	assert(defense.stone_cooldown >= 4.5 / (0.6 + 0.4 * 6.0 / 25.0) - 0.001 and defense.stone_cooldown <= cooldown_bound)
	var events := state.take_events()
	assert(events.size() == 1 and events[0].kind == Event.Kind.STONE_THROWN and events[0].first)
	SiegeDefense.step(state, 0.5, rng)
	assert(crowd[0].hp == 500)
	SiegeDefense.step(state, 0.5, rng)
	assert(defense.stones_in_flight.is_empty())
	assert(crowd[0].hp == 500 - 32, "Direct hit deals the full 32")
	assert(crowd[1].hp == 500 - roundf(32 * (1.0 - 10.0 / 52.0 * 0.5)))
	assert(crowd[0].morale == crowd[0].base_morale - 32 * Config.HIT_MORALE_PER_DAMAGE - 4.0)
	assert(lone.hp == 500 and far.hp == 500)
	var landed := state.take_events().filter(func(e): return e.kind == Event.Kind.STONE_LANDED)
	assert(landed.size() == 1 and landed[0].position == crowd[0].position)
	# A lone attacker is not worth a stone: the defenders wait and retry.
	var quiet := _siege()
	_defenders(quiet, 6)
	_add(quiet, 0, Vector2(quiet.wall.x - 100, 600))
	quiet.siege_defense.stone_cooldown = 0.0
	SiegeDefense.step(quiet, 0.01, rng)
	assert(quiet.siege_defense.stones == 10 and is_equal_approx(quiet.siege_defense.stone_cooldown, Config.SIEGE_STONE_RETRY_SECONDS))
	# Siege skill of companions softens the blow.
	var skilled := _siege(0.0, {}, 0.8)
	_defenders(skilled, 6)
	var target := _add(skilled, 0, Vector2(skilled.wall.x - 100, 600))
	_add(skilled, 0, Vector2(skilled.wall.x - 100, 610))
	skilled.siege_defense.stone_cooldown = 0.0
	SiegeDefense.step(skilled, 0.01, rng)
	SiegeDefense.step(skilled, 1.0, rng)
	assert(target.hp == 500 - roundf(32 * 0.6), "Skill 0.8 halves 40% of stone damage")

func _check_oil() -> void:
	var state := _siege()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	_defenders(state, 4)
	state.siege_defense.stones = 0
	var gate: Array[Unit] = []
	for i in 3:
		gate.append(_add(state, 0, Vector2(state.wall.x - 40, 820 + i * 20)))
	SiegeDefense.step(state, 3.9, rng)
	assert(state.siege_defense.fires.is_empty())
	SiegeDefense.step(state, 0.2, rng)
	var defense: Defense = state.siege_defense
	assert(defense.fires.size() == 1 and defense.cauldrons[0].charges == 1 and defense.cauldrons[0].cooldown == 14.0)
	var fire: Dictionary = defense.fires[0]
	assert(fire.center == Vector2(state.wall.x - 36, 850) and fire.half_size == Vector2(64, 92))
	var events := state.take_events().filter(func(e): return e.kind == Event.Kind.OIL_POURED)
	assert(events.size() == 1 and events[0].first)
	assert(defense.announced == 2)
	# Burning starts in the pouring tick: 6 damage with half armour pierce every half second while it lasts.
	assert(gate[0].hp == 494)
	assert(is_equal_approx(gate[0].morale, gate[0].base_morale - 6.0 - 6.0 * Config.HIT_MORALE_PER_DAMAGE - 1.6))
	SiegeDefense.step(state, 0.01, rng)
	assert(gate[0].hp == 494)
	SiegeDefense.step(state, 0.4, rng)
	assert(gate[0].hp == 494)
	SiegeDefense.step(state, 0.1, rng)
	assert(gate[0].hp == 488)
	for i in 12:
		SiegeDefense.step(state, 0.5, rng)
	assert(defense.fires.is_empty(), "Oil burns out after six seconds")
	var hp := gate[0].hp
	SiegeDefense.step(state, 0.5, rng)
	assert(gate[0].hp == hp)
	# A later stone is no longer announced once oil was.
	var feedback := Feedback.new()
	feedback.advance(0.0, [{"kind": Event.Kind.STONE_THROWN, "first": false}, {"kind": Event.Kind.OIL_POURED, "first": true}])
	assert(feedback.journal() == "Со стены льют кипящее масло!")

func _check_no_defenders() -> void:
	var state := _siege()
	var rng := RandomNumberGenerator.new()
	_defenders(state, 3)
	for i in 6:
		_add(state, 0, Vector2(state.wall.x - 40, 820 + i * 10))
	for i in 40:
		SiegeDefense.step(state, 0.5, rng)
	assert(state.siege_defense.stones == 10 and state.siege_defense.fires.is_empty(), "Three defenders cannot man stones or oil")
	var field := State.new()
	field.setup_groups()
	SiegeDefense.step(field, 1.0, rng) # Field battles have no wall and no supplies.
