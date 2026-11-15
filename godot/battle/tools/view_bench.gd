extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Informational: frame cost of a mass battle with its view (simulation + snapshot + drawing).
##   godot --path godot --script res://battle/tools/view_bench.gd [-- --n=300 --frames=240]
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const Config = preload("res://battle/config.gd")
const BattleView = preload("res://apps/godot/presentation/battle/scene.tscn")
var _view: Node
var _n := 0
var _frames := 240
var _last := 0
var _times: Array[int] = []
var _size := 300

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_size = int(arg.substr(4))
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	if _size < 1 or _frames <= 60:
		push_error("Benchmark needs positive population and more than 60 frames")
		quit(1)
		return
	var c := Catalog.new()
	var g := GearCatalog.new()
	var p := PerkCatalog.new()
	var k := CompanionCatalog.new()
	if not ContentLoader.populate(c) or not ContentLoader.populate(g) or not ContentLoader.populate(p) or not ContentLoader.populate(k):
		push_error("Benchmark content failed to load")
		quit(1)
		return
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.player_unit_cap = _size
	setup.enemy_unit_cap = _size
	var infantry := _size / 2
	var archers := _size / 3
	var cavalry := _size - infantry - archers
	setup.player_army.assign([{"type": "n1", "n": infantry}, {"type": "n2a", "n": archers}, {"type": "n2s", "n": cavalry}])
	setup.enemy_army.assign([{"type": "e1", "n": infantry}, {"type": "e2a", "n": archers}, {"type": "e2s", "n": cavalry}])
	var session = Factory.create(setup, c, g, p, k)
	var actual := [0, 0]
	for unit in session._state.units:
		if not unit.hero and not unit.companion:
			actual[unit.side] += 1
			if unit.weight != 1:
				push_error("Weighted soldiers are not a population benchmark")
				quit(1)
				return
	if actual != [_size, _size]:
		push_error("Population mismatch: %s" % str(actual))
		quit(1)
		return
	print("ordinary_active=%s; special=%d" % [str(actual), session._state.units.size() - 2 * _size])
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	_view = BattleView.instantiate()
	_view.configure(session, false, false, true, setup.seed, setup.biome)
	root.add_child(_view)

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0 and _n > 60:
		_times.append(now - _last)
	_last = now
	_n += 1
	if _n >= _frames:
		_times.sort()
		var sum := 0
		for t in _times:
			sum += t
		print("frames %d, mean %.2f ms, median %.2f ms, p95 %.2f ms, alive %d" % [_times.size(), sum / 1000.0 / _times.size(), _times[_times.size() / 2] / 1000.0, _times[int(_times.size() * 0.95)] / 1000.0, _view.get_battle_snapshot().counts[0] + _view.get_battle_snapshot().counts[1]])
		print("simulation_ticks=%d; backlog_seconds=%.3f; dropped_seconds=%.3f; diagnostics_only=true; audio=false" % [_view._clock.ticks, _view._clock.accumulator, _view._clock.dropped_seconds])
		return true
	return false
