extends RefCounted
## Context-scoped 64-bit handles. Zero is invalid; slots never wrap generations.
## Dense indices can move without changing identity. No domain objects are retained.
const MAX_GENERATION := 0x7fffffff
const SLOT_MASK := 0xffffffff
var _generations := PackedInt32Array()
var _indices := PackedInt32Array()
var _slots := PackedInt32Array()
var _free: Array[int] = []
var _active := 0

func size() -> int: return _active

func allocate(index: int) -> int:
	if index < 0 or handle_at(index) != 0: return 0
	_grow(index)
	var slot: int
	if _free.is_empty():
		slot = _indices.size()
		_indices.append(-1)
		_generations.append(1)
	else:
		slot = _free.pop_back()
	_indices[slot] = index
	_slots[index] = slot
	_active += 1
	return (_generations[slot] << 32) | (slot + 1)

func resolve(handle: int) -> int:
	if handle <= 0: return -1
	var slot := (handle & SLOT_MASK) - 1
	if slot < 0 or slot >= _indices.size() or _generations[slot] != handle >> 32: return -1
	return _indices[slot]

func handle_at(index: int) -> int:
	if index < 0 or index >= _slots.size(): return 0
	var slot := _slots[index]
	return 0 if slot < 0 else (_generations[slot] << 32) | (slot + 1)

func release(handle: int) -> bool:
	var index := resolve(handle)
	if index < 0: return false
	var slot := _slots[index]
	_slots[index] = -1
	_indices[slot] = -1
	_active -= 1
	if _generations[slot] < MAX_GENERATION:
		_generations[slot] += 1
		_free.append(slot)
	return true

func relocate(handle: int, destination: int) -> bool:
	var index := resolve(handle)
	if index < 0 or destination < 0: return false
	if index == destination: return true
	if handle_at(destination) != 0: return false
	_grow(destination)
	var slot := _slots[index]
	_slots[index] = -1
	_slots[destination] = slot
	_indices[slot] = destination
	return true

func _grow(index: int) -> void:
	var previous := _slots.size()
	if index < previous: return
	_slots.resize(index + 1)
	for i in range(previous, index + 1): _slots[i] = -1
