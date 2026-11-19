extends RefCounted
## Mutable broad phase for one simulation phase. Indices refer to State.active_units order.
## Coarse per-side cells for enemy searches; the collision pass has its own fine grid (collision_grid.gd).
## Results are identical to the plain loops they replace.
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const MotionStore = preload("res://runtime/simulation/motion_store.gd")
const TerrainRules = preload("res://core/battle/rules/terrain_rules.gd")


var _units: Array[Unit]
var _motion: MotionStore
var _positions := PackedVector2Array()
var _cells: Array[Dictionary] = [{}, {}] # coarse, per side: Vector2i -> Array[int]
var _locations: Array[Vector2i] = []
var _target_best: Array = [-1, INF]
var _far_cells: Array[Vector2i] = []
var _far_gaps := PackedFloat64Array()
var _spare_buckets: Array[Array] = []
## State.terrain_rules for best_target (TERRAIN.md 4.4: a shooter does not see far into the forest); null in the open.
var terrain = null

func _init(units: Array[Unit], arena: Vector2 = Config.ARENA_SIZE, motion: MotionStore = null) -> void:
	_units = units
	_motion = motion
	synchronize()

## Dense indices changed; reuse the allocated buckets for the new ordering.
func rebuild() -> void:
	for cells in _cells:
		for bucket in cells.values():
			bucket.clear()
			_spare_buckets.append(bucket)
		cells.clear()
	_locations.clear()
	synchronize()

## Refresh after movement and append reinforcements without rebuilding buckets.
func synchronize() -> void:
	if _motion != null: _positions = _motion.positions
	for index in _locations.size():
		update(index)
	for index in range(_locations.size(), _units.size()):
		var cell := _cell(_positions[index] if _motion != null else _units[index].position)
		_locations.append(cell)
		_add(index, cell)

func update(index: int) -> void:
	var unit := _units[index]
	var cell := _cell(_positions[index] if _motion != null else unit.position)
	var previous := _locations[index]
	if cell == previous:
		return
	var old_bucket: Array = _cells[unit.side][previous]
	old_bucket.erase(index)
	if old_bucket.is_empty():
		_cells[unit.side].erase(previous)
		_spare_buckets.append(old_bucket)
	_locations[index] = cell
	_add(index, cell)

func nearby(position: Vector2, radius: float, first_index: int) -> Array[int]:
	var found: Array[int] = []
	nearby_into(position, radius, first_index, found)
	return found

func nearby_into(position: Vector2, radius: float, first_index: int, found: Array[int]) -> void:
	found.clear()
	var lower := _cell(position - Vector2.ONE * radius)
	var upper := _cell(position + Vector2.ONE * radius)
	for x in range(lower.x, upper.x + 1):
		for y in range(lower.y, upper.y + 1):
			var key := Vector2i(x, y)
			for side in 2:
				if not _cells[side].has(key): continue
				for index in _cells[side][key]:
					if index >= first_index:
						found.append(index)
	found.sort() # Preserve the old pair order, including overlapping stacks.

func nearest_enemy(unit: Unit) -> Unit:
	var at := unit.position
	var other_side := 1 - unit.side
	var best_index := -1
	var best_distance := INF
	for cell: Vector2i in _cells[other_side]:
		var left := cell.x * Config.SPATIAL_CELL_SIZE
		var top := cell.y * Config.SPATIAL_CELL_SIZE
		var dx := maxf(maxf(left - at.x, at.x - (left + Config.SPATIAL_CELL_SIZE)), 0.0)
		var dy := maxf(maxf(top - at.y, at.y - (top + Config.SPATIAL_CELL_SIZE)), 0.0)
		if dx * dx + dy * dy > best_distance:
			continue
		for index in _cells[other_side][cell]:
			var enemy: Unit = _units[index]
			if enemy.dead or enemy.gone:
				continue
			var distance := at.distance_squared_to(_positions[index] if _motion != null else enemy.position)
			if distance < best_distance or distance == best_distance and (best_index < 0 or index < best_index):
				best_distance = distance
				best_index = index
	return _units[best_index] if best_index >= 0 else null

