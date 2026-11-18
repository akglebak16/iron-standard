extends Node
const BattleWorker = preload("res://adapters/godot/battle_worker.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const NativeMovement = preload("res://adapters/godot/native/movement.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
## Informational: frame cost of a mass battle with its view (simulation + snapshot + drawing).
##   godot --path godot --script res://tools/battle/view_bench.gd [-- --n=300 --frames=240]
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const Config = preload("res://core/battle/config.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")
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
var _native_sprites := true
var _capture := ""
var _camera_scope := "hero"
var _terrain := "" # TERRAIN Р0б: a field template (data/terrain_templates.gd), empty is the open field.
var _actual_groups := [[], []]
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
var _trace: Array = []
var _detailed := false
var _gpu_timing := true
var _worker := true
var _profile_samples := {}
var _campaign_day := 1
var _campaign_speed := 1
var _campaign_ready := false
var _campaign_start := {}
var _campaign_hide := ""
var _campaign_paused := false
var _sim_thread := true  # the world steps on a worker thread, as in the game (--sim-thread=off: on the main thread)
var _campaign_step_us: Array[int] = []
var _campaign_main_us: Array[int] = []
var _campaign_hud_us: Array[int] = []
const Stats = preload("res://tests/performance/battle_benchmark.gd")
const World = preload("res://apps/godot/composition/world_demo.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")

func _ready() -> void:
	get_viewport().gui_disable_input = true
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
		elif arg.begins_with("--camera="): _camera_scope = arg.trim_prefix("--camera=")
		elif arg.begins_with("--terrain="): _terrain = arg.trim_prefix("--terrain=")
		elif arg == "--sprites=gdscript": _native_sprites = false
		elif arg.begins_with("--capture="): _capture = arg.trim_prefix("--capture=")
		elif arg.begins_with("--out="): _output = arg.trim_prefix("--out=")
		elif arg == "--map-cache=off": _map_cache = false
		elif arg.begins_with("--measure-seconds="): _measure_seconds = float(arg.trim_prefix("--measure-seconds="))
		elif arg == "--camera-route": _camera_route = true
		elif arg == "--profile-details": _detailed = true
		elif arg == "--gpu-timing=off": _gpu_timing = false
		elif arg == "--worker=off": _worker = false
		elif arg.begins_with("--campaign-day="): _campaign_day = int(arg.trim_prefix("--campaign-day="))
		elif arg.begins_with("--campaign-speed="): _campaign_speed = int(arg.trim_prefix("--campaign-speed="))
		elif arg.begins_with("--campaign-hide="): _campaign_hide = arg.trim_prefix("--campaign-hide=")
		elif arg == "--campaign-paused": _campaign_paused = true
		elif arg == "--sim-thread=off": _sim_thread = false
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _gpu_timing)
	if _size < 1 or _frames <= 61 or _mode not in ["battle", "campaign"] or _camera_scope not in ["hero", "near", "wide", "field"]:
		push_error("Invalid diagnostic parameters (positive population, >61 frames, battle/campaign mode)")
		get_tree().quit(1)
		return
	if _mode == "campaign":
		if _campaign_day < 1 or _campaign_day > 200 or _campaign_speed not in [1, 2, 4] or _campaign_hide not in ["", "settlements", "parties", "marks"]:
			push_error("Invalid campaign benchmark day, speed or layer")
			get_tree().quit(1)
			return
		Options.seed_value = _seed
		Options.continue_game = false
		_world = World.instantiate()
		_world.cache_static_artwork = _map_cache
		_world.profile_map_frames = true
		_world.sim_thread = _sim_thread
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
	setup.terrain = Templates.sample(_terrain)
	var infantry := _size / 2
	var archers := _size / 3
	var cavalry := _size - infantry - archers
	setup.player_army.assign([{"type": "n1", "n": infantry}, {"type": "n2a", "n": archers}, {"type": "n3c", "n": cavalry}])
	setup.enemy_army.assign([{"type": "e1", "n": infantry}, {"type": "e2a", "n": archers}, {"type": "e3c", "n": cavalry}])
	var solver := Contacts.create()
	if not solver.is_valid():
		push_error("Native backend unavailable")
		get_tree().quit(1)
		return
	var session = Factory.create(setup, c, g, p, k, solver, NativeMovement.create(), NativeColumns.create())
	if session == null:
		push_error("Cannot create diagnostic battle")
		get_tree().quit(1)
		return
	_session = session
	var actual := [0, 0]
	_actual_groups = [[0, 0, 0], [0, 0, 0]]
	for unit in session._state.units:
		if not unit.hero and not unit.companion:
			actual[unit.side] += 1
			_actual_groups[unit.side][unit.group_kind] += 1
			if unit.weight != 1:
				push_error("Weighted soldiers are not a population benchmark")
				get_tree().quit(1)
				return
	if _actual_groups[0][Config.GROUP_CAVALRY] != cavalry or _actual_groups[1][Config.GROUP_CAVALRY] != cavalry:
		push_error("Missing actual cavalry in mixed benchmark")
		get_tree().quit(1)
		return
	if actual != [_size, _size]:
		push_error("Population mismatch: %s" % str(actual))
		get_tree().quit(1)
		return
	print("ordinary_active=%s; special=%d" % [str(actual), session._state.units.size() - 2 * _size])
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	_view = BattleView.instantiate()
	_view.player_input_enabled = false
	_view.profile_frames = true
	_view._figures.native_enabled = _native_sprites
	_view.configure(session, _audio, _audio, true, setup.seed, setup.biome, BattleWorker.new(session) if _worker else null)
	_view._impacts._rng.seed = _seed
	_view._figures._visual_rng.seed = _seed
	_view._feedback.set_seed(_seed)
	add_child(_view)
	_view._music._rng.seed = _seed
	if _camera_scope != "hero":
		_view.camera.follow_enabled = false
		_view.camera.position = session._state.arena_size * 0.5
		_view.camera.zoom = Vector2.ONE * (0.55 if _camera_scope == "wide" else 1.35)
		if _camera_scope == "field": _view.camera.zoom = Vector2.ONE * _view.camera.min_zoom() # The whole field (TERRAIN Р0а).
		_view.camera.fit_viewport()

