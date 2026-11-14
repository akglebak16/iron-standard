extends SceneTree

const Unit = preload("res://battle/model/unit.gd")
const BattleState = preload("res://battle/model/state.gd")

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
	_check_last_stand_and_kill_heal()
	print("Battle state tests passed")
	quit(0)

func _check_last_stand_and_kill_heal() -> void:
	var battle := BattleState.new()
	var hero := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	hero.hero = true
	hero.perk_effects = {"lastStand": 0.25, "killHeal": 0.03}
	var foe := Unit.new(1, 1, Vector2(10, 0), 100, 0, 1)
	battle.add_unit(hero)
	battle.add_unit(foe)
	battle.hurt(hero, 200, foe)
	assert(not hero.dead and hero.hp == 25.0 and hero.last_stand_used)
	battle.hurt(hero, 20, foe)
	assert(hero.hp == 5.0 and not hero.dead)
	battle.hurt(foe, 200, hero)
	assert(foe.dead and hero.kills == 1)
	assert(hero.hp == 8.0) # Three percent of maximum HP for one kill.
	var second := Unit.new(2, 1, Vector2(12, 0), 50, 0, 1)
	battle.add_unit(second)
	hero.hp = 99.0
	battle.hurt(second, 200, hero)
	assert(hero.hp == 100.0) # Healing is capped at maximum HP.
	battle.hurt(hero, 200, foe)
	assert(hero.dead and hero.hp == 0.0) # Last Stand fires once per battle.
