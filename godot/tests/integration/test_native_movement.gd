extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	assert(Movement.create().is_valid())
	for scenario in ["field", "siege", "mixed"]:
		var siege: bool = scenario == "siege"
		var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
		setup.siege = siege
		setup.hero_profile.clear()
		setup.companion_profiles.clear()
		if scenario == "mixed":
			setup.player_army.assign([{"type": "n1", "n": 35}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 15}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 20}])
		var a := Factory.create(setup, catalog, null, null, null, Contacts.create())
		var b := Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
		for battle in [a, b]:
			battle.issue_order("charge", Vector2.ZERO, 3)
			if scenario == "mixed":
				for unit in battle._state.active_units:
					if unit.hero: continue
					unit.position = Vector2(1200 + unit.side * 100 + (unit.id % 6) * 18, 550 + (unit.id % 12) * 22)
				for group in battle._state.groups[1]: group.order = "charge"
		for tick in 1200:
			if tick == 900:
				for battle in [a, b]: battle._state.kill(battle._hero)
			a.step()
			b.step()
			assert(a._rng.state == b._rng.state, "RNG tick %d siege %s" % [tick, siege])
			assert(a.take_events() == b.take_events(), "Events tick %d siege %s" % [tick, siege])
			if tick % 30 == 0:
				assert(a.snapshot() == b.snapshot(), "Snapshot tick %d" % tick)
				var left_frame = a.snapshot(true).render
				var right_frame = b.snapshot(true).render
				assert(left_frame.size() == right_frame.size())
				for row in left_frame.size(): assert(left_frame.unit_at(row, 0.5) == right_frame.unit_at(row, 0.5), "Render row %d tick %d" % [row, tick])
			for field in ["positions", "velocities", "real_fields", "integer_fields", "vector_fields"]:
				assert(a._state.motion.get(field) == b._state.motion.get(field), "Columns %s tick %d %s" % [field, tick, scenario])
			for index in a._state.units.size():
				assert(a._state.units[index].morale == b._state.units[index].morale)
				assert(a._state.units[index].kills == b._state.units[index].kills)
	print("Native movement parity tests passed")
	quit(0)
