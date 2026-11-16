extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")

static func nearest_enemy(battle: State, unit: Unit, index: SpatialIndex = null) -> Unit:
	if index != null:
		return index.nearest_enemy(unit)
	var nearest: Unit = null
	var best := INF
	for enemy: Unit in battle.active_units:
		if enemy.side == unit.side or enemy.dead or enemy.gone:
			continue
		var distance: float = unit.position.distance_squared_to(enemy.position)
		if distance < best:
			best = distance
			nearest = enemy
	return nearest

static func current(battle: State, unit: Unit) -> Unit:
	var target := battle.unit_for(unit.target_handle)
	return target if target != null and target.side != unit.side and not target.dead and not target.gone else null

static func choose(battle: State, unit: Unit, index: SpatialIndex = null) -> Unit:
	var previous: Unit = current(battle, unit)
	if index != null:
		return index.best_target(unit, previous)
	var best: Unit = null
	var best_distance := INF
	var melee_cavalry := unit.mounted and unit.attack_range <= 0.0
	var melee := unit.attack_range <= 0.0
	var at := unit.position
	for enemy: Unit in battle.active_units:
		if enemy.side == unit.side or enemy.dead or enemy.gone:
			continue
		var enemy_position := enemy.position
		var raw := at.distance_to(enemy_position)
		var distance := raw
		if enemy.fleeing:
			distance *= Config.TARGET_FLEE_DISTANCE_MULTIPLIER
		if melee_cavalry and enemy.attack_range > 0.0 and not enemy.mounted:
			distance *= Config.CAVALRY_ARCHER_TARGET_MULTIPLIER
		if enemy == previous:
			distance *= Config.CURRENT_TARGET_MULTIPLIER
		if melee:
			distance = SpatialIndex.melee_weight(distance, raw, at, unit.speed, enemy, enemy_position, enemy == previous)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

static func refresh(battle: State, unit: Unit, dt: float, rng: RandomNumberGenerator, index: SpatialIndex = null) -> Unit:
	unit.target_timer -= dt
	var target := current(battle, unit)
	if unit.target_timer <= 0.0 or unit.target_handle != 0 and target == null:
		unit.target_timer = Config.RETARGET_MIN_SECONDS + rng.randf() * Config.RETARGET_RANDOM_SECONDS
		var chosen := choose(battle, unit, index)
		# Keep the attacker counts of this tick current (Movement._prepare_ai counted the old targets).
		if unit.attack_range <= 0.0 and chosen != target:
			if target != null: target.attackers -= 1
			if chosen != null: chosen.attackers += 1
		target = chosen
		unit.target_handle = target.unit_handle if target != null else 0
	return target
