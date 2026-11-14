extends SceneTree
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")

func _initialize() -> void:
	_check_melee_windup()
	_check_lost_target()
	_check_ranged_cooldown()
	print("AI attack timing tests passed")
	quit(0)

func _pair(ranged: bool = false) -> Dictionary:
	var battle := State.new()
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	attacker.damage = 30
	attacker.attack_interval = 1.0
	attacker.ai_mode = Config.AI_MODE_SHOOT if ranged else Config.AI_MODE_MELEE
	attacker.attack_range = 300 if ranged else 0
	attacker.target_index = 1
	var target := Unit.new(101, 1, Vector2(200, 100) if ranged else Vector2(120, 100), 100, 0, 1)
	battle.add_unit(attacker)
	battle.add_unit(target)
	return {"battle": battle, "attacker": attacker, "target": target}

func _check_melee_windup() -> void:
	var pair := _pair()
	var attacker: Unit = pair.attacker
	var target: Unit = pair.target
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	CombatStep.step(pair.battle, 0.1, rng)
	assert(attacker.ai_wind_target_index == 1)
	assert(is_equal_approx(attacker.ai_windup, Config.AI_MELEE_WINDUP_SECONDS - 0.1))
	assert(attacker.attack_cooldown >= Config.AI_MELEE_COOLDOWN_MIN and attacker.attack_cooldown <= Config.AI_MELEE_COOLDOWN_MAX)
	assert(target.hp == 100)
	CombatStep.step(pair.battle, 0.1, rng)
	assert(target.hp == 100) # Exactly zero windup is not a hit in the browser.
	CombatStep.step(pair.battle, 0.01, rng)
	assert(target.hp < 100)
	assert(attacker.ai_wind_target_index == -1)
	var hit_hp: float = target.hp
	CombatStep.step(pair.battle, 0.1, rng)
	assert(target.hp == hit_hp) # Ordinary attack cooldown still applies.

func _check_lost_target() -> void:
	var pair := _pair()
	var rng := RandomNumberGenerator.new()
	CombatStep.step(pair.battle, 0.01, rng)
	pair.target.position = Vector2(1000, 100)
	CombatStep.step(pair.battle, Config.AI_MELEE_WINDUP_SECONDS, rng)
	assert(pair.target.hp == 100)
	var dead_pair := _pair()
	CombatStep.step(dead_pair.battle, 0.01, rng)
	dead_pair.target.dead = true
	CombatStep.step(dead_pair.battle, Config.AI_MELEE_WINDUP_SECONDS, rng)
	assert(dead_pair.attacker.ai_wind_target_index == -1)
	assert(dead_pair.target.hp == 100)

func _check_ranged_cooldown() -> void:
	var pair := _pair(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	CombatStep.step(pair.battle, 0.01, rng)
	assert(pair.battle.projectiles.size() == 1)
	assert(pair.attacker.attack_cooldown >= Config.AI_SHOOT_COOLDOWN_MIN and pair.attacker.attack_cooldown <= Config.AI_SHOOT_COOLDOWN_MAX)
	var count: int = pair.battle.projectiles.size()
	CombatStep.step(pair.battle, 0.01, rng)
	assert(pair.battle.projectiles.size() == count)
	var skirm := _pair(true)
	skirm.attacker.ai_mode = Config.AI_MODE_SKIRMISH
	skirm.attacker.velocity = Vector2(Config.SHOOT_MOVE_SPEED_LIMIT + 10, 0)
	CombatStep.step(skirm.battle, 0.01, rng)
	assert(skirm.battle.projectiles.size() == 1) # Mounted skirmisher fires while moving.
