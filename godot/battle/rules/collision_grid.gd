extends RefCounted
## Fine uniform grid over packed positions for the collision pass (Movement._resolve_unit_collisions).
## Plain Arrays per cell: packed arrays inside an Array are copied on element access.
const PAD := 480.0
const CELL := 40.0 # >= 2 * HORSE_COLLISION_RADIUS

var _cells: Array = []
var _at := PackedInt32Array()
var _w := 0
var _h := 0

func _init(pos: PackedVector2Array, arena: Vector2) -> void:
	_w = ceili((arena.x + PAD * 2.0) / CELL) + 1
	_h = ceili((arena.y + PAD * 2.0) / CELL) + 1
	_cells.resize(_w * _h) # cells stay null until used: allocating thousands of empty arrays per tick costs more than the pass
	_at.resize(pos.size())
	for i in pos.size():
		var c := _cell(pos[i])
		_at[i] = c
		_put(i, c)

func move(i: int, p: Vector2) -> void:
	var c := _cell(p)
	var old := _at[i]
	if c == old:
		return
	var bucket: Array = _cells[old]
	bucket.remove_at(bucket.find(i))
	_put(i, c)
	_at[i] = c

## Indices >= first in the cells touching the square around p, in index order.
func query(p: Vector2, r: float, first: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	var x0 := clampi(floori((p.x - r + PAD) / CELL), 0, _w - 1)
	var x1 := clampi(floori((p.x + r + PAD) / CELL), 0, _w - 1)
	var y0 := clampi(floori((p.y - r + PAD) / CELL), 0, _h - 1)
	var y1 := clampi(floori((p.y + r + PAD) / CELL), 0, _h - 1)
	for y in range(y0, y1 + 1):
		var row := y * _w
		for x in range(x0, x1 + 1):
			var bucket = _cells[row + x]
			if bucket == null:
				continue
			for i in bucket:
				if i >= first:
					found.append(i)
	if found.size() > 1:
		found.sort()
	return found

func _put(i: int, c: int) -> void:
	var bucket = _cells[c]
	if bucket == null:
		_cells[c] = [i]
	else:
		bucket.append(i)

func _cell(p: Vector2) -> int:
	return clampi(floori((p.y + PAD) / CELL), 0, _h - 1) * _w + clampi(floori((p.x + PAD) / CELL), 0, _w - 1)
