extends Camera2D

const Event = preload("res://core/battle/combat_event.gd")
const INITIAL_LEAD := Vector2(200, 0)
const FOLLOW_RATE := 5.0
const POINTER_LEAD_RATIO := 0.22
const MAX_POINTER_LEAD := Vector2(140, 100)
const REFERENCE_VIEW_HEIGHT := 700.0
const INITIAL_ZOOM_RANGE := Vector2(0.75, 1.35)
const MANUAL_ZOOM_RANGE := Vector2(0.55, 2.0)
const ZOOM_IN_FACTOR := 1.1
const ZOOM_OUT_FACTOR := 0.91
const HIT_SHAKE_SECONDS := 0.18
const GATE_SHAKE_SECONDS := 0.45 # gateBreak: B.shake = 0.45
const HIT_SHAKE_SCREEN_PIXELS := 3.0

var _arena_size := Vector2.ZERO
var _shake_remaining := 0.0
var _shake_rng := RandomNumberGenerator.new()

func configure(arena_size: Vector2, hero_position: Vector2) -> void:
	_arena_size = arena_size
	_set_zoom(initial_zoom(get_viewport_rect().size.y))
	position = hero_position + INITIAL_LEAD
	fit_viewport()

func advance(dt: float, target: Vector2, hero_down: bool, pointer: Vector2, events: Array[Dictionary]) -> void:
	if target.is_finite():
		if not hero_down:
			target += pointer_lead(target, screen_to_world(pointer))
		position = position.lerp(target, minf(1.0, dt * FOLLOW_RATE))
	advance_shake(dt, events)

func advance_shake(dt: float, events: Array[Dictionary]) -> void:
	_shake_remaining = maxf(0.0, _shake_remaining - dt)
	for event in events:
		if event.kind == Event.Kind.HIT and event.target_hero:
			_shake_remaining = HIT_SHAKE_SECONDS
		elif event.kind == Event.Kind.GATE_BROKEN:
			_shake_remaining = maxf(_shake_remaining, GATE_SHAKE_SECONDS)
	if _shake_remaining > 0.0:
		var amplitude := HIT_SHAKE_SCREEN_PIXELS / zoom.x
		offset = Vector2(_shake_rng.randf_range(-amplitude, amplitude), _shake_rng.randf_range(-amplitude, amplitude))
	else:
		offset = Vector2.ZERO
	fit_viewport()

func shake(seconds: float) -> void:
	_shake_remaining = maxf(_shake_remaining, seconds)

func change_zoom(inward: bool) -> void:
	var factor := ZOOM_IN_FACTOR if inward else ZOOM_OUT_FACTOR
	_set_zoom(clampf(zoom.x * factor, MANUAL_ZOOM_RANGE.x, MANUAL_ZOOM_RANGE.y))
	fit_viewport()

func fit_viewport() -> void:
	var half_view := (get_viewport_rect().size / zoom * 0.5).min(_arena_size * 0.5)
	position = position.clamp(half_view, _arena_size - half_view)
	force_update_scroll()

func screen_to_world(point: Vector2) -> Vector2:
	return position + (point - get_viewport_rect().size * 0.5) / zoom

func is_shaking() -> bool:
	return _shake_remaining > 0.0

func _set_zoom(value: float) -> void:
	zoom = Vector2.ONE * value

static func initial_zoom(height: float) -> float:
	return clampf(height / REFERENCE_VIEW_HEIGHT, INITIAL_ZOOM_RANGE.x, INITIAL_ZOOM_RANGE.y)

static func pointer_lead(hero_position: Vector2, pointer: Vector2) -> Vector2:
	return ((pointer - hero_position) * POINTER_LEAD_RATIO).clamp(-MAX_POINTER_LEAD, MAX_POINTER_LEAD)
