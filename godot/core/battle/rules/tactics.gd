extends RefCounted
## Single-player sideBrain() and playerFollow() from src/03_battle.js.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Event = preload("res://core/battle/combat_event.gd")

## AI side brain. Infantry and archers charge by the distance to enemy squads (groups with at least
## AI_SQUAD_MIN_UNITS ready fighters), so a lone hero or companion riding up no longer starts the charge.
## A charge where most fighters chase targets faster than themselves without closing in for
## AI_KITE_SECONDS is called off: the group re-forms and marches on the nearest squad, the archers first
## when the side is losing men to missiles, and charges again only at contact (DESIGN.md 1.4, step 1). With no squads on the field the old
## nearest-fighter rule is kept, except for a group that has already called off a hopeless chase.
static func enemy_step(battle: State, side: int, elapsed: float, dt: float) -> void:
	var foe := battle.centroid(1 - side)
	var own := battle.centroid(side)
	if foe == Vector2.INF or own == Vector2.INF:
		return
	var groups: Array = battle.groups[side]
	var foe_groups: Array = battle.groups[1 - side]
	var infantry: Group = groups[Config.GROUP_INFANTRY]
	var archers: Group = groups[Config.GROUP_ARCHERS]
	var cavalry: Group = groups[Config.GROUP_CAVALRY]
	battle.ai_scan_timers[side] -= dt
	if battle.ai_scan_timers[side] <= 0.0:
		battle.ai_scan_timers[side] = Config.AI_SQUAD_SCAN_SECONDS
		_scan(battle, side)
	var squads := _has_squads(foe_groups)
	var has_infantry := infantry.has_active_units()
	if infantry.order != Config.ORDER_CHARGE:
		var nearest := _charge_distance(battle, infantry, side, squads)
		if nearest < (Config.AI_KITE_RECHARGE_DISTANCE if infantry.kited else Config.AI_INFANTRY_CHARGE_DISTANCE) or (elapsed > Config.AI_INFANTRY_FORCE_CHARGE_SECONDS and not infantry.kited):
			infantry.order = Config.ORDER_CHARGE
			if has_infantry and side == 1:
				battle.record_notice(Event.Kind.ENEMY_CHARGE)
		elif elapsed > Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
			_advance(infantry, _objective(infantry, foe_groups, foe), Config.AI_INFANTRY_ADVANCE_SPEED, dt)
	if archers.order != Config.ORDER_CHARGE:
		var nearest := _charge_distance(battle, archers, side, squads)
		var objective := _objective(archers, foe_groups, foe)
		if nearest < Config.AI_ARCHER_CHARGE_DISTANCE or (not has_infantry and nearest < Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE):
			archers.order = Config.ORDER_CHARGE
		elif nearest > Config.AI_ARCHER_ADVANCE_DISTANCE and elapsed > Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
			_advance(archers, objective, Config.AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED if has_infantry else Config.AI_ARCHER_ADVANCE_ALONE_SPEED, dt)
		else:
			archers.direction = (objective - archers.center).angle()
	if not cavalry.has_active_units() or cavalry.order == Config.ORDER_CHARGE:
		return
	if cavalry.tactic_state == Config.AI_TACTIC_WAIT:
		if elapsed > Config.AI_CAVALRY_FLANK_DELAY_SECONDS:
			cavalry.tactic_state = Config.AI_TACTIC_FLANK
			var flank_side := 1.0 if cavalry.center.y >= battle.arena_size.y * 0.5 else -1.0
			cavalry.waypoint = Vector2(lerpf(own.x, foe.x, Config.AI_CAVALRY_FLANK_PROGRESS), clampf(foe.y + flank_side * Config.AI_CAVALRY_FLANK_OFFSET, Config.AI_CAVALRY_FLANK_EDGE, battle.arena_size.y - Config.AI_CAVALRY_FLANK_EDGE))
	else:
		var offset := cavalry.waypoint - cavalry.center
		var remaining := offset.length()
		cavalry.direction = offset.angle()
		cavalry.center += offset.normalized() * Config.AI_CAVALRY_FLANK_SPEED * dt
		if remaining < Config.AI_CAVALRY_WAYPOINT_ARRIVAL or _nearest_foe_distance(battle, cavalry.center, 1 - side) < Config.AI_CAVALRY_CHARGE_DISTANCE:
			cavalry.order = Config.ORDER_CHARGE

