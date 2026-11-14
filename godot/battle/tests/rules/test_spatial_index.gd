extends SceneTree
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Index = preload("res://battle/rules/spatial_index.gd")
const Targeting = preload("res://battle/rules/targeting.gd")
const Movement = preload("res://battle/rules/movement.gd")
const LegacyMovement = preload("res://battle/tests/fixtures/legacy_movement.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const LegacyCombatStep = preload("res://battle/tests/fixtures/legacy_combat_step.gd")
const TEST_UNIT_COUNT := 100
const TEST_TICKS := 18
const TEST_DT := 1.0 / 30.0

func _initialize() -> void:
	for seed in [7, 17, 41]:
		for dense in [false, true]:
			_check_battle(seed, dense)
	print("Spatial index differential tests passed")
	quit(0)

func _check_battle(seed: int, dense: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var fast := State.new()
	var reference := State.new()
	fast.setup_groups()
	reference.setup_groups()
	for i in TEST_UNIT_COUNT:
		var side := i % 2
		var center := Vector2(1100, 850) if dense else (Vector2(500, 850) if side == 0 else Vector2(2100, 850))
		var spread := 100.0 if dense else 300.0
		var position := center + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
		if i % 13 == 0:
			position = center # Exact overlaps and tie candidates.
		for state in [fast, reference]:
			var unit := Unit.new(i, side, position, 20 if i % 11 == 0 else 100, 0, 1)
			unit.speed = 50.0
			unit.damage = 15.0
			unit.attack_interval = 0.2
			unit.attack_range = 180.0 if i % 5 == 0 else 0.0
			unit.mounted = i % 7 == 0
			unit.collision_radius = Config.HORSE_COLLISION_RADIUS if unit.mounted else Config.FOOT_COLLISION_RADIUS
			unit.mass = Config.HORSE_MASS if unit.mounted else Config.FOOT_MASS
			unit.fleeing = i % 23 == 0
			unit.dead = i % 29 == 0
			unit.gone = i % 31 == 0
			state.add_grouped_unit(unit, Config.GROUP_INFANTRY)
			state.groups[side][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	var fast_rng := RandomNumberGenerator.new()
	fast_rng.seed = seed
	var reference_rng := RandomNumberGenerator.new()
	reference_rng.seed = seed
	for tick in TEST_TICKS:
		var index := Index.new(fast.units)
		for unit: Unit in fast.units:
			var expected: Unit = Targeting.nearest_enemy(fast, unit)
			assert(index.nearest_enemy(unit) == expected)
		var updated_index = Movement.step_formation_only(fast, TEST_DT)
		LegacyMovement.step(reference, TEST_DT, Vector2(780, 850))
		CombatStep.step(fast, TEST_DT, fast_rng, updated_index)
		LegacyCombatStep.step(reference, TEST_DT, reference_rng)
		assert(fast_rng.state == reference_rng.state)
		assert(fast.projectiles.size() == reference.projectiles.size())
		for shot_index in fast.projectiles.size():
			assert(fast.projectiles[shot_index].impact == reference.projectiles[shot_index].impact)
		for i in TEST_UNIT_COUNT:
			var actual: Unit = fast.units[i]
			var old: Unit = reference.units[i]
			assert(actual.position.is_equal_approx(old.position), "position changed at seed %d, tick %d, unit %d" % [seed, tick, i])
			assert(actual.velocity.is_equal_approx(old.velocity))
			assert(actual.facing == old.facing and actual.gone == old.gone)
			assert(actual.hp == old.hp and actual.dead == old.dead and actual.kills == old.kills)
			assert(actual.attack_cooldown == old.attack_cooldown)
