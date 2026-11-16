extends RefCounted
## Destination and mode from src/03_battle.js aiUnit(), excluding siege walls and attack timers.
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")

static func plan(unit: Unit, group: Group, enemy: Unit, arena_size: Vector2) -> Dictionary:
	plan_into(unit, group, enemy, arena_size, group.slot_position(unit, arena_size))
	return {"mode": unit.ai_mode, "destination": unit.plan_destination, "face": unit.plan_face, "speed_scale": unit.plan_speed, "target_distance": unit.plan_distance}

## Same decision without allocating: the result goes to unit.ai_mode and unit.plan_*.
## `center` is the formation centre fitted to the group this tick (State.formation_centers); with Vector2.INF
## the charge leash is off, as in direct calls from tests.
static func plan_into(unit: Unit, group: Group, enemy: Unit, arena_size: Vector2, slot: Vector2, center := Vector2.INF, dt := 0.0) -> void:
	var position := unit.position
	var enemy_position := enemy.position if enemy != null else Vector2.ZERO
	var slot_distance := position.distance_to(slot)
	var distance := position.distance_to(enemy_position) if enemy != null else INF
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
			if distance < engage and enemy_position.distance_to(slot) < leash:
				mode = Config.AI_MODE_MELEE
	var destination := slot
	var face: float = group.direction if slot_distance < Config.AI_SLOT_FACE_DISTANCE else (slot - position).angle()
	var speed_scale := 1.0
	if mode == Config.AI_MODE_MELEE:
		face = (enemy_position - position).angle()
		destination = enemy_position if distance > reach else position
	elif mode == Config.AI_MODE_SHOOT or mode == Config.AI_MODE_SHOOT_SLOT:
		face = (enemy_position - position).angle()
		if mode == Config.AI_MODE_SHOOT:
			destination = enemy_position if distance > unit.attack_range * Config.AI_SHOOT_APPROACH_RANGE else position
	elif mode == Config.AI_MODE_SKIRMISH:
		face = (enemy_position - position).angle()
		var away := (position - enemy_position).normalized()
		var side := 1.0 if unit.id % 2 else -1.0
		if distance < unit.attack_range * Config.AI_SKIRMISH_CLOSE_RANGE:
			destination = position + away * Config.AI_SKIRMISH_BACK_OFFSET + Vector2(-away.y, away.x) * Config.AI_SKIRMISH_LATERAL_OFFSET * side
		elif distance > unit.attack_range * Config.AI_SKIRMISH_APPROACH_RANGE:
			destination = enemy_position
		else:
			destination = position + Vector2(-away.y, away.x) * Config.AI_SKIRMISH_ORBIT_OFFSET * side
		var margin := Config.AI_SKIRMISH_EDGE_MARGIN
		if destination.x < margin or destination.x > arena_size.x - margin or destination.y < margin or destination.y > arena_size.y - margin:
			destination = arena_size * 0.5
		speed_scale = Config.AI_SKIRMISH_SPEED_MULTIPLIER
	# Charge leash (DESIGN.md 1.4 step 2) for melee fighters; plan() in movement_kernel.hpp does the same.
	if group.order == Config.ORDER_CHARGE and unit.attack_range <= 0.0 and center.is_finite():
		var home := group.formation_point(unit.slot_offset, center, arena_size)
		var away := position.distance_to(home)
		var mounted := unit.mounted
		var leashed := unit.leashed
		var chase := unit.chase_seconds
		# A chase: the target runs away from him (its speed along the line from him) at a good share of his speed.
		var chasing := mode == Config.AI_MODE_MELEE and distance > reach and enemy.velocity.dot(enemy_position - position) / distance >= unit.speed * Config.AI_CHARGE_CHASE_SPEED_SHARE
		if leashed:
			if away < (Config.AI_CHARGE_MOUNTED_RETURN_DISTANCE if mounted else Config.AI_CHARGE_FOOT_RETURN_DISTANCE):
				leashed = false
		elif chasing and (away > (Config.AI_CHARGE_MOUNTED_HARD_LEASH if mounted else Config.AI_CHARGE_FOOT_HARD_LEASH) or chase > Config.AI_CHARGE_CHASE_SECONDS):
			leashed = true
			chase = 0.0
		var soft: float = Config.AI_CHARGE_MOUNTED_SOFT_LEASH if mounted else Config.AI_CHARGE_FOOT_SOFT_LEASH
		if away <= soft:
			chase = 0.0
		if mode == Config.AI_MODE_MELEE and distance > reach:
			if leashed:
				# Walk back to the own place around the group, not to a point behind the fight.
				mode = Config.AI_MODE_SLOT
				destination = home
				face = group.direction if away < Config.AI_SLOT_FACE_DISTANCE else (home - position).angle()
			elif chasing and away > soft and enemy_position.distance_to(home) > away:
				# Stop and wait for a target that would draw him farther from the group.
				chase += dt
				mode = Config.AI_MODE_SLOT
				destination = position
		unit.leashed = leashed
		unit.chase_seconds = chase
	elif unit.leashed or unit.chase_seconds != 0.0:
		unit.leashed = false
		unit.chase_seconds = 0.0
	unit.ai_mode = mode
	unit.plan_destination = destination
	unit.plan_face = face
	unit.plan_speed = speed_scale
	unit.plan_distance = distance
