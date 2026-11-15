extends RefCounted
## Destination and mode from src/03_battle.js aiUnit(), excluding siege walls and attack timers.
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")

static func plan(unit: Unit, group: Group, enemy: Unit, arena_size: Vector2) -> Dictionary:
	plan_into(unit, group, enemy, arena_size, group.slot_position(unit, arena_size))
	return {"mode": unit.ai_mode, "destination": unit.plan_destination, "face": unit.plan_face, "speed_scale": unit.plan_speed, "target_distance": unit.plan_distance}

## Same decision without allocating: the result goes to unit.ai_mode and unit.plan_*.
static func plan_into(unit: Unit, group: Group, enemy: Unit, arena_size: Vector2, slot: Vector2) -> void:
	var slot_distance := unit.position.distance_to(slot)
	var distance := unit.position.distance_to(enemy.position) if enemy != null else INF
	var reach := unit.collision_radius + (enemy.collision_radius if enemy != null else 0.0) + unit.melee_reach
	var mode := Config.AI_MODE_SLOT
	if group.backing and slot_distance > Config.AI_BACKING_SLOT_DISTANCE:
		pass
	elif unit.attack_range > 0.0:
		if unit.mounted:
			if enemy != null and (group.order == Config.ORDER_CHARGE or distance < unit.attack_range * Config.AI_MOUNTED_SKIRMISH_TRIGGER):
				mode = Config.AI_MODE_SKIRMISH
		elif enemy != null and distance < reach + Config.AI_ARCHER_MELEE_BUFFER:
			mode = Config.AI_MODE_MELEE
		elif enemy != null and group.order == Config.ORDER_CHARGE:
			mode = Config.AI_MODE_SHOOT
		elif enemy != null and distance < unit.attack_range and slot_distance < Config.AI_ARCHER_SLOT_DISTANCE:
			mode = Config.AI_MODE_SHOOT_SLOT
	elif enemy != null:
		if group.order == Config.ORDER_CHARGE:
			mode = Config.AI_MODE_MELEE
		else:
			var engage: float = Config.AI_MOUNTED_ENGAGE_DISTANCE if unit.mounted else Config.AI_FOOT_ENGAGE_DISTANCE
			var leash: float = Config.AI_MOUNTED_LEASH_DISTANCE if unit.mounted else Config.AI_FOOT_LEASH_DISTANCE
			if distance < engage and enemy.position.distance_to(slot) < leash:
				mode = Config.AI_MODE_MELEE
	var destination := slot
	var face: float = group.direction if slot_distance < Config.AI_SLOT_FACE_DISTANCE else (slot - unit.position).angle()
	var speed_scale := 1.0
	if mode == Config.AI_MODE_MELEE:
		face = (enemy.position - unit.position).angle()
		destination = enemy.position if distance > reach else unit.position
	elif mode == Config.AI_MODE_SHOOT or mode == Config.AI_MODE_SHOOT_SLOT:
		face = (enemy.position - unit.position).angle()
		if mode == Config.AI_MODE_SHOOT:
			destination = enemy.position if distance > unit.attack_range * Config.AI_SHOOT_APPROACH_RANGE else unit.position
	elif mode == Config.AI_MODE_SKIRMISH:
		face = (enemy.position - unit.position).angle()
		var away := (unit.position - enemy.position).normalized()
		var side := 1.0 if unit.id % 2 else -1.0
		if distance < unit.attack_range * Config.AI_SKIRMISH_CLOSE_RANGE:
			destination = unit.position + away * Config.AI_SKIRMISH_BACK_OFFSET + Vector2(-away.y, away.x) * Config.AI_SKIRMISH_LATERAL_OFFSET * side
		elif distance > unit.attack_range * Config.AI_SKIRMISH_APPROACH_RANGE:
			destination = enemy.position
		else:
			destination = unit.position + Vector2(-away.y, away.x) * Config.AI_SKIRMISH_ORBIT_OFFSET * side
		var margin := Config.AI_SKIRMISH_EDGE_MARGIN
		if destination.x < margin or destination.x > arena_size.x - margin or destination.y < margin or destination.y > arena_size.y - margin:
			destination = arena_size * 0.5
		speed_scale = Config.AI_SKIRMISH_SPEED_MULTIPLIER
	unit.ai_mode = mode
	unit.plan_destination = destination
	unit.plan_face = face
	unit.plan_speed = speed_scale
	unit.plan_distance = distance
