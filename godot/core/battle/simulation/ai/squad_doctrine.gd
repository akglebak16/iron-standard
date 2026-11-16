extends RefCounted
## Stage 1v (DESIGN.md 4.3, decision 14): doctrines of troop types at the group level. The same for both sides, for
## any AI profile and for player orders: a squad of the player and of the AI executes the same order the same way.
## Every group decides every AI_SQUAD_PERIOD_SECONDS, staggered by group number, and at once when its order changes;
## the decisions are inputs the fighter rules read every tick (ai_decision.gd, movement_kernel.hpp):
## - infantry in a charge: formed (a line that keeps its formation and moves its centre) or loose (the old charge);
## - infantry holding: a screen point where its spearmen cover the own archers against closing riders;
## - cavalry in a charge: the shock cycle, run-up and impact, then a rally behind or beyond the target and a new run-up.
## Fighters are sampled with a fixed stride (at most AI_SQUAD_SAMPLE_LIMIT), from the motion columns.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const Unit = preload("res://core/battle/model/unit.gd")

## Group sample: ready fighters, sums of positions, formation offsets and target positions, fleeing targets, melee
## riders and those of them in contact with foot melee, sum of distances to the slots, melee riders' velocity sum.
class Sample:
	var ready := 0
	var position_sum := Vector2.ZERO
	var offset_sum := Vector2.ZERO
	var aim_sum := Vector2.ZERO
	var aimed := 0
	var fleeing := 0
	var riders := 0
	var contact := 0
	var slot_distance_sum := 0.0
	var velocity_sum := Vector2.ZERO

	func mean_position() -> Vector2:
		return position_sum / ready

	func aim() -> Vector2:
		return aim_sum / aimed if aimed > 0 else Vector2.INF

	## Formation centre that fits the sampled fighters for a group facing `direction`.
	func fitted(direction: float) -> Vector2:
		var offset := offset_sum / ready
		return position_sum / ready - Vector2(-sin(direction), cos(direction)) * offset.x - Vector2(cos(direction), sin(direction)) * offset.y

static func step(battle: State, dt: float) -> void:
	if battle.groups.size() != 2:
		return
	for side in 2:
		for kind in battle.groups[side].size():
			var group: Group = battle.groups[side][kind]
			group.doctrine_seconds += dt
			group.doctrine_timer -= dt
			var changed := group.order != group.doctrine_order or group.backing != group.doctrine_backing
			var due := group.doctrine_timer <= 0.0
			if due:
				group.doctrine_timer = maxf(group.doctrine_timer + Config.AI_SQUAD_PERIOD_SECONDS, dt)
			elif not changed:
				continue
			group.doctrine_order = group.order
			group.doctrine_backing = group.backing
			match kind:
				Config.GROUP_INFANTRY: _infantry(battle, group, side)
				Config.GROUP_CAVALRY: _cavalry(battle, group)

static func _infantry(battle: State, group: Group, side: int) -> void:
	if group.order != Config.ORDER_CHARGE or group.backing:
		group.formed = false
		group.doctrine_seconds = maxf(group.doctrine_seconds, Config.AI_FORMATION_SWITCH_SECONDS)
		_screen(battle, group, side)
		return
	group.screen = Vector2.INF
	var sample := sample_group(battle, group)
	if sample.ready == 0:
		group.formed = false
		return
	var wanted := formed_wanted(battle, group, sample)
	if wanted != group.formed and group.doctrine_seconds >= Config.AI_FORMATION_SWITCH_SECONDS:
		group.formed = wanted
		group.doctrine_seconds = 0.0
		if wanted:
			# Re-form where the men stand, facing their targets.
			var aim := sample.aim()
			var fitted := sample.fitted(group.direction)
			if aim != Vector2.INF and aim != fitted:
				group.direction = (aim - fitted).angle()
			group.layout()
			group.center = _fitted_center(group)
			return
	if group.formed:
		_march(group, sample)

## Loose by order, near a siege wall or with the targets across it, in a pursuit and with too few fighters; formed otherwise.
static func formed_wanted(battle: State, group: Group, sample: Sample) -> bool:
	if group.loose or sample.ready < Config.AI_FORMATION_MIN_UNITS:
		return false
	if sample.aimed > 0 and sample.fleeing > sample.aimed * Config.AI_FORMATION_PURSUIT_SHARE:
		return false
	if battle.wall != null:
		var fitted := sample.fitted(group.direction)
		if absf(fitted.x - battle.wall.x) < Config.AI_FORMATION_WALL_DISTANCE:
			return false
		var aim := sample.aim()
		if aim != Vector2.INF and (fitted.x < battle.wall.x) != (aim.x < battle.wall.x):
			return false
	return true

## The line turns towards its targets at AI_FORMATION_TURN_RATE around its own middle and keeps its slots
## AI_FORMATION_LEAD ahead of where it stands, less when the targets are off its front (none when behind).
static func _march(group: Group, sample: Sample) -> void:
	var aim := sample.aim()
	var fitted := sample.fitted(group.direction)
	var heading := group.direction if aim == Vector2.INF or aim == fitted else (aim - fitted).angle()
	var turn := wrapf(heading - group.direction, -PI, PI)
	var limit := Config.AI_FORMATION_TURN_RATE * Config.AI_SQUAD_PERIOD_SECONDS
	group.direction = wrapf(group.direction + clampf(turn, -limit, limit), -PI, PI)
	var lead := Config.AI_FORMATION_LEAD * maxf(0.0, cos(heading - group.direction))
	group.center = sample.fitted(group.direction) + Vector2(cos(group.direction), sin(group.direction)) * lead

