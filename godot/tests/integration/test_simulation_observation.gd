extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Figures = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Impacts = preload("res://apps/godot/presentation/battle/impact_effects.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	var reference := Factory.create(setup, catalog)
	var observed := Factory.create(setup, catalog)
	observed._state.profiler.clock = Time.get_ticks_usec
	observed._state.profiler.detailed = true
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
		# New HUD/atlas queries must also remain detached and RNG-neutral.
		var identities := observed.unit_appearance_ids()
		identities.clear()
		for group in 4:
			var orders := observed.selected_orders(group)
			orders.clear()
		assert(frame.tick == tick + 1)
		assert(reference._rng.state == observed._rng.state)
	assert(reference.snapshot() == observed.snapshot())
	assert(observed._state.profiler.samples.has("contacts"))
	assert(reference._state.profiler.samples.is_empty())
	print("Simulation observation tests passed")
	quit(0)
