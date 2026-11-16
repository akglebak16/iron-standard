extends SceneTree
## Stage 1a-archers (DESIGN.md 4.4, decision 15) in a whole battle: a mass of shooters fires at a dense formation with
## one man ahead of it. The first volley must spread over many men of the front instead of the nearest ones, and few
## arrows may fly at a man who is already doomed or dead (metrics of tests/performance/battle_arena.gd). Both sides
## shoot: side 0 with foot archers, side 1 with a mixed force of foot and horse archers; the C++ kernel and the
## GDScript reference are checked to agree on the outcome.
const Arena = preload("res://tests/performance/battle_arena.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const TICKS := 1200
const LONE_AHEAD := 170.0

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	var foot := _run(catalog, 0, false)
	var native := _run(catalog, 0, true)
	assert(foot == native, "native and reference volleys differ: %s / %s" % [foot, native])
	_check(foot, "foot archers of side 0")
	var mixed := _run(catalog, 1, true)
	_check(mixed, "mixed shooters of side 1")
	print("Archer volley tests passed: ", foot, " ", mixed)
	quit(0)

func _check(result: Dictionary, label: String) -> void:
	# Before the stage the whole first volley went to the men nearest to the shooters: nearest == targets.
	assert(result.first_targets >= 2 * result.first_nearest, "%s: first volley at %d men, nearest are %d" % [label, result.first_targets, result.first_nearest])
	assert(result.lone_aimers < result.lone_nearest, "%s: not every shooter aims at the man ahead" % label)
	assert(result.volleys.dead_share < 0.08 and result.volleys.doomed_share < 0.1, "%s: wasted arrows %s" % [label, result.volleys])

## Shooting side `shooters` holds; the other side stands in a dense block with its first man pushed ahead.
func _run(catalog: Catalog, shooters: int, native: bool) -> Dictionary:
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.seed = 777
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	var archers: Array = [{"type": "n2a", "n": 90}] if shooters == 0 else [{"type": "k2a", "n": 60}, {"type": "k3h", "n": 30}]
	var block: Array = [{"type": "e1", "n": 60}] if shooters == 0 else [{"type": "n1", "n": 45}, {"type": "n3c", "n": 15}]
	setup.player_army.assign(archers if shooters == 0 else block)
	setup.enemy_army.assign(block if shooters == 0 else archers)
	var session = Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create() if native else Callable(), Columns.create() if native else null)
	assert(session != null)
	var state = session._state
	state.mark_gone(session._hero)
	var target_side := 1 - shooters
	var shooter_x := 900.0 if shooters == 0 else 1700.0
	var block_x := 1420.0 if shooters == 0 else 1180.0
	var facing := 0.0 if shooters == 0 else PI
	for kind in [Config.GROUP_INFANTRY, Config.GROUP_ARCHERS, Config.GROUP_CAVALRY]:
		var own = state.groups[shooters][kind]
		_place(state, own, Vector2(shooter_x, 850 + (kind - Config.GROUP_ARCHERS) * 260), facing)
		own.order = Config.ORDER_HOLD
		var foe = state.groups[target_side][kind]
		_place(state, foe, Vector2(block_x, 850 + (kind - Config.GROUP_INFANTRY) * 200), facing + PI)
		foe.order = Config.ORDER_HOLD
	var lone = state.groups[target_side][Config.GROUP_INFANTRY].units[0]
	lone.slot_offset += Vector2(0, LONE_AHEAD)
	lone.position = state.groups[target_side][Config.GROUP_INFANTRY].slot_position(lone, state.arena_size)
	var tracker := Arena.volley_tracker()
	var first_targets := {}
	var first_nearest := {}
	var first_tick := -1
	var lone_aimers := 0
	var lone_nearest := 0
	for tick in range(1, TICKS + 1):
		session.step()
		for event in session.take_events():
			if event.kind != Event.Kind.SHOT: continue
			Arena.track_shot(tracker, state, int(event.target_id), tick)
			var shooter = state.units.filter(func(u): return u.id == int(event.target_id))[0]
			if first_tick < 0: first_tick = tick
			if tick - first_tick < Arena.VOLLEY_TICKS and shooter.side == shooters:
				var target = state.unit_for(shooter.target_handle)
				if target != null: first_targets[target.id] = true
				var nearest = _nearest(state, shooter)
				if nearest != null: first_nearest[nearest.id] = true
		Arena.advance_volleys(tracker, tick)
		if tick == 45:
			# Retargeting has settled once; the man ahead is still alive.
			assert(not lone.dead)
			lone_aimers = lone.aimers
			for unit in state.groups[shooters][Config.GROUP_ARCHERS].units + state.groups[shooters][Config.GROUP_CAVALRY].units:
				if unit.attack_range > 0.0 and _nearest(state, unit) == lone: lone_nearest += 1
	assert(first_tick > 0, "the shooters must fire")
	return {"first_targets": first_targets.size(), "first_nearest": first_nearest.size(), "lone_aimers": lone_aimers,
		"lone_nearest": lone_nearest, "volleys": Arena.volley_report(tracker)}

static func _nearest(state, unit):
	var best := INF
	var found = null
	for enemy in state.active_units:
		if enemy.side == unit.side or enemy.dead or enemy.gone or enemy.hero: continue
		var d: float = unit.position.distance_to(enemy.position)
		if d < best:
			best = d
			found = enemy
	return found

static func _place(state, group, at: Vector2, facing: float) -> void:
	group.center = at
	group.direction = facing
	group.layout(true)
	for unit in group.units:
		unit.position = group.slot_position(unit, state.arena_size)
		unit.velocity = Vector2.ZERO
