extends SceneTree

const Unit = preload("res://battle/model/unit.gd")
const BattleState = preload("res://battle/model/state.gd")
const Config = preload("res://battle/config.gd")

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
	_check_bonded_leader_collapse()
	_check_ordinary_leader_morale()
	_check_companion_down_morale()
	print("Battle state tests passed")
	quit(0)

func _check_companion_down_morale() -> void:
	var battle := BattleState.new()
	var companion := Unit.new(0, 0, Vector2.ZERO, 30, 0, 3)
	companion.companion = true
	var close := Unit.new(1, 0, Vector2(100, 0), 100, 0, 1)
	var far := Unit.new(2, 0, Vector2(200, 0), 100, 0, 1)
	for unit in [companion, close, far]:
		battle.add_unit(unit)
	battle.kill(companion)
	assert(companion.dead)
	assert(close.morale == 86.0 - (1.6 + 3 * 0.5) - Config.COMPANION_DOWN_MORALE_LOSS)
	assert(far.morale == 86.0)

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

func _check_bonded_leader_collapse() -> void:
	var battle := BattleState.new()
	var leader := Unit.new(0, 1, Vector2.ZERO, 100, 0, 3)
	leader.leader = true
	leader.leader_bond = "test_bond"
	battle.add_unit(leader)
	var followers: Array[Unit] = []
	for i in 12:
		var unit := Unit.new(i + 1, 1, Vector2(300 + i * 200, 0), 100, 0, 1)
		unit.leader_bond = leader.leader_bond
		unit.leader_loss_chance = 0.35 if i % 2 == 0 else 0.75
		battle.add_unit(unit)
		followers.append(unit)
	var mortal := Unit.new(13, 1, Vector2(3000, 0), 100, 0, 1)
	mortal.leader_bond = "different_bond"
	mortal.leader_loss_chance = 1.0
	battle.add_unit(mortal)
	var attacker := Unit.new(14, 0, Vector2.ZERO, 100, 0, 1)
	battle.add_unit(attacker)
	var rng := RandomNumberGenerator.new()
	rng.seed = 410
	var reference := RandomNumberGenerator.new()
	reference.seed = rng.seed
	var expected: Array[bool] = []
	for unit in followers:
		expected.append(reference.randf() < unit.leader_loss_chance)
	battle.kill(leader, attacker, rng)
	assert(leader.dead and attacker.kills == 1)
	assert(not mortal.dead)
	for i in followers.size():
		assert(followers[i].dead == expected[i])
	assert(rng.state == reference.state) # One roll per eligible follower, in unit order.

func _check_ordinary_leader_morale() -> void:
	var battle := BattleState.new()
	var leader := Unit.new(0, 1, Vector2.ZERO, 100, 0, 3)
	leader.leader = true
	leader.faction = "emp"
	var nearby := Unit.new(1, 1, Vector2(10, 0), 100, 0, 1)
	var distant := Unit.new(2, 1, Vector2(500, 0), 100, 0, 1)
	for unit in [leader, nearby, distant]:
		battle.add_unit(unit)
	battle.kill(leader)
	assert(nearby.morale == nearby.base_morale - Config.LEADER_DEATH_MORALE - Config.LEADER_GLOBAL_MORALE_LOSS)
	assert(distant.morale == distant.base_morale - Config.LEADER_GLOBAL_MORALE_LOSS)
