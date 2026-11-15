extends RefCounted
## Detached render values. Lifetime: retained by the consumer, never recycled by simulation.
## Columns are returned as explicit copies; definitions are recursively read-only.
## No Unit/State references cross this boundary. Internal fields are writer-only.
const DEAD := 1
const GONE := 2
const HERO := 4
const COMPANION := 8
const MOUNTED := 16
const FLEEING := 32
const BLOCKING := 64
const LEADER := 128

var _render_positions := PackedVector2Array()
var _render_previous := PackedVector2Array()
var _render_flags := PackedInt32Array()
var _render_sides := PackedInt32Array()
var _render_groups := PackedInt32Array()
var _render_dynamic := PackedFloat64Array() # radius, health fraction, facing, speed, windup
var _render_definitions: Array[Dictionary] = []
const STRIDE := 5

func size() -> int: return _render_positions.size()
func positions() -> PackedVector2Array: return _render_positions.duplicate()
func previous_positions() -> PackedVector2Array: return _render_previous.duplicate()
func flags() -> PackedInt32Array: return _render_flags.duplicate()
func sides() -> PackedInt32Array: return _render_sides.duplicate()

## Materialize only visible figures / named speakers. Caller owns this mutable drawing record.
func unit_at(index: int, interpolation: float = 1.0) -> Dictionary:
	var unit := _render_definitions[index].duplicate()
	var bits := _render_flags[index]
	var offset := index * STRIDE
	unit.position = _render_previous[index].lerp(_render_positions[index], interpolation)
	unit.previous_position = _render_previous[index]
	unit.radius = _render_dynamic[offset]
	unit.health_fraction = _render_dynamic[offset + 1]
	unit.facing = _render_dynamic[offset + 2]
	unit.speed = _render_dynamic[offset + 3]
	unit.windup = _render_dynamic[offset + 4]
	unit.group_kind = _render_groups[index]
	unit.dead = bool(bits & DEAD)
	unit.gone = bool(bits & GONE)
	unit.mounted = bool(bits & MOUNTED)
	unit.fleeing = bool(bits & FLEEING)
	unit.blocking = bool(bits & BLOCKING)
	unit.leader = bool(bits & LEADER)
	return unit

static func freeze(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: freeze(child)
		value.make_read_only()
