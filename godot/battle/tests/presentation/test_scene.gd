extends SceneTree
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")
const Combat = preload("res://battle/rules/combat.gd")
const Dialogue = preload("res://battle/presentation/companion_dialogue.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const PresentationPreferences = preload("res://app/presentation_preferences.gd")
const UnitMarkers = preload("res://battle/presentation/unit_markers.gd")
const TICK := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var packed: PackedScene = load("res://app/main.tscn")
	assert(packed != null)
	var scene = packed.instantiate()
	var path := "res://.godot/test-audio-%d.cfg" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute("res://.godot") == OK)
	scene.presentation_preferences = PresentationPreferences.new(path)
	assert(scene.presentation_preferences.save(true, true) == OK)
	root.add_child(scene)
	await process_frame
	var view = scene.get_node("Battle")
	_check_figure_cache(view._figures._art)
	var frame: Dictionary = view.get_battle_snapshot()
	var ground: ShaderMaterial = view._terrain.material
	assert(ground.get_shader_parameter("arena_size") == frame.arena_size)
	assert(view._navigation._ground.material != ground)
	assert(view._navigation._ground.material.get_shader_parameter("road") == ground.get_shader_parameter("road"))
	assert(view._navigation._frame.enemy_strength == frame.counts[1])
	var camera_probe := root.get_canvas_transform() * Vector2(frame.camera_target)
	assert(camera_probe.is_equal_approx(root.get_visible_rect().size * 0.5))
	assert(view._terrain.get_child_count() == 0)
	assert(view._vegetation.entries.size() == view._session.vegetation_layout().size())
	assert(not view._vegetation.entries.is_empty())
	assert(frame.units.size() == 55)
	assert(frame.counts == [29, 26])
	assert(frame.units.filter(func(unit): return unit.companion).size() == 3)
	assert(frame.outcome == Session.Outcome.RUNNING)
	assert(frame.units.any(func(unit): return unit.mounted and unit.look.has("horse")))
	assert(frame.units.any(func(unit): return unit.look.get("weapon") == "bow"))
	var original_look: Dictionary = frame.units[0].look.duplicate(true)
	frame.units[0].look.clear()
	assert(view.get_battle_snapshot().units[0].look == original_look)
	assert(view.get_node("Hud/Status").text.contains("Свои"))
	_check_unit_markers(view, frame)
	frame.units.clear()
	assert(view.get_battle_snapshot().units.size() == 55)
	await physics_frame
	await process_frame
	assert(view.get_battle_snapshot().tick > 0)
	assert(view._music._note_players.any(func(player): return player.playing))
	assert(view.get_node("Camera").position == view.get_battle_snapshot().hero_position)
	var session: Session = view._session
	var target = session._state.units.filter(func(unit): return unit.side == 1)[0]
	session._state.hurt(target, 1, session._hero)
	var injured: Dictionary = view.get_battle_snapshot().units[target.id]
	assert(is_equal_approx(injured.health_fraction, target.hp / target.max_hp))
	assert(UnitMarkers.health_bar(injured).has_area())
	session._state.launch_projectile(Combat.shoot(session._hero, target, session._rng))
	var launch: Dictionary = view.get_battle_snapshot().shots[0]
	assert(launch.progress == 0.0 and not launch.has("source"))
	launch.origin = Vector2.INF
	view._physics_process(TICK)
	assert(view._feedback._labels.size() == 1)
	assert(view._audio._last_played.has(preload("res://battle/presentation/audio/sound_bank.gd").Sound.BOW))
	var mute := InputEventKey.new()
	mute.keycode = KEY_M
	mute.pressed = true
	view._unhandled_input(mute)
	assert(not view._audio.enabled and view.status.text.contains("звук: выкл."))
	assert(view._music.enabled)
	mute.keycode = KEY_N
	view._unhandled_input(mute)
	assert(not view._music.enabled and view.status.text.contains("музыка: выкл."))
	mute.keycode = KEY_G
	view._unhandled_input(mute)
	assert(not view._impacts.blood_enabled and view.status.text.contains("кровь: выкл."))
	assert(scene.presentation_preferences.save(false, false) == OK)
	assert(not PresentationPreferences.new(path).read_blood())
	assert(PresentationPreferences.new(path).read() == {"effects": false, "music": false})
	var flight: Dictionary = view.get_battle_snapshot().shots[0]
	assert(flight.origin.is_finite() and flight.progress > 0.0 and flight.progress < 1.0)
	await process_frame
	for unit in session._state.units:
		if unit.side == 1:
			session._state.kill(unit, session._hero)
	view._physics_process(Config.MORALE_TICK_SECONDS)
	assert(view._figures.has_falling_units())
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + TICK)
	var text: String = view.get_node("Hud/Status").text
	assert(text.contains("Победа") and text.contains("Трофеи:"))
	assert(text.contains("Герой сразил:"))
	assert(text.contains("Ансельм +") and scene._demo_party.comps[0].xp > 0)
	assert(scene._demo_party.gold > 0 and scene._demo_party.hero.xp > 0)
	assert(scene._demo_world.parties.is_empty())
	view._physics_process(TICK)
	assert(view.get_node("Hud/Status").text == text)
	assert(not view._figures.has_falling_units())
	_check_defeat(packed, path)
	await _check_siege_dialogue(path)
	assert(DirAccess.remove_absolute(path) == OK)
	print("Scene tests passed")
	quit(0)

