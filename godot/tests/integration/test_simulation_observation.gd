extends SceneTree
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Figures = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Impacts = preload("res://apps/godot/presentation/battle/impact_effects.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	var reference := Factory.create(setup, catalog)
	var observed := Factory.create(setup, catalog)
	observed._state.profiler.clock = Time.get_ticks_usec
	var figures := Figures.new()
	var impacts := Impacts.new()
	for battle in [reference, observed]: battle.issue_order("charge", Vector2.ZERO, 3)
	for tick in 600:
		reference.step()
		observed.step()
		var events := observed.take_events()
		assert(reference.take_events() == events)
		figures.advance(1.0 / 60.0, events)
		impacts.blood_enabled = tick % 2 == 0
		impacts.advance(1.0 / 60.0, events)
		var frame := observed.snapshot(true)
		assert(frame.tick == tick + 1)
		assert(reference._rng.state == observed._rng.state)
	assert(reference.snapshot() == observed.snapshot())
	assert(observed._state.profiler.samples.has("contacts"))
	assert(reference._state.profiler.samples.is_empty())
	print("Simulation observation tests passed")
	quit(0)
