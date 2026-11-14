extends RefCounted
const Config = preload("res://battle/config.gd")

var side: int
var kind: int # 0 infantry, 1 archers, 2 cavalry
var center: Vector2
var direction: float
var order: String = Config.ORDER_HOLD
var backing: bool = false
var units: Array = []

func _init(group_side: int, group_kind: int, at: Vector2, facing: float) -> void:
	side = group_side
	kind = group_kind
	center = at
	direction = facing

func active_units() -> Array:
	return units.filter(func(u): return not u.dead and not u.gone and not u.fleeing and not u.hero)

func layout(initial: bool = false) -> void:
	var active := active_units()
	var count := active.size()
	if count == 0:
		return
	var factor: float = Config.FORMATION_FACTOR[kind]
	var minimum: int = Config.FORMATION_MIN_COLUMNS[kind]
	var columns: int = mini(count, maxi(minimum, ceili(sqrt(count * factor))))
	var rows: int = ceili(float(count) / columns)
	var width: int = ceili(float(count) / rows)
	var spacing: float = Config.FORMATION_SPACING[kind]
	var perpendicular := Vector2(-sin(direction), cos(direction))
	if initial:
		active.sort_custom(func(a, b): return a.tier > b.tier if a.tier != b.tier else a.id < b.id)
	else:
		active.sort_custom(func(a, b): return a.position.dot(perpendicular) < b.position.dot(perpendicular))
	for i in count:
		var column: int
		var row: int
		var row_width: int
		if initial:
			row = i / width
			column = i % width
			row_width = mini(width, count - row * width)
		else:
			column = i / rows
			row = i % rows
			row_width = width
		active[i].slot_offset = Vector2((column - (row_width - 1) / 2.0) * spacing, -row * spacing * Config.FORMATION_ROW_DEPTH)

func slot_position(unit: RefCounted, arena_size: Vector2) -> Vector2:
	var offset: Vector2 = unit.slot_offset
	var pos := center + Vector2(-sin(direction), cos(direction)) * offset.x + Vector2(cos(direction), sin(direction)) * offset.y
	return pos.clamp(Vector2.ONE * Config.SLOT_EDGE, arena_size - Vector2.ONE * Config.SLOT_EDGE)

func centroid() -> Vector2:
	var active := active_units()
	if active.is_empty():
		return center
	var total := Vector2.ZERO
	for unit in active:
		total += unit.position
	return total / active.size()
