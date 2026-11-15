extends RefCounted
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## CPU baseline. Count and weight checks execute in release too; --ticks is simulation time, not frame count.
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Config = preload("res://battle/config.gd")
var size := 1000
var ticks := 3600
var warmup := 120
var scenario := "contact"
var seed_value := 4242
var output := ""
var legacy_snapshot := false
var profile_phases := false
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
	if size < 1 or ticks < 1 or warmup < 0 or scenario not in ["approach", "contact", "volley", "cavalry", "siege"]:
		fail("Invalid benchmark parameters")
		return
	var catalog := Catalog.new()
	if not ContentLoader.populate(catalog):
		fail("Catalog failed to load")
		return
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.seed = seed_value
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_unit_cap = size
	setup.enemy_unit_cap = size
	setup.siege = scenario == "siege"
	var types := ["n1", "e1"]
	if scenario == "volley": types = ["n2a", "e2a"]
	elif scenario == "cavalry": types = ["n2s", "e2s"]
	setup.player_army.assign([{"type": types[0], "n": size}])
	setup.enemy_army.assign([{"type": types[1], "n": size}])
	var session = Factory.create(setup, catalog)
	if session == null:
		fail("Cannot create benchmark battle")
		return
	if profile_phases: session._state.profiler.clock = Time.get_ticks_usec
	var initial := [0, 0]
	for unit in session._state.units:
		if unit.hero or unit.companion: continue
		initial[unit.side] += 1
		if unit.weight != 1.0:
			fail("Weighted units cannot stand in for individual soldiers")
			return
		if scenario in ["contact", "cavalry", "volley"]:
			var ordinal: int = initial[unit.side] - 1
			var front := 12.0 if scenario == "contact" else 180.0
			unit.position = Vector2(1300.0 + (front + (ordinal / 50) * 24.0) * (-1.0 if unit.side == 0 else 1.0), 200.0 + (ordinal % 50) * 26.0)
	if initial != [size, size]:
		fail("Actual population differs: %s" % str(initial))
		return
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	if scenario in ["contact", "cavalry", "volley"]:
		for group in session._state.groups[1]: group.order = Config.ORDER_CHARGE
	for i in warmup: session.advance(1.0 / 60.0)
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
	for phase in phases: phase_stats[phase] = stats(phases[phase])
	var report := {"engine": Engine.get_version_info().string, "debug": OS.is_debug_build(),
		"cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"scenario": scenario, "seed": seed_value, "requested_per_side": size, "ordinary_initial": initial,
		"special_initial": 1, "weight": 1, "warmup_ticks": warmup, "requested_ticks": ticks,
		"measured_ticks": simulation.size(), "live_min": live_min, "live_max": live_max,
		"simulation": stats(simulation), "snapshot": stats(snapshots), "events": events,
		"snapshot_format": "legacy-dictionaries" if legacy_snapshot else "compact-columns",
		"phase_profile": phase_stats,
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
