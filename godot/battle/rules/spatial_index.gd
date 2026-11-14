extends RefCounted
## Mutable broad phase for one simulation phase. Indices refer to State.units order.
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")

var _units: Array[Unit]
var _cells: Array[Dictionary] = [{}, {}]
var _locations: Array[Vector2i] = []

func _init(units: Array[Unit]) -> void:
	_units = units
	for index in units.size():
		var cell := _cell(units[index].position)
		_locations.append(cell)
		_add(index, cell)

func update(index: int) -> void:
	var cell := _cell(_units[index].position)
	var previous := _locations[index]
	if cell == previous:
		return
	var old_bucket: Array = _cells[_units[index].side][previous]
	old_bucket.erase(index)
	if old_bucket.is_empty():
		_cells[_units[index].side].erase(previous)
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

func _add(index: int, cell: Vector2i) -> void:
	var side: int = _units[index].side
	if not _cells[side].has(cell):
		_cells[side][cell] = []
	_cells[side][cell].append(index)

static func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / Config.SPATIAL_CELL_SIZE), floori(position.y / Config.SPATIAL_CELL_SIZE))
