extends SceneTree
## One screenshot of the world demo: godot --path godot --script res://tools/world_shot.gd -- --out=/tmp/w.png [--frames=60] [--seed=N] [--focus=x,y,zoom]
var _frames := 90
var _out := "user://world.png"
var _n := 0
var _meet := ""  # dialog | fight | auto: stage a bandit meeting before the shot
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--meet="):
			_meet = arg.substr(7)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	root.add_child((load("res://app/world_demo.tscn") as PackedScene).instantiate())
func _process(_d: float) -> bool:
	_n += 1
	if _meet.begins_with("ui_") and _n == 30:
		var d = root.get_child(root.get_child_count() - 1)
		match _meet:
			"ui_town":
				d._town.open_for(d.state, d.state.settlement_near(d.state.player.x, d.state.player.y, 80.0))
			"ui_market":
				d._town.open_for(d.state, d.state.settlement_near(d.state.player.x, d.state.player.y, 80.0))
				d._town.current_tab = "market"
				d._town.render()
			"ui_hero":
				d._party_window.open_for(d.state, "hero")
			"ui_troops":
				d._party_window.open_for(d.state, "troops")
	elif _meet != "" and not _meet.begins_with("ui_") and _n == 30:
		var demo = root.get_child(root.get_child_count() - 1)
		var st = demo.state
		var b = st.roster.make_party("bandit", "bandit", "Шайка", st.player.x + 4, st.player.y, [{"type": "b1", "n": 6}, {"type": "b2", "n": 2}])
		st.player.troops = [{"type": "e1", "n": 40}]
		demo._on_party_met(b, true)
		if _meet != "dialog":
			demo._on_encounter_choice(_meet)
	if _n >= _frames:
		root.get_texture().get_image().save_png(_out)
		quit()
		return true
	return false
