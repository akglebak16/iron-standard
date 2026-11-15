extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const SpatialIndex = preload("res://battle/rules/spatial_index.gd")

static func nearest_enemy(battle: State, unit: Unit, index: SpatialIndex = null) -> Unit:
	if index != null:
		return index.nearest_enemy(unit)
	var nearest: Unit = null
	var best := INF
	for enemy: Unit in battle.units:
		if enemy.side == unit.side or enemy.dead or enemy.gone:
			continue
		var distance: float = unit.position.distance_squared_to(enemy.position)
		if distance < best:
			best = distance
			nearest = enemy
	return nearest

static func current(battle: State, unit: Unit) -> Unit:
	if unit.target_index < 0 or unit.target_index >= battle.units.size():
		return null
	var target: Unit = battle.units[unit.target_index]
	return target if target.side != unit.side and not target.dead and not target.gone else null

static func choose(battle: State, unit: Unit, index: SpatialIndex = null) -> Unit:
	var previous: Unit = current(battle, unit)
	if index != null:
		return index.best_target(unit, previous)
	var best: Unit = null
	var best_distance := INF
	var melee_cavalry := unit.mounted and unit.attack_range <= 0.0
	for enemy: Unit in battle.units:
		if enemy.side == unit.side or enemy.dead or enemy.gone:
			continue
		var distance := unit.position.distance_to(enemy.position)
		if enemy.fleeing:
			distance *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and enemy.attack_range > 0.0 and not enemy.mounted:
			distance *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		if enemy == previous:
			distance *= Config.CURRENT_TARGET_MULTIPLIER
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

static func refresh(battle: State, unit: Unit, dt: float, rng: RandomNumberGenerator, index: SpatialIndex = null) -> Unit:
	unit.target_timer -= dt
	var target := current(battle, unit)
	if unit.target_timer <= 0.0 or unit.target_index >= 0 and target == null:
		unit.target_timer = Config.RETARGET_MIN_SECONDS + rng.randf() * Config.RETARGET_RANDOM_SECONDS
		target = choose(battle, unit, index)
		unit.target_index = target.battle_index if target != null else -1
	return target
