extends RefCounted
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
