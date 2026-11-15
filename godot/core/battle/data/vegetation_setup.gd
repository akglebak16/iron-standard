extends RefCounted

const Plant = preload("res://core/battle/model/plant.gd")
const TREE_ATTEMPTS := {"steppe": 5, "arid": 7}
const DEFAULT_TREE_ATTEMPTS := 15
const BUSH_ATTEMPTS := 16
const TREE_VARIANTS := 3
const BUSH_VARIANTS := 2
const TRUNK_RADIUS := 15.0
const EDGE_MARGIN := Vector2(80, 60)
const FORMATION_CLEARANCE := 330.0
const SIEGE_CLEARANCE := 140.0
const UINT32_MASK := 0xffffffff
const UINT16_MASK := 0xffff
const HALF_WORD_BITS := 16
const UINT32_RANGE := 4294967296.0
const MULBERRY_STEP := 0x6d2b79f5

static func create(size: Vector2, seed_value: int, biome: String, wall_x: float = INF) -> Array[Plant]:
	var plants: Array[Plant] = []
	var state := seed_value & UINT32_MASK
	var tree_count: int = TREE_ATTEMPTS.get(biome, DEFAULT_TREE_ATTEMPTS)
	for i in tree_count + BUSH_ATTEMPTS:
		state = (state + MULBERRY_STEP) & UINT32_MASK
		var x := _mulberry_value(state)
		state = (state + MULBERRY_STEP) & UINT32_MASK
		var point := EDGE_MARGIN + Vector2(x, _mulberry_value(state)) * (size - EDGE_MARGIN * 2.0)
		var tree := i < tree_count
		if point.x >= wall_x - SIEGE_CLEARANCE:
			continue
		if tree and absf(point.y - size.y * 0.5) < FORMATION_CLEARANCE and point.x > FORMATION_CLEARANCE and point.x < size.x - FORMATION_CLEARANCE:
			continue
		plants.append(Plant.new(point, TRUNK_RADIUS if tree else 0.0, i % (TREE_VARIANTS if tree else BUSH_VARIANTS)))
	return plants

## Compatibility with the uint32 Mulberry sampler used for placement in startBattle.
static func _mulberry_value(state: int) -> float:
	var mixed := _imul(state ^ (state >> 15), state | 1)
	mixed ^= (mixed + _imul(mixed ^ (mixed >> 7), mixed | 61)) & UINT32_MASK
	return float(mixed ^ (mixed >> 14)) / UINT32_RANGE

static func _imul(a: int, b: int) -> int:
	var low_a := a & UINT16_MASK
	var low_b := b & UINT16_MASK
	var middle := ((a >> HALF_WORD_BITS) * low_b + (b >> HALF_WORD_BITS) * low_a) & UINT16_MASK
	return (low_a * low_b + (middle << HALF_WORD_BITS)) & UINT32_MASK
