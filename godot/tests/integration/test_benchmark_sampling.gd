extends SceneTree
const Benchmark = preload("res://tests/performance/battle_benchmark.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	for compact in [false, true]:
		var reference = Factory.create(setup, catalog)
		var measured = Factory.create(setup, catalog)
		for i in 60: reference.step()
		assert(Benchmark.warm_session(measured, 60, compact))
		assert(reference.snapshot() == measured.snapshot(), "snapshot warmup cannot alter battle rules")
		assert(reference._rng.state == measured._rng.state)
		assert(not reference.take_events().is_empty(), "setup/warmup emitted real events")
		assert(measured.take_events().is_empty(), "warmup events must not pollute measured counts")
		assert(not measured._render_definitions.is_empty() if compact else not measured._looks.is_empty())
		# A warmed context continues identically to one observed only after its warmup.
		for i in 10:
			reference.step()
			measured.step()
			assert(reference.take_events() == measured.take_events())
		assert(reference.snapshot() == measured.snapshot() and reference._rng.state == measured._rng.state)
	var fresh = Factory.create(setup, catalog)
	assert(Benchmark.warm_session(fresh, 0, true) and fresh.take_events().is_empty())
	# Do not report near-zero timings from a completed session as battle performance.
	fresh._outcome = fresh.Outcome.VICTORY
	assert(not Benchmark.warm_session(fresh, 1, true))
	print("Benchmark sampling tests passed")
	quit(0)