## siegeBrain in src/03_battle.js: gates are battered and may fall, the garrison opens the main gate after 45 s,
## and the defenders come out once the attackers are inside or, with a way open, after a while.
static func siege_step(battle: State, elapsed: float, dt: float = 0.0) -> void:
	var inside := 0
	var near_wall := false
	if battle.column_backend != null:
		var summary: Array = battle.column_backend.wall_status(battle.motion, battle.wall.x + battle.wall.half_width, battle.wall.x - Config.SIEGE_ALERT_DISTANCE, battle.wall.x - Config.SIEGE_DEFENDER_LINE_OFFSET)
		inside = summary[1]
		near_wall = summary[2]
	else:
		var positions := battle.motion.positions
		var flags := battle.motion.integer_fields
		var capacity := battle.motion.capacity
		var fields = battle.motion.I
		for row in positions.size():
			if flags[fields.SIDE * capacity + row] != 0 or flags[fields.DEAD * capacity + row] or flags[fields.GONE * capacity + row] or flags[fields.FLEEING * capacity + row]:
				continue
			if positions[row].x > battle.wall.x + battle.wall.half_width:
				inside += 1
			if positions[row].x > battle.wall.x - Config.SIEGE_ALERT_DISTANCE:
				near_wall = true
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	var cavalry: Group = battle.groups[1][Config.GROUP_CAVALRY]
	var archers: Group = battle.groups[1][Config.GROUP_ARCHERS]
	var open := battle.wall.has_open_gap()
	for index in battle.wall.bash(battle.active_units, dt):
		var gap: Vector2 = battle.wall.gates[index].gap
		battle.record_notice(Event.Kind.GATE_BROKEN, {"position": Vector2(battle.wall.x, (gap.x + gap.y) * 0.5), "gap": gap})
	var fit_infantry := 0
	for unit: Unit in infantry.units:
		if not unit.dead and not unit.gone and not unit.fleeing:
			fit_infantry += 1
	if elapsed > Config.SIEGE_GATE_SORTIE_SECONDS and fit_infantry > Config.SIEGE_GATE_SORTIE_MIN_INFANTRY and battle.wall.open_main_gate():
		battle.record_notice(Event.Kind.GATE_OPENED)
		infantry.order = Config.ORDER_CHARGE
	if infantry.order != Config.ORDER_CHARGE and (inside > Config.SIEGE_INFANTRY_ATTACKERS_INSIDE or (open and elapsed > Config.SIEGE_INFANTRY_FORCE_CHARGE_SECONDS)):
		infantry.order = Config.ORDER_CHARGE
	if cavalry.order != Config.ORDER_CHARGE and (inside > Config.SIEGE_CAVALRY_ATTACKERS_INSIDE or (open and elapsed > Config.SIEGE_CAVALRY_FORCE_CHARGE_SECONDS)):
		cavalry.order = Config.ORDER_CHARGE
		battle.record_notice(Event.Kind.GARRISON_CAVALRY)
	if inside > Config.SIEGE_ARCHERS_ATTACKERS_INSIDE or not infantry.has_active_units():
		archers.order = Config.ORDER_CHARGE
	if near_wall and not battle.siege_alerted:
		battle.siege_alerted = true
		battle.record_notice(Event.Kind.WALL_ALERT)

static func follow_hero(battle: State, hero: Unit) -> void:
	if hero.dead:
		return
	var foe := battle.centroid(1)
	var facing: float = (foe - hero.position).angle() if foe != Vector2.INF else hero.facing
	for group: Group in battle.groups[0]:
		if group.order != Config.ORDER_FOLLOW:
			continue
		var rear: float = Config.FOLLOW_REAR_OFFSET[group.kind]
		var side: float = Config.FOLLOW_CAVALRY_SIDE_OFFSET if group.kind == Config.GROUP_CAVALRY else 0.0
		group.direction = facing
		group.center = hero.position - Vector2(cos(facing), sin(facing)) * rear + Vector2(-sin(facing), cos(facing)) * side

static func relayout(battle: State, dt: float) -> void:
	battle.formation_timer -= dt
	if battle.formation_timer > 0.0:
		return
	battle.formation_timer = Config.FORMATION_RELAYOUT_SECONDS
	for side_groups in battle.groups:
		for group: Group in side_groups:
			if group.order != Config.ORDER_CHARGE:
				group.layout()

## Refreshes the enemy squad picture, the missile-loss memory and the kite check of charging groups.
## Every group is sampled with a fixed stride, at most AI_SQUAD_SAMPLE_LIMIT fighters, so the cost does
## not grow with the army size.
static func _scan(battle: State, side: int) -> void:
	battle.missile_losses[side] *= exp(-Config.AI_SQUAD_SCAN_SECONDS / Config.AI_MISSILE_LOSS_MEMORY_SECONDS)
	var foe_groups: Array = battle.groups[1 - side]
	for group: Group in foe_groups:
		_sample_squad(battle, group)
	for kind in [Config.GROUP_INFANTRY, Config.GROUP_ARCHERS]:
		var group: Group = battle.groups[side][kind]
		if group.order == Config.ORDER_CHARGE:
			_check_kite(battle, group, side)
		else:
			group.squad_distance = _squad_distance(group.center, foe_groups)

