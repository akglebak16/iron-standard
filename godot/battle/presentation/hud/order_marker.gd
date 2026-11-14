extends RefCounted

const Event = preload("res://battle/combat_event.gd")
const Config = preload("res://battle/config.gd")
const LIFETIME := 4.0
const FADE_SECONDS := 1.0
const COLOR := Color("#f1d27a")
const POLE_COLOR := Color("#8a6a40")
const RING_RADIUS := Vector2(26, 10)
const RING_SEGMENTS := 24
const STROKE_WIDTH := 2.0
const POLE_HEIGHT := 31.0
const CLOTH := [Vector2(0, -30), Vector2(19, -29), Vector2(15, -22), Vector2(19, -15), Vector2(0, -14)]

var _remaining := 0.0
var _point := Vector2.ZERO
var _ring := PackedVector2Array()
var _cloth := PackedVector2Array(CLOTH)

func _init() -> void:
	for i in range(RING_SEGMENTS + 1):
		_ring.append(Vector2.from_angle(TAU * i / RING_SEGMENTS) * RING_RADIUS)

func advance(dt: float, events: Array[Dictionary]) -> void:
	_remaining = maxf(0.0, _remaining - dt)
	for event in events:
		if event.kind == Event.Kind.ORDER_APPLIED and event.order == Config.ORDER_HOLD:
			_point = event.point
			_remaining = LIFETIME

func is_visible() -> bool:
	return _remaining > 0.0

func draw(canvas: CanvasItem) -> void:
	if not is_visible():
		return
	var alpha := minf(1.0, _remaining / FADE_SECONDS)
	canvas.draw_set_transform(_point)
	canvas.draw_polyline(_ring, Color(COLOR, alpha), STROKE_WIDTH, true)
	canvas.draw_line(Vector2.ZERO, Vector2.UP * POLE_HEIGHT, Color(POLE_COLOR, alpha), STROKE_WIDTH, true)
	canvas.draw_colored_polygon(_cloth, Color(COLOR, alpha))
	canvas.draw_set_transform(Vector2.ZERO)
