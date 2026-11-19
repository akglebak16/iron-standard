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
# Stage 1v doctrines (simulation/ai/squad_doctrine.gd), the same for both sides; fighters read them every tick.
var formed: bool = false # Infantry charge as a line: the centre moves with the formation, rear ranks keep their places.
var loose: bool = false # Ordered loose: the group never forms a line in a charge (an input for a commander, stage 1g).
var mingled: bool = false # A formed line long in melee went loose; it forms again when the contact is over.
var rally: bool = false # Shock cavalry rides to its rally point (the group centre) instead of fighting.
var screen: Vector2 = Vector2.INF # Spearmen form a line here to cover the own archers; INF when there is no threat.
var screen_lateral: Vector2 = Vector2.DOWN # Direction of that line.
var doctrine_timer: float = 0.0 # Until the next group decision; staggered by group number at creation.
var doctrine_order: String = "" # Order and backing seen at the last decision: a change is decided at once.
var doctrine_backing: bool = false
var doctrine_seconds: float = Config.AI_FORMATION_SWITCH_SECONDS # Since the last formation switch (the first one is free), or in the current cavalry phase.
var contact_seconds: float = 0.0 # Cavalry: riders stuck in foot melee; infantry: a formed line in melee.
# Stage Р3 doctrines with the terrain (squad_doctrine.gd, TERRAIN.md 7).
var post: Vector2 = Vector2.INF # AI archers: the high ground or forest edge the doctrine moved the centre to.
var post_anchor: Vector2 = Vector2.INF # The centre seen at the last decision: a post is sought once it stands still.
var open_waypoint: Vector2 = Vector2.INF # AI cavalry: the flank waypoint after the open-ground check.
# Stage 1b morale summary (rules/morale.gd), written on every morale check; the debug overlay and a future commander
# read it, fighters do not.
var morale_state: int = Config.MORALE_GROUP_STEADY
var morale_pressure: float = 0.0 # Weighted enemy threat against own strength (field assessment).
var morale_fleeing_share: float = 0.0
var _slot_direction := INF
var _slot_lateral := Vector2.DOWN
var _slot_forward := Vector2.RIGHT

func _init(group_side: int, group_kind: int, at: Vector2, facing: float) -> void:
	side = group_side
	kind = group_kind
	center = at
	direction = facing
	doctrine_timer = (group_side * 3 + group_kind) * Config.AI_SQUAD_PERIOD_SECONDS / 6.0

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
		# Stage 1v: within each column the man standing in front takes the front rank, so a re-formed line keeps
		# its ranks instead of swapping men front to back (the formed charge fights with its front ranks).
		var forward := Vector2(cos(direction), sin(direction))
		for start in range(0, count, rows):
			var file := active.slice(start, mini(start + rows, count))
			file.sort_custom(func(a: Unit, b: Unit): return a.position.dot(forward) > b.position.dot(forward))
			for k in file.size():
				active[start + k] = file[k]
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
	return formation_point(unit.slot_offset, center, arena_size)

## The slot of `offset` in a formation centred on `at` with this group's direction (the slot itself when at == center).
func formation_point(offset: Vector2, at: Vector2, arena_size: Vector2) -> Vector2:
	_refresh_frame()
	var pos := at + _slot_lateral * offset.x + _slot_forward * offset.y
	return pos.clamp(Vector2.ONE * Config.SLOT_EDGE, arena_size - Vector2.ONE * Config.SLOT_EDGE)

## Formation centre implied by a fighter standing at `position` with this slot offset (inverse of the slot).
func implied_center(offset: Vector2, position: Vector2) -> Vector2:
	_refresh_frame()
	return position - _slot_lateral * offset.x - _slot_forward * offset.y

func _refresh_frame() -> void:
	if direction != _slot_direction:
		_slot_direction = direction
		var sine := sin(direction)
		var cosine := cos(direction)
		_slot_lateral = Vector2(-sine, cosine)
		_slot_forward = Vector2(cosine, sine)

func centroid() -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit: Unit in units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero: continue
		total += unit.position
		count += 1
	return total / count if count else center
