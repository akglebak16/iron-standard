extends RefCounted
## Mutable broad phase for one simulation phase. Indices refer to State.units order.
## Coarse per-side cells for enemy searches; the collision pass has its own fine grid (collision_grid.gd).
## Results are identical to the plain loops they replace.
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")


var _units: Array[Unit]
var _cells: Array[Dictionary] = [{}, {}] # coarse, per side: Vector2i -> Array[int]
var _locations: Array[Vector2i] = []

func _init(units: Array[Unit], arena: Vector2 = Config.ARENA_SIZE) -> void:
	_units = units
	synchronize()

## Refresh after movement and append reinforcements without rebuilding buckets.
func synchronize() -> void:
	for index in _locations.size():
		update(index)
	for index in range(_locations.size(), _units.size()):
		var cell := _cell(_units[index].position)
		_locations.append(cell)
		_add(index, cell)

func update(index: int) -> void:
	var unit := _units[index]
	var cell := _cell(unit.position)
	var previous := _locations[index]
	if cell == previous:
		return
	var old_bucket: Array = _cells[unit.side][previous]
	old_bucket.erase(index)
	if old_bucket.is_empty():
		_cells[unit.side].erase(previous)
	_locations[index] = cell
	_add(index, cell)

func nearby(position: Vector2, radius: float, first_index: int) -> Array[int]:
	var found: Array[int] = []
	var lower := _cell(position - Vector2.ONE * radius)
	var upper := _cell(position + Vector2.ONE * radius)
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			var key := Vector2i(x, y)
			for side in 2:
				for index in _cells[side].get(key, []):
					if index >= first_index:
						found.append(index)
	found.sort() # Preserve the old pair order, including overlapping stacks.
	return found

func nearest_enemy(unit: Unit) -> Unit:
	var other_side := 1 - unit.side
	var best_index := -1
	var best_distance := INF
	for cell: Vector2i in _cells[other_side]:
		var left := cell.x * Config.SPATIAL_CELL_SIZE
		var top := cell.y * Config.SPATIAL_CELL_SIZE
		var dx := maxf(maxf(left - unit.position.x, unit.position.x - (left + Config.SPATIAL_CELL_SIZE)), 0.0)
		var dy := maxf(maxf(top - unit.position.y, unit.position.y - (top + Config.SPATIAL_CELL_SIZE)), 0.0)
		if dx * dx + dy * dy > best_distance:
			continue
		for index in _cells[other_side][cell]:
			var enemy: Unit = _units[index]
			if enemy.dead or enemy.gone:
				continue
			var distance := unit.position.distance_squared_to(enemy.position)
			if distance < best_distance or distance == best_distance and (best_index < 0 or index < best_index):
				best_distance = distance
				best_index = index
	return _units[best_index] if best_index >= 0 else null