## Same choice as Targeting.choose (weighted distance, lowest index on ties) without scanning far cells.
## The stage 1a melee and ranged weights only raise distances, so the bounds below (the smallest older multiplier)
## still hold; so does skipping an enemy hidden in the forest (stage Р1а), checked only for a candidate that would win.
func best_target(unit: Unit, previous: Unit) -> Unit:
	var at := unit.position
	var other_side := 1 - unit.side
	var cells: Dictionary = _cells[other_side]
	var melee_cavalry := unit.mounted and unit.attack_range <= 0.0
	var melee := unit.attack_range <= 0.0
	var own_speed := unit.speed
	var own_id := unit.id
	var own_damage := unit.damage
	# Only the current target is discounted, so it is weighed first and the bound for everyone else
	# uses the remaining multipliers (never below the cavalry-versus-archers one).
	var min_k := Config.CAVALRY_ARCHER_TARGET_MULTIPLIER if melee_cavalry else 1.0
	var home := _cell(at)
	var size := Config.SPATIAL_CELL_SIZE
	var state := _target_best # One synchronous query at a time in this context.
	state[0] = -1
	state[1] = INF
	if previous != null and not previous.dead and not previous.gone and (melee or terrain == null or not TerrainRules.hidden(terrain, previous.position, at.distance_to(previous.position))):
		var raw := at.distance_to(previous.position)
		var d := raw
		if previous.fleeing:
			d *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and previous.attack_range > 0.0 and not previous.mounted:
			d *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		d *= Config.CURRENT_TARGET_MULTIPLIER
		if melee:
			d = melee_weight(d, raw, at, own_speed, previous, previous.position, true, melee_cavalry)
		else:
			d = ranged_weight(d, own_id, own_damage, previous, true)
		state[0] = previous.battle_index
		state[1] = d
	# Rings of cells around the unit while the next ring could still hold something closer; a far enemy
	# (armies still apart) falls back to one pruned pass over the occupied cells.
	var ring := 0
	while ring <= RING_LIMIT:
		if ring >= 2 and (ring - 1) * size * min_k > float(state[1]) + 1e-6:
			return _units[state[0]] if state[0] >= 0 else null
		if ring == 0:
			_scan_cell(cells, home, at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
		else:
			for dx in range(-ring, ring + 1):
				_scan_cell(cells, home + Vector2i(dx, -ring), at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
				_scan_cell(cells, home + Vector2i(dx, ring), at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
			for dy in range(-ring + 1, ring):
				_scan_cell(cells, home + Vector2i(-ring, dy), at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
				_scan_cell(cells, home + Vector2i(ring, dy), at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
		ring += 1
	# Far targets: scan the closest occupied cell first so the bound prunes the rest.
	var far := _far_cells
	var gaps := _far_gaps
	if far.size() < cells.size():
		far.resize(cells.size())
		gaps.resize(cells.size())
	var far_count := 0
	var nearest_cell := -1
	for cell: Vector2i in cells:
		if absi(cell.x - home.x) <= RING_LIMIT and absi(cell.y - home.y) <= RING_LIMIT:
			continue
		var left := cell.x * size
		var top := cell.y * size
		var gx := maxf(maxf(left - at.x, at.x - (left + size)), 0.0)
		var gy := maxf(maxf(top - at.y, at.y - (top + size)), 0.0)
		var gap := sqrt(gx * gx + gy * gy)
		if nearest_cell < 0 or gap < gaps[nearest_cell]:
			nearest_cell = far_count
		far[far_count] = cell
		gaps[far_count] = gap
		far_count += 1
	if nearest_cell >= 0:
		_scan_cell(cells, far[nearest_cell], at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
	for k in far_count:
		if k != nearest_cell and gaps[k] * min_k <= float(state[1]) + 1e-6:
			_scan_cell(cells, far[k], at, previous, melee_cavalry, melee, own_speed, own_id, own_damage, min_k, state)
	return _units[state[0]] if state[0] >= 0 else null

const RING_LIMIT := 3

## Stage 1a weights of a melee fighter's target (DESIGN.md 4.4, 1.4 step 2), applied after the older multipliers
## and only ever raising the distance, so the search bounds above stay valid. Same arithmetic as consider() in
## movement_kernel.hpp: a target fought by more than TARGET_CROWD_FREE_ATTACKERS others (the fighter himself not
## counted) and one receding faster than the fighter can run look farther away. `raw` is the plain distance.
## Stage 1v (DESIGN.md 4.3): for a melee rider, a spearman facing him (within CHARGE_FRONT_ARC) looks
## TARGET_SPEAR_FRONT_MULTIPLIER farther, so cavalry takes a flank or another target instead of his points.
static func melee_weight(weighted: float, raw: float, at: Vector2, own_speed: float, enemy: Unit, enemy_position: Vector2, own_target: bool, rider := false) -> float:
	var crowd := float(enemy.attackers) - (1.0 if own_target else 0.0) - Config.TARGET_CROWD_FREE_ATTACKERS
	if crowd > 0.0:
		weighted *= 1.0 + Config.TARGET_CROWD_MULTIPLIER * crowd
	if own_speed > 0.0 and raw > 0.0:
		var excess := enemy.velocity.dot(enemy_position - at) / raw - own_speed
		if excess > 0.0:
			weighted *= 1.0 + Config.TARGET_OUTRUN_MULTIPLIER * excess / own_speed
	if rider and enemy.anti_cavalry and not enemy.mounted and not enemy.fleeing and raw > 0.0:
		var turn := (at - enemy_position).angle() - enemy.facing
		if turn > PI:
			turn -= PI * 2.0
		elif turn < -PI:
			turn += PI * 2.0
		if absf(turn) < Config.CHARGE_FRONT_ARC:
			weighted *= Config.TARGET_SPEAR_FRONT_MULTIPLIER
	return weighted

## Stage 1a-archers weights of a shooter's target (DESIGN.md 4.4, decision 15), after the older multipliers and only
## ever raising the distance. Same arithmetic as consider() in movement_kernel.hpp. Overkill: the shooters already
## aiming at the enemy (the shooter himself not counted) plus him, beyond hp / (damage x TARGET_VOLLEY_HIT_SHARE),
## each add TARGET_OVERKILL_MULTIPLIER. Front ranks: a fixed share up to TARGET_FRONT_SPREAD from both ids.
## Stage 1v (DESIGN.md 4.4): a shielded enemy who is not a shooter looks TARGET_SHIELDED_MULTIPLIER farther, so
## shooters and men without shields come first (troop data "shb", not ids).
static func ranged_weight(weighted: float, own_id: int, own_damage: float, enemy: Unit, own_target: bool) -> float:
	if own_damage > 0.0:
		var surplus := float(enemy.aimers) - (1.0 if own_target else 0.0) + 1.0 - enemy.hp / (own_damage * Config.TARGET_VOLLEY_HIT_SHARE)
		if surplus > 0.0:
			weighted *= 1.0 + Config.TARGET_OVERKILL_MULTIPLIER * surplus
	if enemy.attack_range <= 0.0 and enemy.shield_block > 0.0:
		weighted *= Config.TARGET_SHIELDED_MULTIPLIER
	return weighted * (1.0 + Config.TARGET_FRONT_SPREAD * front_share(own_id, enemy.id))

## A fixed number in [0, 1) for a shooter and a target: integer mixing of both ids, the same in C++ (front_share in
## movement_kernel.hpp). Every step stays below 2^53, so 64-bit GDScript ints and int64_t agree.
static func front_share(own_id: int, enemy_id: int) -> float:
	var x := (own_id & 1048575) * 92821 + (enemy_id & 1048575) * 68917
	x = x ^ (x >> 15)
	x = (x % 1000003) * 2654435761
	return float((x >> 20) & 1023) / 1024.0

func _scan_cell(cells: Dictionary, cell: Vector2i, at: Vector2, previous: Unit, melee_cavalry: bool, melee: bool, own_speed: float, own_id: int, own_damage: float, min_k: float, state: Array) -> void:
	var bucket = cells.get(cell)
	if bucket == null:
		return
	var left := cell.x * Config.SPATIAL_CELL_SIZE
	var top := cell.y * Config.SPATIAL_CELL_SIZE
	var gx := maxf(maxf(left - at.x, at.x - (left + Config.SPATIAL_CELL_SIZE)), 0.0)
	var gy := maxf(maxf(top - at.y, at.y - (top + Config.SPATIAL_CELL_SIZE)), 0.0)
	var best: float = state[1]
	if sqrt(gx * gx + gy * gy) * min_k > best + 1e-6:
		return
	var best_index: int = state[0]
	for index in bucket:
		var enemy: Unit = _units[index]
		if enemy.dead or enemy.gone:
			continue
		var enemy_position: Vector2 = _positions[index] if _motion != null else enemy.position
		var raw := at.distance_to(enemy_position)
		var distance := raw
		if enemy.fleeing:
			distance *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and enemy.attack_range > 0.0 and not enemy.mounted:
			distance *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		if enemy == previous:
			distance *= Config.CURRENT_TARGET_MULTIPLIER
		if melee:
			distance = melee_weight(distance, raw, at, own_speed, enemy, enemy_position, enemy == previous, melee_cavalry)
		else:
			distance = ranged_weight(distance, own_id, own_damage, enemy, enemy == previous)
		if (distance < best or distance == best and index < best_index) and (melee or terrain == null or not TerrainRules.hidden(terrain, enemy_position, raw)):
			best = distance
			best_index = index
	state[0] = best_index
	state[1] = best

func _add(index: int, cell: Vector2i) -> void:
	var side: int = _units[index].side
	if not _cells[side].has(cell):
		_cells[side][cell] = _spare_buckets.pop_back() if not _spare_buckets.is_empty() else []
	_cells[side][cell].append(index)

static func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / Config.SPATIAL_CELL_SIZE), floori(position.y / Config.SPATIAL_CELL_SIZE))
