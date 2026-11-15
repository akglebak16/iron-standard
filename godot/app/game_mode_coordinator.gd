extends Node
## Composition/lifecycle only. Each mode requests transitions through signals.
const Menu = preload("res://app/main_menu.tscn")
const Campaign = preload("res://app/world_demo.tscn")
var _mode: Node
var _transition_pending := false

func _ready() -> void:
	if "--cpu-benchmark" in OS.get_cmdline_user_args():
		load("res://tests/performance/battle_benchmark.gd").new().run(get_tree())
		return
	if "--release-smoke" in OS.get_cmdline_user_args():
		add_child(load("res://tools/release_smoke.gd").new())
		return
	_show_menu()

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
	_replace(menu)

func _show_campaign() -> void:
	var campaign := Campaign.instantiate()
	campaign.title_requested.connect(_request_menu)
	_replace(campaign)

func _request_campaign() -> void:
	if _transition_pending: return
	_transition_pending = true
	_show_campaign.call_deferred()

func _request_menu() -> void:
	if _transition_pending: return
	_transition_pending = true
	_show_menu.call_deferred()
