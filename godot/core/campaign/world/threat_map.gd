extends RefCounted
## Campaign threat map, an influence map (docs/modules/ai/DESIGN.md §5.1, ADR-023): every party stamps its strength
## on a grid over the map, fading linearly to zero at `radius`, one layer per faction.
## Derived data only: rebuilt from parties, never saved, spends no RNG. No AI decision reads it yet.
## Cost of a rebuild is linear in the number of parties: each one touches a fixed square of cells.
const Config = preload("res://core/campaign/config.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const SCORE_EPSILON := 0.0001

var width := 5200.0
var height := 3400.0
var cell_size := Config.THREAT_CELL_SIZE
var radius := Config.THREAT_RADIUS
var cols := 1
var rows := 1
var layers: Dictionary = {}  # faction -> PackedFloat32Array(cols * rows)
var stamped_cells := 0       # cells visited by the last rebuild
var sources := 0             # parties stamped by the last rebuild
var built_hour := -1         # world hour of the last rebuild, -1 before the first

func _init(map_width := 5200.0, map_height := 3400.0, cell := Config.THREAT_CELL_SIZE, fade_radius := Config.THREAT_RADIUS) -> void:
	width = map_width
	height = map_height
	cell_size = maxf(1.0, cell)
	radius = maxf(cell_size * 0.5, fade_radius)
	cols = maxi(1, ceili(width / cell_size))
	rows = maxi(1, ceili(height / cell_size))

## Replaces every layer. sources: [{fac: String, x: float, y: float, strength: float}]; non-positive strength is skipped.
## Parties are grouped by faction first, so each layer is written in one local array.
func rebuild(list: Array, hour := -1) -> void:
	var by_faction := {}
	for s in list:
		if float(s.strength) <= 0.0:
			continue
		var f := String(s.fac)
		if not by_faction.has(f):
			by_faction[f] = []
		by_faction[f].append(s)
	layers = {}
	stamped_cells = 0
	sources = 0
	var keys := by_faction.keys()
	keys.sort()
	for f in keys:
		var grid := PackedFloat32Array()
		grid.resize(cols * rows)
		for s in by_faction[f]:
			_stamp(grid, float(s.x), float(s.y), float(s.strength))
			sources += 1
		layers[f] = grid
	built_hour = hour

## rebuild() that rests between parties when the world slice budget (slicer, SliceBudget) is spent; the caller awaits it.
## The layers are swapped in at the end, so nobody sees a half-built map. Keep the two in step with each other.
func rebuild_co(list: Array, hour: int, slicer) -> void:
	var by_faction := {}
	for s in list:
		if float(s.strength) <= 0.0:
			continue
		var f := String(s.fac)
		if not by_faction.has(f):
			by_faction[f] = []
		by_faction[f].append(s)
	var fresh := {}
	var cells := 0
	var count := 0
	var keys := by_faction.keys()
	keys.sort()
	for f in keys:
		var grid := PackedFloat32Array()
		grid.resize(cols * rows)
		for s in by_faction[f]:
			cells += _stamp(grid, float(s.x), float(s.y), float(s.strength))
			count += 1
			if slicer != null and slicer.due():
				await slicer.next_frame()
		fresh[f] = grid
	layers = fresh
	stamped_cells = cells
	sources = count
	built_hour = hour

func _stamp(grid: PackedFloat32Array, x: float, y: float, strength: float) -> int:
	var c0 := maxi(0, floori((x - radius) / cell_size))
	var c1 := mini(cols - 1, floori((x + radius) / cell_size))
	var r0 := maxi(0, floori((y - radius) / cell_size))
	var r1 := mini(rows - 1, floori((y + radius) / cell_size))
	for cy in range(r0, r1 + 1):
		var dy := (cy + 0.5) * cell_size - y
		var row := cy * cols
		for cx in range(c0, c1 + 1):
			var dx := (cx + 0.5) * cell_size - x
			var d := sqrt(dx * dx + dy * dy)
			if d < radius:
				grid[row + cx] += strength * (1.0 - d / radius)
	var visited := (c1 - c0 + 1) * (r1 - r0 + 1)
	stamped_cells += visited
	return visited

func factions() -> Array:
	var keys := layers.keys()
	keys.sort()
	return keys

func cell_index(x: float, y: float) -> int:
	var cx := clampi(floori(x / cell_size), 0, cols - 1)
	var cy := clampi(floori(y / cell_size), 0, rows - 1)
	return cy * cols + cx

func cell_center(i: int) -> Vector2:
	return Vector2((i % cols + 0.5) * cell_size, (i / cols + 0.5) * cell_size)

func _value(fac: String, i: int) -> float:
	var grid: Variant = layers.get(fac)
	return 0.0 if grid == null else float(grid[i])

## Strength of one faction felt at a point.
func influence(fac: String, x: float, y: float) -> float:
	return _value(fac, cell_index(x, y))

## Summed strength of the given enemy factions at a point.
func threat(x: float, y: float, enemies: Array) -> float:
	return _threat_at(cell_index(x, y), enemies)

func _threat_at(i: int, enemies: Array) -> float:
	var total := 0.0
	for f in enemies:
		total += _value(String(f), i)
	return total

## Factions on the map hostile to `fac`; hostile(a, b) -> bool. Sorted, so queries stay deterministic.
func enemies_of(fac: String, hostile: Callable) -> Array:
	var out: Array = []
	for f in factions():
		if f != fac and hostile.call(fac, f):
			out.append(f)
	return out

## Faction-level hostility used by the map (Rules.hostile without party kinds): the dead and bandits fight everyone,
## the player is hostile to states whose relation is below HOSTILE_BELOW, states follow the current wars.
static func factions_hostile(a: String, b: String, wars: Variant, player_rel: Dictionary) -> bool:
	if a == b:
		return false
	if a == Config.UNDEAD_FACTION or b == Config.UNDEAD_FACTION:
		return true
	if a == Config.BANDIT_FACTION or b == Config.BANDIT_FACTION:
		return true
	if a == Config.PLAYER_FACTION or b == Config.PLAYER_FACTION:
		var other := b if a == Config.PLAYER_FACTION else a
		return float(player_rel.get(other, 0)) < Config.HOSTILE_BELOW
	return Rules.at_war(a, b, wars)

## Safest cell centre within `search_radius` of (x, y) for faction `own`: least enemy threat minus own strength,
## plus THREAT_HAVEN_COST per unit of distance to the nearest haven (own settlements: [Vector2]).
## accept(Vector2) -> bool may reject cells (sea, impassable). Equal scores prefer the cell nearest to (x, y).
## Returns (x, y) itself when nothing is accepted.
func safe_cell(x: float, y: float, search_radius: float, own: String, enemies: Array, havens: Array, accept := Callable()) -> Vector2:
	var best := Vector2(x, y)
	var best_score := INF
	var best_step := INF
	var c0 := maxi(0, floori((x - search_radius) / cell_size))
	var c1 := mini(cols - 1, floori((x + search_radius) / cell_size))
	var r0 := maxi(0, floori((y - search_radius) / cell_size))
	var r1 := mini(rows - 1, floori((y + search_radius) / cell_size))
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			var i := cy * cols + cx
			var c := cell_center(i)
			if c.distance_to(Vector2(x, y)) > search_radius:
				continue
			if accept.is_valid() and not accept.call(c):
				continue
			var score := _threat_at(i, enemies) - _value(own, i)
			if not havens.is_empty():
				var near := INF
				for h in havens:
					near = minf(near, c.distance_to(h))
				score += near * Config.THREAT_HAVEN_COST
			var step := c.distance_to(Vector2(x, y))
			if score < best_score - SCORE_EPSILON or (score <= best_score + SCORE_EPSILON and step < best_step):
				best_score = score
				best_step = step
				best = c
	return best

## Front between factions a and b: cells where both are present and neither outweighs the other more than 3:1.
func front(a: String, b: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ga: Variant = layers.get(a)
	var gb: Variant = layers.get(b)
	if ga == null or gb == null:
		return out
	for i in cols * rows:
		var va := float(ga[i])
		var vb := float(gb[i])
		if va >= Config.THREAT_FRONT_MIN and vb >= Config.THREAT_FRONT_MIN and absf(va - vb) <= Config.THREAT_FRONT_BALANCE * (va + vb):
			out.append(cell_center(i))
	return out
