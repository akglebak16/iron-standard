extends RefCounted
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")

static func nearest_enemy(battle: State, unit: Unit) -> Unit:
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
