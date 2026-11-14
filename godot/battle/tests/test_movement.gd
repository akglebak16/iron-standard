extends SceneTree

const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/unit.gd")
const BattleState = preload("res://battle/state.gd")

func _initialize() -> void:
	var battle = BattleState.new()
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
	battle.step_movement(0.1, Vector2(640, 850))
	assert(foot.position.distance_to(first) < 0.01) # holding its slot
	assert(battle.give_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.GROUP_INFANTRY))
	battle.step_movement(0.1, Vector2(640, 850))
	assert(foot.position.x > first.x)
	assert(foot.facing == 0.0)
	assert(battle.give_order(Config.ORDER_FOLLOW, Vector2.ZERO, Config.GROUP_CAVALRY))
	battle.step_movement(0.1, Vector2(900, 850))
	assert(battle.groups[0][Config.GROUP_CAVALRY].center == Vector2(840, 1020))
	assert(battle.give_order(Config.ORDER_RETREAT, Vector2.ZERO, Config.GROUP_INFANTRY))
	assert(battle.groups[0][Config.GROUP_INFANTRY].center.x < foot.position.x)
	foot.fleeing = true
	for tick in 1000:
		battle.step_movement(0.1, Vector2(900, 850))
		if foot.gone:
			break
	assert(foot.gone)
	print("Movement tests passed")
	quit(0)
