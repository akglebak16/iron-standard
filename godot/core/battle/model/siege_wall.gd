extends RefCounted
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")

var x: float
var half_width := Config.SIEGE_WALL_HALF_WIDTH
## Every opening in the wall: gates first (the main one at 0), then a breach in a badly battered wall.
var _gaps: Array[Vector2] = []
var _segments: Array[Rect2] = []
## One per gate, same order as the first gaps: {gap, hp, max, hit, dead, open}. A shut gate is part of the wall.
var gates: Array[Dictionary] = []
## Grows whenever a gate opens or falls, so cached contact geometry is rebuilt.
var revision := 0

## siegeSetup in src/03_battle.js. `damage` 0..1 weakens the gates and, from 0.3, opens a breach; `skill` is the
## attackers' siegecraft (B.siegeF); `castle` has one heavy gate and a thicker wall.
func _init(arena_size: Vector2, damage: float = 0.0, castle: bool = false, skill: float = 0.0, seed_value: int = 7) -> void:
	x = arena_size.x - Config.SIEGE_WALL_RIGHT_OFFSET
	var middle := arena_size.y * 0.5
	var damage01 := clampf(damage, 0.0, 1.0)
	var siegecraft := clampf(skill, 0.0, Config.SIEGE_SKILL_MAX)
	half_width = Config.SIEGE_CASTLE_WALL_HALF_WIDTH if castle else Config.SIEGE_WALL_HALF_WIDTH
	for definition: Vector3 in (Config.SIEGE_CASTLE_GATES if castle else Config.SIEGE_TOWN_GATES):
		var gap := Vector2(middle + definition.x, middle + definition.y)
		var strength := maxf(Config.SIEGE_GATE_MIN_HP, roundf(definition.z * (1.0 - Config.SIEGE_GATE_DAMAGE_WEAKENING * damage01) * (1.0 - Config.SIEGE_GATE_SKILL_WEAKENING * siegecraft)))
		_gaps.append(gap)
		gates.append({"gap": gap, "hp": strength, "max": strength, "hit": 0.0, "dead": false, "open": false})
	if damage01 >= Config.SIEGE_BREACH_MIN_DAMAGE:
		var width := roundf(Config.SIEGE_BREACH_BASE_WIDTH + Config.SIEGE_BREACH_DAMAGE_WIDTH * damage01)
		var side := -1.0 if _mulberry_first(seed_value + Config.SIEGE_BREACH_SEED_OFFSET) < 0.5 else 1.0
		var center := middle + side * Config.SIEGE_BREACH_OFFSET
		_gaps.append(Vector2(center - width * 0.5, center + width * 0.5))
	var ordered := _gaps.duplicate()
	ordered.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var start := 0.0
	for gap in ordered:
		_segments.append(Rect2(x - half_width, start, half_width * 2.0, gap.x - start))
		start = gap.y
	_segments.append(Rect2(x - half_width, start, half_width * 2.0, arena_size.y - start))

## First draw of mulberry32 (src/01_core.js), on unsigned 32-bit values.
static func _mulberry_first(seed_value: int) -> float:
	const MASK := 0xFFFFFFFF
	var a := (seed_value + 0x6D2B79F5) & MASK
	var t := _imul(a ^ (a >> 15), 1 | a)
	t = ((t + _imul(t ^ (t >> 7), 61 | t)) & MASK) ^ t
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

static func _imul(p: int, q: int) -> int:
	p &= 0xFFFFFFFF
	q &= 0xFFFFFFFF
	return ((p & 0xFFFF) * q + ((((p >> 16) * q) & 0xFFFF) << 16)) & 0xFFFFFFFF

## gapShut: a gate that still stands and was not opened from inside.
func _shut(index: int) -> bool:
	if index >= gates.size():
		return false
	var gate: Dictionary = gates[index]
	return float(gate.hp) > 0.0 and not bool(gate.open)

## Openings units can pass through now.
func gaps() -> Array[Vector2]:
	var open: Array[Vector2] = []
	for i in _gaps.size():
		if not _shut(i):
			open.append(_gaps[i])
	return open

## Every opening, shut gates included (drawing, cauldrons).
func all_gaps() -> Array[Vector2]:
	return _gaps.duplicate()

func has_open_gap() -> bool:
	for i in _gaps.size():
		if not _shut(i):
			return true
	return false

func segments() -> Array[Rect2]:
	return _segments.duplicate()

func gap_at(y: float) -> Vector2:
	for i in _gaps.size():
		var gap := _gaps[i]
		if not _shut(i) and y > gap.x and y < gap.y:
			return gap
	return Vector2.ZERO

## Attackers in contact batter shut gates, archers do not (siegeBrain). Returns the indices of gates that fell.
func bash(units: Array, dt: float) -> Array[int]:
	var fallen: Array[int] = []
	for i in gates.size():
		var gate: Dictionary = gates[i]
		gate.hit = maxf(0.0, float(gate.hit) - dt)
		if gate.dead:
			continue
		if float(gate.hp) > 0.0 and not gate.open:
			var gap: Vector2 = gate.gap
			for unit: Unit in units:
				if unit.side != 0 or unit.dead or unit.gone or unit.fleeing or unit.group_kind == Config.GROUP_ARCHERS:
					continue
				var r := unit.collision_radius
				if unit.position.x < x and unit.position.x > x - half_width - r - Config.SIEGE_GATE_BASH_REACH and unit.position.y > gap.x - r and unit.position.y < gap.y + r:
					gate.hp = float(gate.hp) - unit.damage * Config.SIEGE_GATE_BASH_SHARE * dt
					gate.hit = Config.SIEGE_GATE_HIT_FLASH
		if float(gate.hp) <= 0.0:
			gate.hp = 0.0
			gate.dead = true
			revision += 1
			fallen.append(i)
	return fallen

## The garrison throws the main gate open (siegeBrain after 45 s). Returns false if it is already open or broken.
func open_main_gate() -> bool:
	if gates.is_empty() or gates[0].open or float(gates[0].hp) <= 0.0:
		return false
	gates[0].open = true
	revision += 1
	return true

func route(unit: Unit, destination: Vector2) -> Vector2:
	var side := -1.0 if unit.position.x < x else 1.0
	var destination_side := -1.0 if destination.x < x else 1.0
	if side == destination_side:
		return destination
	var spread := float((unit.id * Config.SIEGE_ROUTE_ID_FACTOR) % Config.SIEGE_ROUTE_ID_SPREAD)
	var open := gaps()
	if open.is_empty():
		# All gates shut: walk up to the nearest one and batter it.
		var nearest := Vector2.ZERO
		var nearest_cost := INF
		for gap in _gaps:
			var cost := absf((gap.x + gap.y) * 0.5 - unit.position.y) + spread
			if cost < nearest_cost:
				nearest_cost = cost
				nearest = gap
		return Vector2(x + side * (half_width + unit.collision_radius + 2.0), clampf(unit.position.y, nearest.x + unit.collision_radius, nearest.y - unit.collision_radius))
	var best_gap := Vector2.ZERO
	var best_cost := INF
	for gap in open:
		var center := (gap.x + gap.y) * 0.5
		var cost := absf(center - unit.position.y) + absf(center - destination.y) * Config.SIEGE_ROUTE_DESTINATION_WEIGHT + spread
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
