extends Node2D
## Input/rendering adapter. Simulation is injected before entering the tree.
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
const Demo = preload("res://apps/godot/presentation/battle/demo_config.gd")
const Session = preload("res://battle/application/session.gd")
const Simulation = preload("res://core/battle/api/battle_simulation.gd")
const FixedClock = preload("res://runtime/scheduling/fixed_step_clock.gd")
const ProjectileView = preload("res://apps/godot/presentation/battle/projectile_view.gd")
const CombatFeedback = preload("res://apps/godot/presentation/battle/combat_feedback.gd")
const ImpactEffects = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const UnitView = preload("res://apps/godot/presentation/battle/unit_view.gd")
const CompanionDialogue = preload("res://apps/godot/presentation/battle/companion_dialogue.gd")
const CombatAudio = preload("res://apps/godot/presentation/battle/audio/combat_audio.gd")
const BattleMusic = preload("res://apps/godot/presentation/battle/audio/battle_music.gd")
const TerrainView = preload("res://apps/godot/presentation/battle/terrain/terrain_view.gd")
const VegetationView = preload("res://apps/godot/presentation/battle/terrain/vegetation_view.gd")
const OrderMarker = preload("res://apps/godot/presentation/battle/hud/order_marker.gd")
const NavigationHud = preload("res://apps/godot/presentation/battle/hud/navigation_hud.gd")
const BattleCamera = preload("res://apps/godot/presentation/battle/battle_camera.gd")
const BattleControls = preload("res://apps/godot/presentation/battle/hud/battle_controls.gd")
const SiegeDefenseView = preload("res://apps/godot/presentation/battle/siege_defense_view.gd")
const GroundBake = preload("res://apps/godot/presentation/battle/ground_bake.gd")
const STONE_SHAKE_DISTANCE := 170.0
const STONE_SHAKE_SECONDS := 0.22
const PLAYBACK_SPEEDS := [1.0, 2.0, 0.5]
const BUTTON_ORDER_AHEAD := 60.0

signal battle_finished
signal menu_requested
signal audio_preferences_changed(effects: bool, music: bool)
signal blood_preference_changed(enabled: bool)

@onready var camera: BattleCamera = $Camera
@onready var status: Label = $Hud/Status
@onready var _navigation: NavigationHud = $Hud/Navigation
@onready var _controls: BattleControls = $Hud/Controls
var _session: Session
var _simulation: Simulation
var _clock := FixedClock.new()
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
var _figure_identity_count := -1
var _figure_seed := 0
var _journal_label: Label
var _journal_panel: Panel
var _hud_orders: Dictionary = {}
var _menu_open := false
var _paused_before_menu := false

func configure(session: Session, effects_enabled: bool = true, music_enabled: bool = true, blood_enabled: bool = true,
		terrain_seed: int = 0, biome: String = Config.DEFAULT_BIOME) -> void:
	assert(not is_inside_tree(), "Configure battle before adding it to the tree")
	_session = session
	_figure_seed = terrain_seed
	_figures.biome = biome
	_simulation = Simulation.new(session)
	_dialogue.configure(session.companion_dialogue())
	_effects_enabled = effects_enabled
	_music_enabled = music_enabled
	_impacts.blood_enabled = blood_enabled
	var frame := _simulation.render_snapshot()
	_terrain.configure(frame.arena_size, frame.walls, terrain_seed, biome)
	_vegetation.configure(session.vegetation_layout(), biome, terrain_seed)
	add_child(_terrain)
	add_child(_bake)
	if DisplayServer.get_name() != "headless":
		_bake.configure(frame.arena_size)
		_impacts.on_mark = func(mark: Dictionary): _bake.paint(func(canvas): ImpactEffects.draw_mark(canvas, mark))
		_figures.on_settled = func(unit: Dictionary, headless: bool): _bake.paint(func(canvas): _figures.draw_corpse(canvas, unit, headless))

func get_battle_snapshot() -> Dictionary:
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
	var log_panel := Panel.new()
	_journal_panel = log_panel
	log_panel.position = Vector2(8, 8)
	log_panel.size = Vector2(330, 34)
	log_panel.clip_contents = true
	log_panel.add_theme_stylebox_override("panel", preload("res://ui/game_theme.gd").box("parchment", 10))
	$Hud.add_child(log_panel)
	_journal_label = Label.new()
	_journal_label.position = Vector2(13, 6)
	_journal_label.size = Vector2(304, 22)
	_journal_label.clip_text = true
	_journal_label.max_lines_visible = 1
	_journal_label.add_theme_color_override("font_color", Color("#2a1d10"))
	_journal_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	log_panel.add_child(_journal_label)
	var initial := _simulation.render_snapshot()
	camera.configure(initial.arena_size, initial.hero_position)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_navigation.configure(_terrain.material)
	_controls.group_selected.connect(_select_group)
	_controls.order_selected.connect(_issue_hud_order)
	_controls.weapon_selected.connect(_select_weapon)
	_controls.pause_pressed.connect(_toggle_pause)
	_controls.speed_pressed.connect(_cycle_speed)
	_controls.retreat_pressed.connect(_request_retreat)
	_controls.menu_pressed.connect(menu_requested.emit)
	_audio = CombatAudio.new()
	_audio.enabled = _effects_enabled
	add_child(_audio)
	_music = BattleMusic.new()
	_music.enabled = _music_enabled
	add_child(_music)
	_refresh(0.0, [])
	set_physics_process(false)

