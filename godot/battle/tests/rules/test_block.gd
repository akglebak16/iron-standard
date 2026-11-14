extends SceneTree
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")
const Block = preload("res://battle/rules/block.gd")
const Combat = preload("res://battle/rules/combat.gd")
const State = preload("res://battle/model/state.gd")

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
	print("Block and shield tests passed")
	quit(0)
