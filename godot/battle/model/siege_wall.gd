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

func route(unit: Unit, destination: Vector2) -> Vector2:
	var side := -1.0 if unit.position.x < x else 1.0
	var destination_side := -1.0 if destination.x < x else 1.0
	if side == destination_side:
		return destination
	var best_gap := Vector2.ZERO
	var best_cost := INF
	for gap in _gaps:
		var center := (gap.x + gap.y) * 0.5
		var cost := absf(center - unit.position.y) + absf(center - destination.y) * Config.SIEGE_ROUTE_DESTINATION_WEIGHT
		if cost < best_cost:
			best_cost = cost
			best_gap = gap
	var center := (best_gap.x + best_gap.y) * 0.5
	var half_gap := (best_gap.y - best_gap.x) * 0.5 - unit.collision_radius
	var entry_y := clampf(unit.position.y, center - half_gap, center + half_gap)
	var distance := absf(unit.position.x - x)
	if distance < half_width + Config.SIEGE_ROUTE_CROSS_READY_DISTANCE and absf(unit.position.y - center) < half_gap:
		return Vector2(x - side * Config.SIEGE_ROUTE_CROSS_DISTANCE, entry_y)
	return Vector2(x + side * (half_width + Config.SIEGE_ROUTE_APPROACH_OFFSET), center if distance < Config.SIEGE_ROUTE_CENTERING_DISTANCE else entry_y)

func projectile_multiplier(target: Unit, origin: Vector2, skill: float) -> float:
	if target.side == 1 and target.position.x > x and target.position.x < x + Config.SIEGE_COVER_DEPTH and origin.x < x and gap_at(target.position.y) == Vector2.ZERO:
		return Config.SIEGE_COVER_DAMAGE_MULTIPLIER + Config.SIEGE_COVER_SKILL_SCALE * skill
	return 1.0

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
