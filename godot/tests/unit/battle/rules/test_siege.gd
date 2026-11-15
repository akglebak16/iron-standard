extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Wall = preload("res://core/battle/model/siege_wall.gd")
const Config = preload("res://core/battle/config.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Combat = preload("res://core/battle/rules/combat.gd")

func _initialize() -> void:
	_check_route_and_crossing()
	_check_defender_tactics()
	_check_projectile_cover()
	print("Siege rules tests passed")
	quit(0)

func _check_route_and_crossing() -> void:
	var state := State.new()
	state.setup_groups()
	state.wall = Wall.new(state.arena_size)
	var attacker := Unit.new(0, 0, Vector2(1500, 350), 100, 0, 1)
	attacker.speed = 70.0
	state.add_grouped_unit(attacker, Config.GROUP_INFANTRY)
	var group = state.groups[0][Config.GROUP_INFANTRY]
	group.center = Vector2(1800, 350)
	assert(state.wall.route(attacker, Vector2(1500, 600)) == Vector2(1500, 600))
	assert(state.wall.route(attacker, group.center) == Vector2(1568, 377.5))
	var rng := RandomNumberGenerator.new()
	var crossed := false
	for tick in 300:
		Movement.step(state, 1.0 / 60.0, rng)
		if attacker.position.x > state.wall.x:
			assert(state.wall.gap_at(attacker.position.y) == Vector2(330, 425))
			crossed = true
			break
	assert(crossed)
	attacker.position = Vector2(1660, 850)
	assert(state.wall.route(attacker, Vector2(1400, 850)) == Vector2(1550, 850))

func _check_defender_tactics() -> void:
	var state := State.new()
	state.setup_groups()
	state.wall = Wall.new(state.arena_size)
	var infantry := Unit.new(0, 1, Vector2(1700, 850), 100, 0, 1)
	state.add_grouped_unit(infantry, Config.GROUP_INFANTRY)
	var defenders: Array = state.groups[1]
	for i in 9:
		var attacker := Unit.new(i + 1, 0, Vector2(1700, 850), 100, 0, 1)
		state.add_grouped_unit(attacker, Config.GROUP_INFANTRY)
		Tactics.siege_step(state, 1.0)
		assert((defenders[Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE) == (i + 1 > 2))
		assert((defenders[Config.GROUP_CAVALRY].order == Config.ORDER_CHARGE) == (i + 1 > 4))
		assert((defenders[Config.GROUP_ARCHERS].order == Config.ORDER_CHARGE) == (i + 1 > 8))
	for unit in state.units:
		if unit.side == 0:
			unit.fleeing = true
	defenders[Config.GROUP_INFANTRY].order = Config.ORDER_HOLD
	defenders[Config.GROUP_CAVALRY].order = Config.ORDER_HOLD
	defenders[Config.GROUP_ARCHERS].order = Config.ORDER_HOLD
	Tactics.siege_step(state, 150.0)
	assert(defenders[Config.GROUP_INFANTRY].order == Config.ORDER_HOLD)
	Tactics.siege_step(state, 170.0)
	assert(defenders[Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)
	assert(defenders[Config.GROUP_CAVALRY].order == Config.ORDER_HOLD)
	infantry.dead = true
	Tactics.siege_step(state, 171.0)
	assert(defenders[Config.GROUP_CAVALRY].order == Config.ORDER_CHARGE)
	assert(defenders[Config.GROUP_ARCHERS].order == Config.ORDER_CHARGE)

func _check_projectile_cover() -> void:
	var state := State.new()
	state.wall = Wall.new(state.arena_size)
	var defender := Unit.new(0, 1, Vector2(1670, 700), 1000, 0, 1)
	state.add_unit(defender)
	var shot := {"origin": Vector2(1500, 700), "damage": 100.0, "source": null, "pierce": 0.0}
	var rng := RandomNumberGenerator.new()
	var reference := RandomNumberGenerator.new()
	for sample in [[700.0, 0.0, 0.45], [700.0, 0.7, 0.8], [850.0, 0.0, 1.0]]:
		defender.position.y = sample[0]
		state.siege_skill = sample[1]
		rng.seed = 19
		reference.seed = 19
		var expected := roundi(100.0 * reference.randf_range(0.85, 1.15) * sample[2])
		assert(Combat.arrow_hit(state, shot, defender, rng) == expected)
		assert(rng.state == reference.state)
	assert(state.wall.projectile_multiplier(defender, Vector2(1680, 850), 0.0) == 1.0)