func _process(real_dt: float) -> void:
	if _session == null: return
	var simulation_seconds := _pre_step(real_dt, real_dt)
	if simulation_seconds <= 0.0: return
	var count := _clock.advance(simulation_seconds, _simulation.step)
	if count > 0:
		_post_step(count * FixedClock.STEP_SECONDS, _simulation.take_events(), real_dt)
	queue_redraw()

func _order(order: String, point: Vector2) -> void:
	_simulation.submit([{"kind": "order", "order": order, "point": point, "selection": _selection}])

func _exit_tree() -> void:
	if _simulation != null: _simulation.dispose()

## Effects of a finished battle, music, pause and hero input. Returns the simulation step to run, or 0.
func _pre_step(dt: float, real_dt: float) -> float:
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
		_simulation.submit([{
			"kind": "hero_input",
			"move": Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))),
			"face": (_pointer_world_position() - Vector2(_frame.hero_position)).angle(),
			"sprint": Input.is_key_pressed(KEY_SHIFT),
			"block": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),
			"attack": _attack_pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
			"swap": Input.is_key_pressed(KEY_X),
		}])
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
	if _session == null or _menu_open:
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
		KEY_Q: _order(Config.ORDER_HOLD, _pointer_world_position())
		KEY_E: _order(Config.ORDER_FOLLOW, _frame.hero_position)
		KEY_R: _order(Config.ORDER_CHARGE, _frame.hero_position)
		KEY_F: _order(Config.ORDER_RETREAT, _frame.hero_position)
		KEY_P: _toggle_pause()
		KEY_T: _cycle_speed()
		KEY_ESCAPE: menu_requested.emit()

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

func set_menu_open(open: bool) -> void:
	_finish_pending_step()
	if open and not _menu_open:
		_paused_before_menu = _paused
		_paused = true
	elif not open and _menu_open:
		_paused = _paused_before_menu
	_menu_open = open
	_attack_pressed = false
	_update_status()

func apply_preferences(effects: bool, music: bool, blood: bool) -> void:
	_set_audio_preferences(effects, music)
	_impacts.blood_enabled = blood
	_rebake()

func _issue_hud_order(order: String) -> void:
	var origin: Vector2 = _frame.hero_position
	var enemy: Vector2 = _frame.enemy_center
	var direction := origin.direction_to(enemy) if enemy.is_finite() and enemy != origin else Vector2.RIGHT
	_order(order, origin + direction * BUTTON_ORDER_AHEAD)

func _select_weapon(slot: String) -> void:
	_simulation.submit([{"kind": "weapon", "slot": slot}])
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
	if not _frame.decided and _simulation.submit([{"kind": "retreat"}]):
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
	# One detached read per completed batch of ticks, reused by HUD and drawing.
	_frame = frame if not frame.is_empty() else _simulation.render_snapshot()
	if _figure_identity_count != _frame.render.size():
		var portrait_units: Array[Dictionary] = []
		for index in _frame.render.size(): portrait_units.append(_frame.render.unit_at(index))
		_figures.configure_identities(_session.unit_appearance_ids(), _figure_seed)
		_controls.configure_portraits(portrait_units, _session.unit_appearance_ids())
		_figure_identity_count = _frame.render.size()
	for group in 4: _hud_orders[group] = _session.selected_orders(group)
	camera.advance(dt if real_dt < 0.0 else real_dt, _frame.camera_target, _frame.hero_down, get_viewport().get_mouse_position(), events)
	if attract_mode:
		camera.position = Vector2(_frame.arena_size) * 0.5
	_navigation.update_frame(_frame, dt)
	var finished: bool = _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]
	_feedback.add_dialogue(_dialogue.advance_compact(dt, _frame.render, events, not _frame.walls.is_empty(), finished))
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
	_controls.show_commands(_selection, _hud_orders.get(_selection, []))
	if _journal_panel != null:
		var viewport_width := get_viewport_rect().size.x
		_journal_panel.size.x = viewport_width * 0.46 if viewport_width <= 760 else minf(330, viewport_width * (0.32 if viewport_width > 900 else 0.36))
		_journal_label.size.x = _journal_panel.size.x - 26
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
	_figures.draw_compact(self, _frame.render, visible, _impacts.headless_units(), _vegetation.entries, _selection, _clock.alpha(), attract_mode)
	SiegeDefenseView.draw_over(self, _frame.get("wall_defense", {}))
	for shot in _frame.shots:
		ProjectileView.draw(self, shot)
	_impacts.draw_particles(self)
	_feedback.draw(self)
	if not attract_mode: _dialogue.draw(self)