## Spearmen of a holding infantry group cover the own archers when enemy riders close in on them.
static func _screen(battle: State, group: Group, side: int) -> void:
	group.screen = Vector2.INF
	var archers := sample_group(battle, battle.groups[side][Config.GROUP_ARCHERS])
	var riders := sample_group(battle, battle.groups[1 - side][Config.GROUP_CAVALRY])
	if archers.ready == 0 or riders.riders == 0:
		return
	var archer_center := archers.mean_position()
	var rider_center := riders.mean_position()
	var threat := rider_center - archer_center
	if threat.length() >= Config.AI_SCREEN_THREAT_DISTANCE or riders.velocity_sum.dot(-threat) <= 0.0:
		return
	var own := sample_group(battle, group)
	if own.ready == 0 or own.mean_position().distance_to(archer_center) >= Config.AI_SCREEN_RANGE:
		return
	var toward := threat.normalized()
	group.screen = archer_center + toward * Config.AI_SCREEN_OFFSET
	group.screen_lateral = Vector2(-toward.y, toward.x)

## Shock cavalry: after AI_CAVALRY_MELEE_SECONDS stuck in foot melee, rally away from the targets and charge again.
static func _cavalry(battle: State, group: Group) -> void:
	if group.order != Config.ORDER_CHARGE or group.backing:
		group.rally = false
		group.contact_seconds = 0.0
		return
	var sample := sample_group(battle, group)
	if sample.ready == 0:
		group.rally = false
		return
	if group.rally:
		var arrived := sample.slot_distance_sum / sample.ready < Config.AI_CAVALRY_REFORM_DISTANCE
		if arrived or group.doctrine_seconds >= Config.AI_CAVALRY_RALLY_SECONDS:
			group.rally = false
			group.contact_seconds = 0.0
			group.doctrine_seconds = 0.0
		return
	if sample.riders > 0 and sample.contact >= sample.riders * Config.AI_CAVALRY_CONTACT_SHARE:
		group.contact_seconds += Config.AI_SQUAD_PERIOD_SECONDS
	else:
		group.contact_seconds = 0.0
	if group.contact_seconds < Config.AI_CAVALRY_MELEE_SECONDS:
		return
	var at := sample.mean_position()
	var aim := sample.aim()
	var away := (at - aim).normalized() if aim != Vector2.INF and aim != at else -Vector2(cos(group.direction), sin(group.direction))
	var edge := Vector2.ONE * Config.AI_CAVALRY_RALLY_EDGE
	var rally_point := (at + away * Config.AI_CAVALRY_RALLY_DISTANCE).clamp(edge, battle.arena_size - edge)
	if battle.wall != null and not _clear_of_wall(battle, at, rally_point):
		return # At the wall and in the gates the riders fight on loose, as before.
	group.center = rally_point
	if aim != Vector2.INF and aim != group.center:
		group.direction = (aim - group.center).angle()
	group.rally = true
	group.contact_seconds = 0.0
	group.doctrine_seconds = 0.0
	group.layout()

## Both points on one side of the siege wall and at least AI_FORMATION_WALL_DISTANCE from it.
static func _clear_of_wall(battle: State, a: Vector2, b: Vector2) -> bool:
	var x: float = battle.wall.x
	var reach := Config.AI_FORMATION_WALL_DISTANCE
	return absf(a.x - x) >= reach and absf(b.x - x) >= reach and (a.x < x) == (b.x < x)

static func sample_group(battle: State, group: Group) -> Sample:
	var sample := Sample.new()
	var motion = battle.motion
	var flags: PackedInt64Array = motion.integer_fields
	var reals: PackedFloat64Array = motion.real_fields
	var vectors: PackedVector2Array = motion.vector_fields
	var positions: PackedVector2Array = motion.positions
	var velocities: PackedVector2Array = motion.velocities
	var capacity: int = motion.capacity
	var fields = motion.I
	var count := group.units.size()
	var stride := maxi(1, ceili(float(count) / Config.AI_SQUAD_SAMPLE_LIMIT))
	var rally_check := group.kind == Config.GROUP_CAVALRY
	for index in range(0, count, stride):
		var row: int = group.units[index].battle_index
		if row < 0 or flags[fields.DEAD * capacity + row] or flags[fields.GONE * capacity + row] or flags[fields.FLEEING * capacity + row] or flags[fields.HERO * capacity + row]:
			continue
		var at := positions[row]
		var offset := vectors[motion.V.SLOT_OFFSET * capacity + row]
		sample.ready += 1
		sample.position_sum += at
		sample.offset_sum += offset
		if rally_check:
			sample.slot_distance_sum += at.distance_to(group.slot_position(group.units[index], battle.arena_size))
		var melee_rider := reals[motion.R.ATTACK_RANGE * capacity + row] <= 0.0 and flags[fields.MOUNTED * capacity + row] != 0
		if melee_rider:
			sample.riders += 1
			sample.velocity_sum += velocities[row]
		var target := battle.unit_for(flags[fields.TARGET_HANDLE * capacity + row])
		if target == null or target.dead or target.gone or target.side == group.side:
			continue
		var target_at := target.position
		sample.aim_sum += target_at
		sample.aimed += 1
		if target.fleeing:
			sample.fleeing += 1
		if melee_rider and not target.mounted and target.attack_range <= 0.0:
			var reach: float = reals[motion.R.COLLISION_RADIUS * capacity + row] + target.collision_radius + reals[motion.R.MELEE_REACH * capacity + row]
			if at.distance_to(target_at) < reach + Config.AI_CAVALRY_CONTACT_DISTANCE:
				sample.contact += 1
	return sample

static func _fitted_center(group: Group) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for unit: Unit in group.units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero: continue
		total += group.implied_center(unit.slot_offset, unit.position)
		count += 1
	return total / count if count else group.center
