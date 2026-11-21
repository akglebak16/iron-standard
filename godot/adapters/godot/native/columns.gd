extends "res://core/battle/api/column_backend.gd"
var _kernel: RefCounted
static func create() -> RefCounted:
	if not ClassDB.class_exists("IronColumnKernel"): return null
	var port = new()
	port._kernel = ClassDB.instantiate("IronColumnKernel")
	return port
static func _values(columns: RefCounted) -> Array:
	return [columns.capacity, columns.positions, columns.velocities, columns.real_fields, columns.integer_fields, columns.vector_fields]
func retired_rows(columns: RefCounted) -> PackedInt32Array:
	return _kernel.retired_rows(_values(columns))
func drop_rows(columns: RefCounted, retired: PackedInt32Array) -> void:
	# Synchronous ownership handoff, as in movement.gd (#298): every column leaves the store, so the native
	# adapter is its only owner and compacts it in place without a copy-on-write copy (#322). A rejection
	# leaves the packet slots untouched and the columns go back unchanged.
	var packet := _values(columns)
	columns.positions = PackedVector2Array()
	columns.velocities = PackedVector2Array()
	columns.real_fields = PackedFloat64Array()
	columns.integer_fields = PackedInt64Array()
	columns.vector_fields = PackedVector2Array()
	var out: Array = _kernel.drop_rows(packet, retired)
	if out.size() != 5:
		columns.positions = packet[1]
		columns.velocities = packet[2]
		columns.real_fields = packet[3]
		columns.integer_fields = packet[4]
		columns.vector_fields = packet[5]
		assert(false, "native storage compaction rejected its rows")
		return
	columns.positions = out[0]
	columns.velocities = out[1]
	columns.real_fields = out[2]
	columns.integer_fields = out[3]
	columns.vector_fields = out[4]
func capture(columns: RefCounted, previous: PackedVector2Array) -> PackedVector2Array:
	return _kernel.capture(_values(columns), previous)
func summary(columns: RefCounted) -> Array:
	return _kernel.summary(_values(columns))
func wall_status(columns: RefCounted, inside_x: float, alert_x: float, defender_x: float) -> Array:
	return _kernel.wall_status(_values(columns), inside_x, alert_x, defender_x)
func render(columns: RefCounted, previous: PackedVector2Array, special_flags: PackedInt32Array, definitions: Array[Dictionary]) -> Array:
	return _kernel.render(_values(columns), previous, special_flags, definitions)
func nearby(columns: RefCounted, position: Vector2, radius: float) -> PackedInt32Array:
	return _kernel.nearby(_values(columns), position, radius)
func nearest_ready(columns: RefCounted, position: Vector2, side: int) -> float:
	return _kernel.nearest_ready(_values(columns), position, side)

func densest_ready(columns: RefCounted, side: int, low_x: float, high_x: float, half: float, arena: Vector2, cell: float) -> PackedInt32Array:
	return _kernel.densest_ready(_values(columns), side, low_x, high_x, half, arena, cell)

func projectile_candidates(columns: RefCounted, impacts: PackedVector2Array, arena: Vector2, padding: float, height: float, cell: float) -> Array:
	return _kernel.projectile_candidates(_values(columns), impacts, arena, padding, height, cell)

func terrain_cells(cover: PackedByteArray, elevation: PackedByteArray, width: int, cell: float, points: PackedVector2Array) -> PackedInt32Array:
	return _kernel.terrain_cells(cover, elevation, width, cell, points)
