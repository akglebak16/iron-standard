extends RefCounted
## Optional pure column operations; injected by the composition root.
## State.compact_inactive (#322): rows of the dead and gone, ascending; then a stable compaction without them.
func retired_rows(_columns: RefCounted) -> PackedInt32Array: return PackedInt32Array()
func drop_rows(_columns: RefCounted, _retired: PackedInt32Array) -> void: pass
func capture(_columns: RefCounted, previous: PackedVector2Array) -> PackedVector2Array: return previous
func summary(_columns: RefCounted) -> Array: return []
func wall_status(_columns: RefCounted, _inside_x: float, _alert_x: float, _defender_x: float) -> Array: return []
func render(_columns: RefCounted, _previous: PackedVector2Array, _special_flags: PackedInt32Array, _definitions: Array[Dictionary]) -> Array: return []
func nearby(_columns: RefCounted, _position: Vector2, _radius: float) -> PackedInt32Array: return PackedInt32Array()
func nearest_ready(_columns: RefCounted, _position: Vector2, _side: int) -> float: return INF
func densest_ready(_columns: RefCounted, _side: int, _low_x: float, _high_x: float, _half: float, _arena: Vector2, _cell: float) -> PackedInt32Array: return PackedInt32Array()

func projectile_candidates(_columns: RefCounted, _impacts: PackedVector2Array, _arena: Vector2, _padding: float, _height: float, _cell: float) -> Array: return []
## TERRAIN.md 3.4: the terrain grid read by the native reader at `points` (cover | height << 8); empty without one.
func terrain_cells(_cover: PackedByteArray, _elevation: PackedByteArray, _width: int, _cell: float, _points: PackedVector2Array) -> PackedInt32Array: return PackedInt32Array()
