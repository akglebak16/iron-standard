extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Config = preload("res://core/battle/config.gd")
const Legacy = preload("res://tests/unit/battle/fixtures/legacy_movement.gd")

func _initialize() -> void:
	var historical := _stack(2, false)
	Legacy._resolve_unit_collisions(historical)
	assert(historical.active_units[0].position == historical.active_units[1].position, "historical reference remains unchanged by default")
	for enemy in [false, true]:
		var expected := PackedVector2Array()
		for backend in ["plain", "packed", "native"]:
			var battle := _stack(2, backend == "native")
			var a := battle.active_units[0]
			var b := battle.active_units[1]
			b.side = 1 if enemy else 0
			a.mass = 5.0
			b.mass = 1.0
			var center := (a.position * a.mass + b.position * b.mass) / (a.mass + b.mass)
			if backend == "plain": Movement._resolve_unit_collisions(battle, null)
			else: Movement._resolve_packed(battle, null)
			assert(a.position.distance_to(b.position) > 1.0, "coincident soldiers must start separating")
			assert(a.position.distance_to(center) < b.position.distance_to(center), "heavier unit moves less")
			assert(((a.position * a.mass + b.position * b.mass) / (a.mass + b.mass)).distance_to(center) < 0.001)
			if expected.is_empty(): expected = battle.motion.positions.duplicate()
			else: assert(battle.motion.positions == expected, "fallback direction must match all backends")
	var reference := _stack(96, false)
	var accelerated := _stack(96, true)
	var repeated := _stack(96, true)
	for tick in 30:
		Movement._resolve_packed(reference, null)
		Movement._resolve_packed(accelerated, null)
		Movement._resolve_packed(repeated, null)
		assert(reference.motion.positions == accelerated.motion.positions)
		assert(accelerated.motion.positions == repeated.motion.positions, "crowd resolution is deterministic")
		assert(accelerated.active_units.size() == 96, "contacts cannot hide or remove soldiers")
		for position in accelerated.motion.positions:
			assert(position.is_finite())
			assert(position.x >= Config.FIELD_LEFT_RIGHT_MARGIN and position.x <= Config.ARENA_SIZE.x - Config.FIELD_LEFT_RIGHT_MARGIN)
			assert(position.y >= Config.FIELD_TOP_MARGIN and position.y <= Config.ARENA_SIZE.y - Config.FIELD_BOTTOM_MARGIN)
	var distinct := {}
	for position in accelerated.motion.positions: distinct[position] = true
	assert(distinct.size() > 48, "the stack must spread, not merely remain finite")
	assert(accelerated.native_contact_steps == 30 and accelerated.native_contact_failures == 0)
	print("Coincident contacts tests passed")
	quit(0)

func _stack(count: int, native: bool) -> State:
	var battle := State.new()
	if native:
		battle.contact_solver = Contacts.create()
		assert(battle.contact_solver.is_valid())
	for i in count: battle.add_unit(Unit.new(i, 0, Vector2(1300,900),100,0,1))
	return battle
