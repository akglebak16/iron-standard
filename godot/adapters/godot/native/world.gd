extends RefCounted
## Port of the native campaign world kernel (ADR-025): the threat-map stamp and the contact pairs of the world step.
## create() returns null without the library; the GDScript code (ThreatMap.rebuild, PartyAI.step) stays the reference.
## Counters let benchmarks and tests prove the native path ran and never fell back.
var _kernel: RefCounted
var stamps := 0
var pair_calls := 0
var failures := 0

static func create() -> RefCounted:
	if not ClassDB.class_exists("IronWorldKernel"):
		return null
	var port = new()
	port._kernel = ClassDB.instantiate("IronWorldKernel")
	return port

## [grids, stamped cells, sources] or [] (the caller then stamps in GDScript).
func stamp(xs: PackedFloat64Array, ys: PackedFloat64Array, strengths: PackedFloat64Array, layers: PackedInt32Array, layer_count: int, cols: int, rows: int, cell: float, radius: float) -> Array:
	var out: Array = _kernel.stamp(xs, ys, strengths, layers, layer_count, cols, rows, cell, radius)
	if out.size() != 3 or (out[0] as Array).size() != layer_count:
		failures += 1
		return []
	stamps += 1
	return out

## Flat [i, j, ...] of pairs closer than `reach`, in the order of the reference double loop.
func contact_pairs(xs: PackedFloat64Array, ys: PackedFloat64Array, reach: float) -> PackedInt32Array:
	pair_calls += 1
	return _kernel.contact_pairs(xs, ys, reach)
