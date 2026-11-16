extends RefCounted
const Unit = preload("res://core/battle/model/unit.gd")
const Config = preload("res://core/battle/config.gd")

var side: int
var kind: int # 0 infantry, 1 archers, 2 cavalry
var center: Vector2
var direction: float
var order: String = Config.ORDER_HOLD
var backing: bool = false
var tactic_state: String = Config.AI_TACTIC_WAIT
var waypoint: Vector2 = Vector2.ZERO
var units: Array[Unit] = []
# Squad picture written by the opposing side's tactics scan (tactics.gd), refreshed every AI_SQUAD_SCAN_SECONDS.
var scan_count: int = 0 # Estimated ready fighters (sample count times stride).
var scan_center: Vector2 = Vector2.INF
var scan_points := PackedVector2Array() # Sampled fighter positions, for the distance to the squad's nearest edge.
# Own-side AI state for the kite check.
var squad_distance: float = INF # From this group's center to the nearest enemy squad, at the latest scan.
var kite_seconds: float = 0.0
var kite_gap: float = INF # Best mean chase gap since the chase stopped closing in.
var kited: bool = false # The group once called off a hopeless chase; single fighters no longer trigger its charge.
var focus_kind: int = -1 # Enemy group kind the group marches on after calling off a chase.
var _slot_direction := INF
var _slot_lateral := Vector2.DOWN
var _slot_forward := Vector2.RIGHT

func _init(group_side: int, group_kind: int, at: Vector2, facing: float) -> void:
	side = group_side
	kind = group_kind
	center = at
	direction = facing

func active_units() -> Array[Unit]:
	return units.filter(func(u: Unit): return not u.dead and not u.gone and not u.fleeing and not u.hero)

func has_active_units() -> bool:
	for unit in units:
		if not unit.dead and not unit.gone and not unit.fleeing and not unit.hero: return true
	return false

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
		active.sort_custom(func(a: Unit, b: Unit):
			if a.tier != b.tier:
				return a.tier > b.tier
			if a.troop_id != b.troop_id:
				return a.troop_id < b.troop_id
			return a.id < b.id)
	else:
		active.sort_custom(func(a: Unit, b: Unit): return a.position.dot(perpendicular) < b.position.dot(perpendicular))
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

func slot_position(unit: Unit, arena_size: Vector2) -> Vector2:
	if direction != _slot_direction:
		_slot_direction = direction
		var sine := sin(direction)
		var cosine := cos(direction)
		_slot_lateral = Vector2(-sine, cosine)
		_slot_forward = Vector2(cosine, sine)
	var offset: Vector2 = unit.slot_offset
	var pos := center + _slot_lateral * offset.x + _slot_forward * offset.y
	return pos.clamp(Vector2.ONE * Config.SLOT_EDGE, arena_size - Vector2.ONE * Config.SLOT_EDGE)

func centroid() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit: Unit in units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero: continue
		total += unit.position
		count += 1
	return total / count if count else center
