extends SceneTree
const Movement = preload("res://battle/rules/movement.gd")

const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")
const BattleState = preload("res://battle/model/state.gd")

func _initialize() -> void:
	var battle = BattleState.new()
	var rng := RandomNumberGenerator.new()
	battle.setup_groups()
	var foot = Unit.new(0, 0, Vector2(640, 850), 50, 0, 1)
	foot.speed = 60.0
	var horse = Unit.new(1, 0, Vector2(620, 1230), 80, 0, 2)
	horse.speed = 140.0
	horse.mounted = true
	horse.mass = Config.HORSE_MASS
	horse.collision_radius = Config.HORSE_COLLISION_RADIUS
	var enemy = Unit.new(2, 1, Vector2(1900, 850), 50, 0, 1)
	enemy.speed = 0.0
	battle.add_grouped_unit(foot, Config.GROUP_INFANTRY)
	battle.add_grouped_unit(horse, Config.GROUP_CAVALRY)
	battle.add_grouped_unit(enemy, Config.GROUP_INFANTRY)
	battle.place_units()
	var first: Vector2 = foot.position
	Movement.step(battle, 0.1, rng)
	assert(foot.position.distance_to(first) < 0.01) # holding its slot
	assert(battle.give_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.GROUP_INFANTRY))
	Movement.step(battle, 0.1, rng)
	assert(foot.position.x > first.x)
	assert(foot.facing == 0.0)
	assert(battle.give_order(Config.ORDER_FOLLOW, Vector2.ZERO, Config.GROUP_CAVALRY))
	Movement.step(battle, 0.1, rng)
	assert(battle.give_order(Config.ORDER_RETREAT, Vector2.ZERO, Config.GROUP_INFANTRY))
	assert(battle.groups[0][Config.GROUP_INFANTRY].center.x < foot.position.x)
	foot.fleeing = true
	for tick in 1000:
		Movement.step(battle, 0.1, rng)
		if foot.gone:
			break
	assert(foot.gone)
	_check_post_collision_field_limits()
	print("Movement tests passed")
	quit(0)

func _check_post_collision_field_limits() -> void:
	var battle := BattleState.new()
	var rng := RandomNumberGenerator.new()
	battle.setup_groups()
	var hero := Unit.new(0, 0, Vector2(21, Config.FIELD_TOP_MARGIN - 1.0), 100, 0, 1)
	hero.hero = true
	var ally := Unit.new(1, 0, Vector2(28, Config.FIELD_TOP_MARGIN), 100, 0, 1)
	ally.speed = 0.0
	battle.add_unit(hero)
	battle.add_grouped_unit(ally, Config.GROUP_INFANTRY)
	Movement.step(battle, 0.01, rng)
	assert(hero.position.is_equal_approx(Vector2(Config.FIELD_LEFT_RIGHT_MARGIN, Config.FIELD_TOP_MARGIN)))
	assert(ally.position.x > 28.0)
	# A fleeing unit retains horizontal freedom but still obeys vertical limits.
	hero.fleeing = true
	hero.position = Vector2(-1, Config.FIELD_TOP_MARGIN - 1.0)
	Movement.step(battle, 0.01, rng)
	assert(hero.position.x == -1.0)
	assert(hero.position.y == Config.FIELD_TOP_MARGIN)
