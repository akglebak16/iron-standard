extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Simulation = preload("res://core/battle/api/battle_simulation.gd")
const Worker = preload("res://adapters/godot/battle_worker.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	var loaded := Loader.populate(catalog)
	assert(loaded)
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_army.assign([{"type": "n1", "n": 20}, {"type": "n2a", "n": 10}, {"type": "n3c", "n": 10}])
	setup.enemy_army.assign([{"type": "e1", "n": 20}, {"type": "e2a", "n": 10}, {"type": "e3c", "n": 10}])
	var reference := Simulation.new(Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), Columns.create()))
	var worker := Worker.new(Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), Columns.create()))
	var other := Worker.new(Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), Columns.create()))
	assert(worker.supports_async() and other.supports_async())
	var command: Array[Dictionary] = [{"kind": "order", "order": "charge", "point": Vector2.ZERO, "selection": 3}]
	var accepted := worker.submit(command)
	assert(accepted)
	reference.submit(command)
	command[0].order = "hold" # Submitted commands own their values.
	other.start_batch(4)
	for batch in 180:
		var count := batch % 4 + 1
		worker.start_batch(count)
		for tick in count: reference.step()
		# Getter joins without consuming the completion count or queued events.
		assert(worker.snapshot() == reference.snapshot())
		assert(worker.finish_batch() == count)
		assert(worker.finish_batch() == 0)
		assert(worker.take_events() == reference.take_events())
		var frame := worker.render_snapshot()
		var expected := reference.render_snapshot()
		assert(frame.tick == expected.tick and frame.render.size() == expected.render.size())
		for row in frame.render.size():
			assert(frame.render.unit_at(row, 0.5) == expected.render.unit_at(row, 0.5))
		var saved := worker.snapshot()
		frame.ally_strength = -100
		assert(worker.snapshot() == saved, "Detached published frame cannot mutate simulation")
		if batch == 10:
			# An input callback while the next batch is running must only queue data.
			worker.start_batch(1)
			var queued: Array[Dictionary] = [{"kind": "order", "order": "hold", "point": Vector2(1300, 800), "selection": 3}]
			worker.submit(queued)
			reference.step()
			assert(worker.finish_batch() == 1)
			assert(worker.snapshot() == reference.snapshot())
			assert(worker.take_events() == reference.take_events())
			reference.submit(queued)
	assert(other.finish_batch() == 4 and other.snapshot().tick == 4, "Independent worker context")
	var invalid := worker.submit([{"kind": "bad"}])
	assert(not invalid)
	worker.start_batch(4)
	worker.dispose() # Teardown waits for in-flight work; no abandoned Thread.
	worker.dispose()
	assert(worker.snapshot().is_empty())
	other.dispose()
	reference.dispose()
	print("Battle worker tests passed")
	quit(0)
