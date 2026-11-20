extends RefCounted
const Parameters = preload("res://core/battle/api/movement_parameters.gd")
var _kernel: RefCounted
static func create() -> Callable:
	if not ClassDB.class_exists("IronMovementKernel"): return Callable()
	var port = new()
	port._kernel = ClassDB.instantiate("IronMovementKernel")
	if not port._kernel.configure(Parameters.values()): return Callable()
	return func(columns: RefCounted, context: Dictionary, rng: RandomNumberGenerator, dt: float, begin: bool) -> Array:
		return port.advance(columns, context, rng, dt, begin)
func advance(columns: RefCounted, context: Dictionary, rng: RandomNumberGenerator, dt: float, begin: bool) -> Array:
	# Synchronous ownership handoff: no rule/observer runs until the complete columns return.
	# Every column leaves the store, so the native adapter is its only owner and writes it in place
	# without a copy-on-write copy (#298). The adapter consumes the packet slots only after all
	# validation succeeds; on a rejection they are still here and go back unchanged.
	var packet := [columns.capacity, columns.positions, columns.velocities, columns.real_fields, columns.integer_fields, columns.vector_fields]
	columns.positions = PackedVector2Array()
	columns.velocities = PackedVector2Array()
	columns.real_fields = PackedFloat64Array()
	columns.integer_fields = PackedInt64Array()
	columns.vector_fields = PackedVector2Array()
	var result: Array = _kernel.advance(packet, context, rng, dt, begin)
	if result.size() != 8:
		columns.positions = packet[1]
		columns.velocities = packet[2]
		columns.real_fields = packet[3]
		columns.integer_fields = packet[4]
		columns.vector_fields = packet[5]
		return []
	columns.positions = result[3]
	columns.velocities = result[4]
	columns.real_fields = result[5]
	columns.integer_fields = result[6]
	columns.vector_fields = result[7]
	return result.slice(0, 3)
