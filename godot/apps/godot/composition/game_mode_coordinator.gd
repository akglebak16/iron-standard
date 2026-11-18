extends Node
## Composition/lifecycle only. Each mode requests transitions through signals.
const Menu = preload("res://apps/godot/composition/main_menu.tscn")
const Campaign = preload("res://apps/godot/composition/world_demo.tscn")
const FieldDemo = preload("res://apps/godot/composition/main.tscn")
const SiegeDemo = preload("res://apps/godot/composition/siege_demo.tscn")
const QuickSetup = preload("res://apps/godot/composition/quick_battle_setup.gd")
var _mode: Node
var _transition_pending := false
var _profile_campaign_start := false

var _last_quick := {}
func _ready() -> void:
	if "--overworld-trial" in OS.get_cmdline_user_args():
		add_child(load("res://apps/godot/presentation/overworld/overworld_trial.tscn").instantiate())
		return
	if "--overworld-benchmark" in OS.get_cmdline_user_args():
		add_child(load("res://tests/performance/overworld_trial_benchmark.gd").new())
		return
	if "--view-benchmark" in OS.get_cmdline_user_args():
		add_child(load("res://tests/performance/view_benchmark.gd").new())
		return
	if "--cpu-benchmark" in OS.get_cmdline_user_args():
		load("res://tests/performance/battle_benchmark.gd").new().run(get_tree())
		return
	if "--release-smoke" in OS.get_cmdline_user_args():
		add_child(load("res://tools/release_smoke.gd").new())
		return
	_show_menu()
	if "--campaign-start-benchmark" in OS.get_cmdline_user_args():
		_profile_campaign_start = true
		add_child(load("res://tests/performance/campaign_start_benchmark.gd").new())

func _replace(next: Node) -> void:
	if _mode != null:
		remove_child(_mode)
		_mode.queue_free()
	_mode = next
	add_child(next)
	_transition_pending = false

func _show_menu() -> void:
	var menu := Menu.instantiate()
	menu.campaign_requested.connect(_request_campaign)
	menu.demo_requested.connect(_request_demo)
	menu.quick_battle_requested.connect(_request_quick)
	_replace(menu)

func _show_campaign() -> void:
	var campaign := Campaign.instantiate()
	campaign.profile_startup = _profile_campaign_start
	campaign.title_requested.connect(_request_menu)
	campaign.campaign_requested.connect(_request_campaign)
	_replace(campaign)

func _request_campaign() -> void:
	if _transition_pending: return
	_transition_pending = true
	_show_campaign.call_deferred()

func _request_menu() -> void:
	if _transition_pending: return
	_transition_pending = true
	_show_menu.call_deferred()

func _request_demo(siege: bool) -> void:
	if _transition_pending: return
	_transition_pending = true
	_show_demo.call_deferred(siege)

func _request_quick(options: Dictionary) -> void:
	if _transition_pending: return
	_last_quick = options.duplicate()
	var setup := QuickSetup.build(options)
	if setup == null: return
	_transition_pending = true
	_show_demo.call_deferred(false, setup)

func _show_demo(siege: bool, setup: Resource = null) -> void:
	var demo := (SiegeDemo if siege else FieldDemo).instantiate()
	if setup != null: demo.battle_setup = setup
	demo.title_requested.connect(_request_menu)
	demo.again_requested.connect(func(): _request_quick(_last_quick) if setup != null else _request_demo(siege))
	_replace(demo)
