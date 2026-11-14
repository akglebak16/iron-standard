extends SceneTree

const Unit = preload("res://battle/unit.gd")
const BattleState = preload("res://battle/state.gd")
const Combat = preload("res://battle/combat.gd")

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var battle = BattleState.new()
	battle.setup_groups()
	var attacker = Unit.new(0, 0, Vector2(100, 100), 100, 0, 2)
	attacker.damage = 30.0
	attacker.attack_interval = 1.0
	var defender = Unit.new(1, 1, Vector2(120, 100), 100, 0, 2)
	defender.block_chance = 1.0
	defender.facing = PI
	battle.add_grouped_unit(attacker, 0)
	battle.add_grouped_unit(defender, 0)
	assert(Combat.strike(battle, attacker, defender, rng) == 0)
	assert(defender.hp == 100.0)
	defender.facing = 0.0
	assert(Combat.strike(battle, attacker, defender, rng) > 0)
	assert(defender.hp < 100.0)
	defender.block_chance = 0.0
	for tick in 10:
		battle.step_combat(1.0, rng)
		if defender.dead:
			break
	assert(defender.dead and attacker.kills == 1)
	var archers = BattleState.new()
	archers.setup_groups()
	var archer = Unit.new(0, 0, Vector2(100, 100), 50, 0, 1)
	archer.damage = 20.0
	archer.attack_range = 300.0
	archer.attack_interval = 2.0
	var target = Unit.new(1, 1, Vector2(200, 100), 100, 0, 1)
	archers.add_grouped_unit(archer, 1)
	archers.add_grouped_unit(target, 0)
	archers.step_combat(0.1, rng)
	assert(archers.projectiles.size() == 1)
	assert(target.hp == 100.0)
	archers.step_combat(0.5, rng)
	assert(archers.projectiles.is_empty())
	assert(target.hp < 100.0)
	assert(archer.attack_cooldown > 0.0)
	print("Combat tests passed")
	quit(0)
