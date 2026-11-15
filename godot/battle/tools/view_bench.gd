extends SceneTree
## Informational: frame cost of a mass battle with its view (simulation + snapshot + drawing).
##   godot --path godot --script res://battle/tools/view_bench.gd [-- --n=300 --frames=240]
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const Config = preload("res://battle/config.gd")
const BattleView = preload("res://battle/presentation/scene.tscn")
var _view: Node
var _n := 0
var _frames := 240
var _last := 0
var _times: Array[int] = []
var _size := 300
var _threads := -1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_size = int(arg.substr(4))
		elif arg.begins_with("--threads="):
			_threads = int(arg.substr(10))
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	var c := Catalog.new(); c.load_data()
	var g := GearCatalog.new(); g.load_data()
	var p := PerkCatalog.new(); p.load_data()
	var k := CompanionCatalog.new(); k.load_data()
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.player_army.assign([{"type": "n1", "n": _size / 2}, {"type": "n2a", "n": _size / 3}, {"type": "n2s", "n": _size / 6}])
	setup.enemy_army.assign([{"type": "e1", "n": _size / 2}, {"type": "e2a", "n": _size / 3}, {"type": "e2s", "n": _size / 6}])
	var session = Factory.create(setup, c, g, p, k)
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	_view = BattleView.instantiate()
	_view.configure(session, false, false, true, setup.seed, setup.biome)
	root.add_child(_view)

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	if _n == 1 and _threads >= 0:
		_view.threaded = _threads == 1
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
		return true
	return false