func _check_unit_markers(view, frame: Dictionary) -> void:
	var foot: Dictionary = frame.units.filter(func(unit): return unit.side == 0 and unit.group_kind == Config.GROUP_INFANTRY and not unit.hero and not unit.companion)[0]
	var archer: Dictionary = frame.units.filter(func(unit): return unit.side == 0 and unit.group_kind == Config.GROUP_ARCHERS and not unit.companion)[0]
	var companion: Dictionary = frame.units.filter(func(unit): return unit.companion)[0]
	var enemy: Dictionary = frame.units.filter(func(unit): return unit.side == 1)[0]
	assert(companion.companion_name == "Брат Ансельм")
	assert(not UnitMarkers.health_bar(foot).has_area())
	assert(UnitMarkers.ring_style(foot, view._selection) == UnitMarkers.ALLY_SELECTED_RING)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	view._unhandled_input(key)
	assert(view.status.text.contains("Выбрано: Стрелки"))
	assert(UnitMarkers.ring_style(foot, view._selection) == UnitMarkers.ALLY_IDLE_RING)
	assert(UnitMarkers.ring_style(archer, view._selection) == UnitMarkers.ALLY_SELECTED_RING)
	assert(UnitMarkers.ring_style(enemy, view._selection) == UnitMarkers.ENEMY_RING)
	assert(UnitMarkers.ring_style(companion, view._selection) == UnitMarkers.COMPANION_RING)
	key.keycode = KEY_4
	view._unhandled_input(key)
	assert(view.status.text.contains("Выбрано: Весь отряд"))

func _check_figure_cache(art) -> void:
	var unit := {"side": 0, "faction": "nord", "hero": false, "companion": false, "mounted": false, "look": {"weapon": "sword"}}
	var foot: Dictionary = art.layers(unit)
	assert(foot.body.get_image().get_used_rect().has_area())
	assert(foot.weapon.get_image().get_used_rect().has_area())
	assert(art.layers(unit).body == foot.body)
	unit.look.weapon = "bow"
	var archer: Dictionary = art.layers(unit)
	assert(archer.weapon.get_image().get_data() != foot.weapon.get_image().get_data())
	unit.mounted = true
	assert(art.layers(unit).body.get_image().get_data() != archer.body.get_image().get_data())

func _check_defeat(packed: PackedScene, path: String) -> void:
	var scene = packed.instantiate()
	scene.presentation_preferences = PresentationPreferences.new(path)
	scene.battle_setup = scene.battle_setup.duplicate(true)
	scene.battle_setup.player_army.clear()
	scene.battle_setup.companion_profiles.clear()
	root.add_child(scene)
	var view = scene.get_node("Battle")
	assert(not view._audio.enabled and not view._music.enabled)
	assert(not view._impacts.blood_enabled)
	view._music.advance(1.0)
	assert(view._music._note_players.is_empty())
	var session: Session = view._session
	session._state.kill(session._hero)
	view._physics_process(TICK)
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + TICK)
	assert(view.get_node("Hud/Status").text.contains("Герой очнулся у города Вентум"))
	assert(scene._demo_party.position == Vector2(110, 134) and scene._demo_party.gold == 80)
	assert(scene._demo_world.parties[0].state == "idle" and scene._demo_world.parties[0].cd == 10)

func _check_siege_dialogue(path: String) -> void:
	var scene = load("res://app/siege_demo.tscn").instantiate()
	scene.presentation_preferences = PresentationPreferences.new(path)
	root.add_child(scene)
	var view = scene.get_node("Battle")
	view.set_physics_process(false)
	var session: Session = view._session
	var rng_state: int = session._rng.state
	var frame := session.snapshot()
	assert(view._terrain.get_child_count() == 1)
	assert(view._terrain.get_child(0)._segments == frame.walls)
	assert(view._navigation._frame.walls == frame.walls)
	var events: Array[Dictionary] = []
	view._refresh(Dialogue.START_DELAY.y, events)
	var catalog := CompanionCatalog.new()
	assert(catalog.load_data())
	var definition := catalog.get_companion("vikenty")
	var status: String = view.status.text
	assert(definition.voice.siege.any(func(line): return status.contains(Dialogue.JOURNAL_LINE % [definition.name, line])))
	assert(view._dialogue.has_bubbles())
	assert(session._rng.state == rng_state and session.snapshot() == frame)
	await process_frame
	await process_frame
