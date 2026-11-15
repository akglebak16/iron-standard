extends SceneTree
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	var kernel = ClassDB.instantiate("IronContactKernel")
	assert(kernel != null)
	assert(not kernel.configure(PackedFloat64Array(),PackedVector2Array(),PackedFloat64Array(),PackedVector2Array()))
	assert(kernel.solve(PackedVector2Array(),PackedVector2Array(),PackedFloat64Array(),PackedFloat64Array(),PackedInt32Array(),PackedByteArray(),PackedByteArray()).is_empty())
	kernel = null
	for siege in [false, true]:
		var setup = load("res://content/scenarios/demo_siege.tres" if siege else "res://content/scenarios/demo_battle.tres").to_setup()
		setup.companion_profiles.clear()
		setup.hero_profile.clear()
		setup.seed = 4242
		setup.player_army.assign([{"type":"n1", "n":35}, {"type":"n2a", "n":20}, {"type":"n2s", "n":15}])
		setup.enemy_army.assign([{"type":"k1", "n":30}, {"type":"k2a", "n":20}, {"type":"k2c", "n":20}])
		var reference = Factory.create(setup, catalog)
		var accelerated = Factory.create(setup, catalog, null, null, null, Contacts.create())
		assert(accelerated._state.contact_solver.is_valid(), "Native backend must actually load")
		# Dense, coincident, out-of-bounds and inactive columns, including static contacts.
		var random := RandomNumberGenerator.new()
		random.seed = 53
		for repetition in 10:
			for i in reference._state.units.size():
				var a = reference._state.units[i]
				var b = accelerated._state.units[i]
				a.position = Vector2(random.randf_range(-40, 2450), random.randf_range(-30, 1430)) if repetition % 2 == 0 else Vector2(1800, 650) + Vector2(random.randf_range(-40,40), random.randf_range(-40,40))
				if i % 7 == 0: a.position = Vector2(1800,650)
				a.velocity = Vector2(random.randf_range(-20,20), random.randf_range(-20,20))
				a.dead = i % 13 == 0
				a.gone = i % 17 == 0
				a.fleeing = i % 5 == 0
				b.position = a.position
				b.velocity = a.velocity
				b.dead = a.dead
				b.gone = a.gone
				b.fleeing = a.fleeing
			Movement._resolve_packed(reference._state, null)
			Movement._resolve_packed(accelerated._state, null)
			_compare(reference, accelerated, repetition)
		# Fresh paired contexts: same full battle, RNG, events and outputs every tick.
		reference = Factory.create(setup, catalog)
		accelerated = Factory.create(setup, catalog, null, null, null, Contacts.create())
		reference.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
		accelerated.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
		for tick in 900:
			reference.advance(1.0/60.0)
			accelerated.advance(1.0/60.0)
			_compare(reference, accelerated, tick)
		assert(accelerated._state.native_contact_steps == 900)
		assert(accelerated._state.native_contact_failures == 0)
	print("Native contacts tests passed")
	quit(0)

func _compare(a, b, tick: int) -> void:
	for i in a._state.units.size():
		var x = a._state.units[i]
		var y = b._state.units[i]
		assert(x.position == y.position and x.velocity == y.velocity, "Native contact differs at tick %d unit %d: %s/%s vs %s/%s" % [tick,i,x.position,x.velocity,y.position,y.velocity])
		assert([x.hp,x.dead,x.gone,x.target_handle,x.kills] == [y.hp,y.dead,y.gone,y.target_handle,y.kills])
	assert(a._state.take_events() == b._state.take_events())
	assert(a.take_events() == b.take_events())
	assert(a._rng.state == b._rng.state)
