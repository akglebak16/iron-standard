extends RefCounted
## Immutable-between-rebuilds obstacle centers; independent of the moving-unit grid.
## Stable obstacle order preserves the sequential constraint solver's semantics.
const CELL := 128.0
var _positions := PackedVector2Array()
var _radii := PackedFloat64Array()
var _cells: Dictionary = {}
var _max_radius := 0.0
var _candidates: Array[int] = []
var revision := 0

func rebuild(positions: PackedVector2Array, radii: PackedFloat64Array) -> void:
	assert(positions.size() == radii.size())
	_positions = positions.duplicate()
	_radii = radii.duplicate()
	_cells.clear()
	_max_radius = 0.0
	for i in positions.size():
		var cell := _cell(positions[i])
		if not _cells.has(cell): _cells[cell] = []
		_cells[cell].append(i)
		_max_radius = maxf(_max_radius, radii[i])
	revision += 1

func query_into(at: Vector2, radius: float, first: int, found: Array[int]) -> void:
	found.clear()
	var reach := Vector2.ONE * (radius + _max_radius)
	var lower := _cell(at - reach)
	var upper := _cell(at + reach)
	for y in range(lower.y, upper.y + 1):
		for x in range(lower.x, upper.x + 1):
			var cell := Vector2i(x, y)
			if not _cells.has(cell): continue
			for index in _cells[cell]:
				if index >= first: found.append(index)
	if found.size() > 1: found.sort()

func constrain(at: Vector2, radius: float) -> Vector2:
	var first := 0
	while first < _positions.size():
		query_into(at, radius, first, _candidates)
		var moved := false
		for index in _candidates:
			first = index + 1
			var reach := radius + _radii[index]
			var offset := at - _positions[index]
			var distance_squared := offset.length_squared()
			if distance_squared >= reach * reach: continue
			var normal := Vector2.RIGHT if distance_squared == 0.0 else offset / sqrt(distance_squared)
			at = _positions[index] + normal * reach
			# A push can introduce a later contact outside the original query.
			moved = true
			break
		if not moved: break
	return at

static func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))
