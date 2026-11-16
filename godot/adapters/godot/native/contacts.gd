extends RefCounted
## One port instance per battle. Only detached value columns cross this boundary.
var _kernel: RefCounted
var _geometry: Dictionary = {}

static func create() -> Callable:
	if not ClassDB.class_exists("IronContactKernel"):
		return Callable()
	var port = new()
	port._kernel = ClassDB.instantiate("IronContactKernel")
	# Bound Callables do not retain RefCounted targets; capture the port explicitly.
	return func(columns: RefCounted, geometry: Dictionary) -> Array: return port.solve(columns, geometry)

func solve(columns: RefCounted, geometry: Dictionary) -> Array:
	if not is_same(_geometry, geometry):
		if not _kernel.configure(geometry.parameters, geometry.positions, geometry.radii, geometry.gaps):
			return []
		_geometry = geometry
	return _kernel.solve_columns(columns.positions, columns.velocities, columns.capacity, columns.real_fields, columns.integer_fields)
