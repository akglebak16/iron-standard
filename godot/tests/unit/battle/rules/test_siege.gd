extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Wall = preload("res://core/battle/model/siege_wall.gd")
const Config = preload("res://core/battle/config.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Feedback = preload("res://apps/godot/presentation/battle/combat_feedback.gd")

func _initialize() -> void:
	_check_route_and_crossing()
	_check_defender_tactics()
	_check_projectile_cover()
	_check_gates()
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
	# wallVia: every gate is shut, so the attacker walks up to the nearest one (330..410) to batter it.
	assert(state.wall.route(attacker, group.center) == Vector2(1620 - 22 - 12.5 - 2, 350))
	state.wall.gates[1].hp = 0.0
	assert(state.wall.bash([attacker], 0.1) == [1] and state.wall.gates[1].dead and state.wall.revision == 1)
	assert(state.wall.route(attacker, group.center) == Vector2(1568, 370))
	var rng := RandomNumberGenerator.new()
	var crossed := false
	for tick in 300:
		Movement.step(state, 1.0 / 60.0, rng)
		if attacker.position.x > state.wall.x:
			assert(state.wall.gap_at(attacker.position.y) == Vector2(330, 410))
			crossed = true
			break
	assert(crossed)
	attacker.position = Vector2(1660, 850)
	assert(state.wall.route(attacker, Vector2(1400, 850)) == Vector2(1672, 370), "The main gate is shut: back out through the side gate")
	assert(state.wall.open_main_gate() and not state.wall.open_main_gate())
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
	assert(defenders[Config.GROUP_INFANTRY].order == Config.ORDER_HOLD, "With every gate shut the garrison waits")
	state.wall.gates[2].hp = 0.0
	Tactics.siege_step(state, 170.0)
	assert(defenders[Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)
	assert(defenders[Config.GROUP_CAVALRY].order == Config.ORDER_HOLD)
	infantry.dead = true
	Tactics.siege_step(state, 171.0)
	assert(defenders[Config.GROUP_CAVALRY].order == Config.ORDER_CHARGE)
	assert(defenders[Config.GROUP_ARCHERS].order == Config.ORDER_CHARGE)

## siegeBrain: attackers in contact batter a gate (archers do not), it falls with «Ворота пали!»; after 45 s a garrison
## with more than ten fighters on foot opens the main gate and charges.
func _check_gates() -> void:
	var state := State.new()
	state.setup_groups()
	state.wall = Wall.new(state.arena_size)
	var ram := Unit.new(0, 0, Vector2(1620 - 22 - 12.5 - 2, 850), 100, 0, 1)
	ram.damage = 20.0
	state.add_grouped_unit(ram, Config.GROUP_INFANTRY)
	var archer := Unit.new(1, 0, Vector2(1620 - 22 - 12.5 - 2, 860), 100, 0, 1)
	archer.damage = 1000.0
	state.add_grouped_unit(archer, Config.GROUP_ARCHERS)
	var defender := Unit.new(2, 1, Vector2(1700, 850), 100, 0, 1)
	state.add_grouped_unit(defender, Config.GROUP_INFANTRY)
	state.take_events()
	Tactics.siege_step(state, 1.0, 10.0)
	assert(state.wall.gates[0].hp == 900.0 - 20.0 * 0.35 * 10.0 and state.wall.gates[0].hit == 0.3, "Only the infantryman batters")
	Tactics.siege_step(state, 2.0, 200.0)
	assert(state.wall.gates[0].dead and state.wall.gap_at(850.0) == Vector2(775, 925))
	var broken := state.take_events().filter(func(e): return e.kind == Event.Kind.GATE_BROKEN)
	assert(broken.size() == 1 and broken[0].position == Vector2(1620, 850))
	assert(Feedback.GATE_BROKEN == "Ворота пали!")
	var sortie := State.new()
	sortie.setup_groups()
	sortie.wall = Wall.new(sortie.arena_size)
	for i in 11:
		sortie.add_grouped_unit(Unit.new(i, 1, Vector2(1700, 600 + i * 20), 100, 0, 1), Config.GROUP_INFANTRY)
	Tactics.siege_step(sortie, 45.0, 0.1)
	assert(not sortie.wall.gates[0].open, "Not before 45 s")
	Tactics.siege_step(sortie, 45.1, 0.1)
	assert(sortie.wall.gates[0].open and sortie.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)
	assert(sortie.take_events().any(func(e): return e.kind == Event.Kind.GATE_OPENED))
	sortie.groups[1][Config.GROUP_INFANTRY].units[0].dead = true
	var few := State.new()
	few.setup_groups()
	few.wall = Wall.new(few.arena_size)
	for i in 10:
		few.add_grouped_unit(Unit.new(i, 1, Vector2(1700, 600 + i * 20), 100, 0, 1), Config.GROUP_INFANTRY)
	Tactics.siege_step(few, 100.0, 0.1)
	assert(not few.wall.gates[0].open, "Ten fighters keep the gate shut")

func _check_projectile_cover() -> void:
	var state := State.new()
	state.wall = Wall.new(state.arena_size)
	var defender := Unit.new(0, 1, Vector2(1670, 700), 1000, 0, 1)
	state.add_unit(defender)
	var shot := {"origin": Vector2(1500, 700), "damage": 100.0, "source": null, "pierce": 0.0}
	var rng := RandomNumberGenerator.new()
	var reference := RandomNumberGenerator.new()
	for sample in [[700.0, 0.0, 0.45], [700.0, 0.7, 0.8], [850.0, 0.0, 0.45], [850.0, 0.0, 1.0]]:
		if sample == [850.0, 0.0, 1.0]:
			state.wall.open_main_gate() # Behind an open gate there is no cover; a shut gate covers like the wall.
		defender.position.y = sample[0]
		state.siege_skill = sample[1]
		rng.seed = 19
		reference.seed = 19
		var expected := roundi(100.0 * reference.randf_range(0.85, 1.15) * sample[2])
		assert(Combat.arrow_hit(state, shot, defender, rng) == expected)
		assert(rng.state == reference.state)
	assert(state.wall.projectile_multiplier(defender, Vector2(1680, 850), 0.0) == 1.0)
