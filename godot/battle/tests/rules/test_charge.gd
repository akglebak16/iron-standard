extends SceneTree
const Charge = preload("res://battle/rules/charge.gd")
const Movement = preload("res://battle/rules/movement.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Damage = preload("res://battle/rules/damage.gd")
const Config = preload("res://battle/config.gd")

func _initialize() -> void:
	_check_plain_hit()
	_check_anti_cavalry()
	_check_block_and_direction()
	_check_movement_integration()
	print("Charge tests passed")
	quit(0)

func _pair() -> Dictionary:
	var battle := State.new()
	battle.setup_groups()
	var rider := Unit.new(0, 0, Vector2(100, 100), 100, 0, 2)
	rider.mounted = true
	rider.collision_radius = Config.HORSE_COLLISION_RADIUS
	rider.mass = Config.HORSE_MASS
	rider.velocity = Vector2(Config.CHARGE_MIN_SPEED + 20.0, 0)
	rider.speed = 140
	rider.damage = 30
	var target := Unit.new(1, 1, Vector2(130, 100), 100, 0, 1)
	target.facing = PI
	battle.add_grouped_unit(rider, Config.GROUP_CAVALRY)
	battle.add_grouped_unit(target, Config.GROUP_INFANTRY)
	return {"battle": battle, "rider": rider, "target": target}

func _check_plain_hit() -> void:
	var pair := _pair()
	var rider: Unit = pair.rider
	var target: Unit = pair.target
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	assert(Charge.can_hit(rider, target))
	var expected_raw: float = rider.damage * (Config.CHARGE_BASE_DAMAGE + rider.velocity.length() / Config.CHARGE_SPEED_DAMAGE_DIVISOR)
	var expected: int = Damage.after_armor(expected_raw, target.armor)
	assert(Charge.hit(pair.battle, rider, target, rng) == expected)
	assert(target.hp == 100 - expected)
	assert(target.position.is_equal_approx(Vector2(130 + Config.CHARGE_KNOCKBACK, 100)))
	assert(rider.velocity.is_equal_approx(Vector2(40, 0)))
	assert(rider.attack_cooldown == Config.CHARGE_ATTACK_COOLDOWN)
	assert(rider.charge_cooldown == Config.CHARGE_COOLDOWN)
	assert(not Charge.can_hit(rider, target))
	rider.charge_cooldown = 0
	assert(not Charge.can_hit(rider, target)) # Speed now below threshold.
	rider.velocity = Vector2(Config.CHARGE_MIN_SPEED, 0)
	assert(not Charge.can_hit(rider, target))
	rider.velocity = Vector2(Config.CHARGE_MIN_SPEED + 1.0, 0)
	rider.attack_range = 200
	assert(not Charge.can_hit(rider, target)) # Mounted archer uses skirmish mode.
	rider.attack_range = 0
	target.gone = true
	assert(not Charge.can_hit(rider, target))

func _check_anti_cavalry() -> void:
	var pair := _pair()
	var rider: Unit = pair.rider
	var target: Unit = pair.target
	target.anti_cavalry = true
	target.block_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = rng.seed
	var counter_raw: float = Config.CHARGE_COUNTER_DAMAGE * expected_rng.randf_range(Config.CHARGE_COUNTER_RANDOM_MIN, Config.CHARGE_COUNTER_RANDOM_MAX)
	var expected_counter: int = Damage.after_armor(counter_raw, rider.armor)
	var expected_charge: int = Damage.after_armor(rider.damage * (Config.CHARGE_BASE_DAMAGE + rider.velocity.length() / Config.CHARGE_SPEED_DAMAGE_DIVISOR) * Config.CHARGE_ANTI_DAMAGE_MULTIPLIER, target.armor)
	assert(Charge.hit(pair.battle, rider, target, rng) == expected_charge)
	assert(rider.hp == 100 - expected_counter)
	assert(target.hp == 100 - expected_charge)
	assert(rng.state == expected_rng.state) # Anti-cavalry response skips the block roll.

func _check_block_and_direction() -> void:
	var pair := _pair()
	var rider: Unit = pair.rider
	var target: Unit = pair.target
	target.block_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var expected: int = Damage.after_armor(rider.damage * (Config.CHARGE_BASE_DAMAGE + rider.velocity.length() / Config.CHARGE_SPEED_DAMAGE_DIVISOR) * Config.CHARGE_BLOCK_DAMAGE_MULTIPLIER, 0)
	assert(Charge.hit(pair.battle, rider, target, rng) == expected)
	var rear := _pair()
	rear.target.facing = 0.0
	rear.target.anti_cavalry = true
	rear.target.block_chance = 1.0
	var rear_rng := RandomNumberGenerator.new()
	assert(Charge.hit(rear.battle, rear.rider, rear.target, rear_rng) > expected)
	assert(rear.rider.hp == 100) # Neither counterattack nor frontal block applies from behind.
	var fleeing := _pair()
	fleeing.target.anti_cavalry = true
	fleeing.target.fleeing = true
	var flee_rng := RandomNumberGenerator.new()
	Charge.hit(fleeing.battle, fleeing.rider, fleeing.target, flee_rng)
	assert(fleeing.rider.hp == 100)

func _check_movement_integration() -> void:
	var pair := _pair()
	var battle: State = pair.battle
	var rider: Unit = pair.rider
	var target: Unit = pair.target
	battle.groups[0][Config.GROUP_CAVALRY].order = Config.ORDER_CHARGE
	var rng := RandomNumberGenerator.new()
	Movement.step(battle, 0.01, rng)
	assert(target.hp < 100)
	assert(rider.charge_cooldown > 0)
	var hp_after_hit: float = target.hp
	Movement.step(battle, 0.01, rng)
	assert(target.hp == hp_after_hit) # Cooldown prevents a second charge.
