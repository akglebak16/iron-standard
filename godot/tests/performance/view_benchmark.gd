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
const Stats = preload("res://tests/performance/battle_benchmark.gd")
const World = preload("res://apps/godot/composition/world_demo.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")

func _ready() -> void:
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
	if _size < 1 or _frames <= 61 or _mode not in ["battle", "campaign"]:
		push_error("Invalid diagnostic parameters (positive population, >61 frames, battle/campaign mode)")
		get_tree().quit(1)
		return
	if _mode == "campaign":
		Options.seed_value = _seed
		Options.continue_game = false
		_world = World.instantiate()
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
	if _world == null and _view == null: return
	var now := Time.get_ticks_usec()
	if _last > 0 and _n >= 60: _times.append(now - _last)
	_last = now
	_n += 1
	if _n == 60 and _view != null: _tick_start = _view._clock.ticks
	if _n >= _frames: _finish()

func _finish() -> void:
	set_process(false)
	var report := {"mode":_mode,"debug":OS.is_debug_build(),"engine":Engine.get_version_info().string,
		"seed":_seed,"display":DisplayServer.get_name(),"viewport":str(get_viewport().get_visible_rect().size),
		"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"cpu":OS.get_processor_name(),
		"warmup_frames":60,"frame":Stats.stats(_times),"diagnostics_only":true}
	if _view != null:
		report.merge({"ordinary_initial":[_size,_size],"special_initial":1,
			"sound":_view._effects_enabled,"music":_view._music_enabled,
			"simulation_ticks_measured":_view._clock.ticks - _tick_start,
			"simulation_ticks_total":_view._clock.ticks,"backlog_seconds":_view._clock.accumulator,
			"dropped_seconds":_view._clock.dropped_seconds,"live":_session.snapshot(true).counts,
			"native_steps":_session._state.native_contact_steps,"native_failures":_session._state.native_contact_failures})
	else:
		report.merge({"world_clock_paused":_world.state.clock.paused,"world_clock_speed":_world.state.clock.speed,
			"parties":_world.state.roster.parties.size()})
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
