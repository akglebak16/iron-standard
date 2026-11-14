extends SceneTree

const Unit = preload("res://battle/unit.gd")
const BattleState = preload("res://battle/state.gd")

func _initialize() -> void:
	var battle = BattleState.new()
	var attacker = Unit.new(0, 0, Vector2.ZERO, 100.0, 0.0, 1)
	var victim = Unit.new(1, 1, Vector2(10, 0), 50.0, 55.0, 2)
	var ally = Unit.new(2, 1, Vector2(20, 0), 100.0, 0.0, 1)
	var distant = Unit.new(3, 1, Vector2(200, 0), 100.0, 0.0, 1)
	for unit in [attacker, victim, ally, distant]:
		battle.add_unit(unit)
	assert(battle.hurt(victim, 40.0, attacker) == 20)
	assert(victim.hp == 30.0)
	assert(is_equal_approx(victim.morale, 100.0 - 2.4))
	assert(battle.hurt(victim, 60.0, attacker) == 30)
	assert(victim.dead and victim.hp == 0.0)
	assert(attacker.kills == 1)
	assert(is_equal_approx(ally.morale, 86.0 - 2.6))
	assert(distant.morale == 86.0)
	assert(battle.hurt(victim, 60.0, attacker) == 0)
	assert(attacker.kills == 1)
	print("Battle state tests passed")
	quit(0)
