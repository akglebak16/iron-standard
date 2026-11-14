extends SceneTree
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Movement = preload("res://battle/rules/movement.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const TICK_SECONDS := 0.1

func _initialize() -> void:
	_check_skirmisher_enters_range_after_attack_check()
	_check_melee_wind_expires_before_movement()
	_check_earlier_unit_can_stop_later_unit()
	print("AI tick order tests passed")
	quit(0)

func _pair() -> Dictionary:
	var battle := State.new()
	battle.setup_groups()
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	var target := Unit.new(1, 1, Vector2(205, 100), 100, 0, 1)
	target.speed = 0.0
	battle.add_grouped_unit(attacker, Config.GROUP_CAVALRY)
	battle.add_grouped_unit(target, Config.GROUP_INFANTRY)
	battle.groups[0][Config.GROUP_CAVALRY].order = Config.ORDER_CHARGE
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	return {"battle": battle, "attacker": attacker, "target": target, "rng": rng}

func _check_skirmisher_enters_range_after_attack_check() -> void:
	var pair := _pair()
	var attacker: Unit = pair.attacker
	attacker.mounted = true
	attacker.speed = 400.0
	attacker.attack_range = 100.0
	attacker.damage = 20.0
	attacker.collision_radius = Config.HORSE_COLLISION_RADIUS
	attacker.mass = Config.HORSE_MASS
	Movement.step(pair.battle, TICK_SECONDS, Vector2.ZERO, 0.0, pair.rng)
	assert(attacker.ai_mode == Config.AI_MODE_SKIRMISH)
	assert(attacker.position.distance_to(pair.target.position) < attacker.attack_range)
	assert(pair.battle.projectiles.is_empty()) # Entry into range happened after this tick's attack check.
	var position_before_shot: Vector2 = attacker.position
	Movement.step(pair.battle, TICK_SECONDS, Vector2.ZERO, 0.0, pair.rng)
	assert(pair.battle.projectiles.size() == 1)
	var origin: Vector2 = pair.battle.projectiles[0].origin
	assert(is_equal_approx(origin.x, position_before_shot.x)) # Shot preceded this tick's movement.
	CombatStep.resolve_projectiles(pair.battle, TICK_SECONDS, pair.rng)
	assert(pair.battle.projectiles.size() == 1) # Flight advances after all unit movement.

func _check_melee_wind_expires_before_movement() -> void:
	var pair := _pair()
	var attacker: Unit = pair.attacker
	var target: Unit = pair.target
	attacker.group_kind = Config.GROUP_INFANTRY
	attacker.speed = 100.0
	attacker.damage = 30.0
	attacker.ai_windup = 0.05
	attacker.ai_wind_target_id = 1
	attacker.attack_cooldown = 1.0
	target.position = Vector2(150, 100)
	pair.battle.groups[0][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	Movement.step(pair.battle, TICK_SECONDS, Vector2.ZERO, 0.0, pair.rng)
	assert(attacker.position.x > 100.0)
	assert(target.hp == 100.0) # Previous position was outside the finishing strike's reach.
	assert(attacker.ai_wind_target_id == -1)

func _check_earlier_unit_can_stop_later_unit() -> void:
	var pair := _pair()
	var attacker: Unit = pair.attacker
	var target: Unit = pair.target
	attacker.group_kind = Config.GROUP_INFANTRY
	attacker.damage = 1000.0
	attacker.ai_windup = 0.05
	attacker.ai_wind_target_id = 1
	attacker.attack_cooldown = 1.0
	target.position = Vector2(120, 100)
	target.speed = 100.0
	pair.battle.groups[0][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	pair.battle.groups[1][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	var target_start: Vector2 = target.position
	Movement.step(pair.battle, TICK_SECONDS, Vector2.ZERO, 0.0, pair.rng)
	assert(target.dead)
	assert(target.position == target_start) # Dead before its own turn, so it never moves.
