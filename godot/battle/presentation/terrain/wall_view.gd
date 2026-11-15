extends Node2D

const STONE := Color("#857a68")
const MORTAR := Color("#554c40")
const EDGE := Color("#2a2219")
const PARAPET := Color("#a49884")
const TOWER := Color("#93876f")
const TOWER_INNER := Color("#6d6252")
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)
const RUBBLE := [Color("#7a6f5e"), Color("#968a74")]
const GATE_WOOD := Color("#5b3d22")
const GATE_IRON := Color("#393631")
const STONE_COURSE := 14.0
const EDGE_WIDTH := 2.0
const MERLON_SIZE := Vector2(9, 12)
const MERLON_PITCH := 22.0
const TOWER_RADIUS := 34.0
const TOWER_INNER_RADIUS := 22.0
const RUBBLE_COUNT := 26
const RUBBLE_END_MARGIN := 18.0
const RUBBLE_X_SPREAD := 6.0
const RUBBLE_RADIUS := Vector2(3, 9)
const GATE_MIN_WIDTH := 140.0
const GATE_OPEN_ANGLE := 0.9
const GATE_LEAF_SIZE := Vector2(52, 14)
const GATE_LEAF_OFFSET := Vector2(10, 52)
const SHADOW_OFFSET := Vector2(-12, 10)
const TOWER_SHADOW_OFFSET := Vector2(-6, 10)
const HINGE_SIZE := Vector2(4, 14)
const HINGE_SPACING := 15.0

var _segments: Array[Rect2] = []
var _openings: Array[Rect2] = []
var _rubble: Array[Dictionary] = []

func configure(walls: Array[Rect2], seed_value: int) -> void:
	_segments = walls.duplicate()
	_openings.clear()
	_rubble.clear()
	_segments.sort_custom(func(a: Rect2, b: Rect2): return a.position.y < b.position.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(1, _segments.size()):
		var preceding := _segments[i - 1]
		var following := _segments[i]
		var width := following.position.y - preceding.end.y
		if width <= 0.0:
			continue
		var opening := Rect2(preceding.position.x, preceding.end.y, preceding.size.x, width)
		_openings.append(opening)
		var inset := minf(RUBBLE_END_MARGIN, width * 0.5)
		for j in RUBBLE_COUNT:
			_rubble.append({
				"position": Vector2(rng.randf_range(opening.position.x - RUBBLE_X_SPREAD, opening.end.x + RUBBLE_X_SPREAD),
					rng.randf_range(opening.position.y + inset, opening.end.y - inset)),
				"radius": rng.randf_range(RUBBLE_RADIUS.x, RUBBLE_RADIUS.y),
				"color": RUBBLE[rng.randi_range(0, RUBBLE.size() - 1)],
			})
	queue_redraw()

func _draw() -> void:
	for segment in _segments:
		draw_rect(Rect2(segment.position + SHADOW_OFFSET, segment.size), SHADOW)
	_draw_rubble()
	for segment in _segments:
		_draw_segment(segment)
	for opening in _openings:
		var center := opening.get_center()
		_draw_tower(Vector2(center.x, opening.position.y))
		_draw_tower(Vector2(center.x, opening.end.y))
		if opening.size.y > GATE_MIN_WIDTH:
			_draw_gate_leaf(center, -1.0)
			_draw_gate_leaf(center, 1.0)

func _draw_rubble() -> void:
	for piece in _rubble:
		draw_circle(piece.position, piece.radius, EDGE, true, -1.0, true)
		draw_circle(piece.position, piece.radius - EDGE_WIDTH * 0.5, piece.color, true, -1.0, true)

func _draw_segment(segment: Rect2) -> void:
	draw_rect(segment, STONE)
	var rows := ceili(segment.size.y / STONE_COURSE)
	for row in rows:
		var start := segment.position.y + row * STONE_COURSE
		var end := minf(segment.end.y, start + STONE_COURSE)
		draw_line(Vector2(segment.position.x, start), Vector2(segment.end.x, start), MORTAR)
		var joint := segment.position.x + segment.size.x * (0.25 if row % 2 == 0 else 0.5)
		draw_line(Vector2(joint, start), Vector2(joint, end), MORTAR)
	for slot in floori(segment.size.y / MERLON_PITCH):
		var top := segment.position.y + slot * MERLON_PITCH + (MERLON_PITCH - MERLON_SIZE.y) * 0.5
		var merlon := Rect2(Vector2(segment.end.x - MERLON_SIZE.x, top), MERLON_SIZE)
		draw_rect(merlon, PARAPET)
		draw_rect(merlon, EDGE, false, 1.0)
	draw_rect(segment, EDGE, false, EDGE_WIDTH)

func _draw_tower(position: Vector2) -> void:
	draw_circle(position + TOWER_SHADOW_OFFSET, TOWER_RADIUS, SHADOW, true, -1.0, true)
	draw_circle(position, TOWER_RADIUS, EDGE, true, -1.0, true)
	draw_circle(position, TOWER_RADIUS - EDGE_WIDTH, TOWER, true, -1.0, true)
	draw_circle(position, TOWER_INNER_RADIUS, TOWER_INNER, true, -1.0, true)

func _draw_gate_leaf(center: Vector2, side: float) -> void:
	draw_set_transform(center + GATE_LEAF_OFFSET * Vector2(1, side), side * GATE_OPEN_ANGLE)
	var bounds := Rect2(-GATE_LEAF_SIZE * 0.5, GATE_LEAF_SIZE)
	draw_rect(bounds, GATE_WOOD)
	draw_rect(Rect2(Vector2(-HINGE_SPACING, bounds.position.y), HINGE_SIZE), GATE_IRON)
	draw_rect(Rect2(Vector2(HINGE_SPACING, bounds.position.y), HINGE_SIZE), GATE_IRON)
	draw_rect(bounds, EDGE, false, EDGE_WIDTH)
	draw_set_transform(Vector2.ZERO)
