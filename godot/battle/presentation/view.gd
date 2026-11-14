extends Node2D
## Input/rendering adapter. Simulation is injected before entering the tree.
const Config = preload("res://battle/config.gd")
const Demo = preload("res://battle/presentation/demo_config.gd")
const Session = preload("res://battle/application/session.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")

@onready var camera: Camera2D = $Camera
@onready var status: Label = $Hud/Status
var _session: Session
var _frame: Dictionary = {}
var _selection := Config.ALL_GROUPS

func configure(session: Session) -> void:
	assert(not is_inside_tree(), "Configure battle before adding it to the tree")
	_session = session

func get_battle_snapshot() -> Dictionary:
	return _session.snapshot() if _session != null else {}

func _ready() -> void:
	if _session == null:
		push_error("Battle view requires a session")
		set_physics_process(false)
		set_process_unhandled_input(false)
		return
	camera.zoom = Vector2.ONE * Demo.CAMERA_ZOOM
	_refresh()

func _physics_process(dt: float) -> void:
	if _frame.outcome != Session.Outcome.RUNNING:
		return
	var input := HeroInput.new()
	input.move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	input.face = (get_global_mouse_position() - Vector2(_frame.hero_position)).angle()
	input.sprint = Input.is_key_pressed(KEY_SHIFT)
	input.block = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	input.attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	input.swap = Input.is_key_pressed(KEY_X)
	_session.set_hero_input(input)
	_session.advance(dt)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if _session == null or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: _selection = Config.GROUP_INFANTRY
		KEY_2: _selection = Config.GROUP_ARCHERS
		KEY_3: _selection = Config.GROUP_CAVALRY
		KEY_4: _selection = Config.ALL_GROUPS
		KEY_Q: _session.issue_order(Config.ORDER_HOLD, get_global_mouse_position(), _selection)
		KEY_E: _session.issue_order(Config.ORDER_FOLLOW, _frame.hero_position, _selection)
		KEY_R: _session.issue_order(Config.ORDER_CHARGE, _frame.hero_position, _selection)
		KEY_F: _session.issue_order(Config.ORDER_RETREAT, _frame.hero_position, _selection)

func _refresh() -> void:
	# One detached read per physics tick, reused by HUD and drawing.
	_frame = _session.snapshot()
	camera.position = _frame.hero_position
	var label: String = Demo.IN_PROGRESS
	match _frame.outcome:
		Session.Outcome.HERO_DOWN: label = Demo.HERO_DOWN
		Session.Outcome.VICTORY: label = Demo.VICTORY
		Session.Outcome.DEFEAT: label = Demo.DEFEAT
	status.text = Demo.HUD_TEXT % [label, _frame.counts[0], _frame.counts[1], int(_frame.stamina)]
	queue_redraw()

func _draw() -> void:
	if _frame.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, _frame.arena_size), Demo.GROUND_COLOR)
	for unit in _frame.units:
		if unit.gone:
			continue
		var color: Color = Demo.DEAD_COLOR if unit.dead else (Demo.PLAYER_COLOR if unit.side == 0 else Demo.ENEMY_COLOR)
		draw_circle(unit.position, unit.radius, color)
		if unit.hero and not unit.dead:
			draw_arc(unit.position, unit.radius + Demo.HERO_RING_PADDING, 0.0, TAU, Demo.HERO_RING_SEGMENTS, Color.WHITE, Demo.HERO_RING_WIDTH)
	for impact in _frame.shots:
		draw_circle(impact, Demo.PROJECTILE_RADIUS, Color.YELLOW)
