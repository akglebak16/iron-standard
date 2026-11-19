extends SceneTree
## The player's allies (#243): their own army on his side, in their own groups under their own commander (the side
## brain of tactics.gd), sharing his side's unit cap; his orders, his HUD and his hero's fall leave them alone. The same
## battle runs on the GDScript reference and on the native kernels (9 group slots) and must stay equal tick by tick.
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Config = preload("res://core/battle/config.gd")
const TICKS := 1500

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	assert(Movement.create().is_valid(), "the native library is loaded")
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.seed = 243
	var ally_faction := _faction_with_all_kinds(catalog, [setup.player_faction, setup.enemy_faction])
	assert(not ally_faction.is_empty())
	setup.ally_faction = ally_faction
	setup.ally_army.assign(_army(catalog, ally_faction, [14, 6, 4]))
	var enemy: Array[Dictionary] = []
	for stack in setup.enemy_army:
		enemy.append({"type": stack.type, "n": int(stack.n) * 2})
	setup.enemy_army.assign(enemy)
	# The side cap is shared: a small cap scales both armies down by their head counts.
	var capped = setup.duplicate()
	capped.player_unit_cap = 30
	var caps: Array[int] = Factory.side_caps(capped, 30)
	assert(caps[0] + caps[1] == 30 and caps[0] > 0 and caps[1] > 0, str(caps))
	var small := Factory.create(capped, catalog, null, null, null, Contacts.create())
	var side_fighters := small._state.units.filter(func(u): return u.side == 0 and not u.hero).size()
	assert(side_fighters <= 30 + 3, "the allies count into the player's side cap (%d)" % side_fighters) # +rounding per stack

	var a := Factory.create(setup, catalog, null, null, null, Contacts.create())
	var b := Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
	assert(a != null and b != null)
	for battle in [a, b]:
		var state = battle._state
		assert(state.groups.size() == 3 and state.has_allies())
		var allies := 0
		for unit in state.units:
			if unit.command == Config.COMMAND_ALLY:
				allies += 1
				assert(unit.side == 0 and unit.faction == ally_faction and state.group_of(unit) in state.groups[Config.COMMAND_ALLY])
			elif unit.side == 0 and not unit.hero:
				assert(unit.command == Config.COMMAND_PLAYER and state.group_of(unit) in state.groups[0])
		assert(allies == 24, "every allied soldier stands in the allied groups (%d)" % allies)
		# the player's orders and his HUD are for his own men only
		assert(battle.issue_order(Config.ORDER_FOLLOW, Vector2.ZERO, Config.ALL_GROUPS))
	a.step()
	b.step()
	for battle in [a, b]:
		var state = battle._state
		for group in state.groups[0]:
			assert(group.order == Config.ORDER_FOLLOW)
		for group in state.groups[Config.COMMAND_ALLY]:
			assert(group.order != Config.ORDER_FOLLOW, "the allies do not follow the player's hero")
		var shown: Array = battle.snapshot().player_groups
		assert(shown.size() == 3)
	var ally_charge := -1
	var ally_kills := 0
	for tick in TICKS:
		if tick == 900:
			for battle in [a, b]: battle._state.kill(battle._hero)
		a.step()
		b.step()
		assert(a._rng.state == b._rng.state, "RNG tick %d" % tick)
		assert(a.take_events() == b.take_events(), "Events tick %d" % tick)
		for field in ["positions", "velocities", "real_fields", "integer_fields", "vector_fields"]:
			assert(a._state.motion.get(field) == b._state.motion.get(field), "Columns %s tick %d" % [field, tick])
		if tick % 60 == 0:
			assert(a.snapshot() == b.snapshot(), "Snapshot tick %d" % tick)
		if ally_charge < 0 and tick < 900:
			for group in a._state.groups[Config.COMMAND_ALLY]:
				if group.order == Config.ORDER_CHARGE:
					ally_charge = tick
	for unit in a._state.units:
		if unit.command == Config.COMMAND_ALLY:
			ally_kills += unit.kills
	assert(ally_charge >= 0, "the allied commander leads his men into the charge on his own")
	assert(ally_kills > 0, "the allies fight: %d kills" % ally_kills)
	assert(int(b._state.native_movement_steps) > 0 and int(b._state.native_movement_failures) == 0, "the native kernel ran with 9 groups")
	print("Battle allies tests passed (allied charge at tick %d, %d kills)" % [ally_charge, ally_kills])
	quit(0)

static func _faction_with_all_kinds(catalog: Catalog, skip: Array) -> String:
	for faction in ["dom", "khan", "gal", "rus", "nord", "emp"]:
		if faction in skip:
			continue
		var kinds := {}
		for troop in catalog.for_faction(faction):
			kinds[int(troop.grp)] = true
		if kinds.size() == 3:
			return faction
	return ""

static func _army(catalog: Catalog, faction: String, counts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in 3:
		for troop in catalog.for_faction(faction):
			if int(troop.grp) == kind:
				out.append({"type": troop.id, "n": counts[kind]})
				break
	return out
