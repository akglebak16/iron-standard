extends SceneTree
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Combat = preload("res://battle/rules/combat.gd")
const Step = preload("res://battle/rules/combat_step.gd")

func resolve(indexed: bool) -> Array:
	var state := State.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 150:
		var unit := Unit.new(i + 100, i % 2, Vector2((i % 15) * 24, (i / 15) * 24), 100, 0, 1)
		unit.damage = 10
		unit.attack_range = 1000
		unit.accuracy = 0.8
		state.add_unit(unit)
	for i in 50:
		var shot := Combat.shoot(state.units[i * 2], state.units[i * 2 + 1], rng)
		shot.time = shot.duration
		state.launch_projectile(shot)
	# Test current positions, including overlapping ties and crossing a cell edge.
	state.units[1].position = Vector2(64, 24)
	state.units[3].position = state.units[1].position
	Step.resolve_projectiles(state, 1.0 / 60.0, rng, indexed)
	var values: Array = []
	for unit in state.units: values.append([unit.hp, unit.dead, unit.kills])
	return [values, state.take_events(), rng.state]

func _initialize() -> void:
	assert(resolve(true) == resolve(false))
	print("Projectile broadphase tests passed")
	quit(0)
