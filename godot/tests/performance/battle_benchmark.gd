extends RefCounted
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const NativeMovement = preload("res://adapters/godot/native/movement.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
## CPU baseline. Count and weight checks execute in release too; --ticks is simulation time, not frame count.
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Config = preload("res://core/battle/config.gd")
var size := 1000
var ticks := 3600
var warmup := 120
var scenario := "contact"
var seed_value := 4242
var output := ""
var legacy_snapshot := false
var profile_phases := false
var profile_details := false
var contact_backend := "native"
var movement_backend := "native"
var _tree: SceneTree

func run(tree: SceneTree) -> void:
	_tree = tree
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="): size = int(arg.trim_prefix("--n="))
		elif arg.begins_with("--ticks="): ticks = int(arg.trim_prefix("--ticks="))
		elif arg.begins_with("--warmup="): warmup = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--seed="): seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg == "--legacy-snapshot": legacy_snapshot = true
		elif arg == "--profile-phases": profile_phases = true
		elif arg == "--profile-details":
			profile_phases = true
			profile_details = true
		elif arg.begins_with("--movement="): movement_backend = arg.trim_prefix("--movement=")
		elif arg.begins_with("--contacts="): contact_backend = arg.trim_prefix("--contacts=")
	if size < 1 or ticks < 1 or warmup < 0 or scenario not in ["approach", "contact", "volley", "cavalry", "siege", "mixed"]:
		fail("Invalid benchmark parameters")
		return
	var catalog := Catalog.new()
	if not ContentLoader.populate(catalog):
		fail("Catalog failed to load")
		return
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.seed = seed_value
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_unit_cap = size
	setup.enemy_unit_cap = size
	setup.siege = scenario == "siege"
	var types := ["n1", "e1"]
	if scenario == "volley": types = ["n2a", "e2a"]
	elif scenario == "cavalry": types = ["n3c", "e3c"]
	setup.player_army.assign([{"type": types[0], "n": size}])
	setup.enemy_army.assign([{"type": types[1], "n": size}])
	if scenario == "mixed":
		var infantry := size / 2
		var archers := size / 3
		var cavalry := size - infantry - archers
		setup.player_army.assign([{"type": "n1", "n": infantry}, {"type": "n2a", "n": archers}, {"type": "n3c", "n": cavalry}])
		setup.enemy_army.assign([{"type": "e1", "n": infantry}, {"type": "e2a", "n": archers}, {"type": "e3c", "n": cavalry}])
	if contact_backend not in ["native", "gdscript"] or movement_backend not in ["native", "gdscript"]:
		fail("Unknown contact backend")
		return
	var solver := Contacts.create() if contact_backend == "native" else Callable()
	if contact_backend == "native" and not solver.is_valid():
		fail("Native contact backend unavailable")
		return
	var movement := NativeMovement.create() if movement_backend == "native" else Callable()
	if movement_backend == "native" and not movement.is_valid():
		fail("Native movement backend unavailable")
		return
	var session = Factory.create(setup, catalog, null, null, null, solver, movement, NativeColumns.create() if movement_backend == "native" else null)
	if session == null:
		fail("Cannot create benchmark battle")
		return
	if profile_phases: session._state.profiler.clock = Time.get_ticks_usec
	session._state.profiler.detailed = profile_details
	var initial := [0, 0]
	var mounted := [0, 0]
	var ranged := [0, 0]
	for unit in session._state.units:
		if unit.hero or unit.companion: continue
		initial[unit.side] += 1
		if unit.mounted: mounted[unit.side] += 1
		if unit.attack_range > 0: ranged[unit.side] += 1
		if unit.weight != 1.0:
			fail("Weighted units cannot stand in for individual soldiers")
			return
		if scenario in ["contact", "cavalry", "volley"]:
			var ordinal: int = initial[unit.side] - 1
			var front := 12.0 if scenario == "contact" else 180.0
			# The dense block stands in the middle of the field (TERRAIN Р0а: 1000 a side fight on a larger field); on the
			# base field these are the old coordinates.
			var middle: Vector2 = (session._state.arena_size - Config.ARENA_SIZE) * 0.5
			unit.position = Vector2(1300.0 + middle.x + (front + (ordinal / 50) * 24.0) * (-1.0 if unit.side == 0 else 1.0), 200.0 + middle.y + (ordinal % 50) * 26.0)
	if scenario == "cavalry" and mounted != [size, size] or scenario == "volley" and ranged != [size, size]:
		fail("Scenario composition does not match its name")
		return
	if initial != [size, size]:
		fail("Actual population differs: %s" % str(initial))
		return
	if scenario == "mixed" and (mounted != [size - size / 2 - size / 3, size - size / 2 - size / 3] or ranged != [size / 3, size / 3]):
		fail("Mixed scenario composition mismatch")
		return
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	if scenario in ["contact", "cavalry", "volley"]:
		for group in session._state.groups[1]: group.order = Config.ORDER_CHARGE
	if not warm_session(session, warmup, not legacy_snapshot):
		fail("Battle ended during warmup; choose a shorter warmup or another scenario")
		return
	var simulation: Array[int] = []
	var snapshots: Array[int] = []
	var phases := {}
	var live_min := size * 2 + 1
	var live_max := 0
	var events := {}
	var memory_start := OS.get_static_memory_usage()
	for i in ticks:
		var start := Time.get_ticks_usec()
		session.advance(1.0 / 60.0)
		simulation.append(Time.get_ticks_usec() - start)
		if profile_phases:
			for phase in session._state.profiler.samples:
				if not phases.has(phase): phases[phase] = [] as Array[int]
				phases[phase].append(session._state.profiler.samples[phase])
		start = Time.get_ticks_usec()
		var frame: Dictionary = session.snapshot(not legacy_snapshot)
		snapshots.append(Time.get_ticks_usec() - start)
		var live: int = frame.counts[0] + frame.counts[1]
		live_min = mini(live_min, live)
		live_max = maxi(live_max, live)
		for event in session.take_events():
			var key := str(event.kind)
			events[key] = int(events.get(key, 0)) + 1
		if frame.outcome in [session.Outcome.VICTORY, session.Outcome.DEFEAT]: break
	var phase_stats := {}
	if movement_backend == "native" and (session._state.native_movement_steps == 0 or session._state.native_movement_failures != 0):
		fail("Native movement was not executed reliably")
		return
	if contact_backend == "native" and (session._state.native_contact_steps == 0 or session._state.native_contact_failures != 0):
		fail("Native contact fallback occurred")
		return
	for phase in phases: phase_stats[phase] = stats(phases[phase])
	var report := {"engine": Engine.get_version_info().string, "debug": OS.is_debug_build(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"scenario": scenario, "seed": seed_value, "requested_per_side": size, "ordinary_initial": initial,
		"special_initial": 1, "weight": 1, "warmup_ticks": warmup, "requested_ticks": ticks,
		"sampling_version": 2, "warmup_snapshots": true, "warmup_events_discarded": true,
		"measured_ticks": simulation.size(), "live_min": live_min, "live_max": live_max,
		"simulation": stats(simulation), "snapshot": stats(snapshots), "events": events,
		"snapshot_format": "legacy-dictionaries" if legacy_snapshot else "compact-columns",
		"phase_profile": phase_stats,
		"ordinary_mounted": mounted, "ordinary_ranged": ranged,
		"movement_backend": movement_backend, "native_movement_steps": session._state.native_movement_steps,
		"native_movement_failures": session._state.native_movement_failures, "native_movement_interactions": session._state.native_movement_interactions,
		"contact_backend": contact_backend, "native_contact_steps": session._state.native_contact_steps,
		"native_contact_failures": session._state.native_contact_failures,
		"active_storage_records": session._state.active_units.size(),
		"outcome_history_records": session._state.units.size(),
		"memory_start_bytes": memory_start if memory_start > 0 else null,
		"memory_end_bytes": OS.get_static_memory_usage() if OS.get_static_memory_usage() > 0 else null,
		"gpu_time": null, "note": "Headless CPU benchmark, not an FPS measurement. Early battle termination shortens the sample."}
	var encoded := JSON.stringify(report)
	print(encoded)
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			fail("Cannot write benchmark report")
			return
		file.store_string(encoded + "\n")
	_tree.quit(0)

## Warm the same snapshot path that is measured and remove setup/warmup events.
## A battle already finished cannot provide a meaningful steady-state sample.
static func warm_session(session, count: int, compact: bool) -> bool:
	for i in count:
		session.advance(1.0 / 60.0)
		var frame: Dictionary = session.snapshot(compact)
		session.take_events()
		if frame.outcome in [session.Outcome.VICTORY, session.Outcome.DEFEAT]: return false
	# Also remove setup notices when warmup is explicitly zero.
	session.take_events()
	return true

static func stats(samples: Array[int]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted: total += value
	return {"count": sorted.size(), "mean_ms": total / float(sorted.size()) / 1000.0,
		"p50_ms": sorted[int((sorted.size() - 1) * 0.50)] / 1000.0,
		"p95_ms": sorted[int((sorted.size() - 1) * 0.95)] / 1000.0,
		"p99_ms": sorted[int((sorted.size() - 1) * 0.99)] / 1000.0}

func fail(message: String) -> void:
	push_error(message)
	_tree.quit(1)