func _prepare_campaign() -> void:
	var state: RefCounted = _world.state
	var away: bool = state.player.away
	state.player.away = true
	while state.clock.day < _campaign_day:
		state.clock.advance(1.0, state.step, state.hour_tick)
	state.player.away = away
	state.waiting = true
	state.clock.paused = _campaign_paused
	state.clock.speed = _campaign_speed
	_campaign_start = {"day":state.clock.day,"hour":state.clock.hour,"parties":state.roster.parties.size(),
		"wars":state.wars.wars.size(),"undead_parties":state.roster.parties.filter(func(p): return p.fac == "undead").size()}
	if _campaign_hide == "settlements":
		_world.map_view._settlement_layer.hide()
	elif _campaign_hide == "marks":
		_world._marks.hide()
	elif _campaign_hide == "parties":
		for child in _world.map_view.get_children():
			if child.get_script() != null and child.get_script().resource_path.ends_with("/world_parties_layer.gd"):
				child.hide()
	_campaign_ready = true

func _process(_delta: float) -> void:
	if _world != null and not _world._ready_to_play: return
	if _world != null and _world.map_view._static_cache != null and not _world.map_view._static_cache.ready_to_show: return
	if _world == null and _view == null: return
	if _world != null and not _campaign_ready:
		_prepare_campaign()
	var now := Time.get_ticks_usec()
	if _world != null and _camera_route:
		_world.camera.detached = true
		var elapsed := float(now - _measure_start) / 1000000.0 if _measure_start > 0 else 0.0
		_world.camera.position = Vector2(2600 + sin(elapsed * 0.2) * 1600, 1700 + sin(elapsed * 0.13) * 1100)
		_world.camera.zoom = Vector2.ONE * [0.25, 0.9, 2.5][int(elapsed / 10.0) % 3]
	if _last > 0 and _n >= 60:
		_times.append(now - _last)
		if _world != null:
			if _world.map_steps > 0: _campaign_step_us.append(_world.map_step_us)
			_campaign_main_us.append(_world.map_main_us)
			_campaign_hud_us.append(_world.map_hud_us)
		if _view != null:
			_view.frame_profile.minimap_us = _view._navigation.last_draw_usec
			_view.frame_profile.bake_us = _view._bake.last_paint_us if _view._bake.last_paint_frame >= Engine.get_process_frames() - 1 else 0
			if _detailed: _trace.append([now - _measure_start, now - _last, _view.frame_profile.duplicate(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0])
			for phase in _view.frame_profile:
				if not _profile_samples.has(phase): _profile_samples[phase] = []
				_profile_samples[phase].append(_view.frame_profile[phase])
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
	if _view != null: _view._simulation.render_snapshot() # Join before diagnostics read session counters.
	var report := {"trace": _trace, "mode":_mode,"debug":OS.is_debug_build(),"engine":Engine.get_version_info().string,
		"gpu_timing": _gpu_timing, "worker": _worker, "visual_seed": _seed,
		"seed":_seed,"display":DisplayServer.get_name(),"viewport":str(get_viewport().get_visible_rect().size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"cpu":OS.get_processor_name(),
		"warmup_frames":60,"frame":Stats.stats(_times),"diagnostics_only":true,
		"draw_calls_mean":_draw_calls / maxi(1, _times.size()),"render_cpu":Stats.stats(_render_cpu),
		"render_gpu":Stats.stats(_render_gpu),"video_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)}
	if not _gpu_timing:
		report.render_gpu = null
		report.render_cpu = null
	report.merge({"native_movement_steps": _session._state.native_movement_steps if _session != null else 0,
		"native_movement_failures": _session._state.native_movement_failures if _session != null else 0,
		"measurement_seconds":float(Time.get_ticks_usec() - _measure_start) / 1000000.0,
		"native_sprites":_native_sprites,"camera_scope":_camera_scope,"terrain":_terrain,"camera_route":_camera_route,"video_memory_samples":_memory_samples})
	var phases := {}
	for phase in _profile_samples:
		var samples: Array[int] = []
		samples.assign(_profile_samples[phase])
		phases[phase] = Stats.stats(samples)
	report.phase_profile = phases
	if _view != null:
		report.merge({"ordinary_initial":[_size,_size],"actual_groups":_actual_groups,"special_initial":1,
			"sound":_view._effects_enabled,"music":_view._music_enabled,
			"simulation_ticks_measured":_view._clock.ticks - _tick_start,
			"simulation_ticks_total":_view._clock.ticks,"backlog_seconds":_view._clock.accumulator,
			"dropped_seconds":_view._clock.dropped_seconds,"live":_session.snapshot(true).counts,
			"native_steps":_session._state.native_contact_steps,"native_failures":_session._state.native_contact_failures})
	else:
		var sorted := _times.duplicate()
		sorted.sort()
		var tail_count := maxi(1, ceili(sorted.size() * 0.01))
		var tail_us := 0.0
		for i in range(sorted.size() - tail_count, sorted.size()):
			tail_us += sorted[i]
		report.merge({"world_clock_paused":_world.state.clock.paused,"world_clock_speed":_world.state.clock.speed,
			"campaign_start":_campaign_start,"hidden_layer":_campaign_hide,
			"world_main_thread":Stats.stats(_campaign_main_us) if not _campaign_main_us.is_empty() else {},
			"world_active_step_frames":Stats.stats(_campaign_step_us) if not _campaign_step_us.is_empty() else {},
			"world_hud":Stats.stats(_campaign_hud_us),
			"fps_mean":1000.0 / report.frame.mean_ms,"fps_1pct_low":1000000.0 * tail_count / maxf(1.0, tail_us),
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
	if not _capture.is_empty():
		var error := get_viewport().get_texture().get_image().save_png(_capture)
		if error != OK: push_error("Cannot capture benchmark frame")
	for child in get_children(): child.queue_free()
	_view = null
	_world = null
	_session = null
	await get_tree().process_frame
	get_tree().quit(0)
