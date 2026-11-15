extends Node
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
## Informational: frame cost of a mass battle with its view (simulation + snapshot + drawing).
##   godot --path godot --script res://tools/battle/view_bench.gd [-- --n=300 --frames=240]
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const Config = preload("res://core/battle/config.gd")
const BattleView = preload("res://apps/godot/presentation/battle/scene.tscn")
var _view: Node
var _n := 0
var _frames := 240
var _last := 0
var _times: Array[int] = []
var _size := 300
var _mode := "battle"
var _seed := 4242
var _audio := false
var _output := ""
var _world: Node
var _session: RefCounted
var _tick_start := 0
var _map_cache := true
var _draw_calls := 0.0
var _render_cpu: Array[int] = []
var _render_gpu: Array[int] = []
var _measure_seconds := 0.0
var _measure_start := 0
var _camera_route := false
var _memory_samples: Array[float] = []
const Stats = preload("res://tests/performance/battle_benchmark.gd")
const World = preload("res://apps/godot/composition/world_demo.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")

func _ready() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_size = int(arg.substr(4))
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
		elif arg.begins_with("--mode="): _mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--seed="): _seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--audio="):
			if arg.trim_prefix("--audio=") not in ["on","off"]:
				push_error("Audio must be on/off")
				get_tree().quit(1)
				return
			_audio = arg == "--audio=on"
		elif arg.begins_with("--out="): _output = arg.trim_prefix("--out=")
		elif arg == "--map-cache=off": _map_cache = false
		elif arg.begins_with("--measure-seconds="): _measure_seconds = float(arg.trim_prefix("--measure-seconds="))
		elif arg == "--camera-route": _camera_route = true
	if _size < 1 or _frames <= 61 or _mode not in ["battle", "campaign"]:
		push_error("Invalid diagnostic parameters (positive population, >61 frames, battle/campaign mode)")
		get_tree().quit(1)
		return
	if _mode == "campaign":
		Options.seed_value = _seed
		Options.continue_game = false
		_world = World.instantiate()
		_world.cache_static_artwork = _map_cache
		add_child(_world)
		return
	var c := Catalog.new()
	var g := GearCatalog.new()
	var p := PerkCatalog.new()
	var k := CompanionCatalog.new()
	if not ContentLoader.populate(c) or not ContentLoader.populate(g) or not ContentLoader.populate(p) or not ContentLoader.populate(k):
		push_error("Benchmark content failed to load")
		get_tree().quit(1)
		return
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.seed = _seed
	setup.companion_profiles.clear()
	setup.player_unit_cap = _size
	setup.enemy_unit_cap = _size
	var infantry := _size / 2
	var archers := _size / 3
	var cavalry := _size - infantry - archers
	setup.player_army.assign([{"type": "n1", "n": infantry}, {"type": "n2a", "n": archers}, {"type": "n2s", "n": cavalry}])
	setup.enemy_army.assign([{"type": "e1", "n": infantry}, {"type": "e2a", "n": archers}, {"type": "e2s", "n": cavalry}])
	var solver := Contacts.create()
	if not solver.is_valid():
		push_error("Native backend unavailable")
		get_tree().quit(1)
		return
	var session = Factory.create(setup, c, g, p, k, solver)
	if session == null:
		push_error("Cannot create diagnostic battle")
		get_tree().quit(1)
		return
	_session = session
	var actual := [0, 0]
	for unit in session._state.units:
		if not unit.hero and not unit.companion:
			actual[unit.side] += 1
			if unit.weight != 1:
				push_error("Weighted soldiers are not a population benchmark")
				get_tree().quit(1)
				return
	if actual != [_size, _size]:
		push_error("Population mismatch: %s" % str(actual))
		get_tree().quit(1)
		return
	print("ordinary_active=%s; special=%d" % [str(actual), session._state.units.size() - 2 * _size])
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	_view = BattleView.instantiate()
	_view.configure(session, _audio, _audio, true, setup.seed, setup.biome)
	add_child(_view)

func _process(_delta: float) -> void:
	if _world != null and not _world._ready_to_play: return
	if _world != null and _world.map_view._static_cache != null and not _world.map_view._static_cache.ready_to_show: return
	if _world == null and _view == null: return
	var now := Time.get_ticks_usec()
	if _world != null and _camera_route:
		_world.camera.detached = true
		var elapsed := float(now - _measure_start) / 1000000.0 if _measure_start > 0 else 0.0
		_world.camera.position = Vector2(2600 + sin(elapsed * 0.2) * 1600, 1700 + sin(elapsed * 0.13) * 1100)
		_world.camera.zoom = Vector2.ONE * [0.25, 0.9, 2.5][int(elapsed / 10.0) % 3]
	if _last > 0 and _n >= 60:
		_times.append(now - _last)
		_draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_render_cpu.append(roundi(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) * 1000.0))
		_render_gpu.append(roundi(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) * 1000.0))
	_last = now
	_n += 1
	if _n == 60: _measure_start = now
	if _n >= 60 and _n % 120 == 0: _memory_samples.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	if _n == 60 and _view != null: _tick_start = _view._clock.ticks
	if (_measure_seconds > 0.0 and _measure_start > 0 and now - _measure_start >= _measure_seconds * 1000000.0) or (_measure_seconds <= 0.0 and _n >= _frames): _finish()

func _finish() -> void:
	set_process(false)
	var report := {"mode":_mode,"debug":OS.is_debug_build(),"engine":Engine.get_version_info().string,
		"seed":_seed,"display":DisplayServer.get_name(),"viewport":str(get_viewport().get_visible_rect().size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"cpu":OS.get_processor_name(),
		"warmup_frames":60,"frame":Stats.stats(_times),"diagnostics_only":true,
		"draw_calls_mean":_draw_calls / maxi(1, _times.size()),"render_cpu":Stats.stats(_render_cpu),
		"render_gpu":Stats.stats(_render_gpu),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
	report.merge({"measurement_seconds":float(Time.get_ticks_usec() - _measure_start) / 1000000.0,
		"camera_route":_camera_route,"video_memory_samples":_memory_samples})
	if _view != null:
		report.merge({"ordinary_initial":[_size,_size],"special_initial":1,
			"sound":_view._effects_enabled,"music":_view._music_enabled,
			"simulation_ticks_measured":_view._clock.ticks - _tick_start,
			"simulation_ticks_total":_view._clock.ticks,"backlog_seconds":_view._clock.accumulator,
			"dropped_seconds":_view._clock.dropped_seconds,"live":_session.snapshot(true).counts,
			"native_steps":_session._state.native_contact_steps,"native_failures":_session._state.native_contact_failures})
	else:
		report.merge({"world_clock_paused":_world.state.clock.paused,"world_clock_speed":_world.state.clock.speed,
			"parties":_world.state.roster.parties.size(),"map_cache":_map_cache,
			"map_cache_active":_world.map_view._static_cache != null,
			"world_day":_world.state.clock.day,"world_hour":_world.state.clock.hour})
	print(JSON.stringify(report))
	if not _output.is_empty():
		var file := FileAccess.open(_output,FileAccess.WRITE)
		if file == null:
			push_error("Cannot write diagnostic report")
			get_tree().quit(1)
			return
		file.store_string(JSON.stringify(report) + "\n")
	for child in get_children(): child.queue_free()
	_view = null
	_world = null
	_session = null
	await get_tree().process_frame
	get_tree().quit(0)
