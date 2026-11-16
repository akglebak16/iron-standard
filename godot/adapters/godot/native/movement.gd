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
	# The native adapter consumes only these two packet slots after all validation succeeds.
	var packet := [columns.capacity, columns.positions, columns.velocities, columns.real_fields, columns.integer_fields, columns.vector_fields]
	columns.real_fields = PackedFloat64Array()
	columns.integer_fields = PackedInt64Array()
	var result: Array = _kernel.advance(packet, context, rng, dt, begin)
	if result.size() != 8:
		columns.real_fields = packet[3]
		columns.integer_fields = packet[4]
		return []
	columns.positions = result[3]
	columns.velocities = result[4]
	columns.real_fields = result[5]
	columns.integer_fields = result[6]
	columns.vector_fields = result[7]
	return result.slice(0, 3)
