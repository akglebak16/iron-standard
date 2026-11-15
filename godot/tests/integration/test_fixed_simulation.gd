extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Clock = preload("res://runtime/scheduling/fixed_step_clock.gd")
const Simulation = preload("res://core/battle/api/battle_simulation.gd")
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Event = preload("res://battle/combat_event.gd")

func run_at(fps: int) -> Dictionary:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	var simulation := Simulation.new(Factory.create(setup, catalog))
	var clock := Clock.new()
	var commands: Array[Dictionary] = [{"kind": "order", "order": "charge", "point": Vector2.ZERO, "selection": 3}]
	assert(simulation.submit(commands))
	commands[0].order = "invalid" # Caller changes cannot change queued commands.
	for frame in fps * 3: clock.advance(1.0 / fps, simulation.step)
	assert(clock.ticks == 180 and clock.dropped_seconds == 0.0)
	var events := simulation.take_events()
	assert(events.any(func(e): return e.kind == Event.Kind.ORDER_APPLIED and e.order == "charge"))
	assert(events.any(func(e): return e.kind == Event.Kind.BATTLE_STARTED))
	assert(simulation.take_events().is_empty())
	var snapshot := simulation.snapshot()
	var expected = snapshot.units[0].position
	snapshot.units[0].position = Vector2.INF
	assert(simulation.snapshot().units[0].position == expected)
	return simulation.snapshot()

func _initialize() -> void:
	var reference := run_at(60)
	assert(run_at(30) == reference)
	assert(run_at(144) == reference)
	var clock := Clock.new()
	assert(clock.advance(10.0, func(): pass) == Clock.MAX_STEPS)
	assert(clock.overloads == 1 and clock.dropped_seconds > 9.0)
	for invalid in [0.0, -1.0, NAN, INF]: assert(clock.advance(invalid, func(): pass) == 0)
	clock.reset()
	assert(clock.accumulator == 0.0)
	print("Fixed simulation tests passed")
	quit(0)
