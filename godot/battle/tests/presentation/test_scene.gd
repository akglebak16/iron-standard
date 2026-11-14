extends SceneTree
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")
const TICK := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var packed: PackedScene = load("res://app/main.tscn")
	assert(packed != null)
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var view = scene.get_node("Battle")
	var frame: Dictionary = view.get_battle_snapshot()
	assert(frame.units.size() == 55)
	assert(frame.counts == [29, 26])
	assert(frame.units.filter(func(unit): return unit.companion).size() == 3)
	assert(frame.outcome == Session.Outcome.RUNNING)
	assert(view.get_node("Hud/Status").text.contains("Свои"))
	frame.units.clear()
	assert(view.get_battle_snapshot().units.size() == 55)
	await physics_frame
	await process_frame
	assert(view.get_battle_snapshot().tick > 0)
	assert(view.get_node("Camera").position == view.get_battle_snapshot().hero_position)
	var session: Session = view._session
	for unit in session._state.units:
		if unit.side == 1:
			session._state.kill(unit)
	view._physics_process(Config.MORALE_TICK_SECONDS)
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + TICK)
	var text: String = view.get_node("Hud/Status").text
	assert(text.contains("Победа") and text.contains("Трофеи:"))
	assert(text.contains("Ансельм +") and scene._demo_party.comps[0].xp > 0)
	assert(scene._demo_party.gold > 0 and scene._demo_party.hero.xp > 0)
	view._physics_process(TICK)
	assert(view.get_node("Hud/Status").text == text)
	print("Scene tests passed")
	quit(0)
