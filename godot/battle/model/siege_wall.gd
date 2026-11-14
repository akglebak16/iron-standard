extends RefCounted
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")

var x: float
var half_width := Config.SIEGE_WALL_HALF_WIDTH
var _gaps: Array[Vector2] = []
var _segments: Array[Rect2] = []

func _init(arena_size: Vector2) -> void:
	x = arena_size.x - Config.SIEGE_WALL_RIGHT_OFFSET
	for offsets: Vector2 in Config.SIEGE_GAP_OFFSETS:
		_gaps.append(offsets + Vector2.ONE * arena_size.y * 0.5)
	var ordered := _gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var start := 0.0
	for gap in ordered:
		_segments.append(Rect2(x - half_width, start, half_width * 2.0, gap.x - start))
		start = gap.y
	_segments.append(Rect2(x - half_width, start, half_width * 2.0, arena_size.y - start))

func segments() -> Array[Rect2]:
	return _segments.duplicate()

func gap_at(y: float) -> Vector2:
	for gap in _gaps:
		if y > gap.x and y < gap.y:
			return gap
	return Vector2.ZERO

func constrain(unit: Unit) -> void:
	var clearance := half_width + unit.collision_radius * Config.SIEGE_WALL_RADIUS_PADDING
	var offset := unit.position.x - x
	if absf(offset) >= clearance:
		return
	var gap := gap_at(unit.position.y)
	if gap != Vector2.ZERO:
		var padding := unit.collision_radius * Config.SIEGE_GAP_RADIUS_PADDING
		unit.position.y = clampf(unit.position.y, gap.x + padding, gap.y - padding)
		return
	unit.position.x = x - clearance if offset < 0.0 else x + clearance
	# The original uses the left side when checking velocity at the exact centerline.
	if signf(unit.velocity.x) != (-1.0 if offset <= 0.0 else 1.0):
		unit.velocity.x = 0.0
