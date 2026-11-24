extends SceneTree
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Block = preload("res://core/battle/rules/block.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const State = preload("res://core/battle/model/state.gd")

func _initialize() -> void:
	var target := Unit.new(0, 1, Vector2.ZERO, 500, 0, 1)
	target.block_chance = 0.2
	assert(is_equal_approx(Block.chance(target, false), 0.2))
	assert(is_equal_approx(Block.chance(target, true), 0.17))
	target.shield_block = 0.3
	assert(is_equal_approx(Block.chance(target, true), 0.55))
	target.block_chance = 0.8
	assert(Block.chance(target, true) == Config.SHIELD_ARROW_MAX_BLOCK)
	target.hero = true
	target.block_chance = 0.9
	target.blocking = true
	assert(Block.chance(target, false) == Config.HERO_MAX_BLOCK_CHANCE)
	assert(Block.chance(target, true) == Config.HERO_MAX_BLOCK_CHANCE)
	target.blocking = false
	target.block_chance = 0.8
	assert(is_equal_approx(Block.chance(target, false), 0.2))
	assert(is_equal_approx(Block.chance(target, true), 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var before := rng.state
	assert(not Block.check(target, PI, true, rng)) # Attack from behind.
	assert(rng.state == before)
	target.block_chance = 0.0
	target.shield_block = 0.0
	assert(not Block.check(target, 0.0, true, rng))
	assert(rng.state == before)
	# The projectile uses the shield rule; melee uses only the base block chance.
	target.hero = false
	target.shield_block = 1.0
	target.block_chance = 0.0
	var attacker := Unit.new(1, 0, Vector2(50, 0), 100, 0, 1)
	attacker.damage = 30
	var shot := {"source": attacker, "origin": attacker.position - Vector2(0, Config.PROJECTILE_START_HEIGHT), "damage": attacker.damage, "pierce": 0.0}
	var battle := State.new()
	assert(Combat.arrow_hit(battle, shot, target, rng) == 0)
	assert(target.hp == 500)
	target.shield_block = 0.0
	assert(Combat.arrow_hit(battle, shot, target, rng) > 0)
	assert(target.hp < 500)
	_test_shield_wall()
	print("Block and shield tests passed")
	quit(0)

## Stage 1g part 5 (#270): a shield bearer in the commander's shield wall (Group.wall) holds an arrow from the front
## AI_CMD_WALL_ARROW_BLOCK more often, still at most SHIELD_ARROW_MAX_BLOCK; the blow in melee, a man without a shield
## and the hero keep their rules, and no wall means the old chance (the reference battle stays as it was).
func _test_shield_wall() -> void:
	var man := Unit.new(0, 1, Vector2.ZERO, 500, 0, 1)
	man.block_chance = 0.22
	man.shield_block = 0.18
	var plain := Block.chance(man, true)
	assert(is_equal_approx(plain, 0.22 * Config.SHIELD_ARROW_BONUS_MULTIPLIER + 0.18))
	assert(is_equal_approx(Block.chance(man, true, true), plain + Config.AI_CMD_WALL_ARROW_BLOCK), "The wall holds arrows better")
	assert(Block.chance(man, false, true) == Block.chance(man, false), "Melee blows: the wall changes nothing")
	man.block_chance = 0.6
	assert(Block.chance(man, true, true) == Config.SHIELD_ARROW_MAX_BLOCK, "Still at most the shield cap")
	man.shield_block = 0.0
	assert(Block.chance(man, true, true) == Block.chance(man, true), "No shield, no wall")
	man.hero = true
	man.shield_block = 0.18
	assert(Block.chance(man, true, true) == Block.chance(man, true), "The hero keeps his own rule")
	# In a battle: the arrow reads the wall of the man's group. A wall man holds an arrow the plain one takes for the
	# same random number; from behind (out of BLOCK_ARC) the wall does not help.
	var battle := State.new()
	battle.setup_groups()
	var target := Unit.new(0, 1, Vector2(500, 500), 500, 0, 1)
	target.block_chance = 0.22
	target.shield_block = 0.18
	battle.add_grouped_unit(target, Config.GROUP_INFANTRY)
	var attacker := Unit.new(1, 0, Vector2(300, 500), 100, 0, 1)
	attacker.damage = 10
	battle.add_grouped_unit(attacker, Config.GROUP_ARCHERS)
	target.facing = PI # Facing the shooter.
	var shot := {"source": attacker, "origin": attacker.position - Vector2(0, Config.PROJECTILE_START_HEIGHT), "damage": attacker.damage, "pierce": 0.0}
	var group := battle.group_of(target)
	var held := [0, 0]
	for wall in [false, true]:
		group.wall = wall
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 400:
			var before := target.hp
			Combat.arrow_hit(battle, shot, target, rng)
			if target.hp == before: held[int(wall)] += 1
			target.hp = 500
	assert(held[1] > held[0] + 30, "The wall holds more arrows from the front: %s" % str(held))
	target.facing = 0.0 # The shooter behind.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	assert(Combat.arrow_hit(battle, shot, target, rng) > 0, "No block from behind, wall or not")