## Same choice as Targeting.choose (weighted distance, lowest index on ties) without scanning far cells.
func best_target(unit: Unit, previous: Unit) -> Unit:
	var other_side := 1 - unit.side
	var cells: Dictionary = _cells[other_side]
	var melee_cavalry := unit.mounted and unit.attack_range <= 0.0
	# Only the current target is discounted, so it is weighed first and the bound for everyone else
	# uses the remaining multipliers (never below the cavalry-versus-archers one).
	var min_k := Config.CAVALRY_ARCHER_TARGET_MULTIPLIER if melee_cavalry else 1.0
	var home := _cell(unit.position)
	var size := Config.SPATIAL_CELL_SIZE
	var state := [-1, INF] # best index, best weighted distance
	if previous != null and not previous.dead and not previous.gone:
		var d := unit.position.distance_to(previous.position)
		if previous.fleeing:
			d *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and previous.attack_range > 0.0 and not previous.mounted:
			d *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		d *= Config.CURRENT_TARGET_MULTIPLIER
		state = [previous.battle_index, d]
	# Rings of cells around the unit while the next ring could still hold something closer; a far enemy
	# (armies still apart) falls back to one pruned pass over the occupied cells.
	var ring := 0
	while ring <= RING_LIMIT:
		if ring >= 2 and (ring - 1) * size * min_k > float(state[1]) + 1e-6:
			return _units[state[0]] if state[0] >= 0 else null
		if ring == 0:
			_scan_cell(cells, home, unit, previous, melee_cavalry, min_k, state)
		else:
			for dx in range(-ring, ring + 1):
				_scan_cell(cells, home + Vector2i(dx, -ring), unit, previous, melee_cavalry, min_k, state)
				_scan_cell(cells, home + Vector2i(dx, ring), unit, previous, melee_cavalry, min_k, state)
			for dy in range(-ring + 1, ring):
				_scan_cell(cells, home + Vector2i(-ring, dy), unit, previous, melee_cavalry, min_k, state)
				_scan_cell(cells, home + Vector2i(ring, dy), unit, previous, melee_cavalry, min_k, state)
		ring += 1
	# Far targets: scan the closest occupied cell first so the bound prunes the rest.
	var far: Array[Vector2i] = []
	var gaps := PackedFloat64Array()
	var nearest_cell := -1
	for cell: Vector2i in cells:
		if absi(cell.x - home.x) <= RING_LIMIT and absi(cell.y - home.y) <= RING_LIMIT:
			continue
		var left := cell.x * size
		var top := cell.y * size
		var gx := maxf(maxf(left - unit.position.x, unit.position.x - (left + size)), 0.0)
		var gy := maxf(maxf(top - unit.position.y, unit.position.y - (top + size)), 0.0)
		var gap := sqrt(gx * gx + gy * gy)
		if nearest_cell < 0 or gap < gaps[nearest_cell]:
			nearest_cell = far.size()
		far.append(cell)
		gaps.append(gap)
	if nearest_cell >= 0:
		_scan_cell(cells, far[nearest_cell], unit, previous, melee_cavalry, min_k, state)
	for k in far.size():
		if k != nearest_cell and gaps[k] * min_k <= float(state[1]) + 1e-6:
			_scan_cell(cells, far[k], unit, previous, melee_cavalry, min_k, state)
	return _units[state[0]] if state[0] >= 0 else null

const RING_LIMIT := 3

func _scan_cell(cells: Dictionary, cell: Vector2i, unit: Unit, previous: Unit, melee_cavalry: bool, min_k: float, state: Array) -> void:
	var bucket = cells.get(cell)
	if bucket == null:
		return
	var left := cell.x * Config.SPATIAL_CELL_SIZE
	var top := cell.y * Config.SPATIAL_CELL_SIZE
	var gx := maxf(maxf(left - unit.position.x, unit.position.x - (left + Config.SPATIAL_CELL_SIZE)), 0.0)
	var gy := maxf(maxf(top - unit.position.y, unit.position.y - (top + Config.SPATIAL_CELL_SIZE)), 0.0)
	var best: float = state[1]
	if sqrt(gx * gx + gy * gy) * min_k > best + 1e-6:
		return
	var best_index: int = state[0]
	for index in bucket:
		var enemy: Unit = _units[index]
		if enemy.dead or enemy.gone:
			continue
		var distance := unit.position.distance_to(enemy.position)
		if enemy.fleeing:
			distance *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and enemy.attack_range > 0.0 and not enemy.mounted:
			distance *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		if enemy == previous:
			distance *= Config.CURRENT_TARGET_MULTIPLIER
		if distance < best or distance == best and index < best_index:
			best = distance
			best_index = index
	state[0] = best_index
	state[1] = best

func _add(index: int, cell: Vector2i) -> void:
	var side: int = _units[index].side
	if not _cells[side].has(cell):
		_cells[side][cell] = []
	_cells[side][cell].append(index)

static func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / Config.SPATIAL_CELL_SIZE), floori(position.y / Config.SPATIAL_CELL_SIZE))