static func _sample_squad(battle: State, group: Group) -> void:
	var flags := battle.motion.integer_fields
	var positions := battle.motion.positions
	var capacity := battle.motion.capacity
	var fields = battle.motion.I
	var count := group.units.size()
	var stride := maxi(1, ceili(float(count) / Config.AI_SQUAD_SAMPLE_LIMIT))
	var total := Vector2.ZERO
	group.scan_points.clear()
	for index in range(0, count, stride):
		var row: int = group.units[index].battle_index
		if row < 0 or flags[fields.DEAD * capacity + row] or flags[fields.GONE * capacity + row] or flags[fields.FLEEING * capacity + row] or flags[fields.HERO * capacity + row]:
			continue
		group.scan_points.append(positions[row])
		total += positions[row]
	group.scan_count = group.scan_points.size() * stride
	group.scan_center = total / group.scan_points.size() if not group.scan_points.is_empty() else Vector2.INF

static func _is_squad(group: Group) -> bool:
	return group.scan_count >= Config.AI_SQUAD_MIN_UNITS

static func _has_squads(foe_groups: Array) -> bool:
	for group: Group in foe_groups:
		if _is_squad(group): return true
	return false

## Distance from a point to the nearest sampled fighter of any enemy squad.
static func _squad_distance(point: Vector2, foe_groups: Array, only_kind: int = -1) -> float:
	var closest := INF
	for group: Group in foe_groups:
		if not _is_squad(group) or (only_kind >= 0 and group.kind != only_kind): continue
		for position in group.scan_points:
			closest = minf(closest, point.distance_squared_to(position))
	return sqrt(closest)

static func _charge_distance(battle: State, group: Group, side: int, squads: bool) -> float:
	if squads: return group.squad_distance
	return INF if group.kited else _nearest_foe_distance(battle, group.center, 1 - side)

static func _objective(group: Group, foe_groups: Array, foe: Vector2) -> Vector2:
	if group.focus_kind >= 0:
		var squad: Group = foe_groups[group.focus_kind]
		if _is_squad(squad): return squad.scan_center
	return foe

## A charge is hopeless when most sampled fighters chase faster targets out of reach and the mean gap
## has not shrunk by AI_KITE_PROGRESS_DISTANCE for AI_KITE_SECONDS.
static func _check_kite(battle: State, group: Group, side: int) -> void:
	var count := group.units.size()
	var stride := maxi(1, ceili(float(count) / Config.AI_SQUAD_SAMPLE_LIMIT))
	var ready := 0
	var chasers := 0
	var gap_total := 0.0
	for index in range(0, count, stride):
		var unit: Unit = group.units[index]
		if unit.battle_index < 0 or unit.dead or unit.gone or unit.fleeing or unit.hero:
			continue
		ready += 1
		var target := battle.unit_for(unit.target_handle)
		if target == null or target.dead or target.gone:
			continue
		var gap := unit.position.distance_to(target.position)
		if gap > maxf(Config.AI_KITE_CONTACT_DISTANCE, unit.attack_range) and target.speed > unit.speed * Config.AI_KITE_SPEED_RATIO:
			chasers += 1
			gap_total += gap
	if ready == 0 or chasers <= ready * Config.AI_KITE_CHASER_SHARE:
		group.kite_seconds = 0.0
		group.kite_gap = INF
		return
	var gap := gap_total / chasers
	if gap < group.kite_gap - Config.AI_KITE_PROGRESS_DISTANCE:
		group.kite_gap = gap
		group.kite_seconds = 0.0
		return
	group.kite_seconds += Config.AI_SQUAD_SCAN_SECONDS
	if group.kite_seconds >= Config.AI_KITE_SECONDS:
		_call_off_charge(battle, group, side)

## Back into formation where the men stand, facing the squad to march on.
static func _call_off_charge(battle: State, group: Group, side: int) -> void:
	var foe_groups: Array = battle.groups[1 - side]
	group.order = Config.ORDER_HOLD
	group.kited = true
	group.kite_seconds = 0.0
	group.kite_gap = INF
	group.center = group.centroid()
	group.focus_kind = -1
	var archers: Group = foe_groups[Config.GROUP_ARCHERS]
	if battle.missile_losses[side] >= Config.AI_MISSILE_PRESSURE_LOSSES and _is_squad(archers):
		group.focus_kind = Config.GROUP_ARCHERS
	else:
		var closest := INF
		for squad: Group in foe_groups:
			var distance := _squad_distance(group.center, foe_groups, squad.kind)
			if distance < closest:
				closest = distance
				group.focus_kind = squad.kind
	var objective := _objective(group, foe_groups, battle.centroid(1 - side))
	if objective != Vector2.INF and objective != group.center:
		group.direction = (objective - group.center).angle()
	group.squad_distance = _squad_distance(group.center, foe_groups)
	group.layout()

static func _nearest_foe_distance(battle: State, point: Vector2, side: int) -> float:
	if battle.column_backend != null: return battle.column_backend.nearest_ready(battle.motion, point, side)
	var closest := INF
	for unit: Unit in battle.active_units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			closest = minf(closest, point.distance_to(unit.position))
	return closest

static func _advance(group: Group, foe: Vector2, speed: float, dt: float) -> void:
	var angle := (foe - group.center).angle()
	group.direction = angle
	group.center += Vector2(cos(angle), sin(angle)) * speed * dt
