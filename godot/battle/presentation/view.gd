extends Node2D
## Input/rendering adapter. Simulation is injected before entering the tree.
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
const Demo = preload("res://battle/presentation/demo_config.gd")
const Session = preload("res://battle/application/session.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const ProjectileView = preload("res://battle/presentation/projectile_view.gd")
const CombatFeedback = preload("res://battle/presentation/combat_feedback.gd")
const ImpactEffects = preload("res://battle/presentation/impact_effects.gd")
const UnitView = preload("res://battle/presentation/unit_view.gd")
const CompanionDialogue = preload("res://battle/presentation/companion_dialogue.gd")
const CombatAudio = preload("res://battle/presentation/audio/combat_audio.gd")
const BattleMusic = preload("res://battle/presentation/audio/battle_music.gd")
const TerrainView = preload("res://battle/presentation/terrain/terrain_view.gd")
const VegetationView = preload("res://battle/presentation/terrain/vegetation_view.gd")
const OrderMarker = preload("res://battle/presentation/hud/order_marker.gd")
const NavigationHud = preload("res://battle/presentation/hud/navigation_hud.gd")
const BattleCamera = preload("res://battle/presentation/battle_camera.gd")
const BattleControls = preload("res://battle/presentation/hud/battle_controls.gd")
const SiegeDefenseView = preload("res://battle/presentation/siege_defense_view.gd")
const GroundBake = preload("res://battle/presentation/ground_bake.gd")
const STONE_SHAKE_DISTANCE := 170.0
const STONE_SHAKE_SECONDS := 0.22
const PLAYBACK_SPEEDS := [1.0, 2.0, 0.5]
const BUTTON_ORDER_AHEAD := 60.0

signal battle_finished
signal audio_preferences_changed(effects: bool, music: bool)
signal blood_preference_changed(enabled: bool)

@onready var camera: BattleCamera = $Camera
@onready var status: Label = $Hud/Status
@onready var _navigation: NavigationHud = $Hud/Navigation
@onready var _controls: BattleControls = $Hud/Controls
var _session: Session
var _frame: Dictionary = {}
var _selection := Config.ALL_GROUPS
var _feedback := CombatFeedback.new()
var _impacts := ImpactEffects.new()
var _figures := UnitView.new()
var _bake := GroundBake.new()
var _dialogue := CompanionDialogue.new()
var _audio: CombatAudio
var _music: BattleMusic
var _effects_enabled := true
var _music_enabled := true
var _result_summary := ""
var _terrain := TerrainView.new()
var _vegetation := VegetationView.new()
var _order_marker := OrderMarker.new()
var _paused := false
var _speed_index := 0
var _attack_pressed := false
var attract_mode := false
var _journal_label: Label

func configure(session: Session, effects_enabled: bool = true, music_enabled: bool = true, blood_enabled: bool = true,
		terrain_seed: int = 0, biome: String = Config.DEFAULT_BIOME) -> void:
	assert(not is_inside_tree(), "Configure battle before adding it to the tree")
	_session = session
	_dialogue.configure(session.companion_dialogue())
	_effects_enabled = effects_enabled
	_music_enabled = music_enabled
	_impacts.blood_enabled = blood_enabled
	var frame := session.snapshot()
	_terrain.configure(frame.arena_size, frame.walls, terrain_seed, biome)
	_vegetation.configure(session.vegetation_layout(), biome, terrain_seed)
	add_child(_terrain)
	if DisplayServer.get_name() != "headless":
		_bake.configure(frame.arena_size)
		add_child(_bake)
		_impacts.on_mark = func(mark: Dictionary): _bake.paint(func(canvas): ImpactEffects.draw_mark(canvas, mark))
		_figures.on_settled = func(unit: Dictionary, headless: bool): _bake.paint(func(canvas): _figures.draw_corpse(canvas, unit, headless))

func get_battle_snapshot() -> Dictionary:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_post_step(_task_dt, _task_events, 0.0, _task_frame)
		_task = -1
	return _session.snapshot() if _session != null else {}

func show_result_summary(summary: String) -> void:
	_result_summary = summary
	_update_status()

func _ready() -> void:
	if _session == null:
		push_error("Battle view requires a session")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	status.hide()
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(8, 8)
	log_panel.custom_minimum_size.x = 310
	log_panel.add_theme_stylebox_override("panel", preload("res://ui/game_theme.gd").box("parchment", 10))
	$Hud.add_child(log_panel)
	_journal_label = Label.new()
	_journal_label.custom_minimum_size.x = 290
	_journal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal_label.add_theme_color_override("font_color", Color("#2a1d10"))
	_journal_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	log_panel.add_child(_journal_label)
	var initial := _session.snapshot()
	camera.configure(initial.arena_size, initial.hero_position)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_navigation.configure(_terrain.material)
	_controls.group_selected.connect(_select_group)
	_controls.order_selected.connect(_issue_hud_order)
	_controls.weapon_selected.connect(_select_weapon)
	_controls.pause_pressed.connect(_toggle_pause)
	_controls.speed_pressed.connect(_cycle_speed)
	_controls.retreat_pressed.connect(_request_retreat)
	_audio = CombatAudio.new()
	_audio.enabled = _effects_enabled
	add_child(_audio)
	_music = BattleMusic.new()
	_music.enabled = _music_enabled
	add_child(_music)
	_refresh(0.0, [])
	set_physics_process(false)
	# Headless runs (tests, tools) stay single-threaded so scripts may touch the session between frames.
	threaded = OS.get_processor_count() > 1 and OS.get_name() != "Web" and DisplayServer.get_name() != "headless"

## Live battles step once per rendered frame with dt capped like the browser (battleUpdate: min(dt, 1/30)), so a heavy
## fight slows down instead of piling up catch-up ticks. Where threads are available the step runs on a worker
## while the previous frame is drawn. Tests turn frame_driven off and call _physics_process themselves.
const MAX_FRAME_STEP := 1.0 / 30.0
var frame_driven := true
var threaded := false
var _task := -1
var _task_dt := 0.0
var _task_events: Array[Dictionary] = []
var _task_frame: Dictionary = {}
var _pending: Array[Callable] = []

func _process(real_dt: float) -> void:
	if not frame_driven or _session == null:
		return
	if _task >= 0:
		_finish_task(real_dt)
	var simulation_dt := _pre_step(minf(real_dt, MAX_FRAME_STEP), real_dt)
	if simulation_dt <= 0.0:
		return
	if threaded:
		_task_dt = simulation_dt
		_task = WorkerThreadPool.add_task(_worker_step, true, "battle step")
	else:
		_session.advance(simulation_dt)
		_post_step(simulation_dt, _session.take_events(), real_dt)

func _physics_process(dt: float) -> void:
	_finish_pending_step()
	var simulation_dt := _pre_step(dt, dt)
	if simulation_dt > 0.0:
		_session.advance(simulation_dt)
		_post_step(simulation_dt, _session.take_events(), dt)

func _worker_step() -> void:
	_session.advance(_task_dt)
	_task_events = _session.take_events()
	_task_frame = _session.snapshot()

func _finish_task(real_dt: float) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_post_step(_task_dt, _task_events, real_dt, _task_frame)
	_task_events = []
	_task_frame = {}

## Session calls from input handlers wait until the worker is done with the session.
func _to_session(call: Callable) -> void:
	if _task >= 0:
		_pending.append(call)
	else:
		call.call()

## Rare player actions with an immediate answer just wait for the running step.
func _finish_pending_step() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_post_step(_task_dt, _task_events, 0.0, _task_frame)
		_task = -1

func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

## Effects of a finished battle, music, pause and hero input. Returns the simulation step to run, or 0.
func _pre_step(dt: float, real_dt: float) -> float:
	for call in _pending:
		call.call()
	_pending.clear()
	if _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		if _feedback.has_effects() or _impacts.has_particles() or _figures.has_falling_units() or _dialogue.has_bubbles() or _order_marker.is_visible() or camera.is_shaking():
			_feedback.advance(dt, [])
			_impacts.advance(dt, [])
			_figures.advance(dt, [])
			_dialogue.age(dt)
			_order_marker.advance(dt, [])
			if camera.is_shaking():
				camera.advance_shake(dt, [])
				_navigation.queue_redraw()
			queue_redraw()
		return 0.0
	_music.advance(real_dt)
	if _paused:
		return 0.0
	var simulation_dt: float = dt * PLAYBACK_SPEEDS[_speed_index]
	if _frame.outcome == Session.Outcome.RUNNING and not attract_mode:
		var input := HeroInput.new()
		input.move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		input.face = (_pointer_world_position() - Vector2(_frame.hero_position)).angle()
		input.sprint = Input.is_key_pressed(KEY_SHIFT)
		input.block = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		input.attack = _attack_pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		input.swap = Input.is_key_pressed(KEY_X)
		_session.set_hero_input(input)
	return simulation_dt

func _post_step(simulation_dt: float, events: Array[Dictionary], real_dt: float, frame: Dictionary = {}) -> void:
	_feedback.advance(simulation_dt, events)
	_feedback.add_fatal_impacts(_impacts.advance(simulation_dt, events))
	_figures.advance(simulation_dt, events)
	_order_marker.advance(simulation_dt, events)
	_refresh(simulation_dt, events, real_dt, frame)
	for event in events:
		if event.kind == Event.Kind.STONE_LANDED and not _frame.hero_down and Vector2(_frame.hero_position).distance_to(event.position) < STONE_SHAKE_DISTANCE:
			camera.shake(STONE_SHAKE_SECONDS)
	_audio.advance(real_dt, events, camera.position)
	if _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		battle_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _session == null:
		return
	if event is InputEventMouseButton:
		_handle_battle_mouse(event)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_M:
			_set_audio_preferences(not _effects_enabled, _music_enabled)
		KEY_N:
			_set_audio_preferences(_effects_enabled, not _music_enabled)
		KEY_G:
			_impacts.blood_enabled = not _impacts.blood_enabled
			_rebake()
			blood_preference_changed.emit(_impacts.blood_enabled)
			_update_status()
			queue_redraw()
		KEY_1: _select_group(Config.GROUP_INFANTRY)
		KEY_2: _select_group(Config.GROUP_ARCHERS)
		KEY_3: _select_group(Config.GROUP_CAVALRY)
		KEY_4: _select_group(Config.ALL_GROUPS)
		KEY_Q: _to_session(_session.issue_order.bind(Config.ORDER_HOLD, _pointer_world_position(), _selection))
		KEY_E: _to_session(_session.issue_order.bind(Config.ORDER_FOLLOW, _frame.hero_position, _selection))
		KEY_R: _to_session(_session.issue_order.bind(Config.ORDER_CHARGE, _frame.hero_position, _selection))
		KEY_F: _to_session(_session.issue_order.bind(Config.ORDER_RETREAT, _frame.hero_position, _selection))
		KEY_P: _toggle_pause()
		KEY_T: _cycle_speed()

func _input(event: InputEvent) -> void:
	# A press consumed by a Control must not become a held battlefield attack.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_attack_pressed = false

func _handle_battle_mouse(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_attack_pressed = true
	elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		camera.change_zoom(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		_navigation.queue_redraw()
		queue_redraw()

func _pointer_world_position() -> Vector2:
	return camera.screen_to_world(get_viewport().get_mouse_position())

func _on_viewport_resized() -> void:
	camera.fit_viewport()
	_navigation.queue_redraw()
	queue_redraw()

func _select_group(group: int) -> void:
	_selection = group
	_update_status()
	queue_redraw()

func _issue_hud_order(order: String) -> void:
	var origin: Vector2 = _frame.hero_position
	var enemy: Vector2 = _frame.enemy_center
	var direction := origin.direction_to(enemy) if enemy.is_finite() and enemy != origin else Vector2.RIGHT
	_to_session(_session.issue_order.bind(order, origin + direction * BUTTON_ORDER_AHEAD, _selection))

func _select_weapon(slot: String) -> void:
	_finish_pending_step()
	_session.request_weapon_slot(slot)
	_update_status()

func _toggle_pause() -> void:
	if _frame.outcome not in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		_paused = not _paused
		_update_status()

func _cycle_speed() -> void:
	if _frame.outcome not in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		_speed_index = (_speed_index + 1) % PLAYBACK_SPEEDS.size()
		_update_status()

func _request_retreat() -> void:
	_finish_pending_step()
	if _session.request_retreat():
		_paused = false
		_update_status()

## Blood toggled: repaint the bake from what is still kept (marks without blood, settled corpses).
func _rebake() -> void:
	if not _impacts.on_mark.is_valid():
		return
	_bake.clear()
	for mark in _impacts.marks():
		_bake.paint(func(canvas): ImpactEffects.draw_mark(canvas, mark))
	for corpse in _figures.baked_corpses():
		_bake.paint(func(canvas): _figures.draw_corpse(canvas, corpse[0], corpse[1]))

func _set_audio_preferences(effects: bool, music: bool) -> void:
	_effects_enabled = effects
	_music_enabled = music
	_audio.enabled = effects
	_music.enabled = music
	_update_status()
	audio_preferences_changed.emit(effects, music)

func _refresh(dt: float, events: Array[Dictionary], real_dt: float = -1.0, frame: Dictionary = {}) -> void:
	# One detached read per simulation step, reused by HUD and drawing (taken on the worker when threaded).
	_frame = frame if not frame.is_empty() else _session.snapshot()
	camera.advance(dt if real_dt < 0.0 else real_dt, _frame.camera_target, _frame.hero_down, get_viewport().get_mouse_position(), events)
	if attract_mode:
		camera.position = Vector2(_frame.arena_size) * 0.5
	_navigation.update_frame(_frame, dt)
	var finished: bool = _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]
	_feedback.add_dialogue(_dialogue.advance(dt, _frame.units, events, not _frame.walls.is_empty(), finished))
	_update_status()
	queue_redraw()

func _update_status() -> void:
	var label: String = Demo.IN_PROGRESS
	match _frame.outcome:
		Session.Outcome.HERO_DOWN: label = Demo.HERO_DOWN
		Session.Outcome.VICTORY: label = Demo.VICTORY
		Session.Outcome.DEFEAT: label = Demo.DEFEAT
	var finished: bool = _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]
	_controls.update_frame(_frame, _selection, _paused, PLAYBACK_SPEEDS[_speed_index], finished)
	status.text = Demo.HUD_TEXT % [label, _frame.ally_strength, _frame.enemy_strength, roundi(_frame.stamina), Demo.GROUP_NAMES[_selection], BattleControls.format_time(_frame.elapsed_seconds)]
	var reserve: Array = _frame.get("reserve", [0, 0])
	if reserve[0] > 0 or reserve[1] > 0:
		status.text += Demo.RESERVE_HUD_TEXT % [reserve[0], reserve[1]]
	if not _frame.hero_down and not _frame.hero_weapon_name.is_empty():
		status.text += Demo.WEAPON_HUD_TEXT % _frame.hero_weapon_name
	status.text += Demo.CONTROL_HINT
	status.text += Demo.SOUND_HINT % [Demo.SOUND_ON if _effects_enabled else Demo.SOUND_OFF, Demo.SOUND_ON if _music_enabled else Demo.SOUND_OFF]
	status.text += Demo.BLOOD_HINT % (Demo.SOUND_ON if _impacts.blood_enabled else Demo.SOUND_OFF)
	var journal := _feedback.journal()
	if not journal.is_empty():
		status.text += "\n" + journal
	status.text += _result_summary
	if _journal_label != null:
		_journal_label.text = (journal if not journal.is_empty() else "Бой начался.\nWASD · мышь · Q / E / R / F") + _result_summary

func _draw() -> void:
	if _frame.is_empty():
		return
	var visible := (get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(UnitView.VIEW_MARGIN)
	_impacts.draw_ground(self, visible)
	_order_marker.draw(self)
	SiegeDefenseView.draw_under(self, _frame.get("wall_defense", {}), _frame.elapsed_seconds)
	if attract_mode:
		var demo_units: Array[Dictionary] = []
		for unit in _frame.units:
			if not unit.hero and not unit.companion: demo_units.append(unit)
		_figures.draw(self, demo_units, visible, _impacts.headless_units(), _vegetation.entries, _selection)
	else:
		_figures.draw(self, _frame.units, visible, _impacts.headless_units(), _vegetation.entries, _selection)
	SiegeDefenseView.draw_over(self, _frame.get("wall_defense", {}))
	for shot in _frame.shots:
		ProjectileView.draw(self, shot)
	_impacts.draw_particles(self)
	_feedback.draw(self)
	if not attract_mode: _dialogue.draw(self)
