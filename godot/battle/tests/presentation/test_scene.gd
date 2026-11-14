extends SceneTree
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")
const Combat = preload("res://battle/rules/combat.gd")
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
	var target = session._state.units.filter(func(unit): return unit.side == 1)[0]
	session._state.projectiles.append(Combat.shoot(session._hero, target, session._rng))
	var launch: Dictionary = view.get_battle_snapshot().shots[0]
	assert(launch.progress == 0.0 and not launch.has("source"))
	launch.origin = Vector2.INF
	view._physics_process(TICK)
	var flight: Dictionary = view.get_battle_snapshot().shots[0]
	assert(flight.origin.is_finite() and flight.progress > 0.0 and flight.progress < 1.0)
	await process_frame
	for unit in session._state.units:
		if unit.side == 1:
			session._state.kill(unit)
	view._physics_process(Config.MORALE_TICK_SECONDS)
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + TICK)
	var text: String = view.get_node("Hud/Status").text
	assert(text.contains("Победа") and text.contains("Трофеи:"))
	assert(text.contains("Ансельм +") and scene._demo_party.comps[0].xp > 0)
	assert(scene._demo_party.gold > 0 and scene._demo_party.hero.xp > 0)
	assert(scene._demo_world.parties.is_empty())
	view._physics_process(TICK)
	assert(view.get_node("Hud/Status").text == text)
	_check_defeat(packed)
	print("Scene tests passed")
	quit(0)

func _check_defeat(packed: PackedScene) -> void:
	var scene = packed.instantiate()
	scene.battle_setup = scene.battle_setup.duplicate(true)
	scene.battle_setup.player_army.clear()
	scene.battle_setup.companion_profiles.clear()
	root.add_child(scene)
	var view = scene.get_node("Battle")
	var session: Session = view._session
	session._state.kill(session._hero)
	view._physics_process(TICK)
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + TICK)
	assert(view.get_node("Hud/Status").text.contains("Герой очнулся у города Вентум"))
	assert(scene._demo_party.position == Vector2(110, 134) and scene._demo_party.gold == 80)
	assert(scene._demo_world.parties[0].state == "idle" and scene._demo_world.parties[0].cd == 10)
