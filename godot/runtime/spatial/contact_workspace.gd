extends RefCounted
## Reused columns for a contact pass. Owned by one simulation context, never a view.
var positions := PackedVector2Array()
var velocities := PackedVector2Array()
var fleeing := PackedByteArray()
var radii := PackedFloat64Array()
var masses := PackedFloat64Array()
var sides := PackedInt32Array()
var live := PackedByteArray()

func resize(count: int) -> void:
	if positions.size() == count: return
	positions.resize(count)
	velocities.resize(count)
	fleeing.resize(count)
	radii.resize(count)
	masses.resize(count)
	sides.resize(count)
	live.resize(count)
