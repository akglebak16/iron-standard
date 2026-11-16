extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const Config = preload("res://core/battle/config.gd")
const KITE_CENTER := Vector2(1250, 850)
const KITE_RADIUS := 220.0
func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	assert(Movement.create().is_valid())
	for scenario in ["field", "siege", "castle", "breach", "mixed", "kite"]:
		var siege: bool = scenario in ["siege", "castle", "breach"]
		var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
		setup.siege = siege
		setup.castle = scenario == "castle"
		setup.wall_damage = 0.65 if scenario == "breach" else 0.0
		setup.hero_profile.clear()
		setup.companion_profiles.clear()
		if scenario == "kite":
			# Stage 1a rules (DESIGN.md 1.4, 4.4): a fast hero circles in front of a charging mixed enemy.
			setup.player_army.assign([{"type": "n1", "n": 20}, {"type": "n2a", "n": 20}])
			setup.enemy_army.assign([{"type": "k1", "n": 40}, {"type": "k2c", "n": 15}, {"type": "e1", "n": 25}])
			setup.hero_position = KITE_CENTER + Vector2(KITE_RADIUS, 0)
		if scenario == "mixed":
			setup.player_army.assign([{"type": "n1", "n": 35}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 15}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 20}])
		var a := Factory.create(setup, catalog, null, null, null, Contacts.create())
		var b := Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
		var input := HeroInput.new()
		var fired := {"crowd": false, "wait": false, "leashed": false}
		for battle in [a, b]:
			if scenario == "kite":
				battle._hero.speed = 260.0
				battle._hero.max_hp = 1000000.0
				battle._hero.hp = battle._hero.max_hp
				for group in battle._state.groups[0]: group.order = Config.ORDER_HOLD
				for group in battle._state.groups[1]: group.order = Config.ORDER_CHARGE
				# Split the enemy infantry into two wings far from their formation places: the leash must pull them back.
				for unit in battle._state.groups[1][Config.GROUP_INFANTRY].units:
					unit.position.y += 420.0 if unit.id % 2 else -420.0
				continue
			battle.issue_order("charge", Vector2.ZERO, 3)
			if scenario == "mixed":
				for unit in battle._state.active_units:
					if unit.hero: continue
					unit.position = Vector2(1200 + unit.side * 100 + (unit.id % 6) * 18, 550 + (unit.id % 12) * 22)
				for group in battle._state.groups[1]: group.order = "charge"
		for tick in 1200:
			if siege and tick == 300:
				for battle in [a, b]: battle._state.wall.open_main_gate()
			if siege and tick == 600:
				for battle in [a, b]:
					for gate in battle._state.wall.gates: gate.hp = 0.0
			if tick == 900 and scenario != "kite":
				for battle in [a, b]: battle._state.kill(battle._hero)
			if scenario == "kite":
				var offset: Vector2 = a._hero.position - KITE_CENTER
				var radial := offset.normalized() if offset.length() > 1.0 else Vector2.RIGHT
				var move := Vector2(-radial.y, radial.x) + radial * clampf((KITE_RADIUS - offset.length()) / 40.0, -1.0, 1.0)
				input.move = move.normalized()
				input.face = move.angle()
				for battle in [a, b]: assert(battle.set_hero_input(input))
				for unit in a._state.active_units:
					if unit.attackers > Config.TARGET_CROWD_FREE_ATTACKERS: fired.crowd = true
					if unit.chase_seconds > 0.0: fired.wait = true
					if unit.leashed: fired.leashed = true
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
		if scenario == "kite":
			assert(fired.crowd and fired.wait and fired.leashed, "the stage 1a rules must fire in the compared battle: %s" % fired)
	print("Native movement parity tests passed")
	quit(0)
