extends SceneTree
const Combat = preload("res://battle/rules/combat.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")

func _initialize() -> void:
	_test_spread_and_lead()
	_test_hit_height_and_origin()
	print("Projectile tests passed")
	quit(0)

func _test_spread_and_lead() -> void:
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	attacker.accuracy = 0.02
	attacker.damage = 20
	var target := Unit.new(1, 1, Vector2(200, 100), 100, 0, 1)
	target.velocity = Vector2(10, -5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 42
	var spread: float = Config.SHOT_BASE_SCATTER + 100.0 * attacker.accuracy
	var duration: float = 100.0 / Config.SHOT_SPEED + Config.PROJECTILE_START_DELAY
	var expected := target.position + target.velocity * duration * Config.AIM_VELOCITY_LEAD
	expected += Vector2((expected_rng.randf() + expected_rng.randf() - 1.0) * spread, (expected_rng.randf() + expected_rng.randf() - 1.0) * spread)
	var shot: Dictionary = Combat.shoot(attacker, target, rng)
	assert(shot.impact.is_equal_approx(expected))
	assert(shot.origin == Vector2(100, 84))
	assert(is_equal_approx(shot.duration, duration))
	assert(not shot.throwing and not shot.crossbow)
	attacker.weapon_kind = Config.PROJECTILE_THROW_WEAPON
	var thrown: Dictionary = Combat.shoot(attacker, target, rng)
	assert(thrown.throwing)
	assert(is_equal_approx(thrown.duration, 100.0 / Config.THROW_SPEED + Config.PROJECTILE_START_DELAY))
	attacker.weapon_kind = Config.PROJECTILE_CROSSBOW_WEAPON
	assert(Combat.shoot(attacker, target, rng).crossbow)

func _test_hit_height_and_origin() -> void:
	var battle := State.new()
	battle.setup_groups()
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	attacker.hero = true # Keep projectile resolution isolated from AI attacks.
	var target := Unit.new(1, 1, Vector2(200, 100), 100, 0, 1)
	target.fleeing = true # Projectile can hit fleeing units; AI attack step skips them.
	target.block_chance = 1.0
	target.facing = PI
	battle.add_unit(attacker)
	battle.add_unit(target)
	var shot := {"side": 0, "source": attacker, "origin": Vector2(100, 84), "impact": Vector2(200, 90), "damage": 20.0, "pierce": 0.0, "time": 0.0, "duration": 0.1}
	battle.projectiles.append(shot)
	attacker.position = Vector2(300, 100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	CombatStep.step(battle, 0.1, rng)
	assert(target.hp == 100.0) # Blocking uses the launch point, not the current shooter position.
	assert(battle.projectiles.is_empty())
	target.block_chance = 0.0
	shot = shot.duplicate()
	shot.time = 0.0
	battle.projectiles.append(shot)
	CombatStep.step(battle, 0.1, rng)
	assert(target.hp < 100.0)
