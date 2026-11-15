extends SceneTree
const CombatStep = preload("res://core/battle/rules/combat_step.gd")

const Unit = preload("res://core/battle/model/unit.gd")
const BattleState = preload("res://core/battle/model/state.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Config = preload("res://core/battle/config.gd")
const EquipmentConfig = preload("res://core/equipment/config.gd")

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
		CombatStep.step(battle, 1.0, rng)
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
	CombatStep.step(archers, 0.1, rng)
	assert(archers.projectiles.size() == 1)
	assert(target.hp == 100.0)
	CombatStep.step(archers, 0.5, rng)
	assert(archers.projectiles.is_empty())
	assert(target.hp < 100.0)
	assert(archer.attack_cooldown > 0.0)
	_check_bonded_leader_combat_rng()
	_check_damage_response()
	print("Combat tests passed")
	quit(0)

func _check_bonded_leader_combat_rng() -> void:
	var battle := BattleState.new()
	var attacker := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	attacker.damage = 200.0
	var leader := Unit.new(1, 1, Vector2(10, 0), 20, 0, 3)
	leader.leader_bond = "test_bond"
	leader.leader = true
	battle.add_unit(attacker)
	battle.add_unit(leader)
	var minion := Unit.new(2, 1, Vector2(300, 0), 100, 0, 1)
	minion.leader_bond = leader.leader_bond
	minion.leader_loss_chance = 1.0
	battle.add_unit(minion)
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	assert(Combat.strike(battle, attacker, leader, rng) > 0)
	assert(leader.dead and minion.dead and attacker.kills == 1)

func _check_damage_response() -> void:
	var battle := BattleState.new()
	var attacker := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	attacker.damage = 30.0
	var target := Unit.new(1, 1, Vector2(10, 0), 500, 0, 1)
	target.facing = PI
	target.projectile_damage_multiplier = 0.0
	target.blunt_melee_damage_multiplier = 0.0
	battle.add_unit(attacker)
	battle.add_unit(target)
	var rng := RandomNumberGenerator.new()
	attacker.blunt_melee = true
	assert(Combat.strike(battle, attacker, target, rng) == 1)
	attacker.damage_type = EquipmentConfig.DAMAGE_TYPE_BLUNT
	assert(Combat.hero_strike(battle, attacker, target, 0, rng) == 1)
	assert(Combat.arrow_hit(battle, Combat.shoot(attacker, target, rng), target, rng) == 1)
	attacker.damage_type = EquipmentConfig.DAMAGE_TYPE_CUT
	assert(Combat.strike(battle, attacker, target, rng) > 1)
