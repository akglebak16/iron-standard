extends Node2D
## Input/rendering adapter. Simulation is injected before entering the tree.
const Config = preload("res://battle/config.gd")
const Demo = preload("res://battle/presentation/demo_config.gd")
const Session = preload("res://battle/application/session.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const ProjectileView = preload("res://battle/presentation/projectile_view.gd")
const CombatFeedback = preload("res://battle/presentation/combat_feedback.gd")
const ImpactEffects = preload("res://battle/presentation/impact_effects.gd")
const CombatAudio = preload("res://battle/presentation/audio/combat_audio.gd")
const BattleMusic = preload("res://battle/presentation/audio/battle_music.gd")

signal battle_finished
signal audio_preferences_changed(effects: bool, music: bool)

@onready var camera: Camera2D = $Camera
@onready var status: Label = $Hud/Status
var _session: Session
var _frame: Dictionary = {}
var _selection := Config.ALL_GROUPS
var _feedback := CombatFeedback.new()
var _impacts := ImpactEffects.new()
var _audio: CombatAudio
var _music: BattleMusic
var _effects_enabled := true
var _music_enabled := true
var _result_summary := ""

func configure(session: Session, effects_enabled: bool = true, music_enabled: bool = true) -> void:
	assert(not is_inside_tree(), "Configure battle before adding it to the tree")
	_session = session
	_effects_enabled = effects_enabled
	_music_enabled = music_enabled

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
	camera.zoom = Vector2.ONE * Demo.CAMERA_ZOOM
	_audio = CombatAudio.new()
	_audio.enabled = _effects_enabled
	add_child(_audio)
	_music = BattleMusic.new()
	_music.enabled = _music_enabled
	add_child(_music)
	_refresh()

func _physics_process(dt: float) -> void:
	if _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		if _feedback.has_effects() or _impacts.has_particles():
			_feedback.advance(dt, [])
			_impacts.advance(dt, [])
			queue_redraw()
		return
	_music.advance(dt)
	if _frame.outcome == Session.Outcome.RUNNING:
		var input := HeroInput.new()
		input.move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
		input.face = (get_global_mouse_position() - Vector2(_frame.hero_position)).angle()
		input.sprint = Input.is_key_pressed(KEY_SHIFT)
		input.block = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		input.attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		input.swap = Input.is_key_pressed(KEY_X)
		_session.set_hero_input(input)
	_session.advance(dt)
	var events := _session.take_events()
	_feedback.advance(dt, events)
	_impacts.advance(dt, events)
	_refresh()
	_audio.advance(dt, events, camera.position)
	if _frame.outcome in [Session.Outcome.VICTORY, Session.Outcome.DEFEAT]:
		battle_finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if _session == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_M:
			_set_audio_preferences(not _effects_enabled, _music_enabled)
		KEY_N:
			_set_audio_preferences(_effects_enabled, not _music_enabled)
		KEY_1: _selection = Config.GROUP_INFANTRY
		KEY_2: _selection = Config.GROUP_ARCHERS
		KEY_3: _selection = Config.GROUP_CAVALRY
		KEY_4: _selection = Config.ALL_GROUPS
		KEY_Q: _session.issue_order(Config.ORDER_HOLD, get_global_mouse_position(), _selection)
		KEY_E: _session.issue_order(Config.ORDER_FOLLOW, _frame.hero_position, _selection)
		KEY_R: _session.issue_order(Config.ORDER_CHARGE, _frame.hero_position, _selection)
		KEY_F: _session.issue_order(Config.ORDER_RETREAT, _frame.hero_position, _selection)

func _set_audio_preferences(effects: bool, music: bool) -> void:
	_effects_enabled = effects
	_music_enabled = music
	_audio.enabled = effects
	_music.enabled = music
	_update_status()
	audio_preferences_changed.emit(effects, music)

func _refresh() -> void:
	# One detached read per physics tick, reused by HUD and drawing.
	_frame = _session.snapshot()
	camera.position = _frame.camera_target
	_update_status()
	queue_redraw()

func _update_status() -> void:
	var label: String = Demo.IN_PROGRESS
	match _frame.outcome:
		Session.Outcome.HERO_DOWN: label = Demo.HERO_DOWN
		Session.Outcome.VICTORY: label = Demo.VICTORY
		Session.Outcome.DEFEAT: label = Demo.DEFEAT
	status.text = Demo.HUD_TEXT % [label, _frame.counts[0], _frame.counts[1], int(_frame.stamina)]
	status.text += Demo.SOUND_HINT % [Demo.SOUND_ON if _effects_enabled else Demo.SOUND_OFF, Demo.SOUND_ON if _music_enabled else Demo.SOUND_OFF]
	var journal := _feedback.journal()
	if not journal.is_empty():
		status.text += "\n" + journal
	status.text += _result_summary

func _draw() -> void:
	if _frame.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, _frame.arena_size), Demo.GROUND_COLOR)
	for segment: Rect2 in _frame.walls:
		draw_rect(segment, Demo.WALL_COLOR)
	_impacts.draw_ground(self)
	for unit in _frame.units:
		if unit.gone:
			continue
		var color: Color = Demo.DEAD_COLOR if unit.dead else (Demo.PLAYER_COLOR if unit.side == 0 else Demo.ENEMY_COLOR)
		draw_circle(unit.position, unit.radius, color)
		if unit.hero and not unit.dead:
			draw_arc(unit.position, unit.radius + Demo.HERO_RING_PADDING, 0.0, TAU, Demo.HERO_RING_SEGMENTS, Color.WHITE, Demo.HERO_RING_WIDTH)
		elif unit.companion and not unit.dead:
			draw_arc(unit.position, unit.radius + Demo.HERO_RING_PADDING, 0.0, TAU, Demo.HERO_RING_SEGMENTS, Demo.COMPANION_RING_COLOR, Demo.HERO_RING_WIDTH)
	for shot in _frame.shots:
		ProjectileView.draw(self, shot)
	_impacts.draw_particles(self)
	_feedback.draw(self)
