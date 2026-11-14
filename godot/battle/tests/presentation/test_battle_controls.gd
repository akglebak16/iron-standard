extends SceneTree

const DemoScene = preload("res://app/main.tscn")
const Session = preload("res://battle/application/session.gd")
const Config = preload("res://battle/config.gd")
const BattleControls = preload("res://battle/presentation/hud/battle_controls.gd")
const STEP := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	root.size = Vector2i(960, 650)
	var scene := DemoScene.instantiate()
	root.add_child(scene)
	var view = scene.get_node("Battle")
	view.set_physics_process(false)
	view._audio.enabled = false
	view._music.enabled = false
	await process_frame
	await process_frame
	var controls: BattleControls = view._controls
	var session: Session = view._session
	_check_slots(view, controls, session)
	_check_orders(view, controls, session)
	_check_playback(view, controls)
	_check_retreat(view, controls, session)
	assert(BattleControls.format_time(60.99) == "1:00")
	scene.free()
	print("Battle controls tests passed")
	quit(0)

func _check_slots(view, controls: BattleControls, session: Session) -> void:
	var sword: Button = controls._slot_buttons[Session.WEAPON_SLOT_MELEE]
	var bow: Button = controls._slot_buttons[Session.WEAPON_SLOT_RANGED]
	assert(controls._health.value == session._hero.max_hp)
	assert(controls._stamina.value == Config.HERO_MAX_STAMINA)
	assert(sword.text == "Рыцарский меч" and sword.button_pressed)
	assert(bow.text == "Длинный лук" and not bow.button_pressed)
	session._hero.attack_windup = STEP * 2.0
	bow.pressed.emit()
	view._physics_process(STEP)
	assert(sword.button_pressed and not bow.button_pressed)
	session._hero.attack_windup = -1.0
	view._physics_process(STEP)
	assert(bow.button_pressed and not sword.button_pressed)
	assert(view.status.text.contains(bow.text))
	assert(not session.request_weapon_slot(Session.WEAPON_SLOT_RANGED))
	_click_weapon_button(view, sword)
	assert(sword.button_pressed and session._hero.attack_windup < 0.0)

func _click_weapon_button(view, button: Button) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.pressed = pressed
		Input.parse_input_event(click)
		Input.flush_buffered_events()
		view._physics_process(STEP)

func _check_orders(view, controls: BattleControls, session: Session) -> void:
	controls._group_buttons[Config.GROUP_ARCHERS].pressed.emit()
	assert(view._selection == Config.GROUP_ARCHERS)
	assert(controls._group_buttons[Config.GROUP_ARCHERS].text == "Стрелки 6")
	var frame := session.snapshot()
	controls._order_buttons[0].pressed.emit()
	view._physics_process(STEP)
	assert(view._order_marker.is_visible())
	var expected: Vector2 = Vector2(frame.hero_position) + Vector2(frame.hero_position).direction_to(frame.enemy_center) * view.BUTTON_ORDER_AHEAD
	assert(view._order_marker._point.is_equal_approx(expected))
	controls._order_buttons[3].pressed.emit()
	view._physics_process(STEP)
	assert(not session.snapshot().decided)
	assert(session._state.groups[0][Config.GROUP_ARCHERS].backing)

func _check_playback(view, controls: BattleControls) -> void:
	controls._pause.pressed.emit()
	var paused: Dictionary = view.get_battle_snapshot()
	view._physics_process(STEP)
	assert(view._paused and view.get_battle_snapshot() == paused)
	controls._speed.pressed.emit()
	view._physics_process(STEP)
	assert(view.get_battle_snapshot() == paused)
	controls._pause.pressed.emit()
	view._physics_process(STEP)
	var fast: Dictionary = view.get_battle_snapshot()
	assert(is_equal_approx(fast.elapsed_seconds - paused.elapsed_seconds, STEP * 2.0))
	controls._speed.pressed.emit()
	view._physics_process(STEP)
	assert(is_equal_approx(view.get_battle_snapshot().elapsed_seconds - fast.elapsed_seconds, STEP * 0.5))
	controls._speed.pressed.emit()

func _check_retreat(view, controls: BattleControls, session: Session) -> void:
	controls._pause.pressed.emit()
	controls._retreat.pressed.emit()
	assert(not view._paused)
	view._physics_process(STEP)
	assert(session.snapshot().decided and controls._retreat.disabled)
	assert(view.status.text.contains("Отряд отступает!"))
	assert(session.result().is_empty() and not session.request_retreat())
	view._physics_process(Config.BATTLE_END_DELAY_SECONDS + STEP)
	assert(session.snapshot().outcome == Session.Outcome.DEFEAT)
	assert(not session.result().win and not session.result().heroDown)
	assert(controls._pause.disabled and controls._speed.disabled)
