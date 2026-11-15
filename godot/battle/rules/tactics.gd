extends RefCounted
## Single-player sideBrain() and playerFollow() from src/03_battle.js.
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Group = preload("res://battle/model/group.gd")
const Unit = preload("res://battle/model/unit.gd")
const Event = preload("res://battle/combat_event.gd")
const NativeSwitch = preload("res://battle/rules/native_switch.gd")

static func enemy_step(battle: State, side: int, elapsed: float, dt: float) -> void:
	var foe := battle.centroid(1 - side)
	var own := battle.centroid(side)
	if foe == Vector2.INF or own == Vector2.INF:
		return
	var groups: Array = battle.groups[side]
	var infantry: Group = groups[Config.GROUP_INFANTRY]
	var archers: Group = groups[Config.GROUP_ARCHERS]
	var cavalry: Group = groups[Config.GROUP_CAVALRY]
	var has_infantry := infantry.has_active()
	if infantry.order != Config.ORDER_CHARGE:
		var nearest := _nearest_foe_distance(battle, infantry.center, 1 - side)
		if nearest < Config.AI_INFANTRY_CHARGE_DISTANCE or elapsed > Config.AI_INFANTRY_FORCE_CHARGE_SECONDS:
			infantry.order = Config.ORDER_CHARGE
			if has_infantry and side == 1:
				battle.record_notice(Event.Kind.ENEMY_CHARGE)
		elif elapsed > Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
			_advance(infantry, foe, Config.AI_INFANTRY_ADVANCE_SPEED, dt)
	if archers.order != Config.ORDER_CHARGE:
		var nearest := _nearest_foe_distance(battle, archers.center, 1 - side)
		if nearest < Config.AI_ARCHER_CHARGE_DISTANCE or (not has_infantry and nearest < Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE):
			archers.order = Config.ORDER_CHARGE
		elif nearest > Config.AI_ARCHER_ADVANCE_DISTANCE and elapsed > Config.AI_GROUP_ADVANCE_DELAY_SECONDS:
			_advance(archers, foe, Config.AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED if has_infantry else Config.AI_ARCHER_ADVANCE_ALONE_SPEED, dt)
		else:
			archers.direction = (foe - archers.center).angle()
	if not cavalry.has_active() or cavalry.order == Config.ORDER_CHARGE:
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

static func siege_step(battle: State, elapsed: float) -> void:
	var inside := 0
	var near_wall := false
	for unit: Unit in battle.units:
		if unit.side != 0 or unit.dead or unit.gone or unit.fleeing:
			continue
		if unit.position.x > battle.wall.x + battle.wall.half_width:
			inside += 1
		if unit.position.x > battle.wall.x - Config.SIEGE_ALERT_DISTANCE:
			near_wall = true
	var infantry: Group = battle.groups[1][Config.GROUP_INFANTRY]
	var cavalry: Group = battle.groups[1][Config.GROUP_CAVALRY]
	var archers: Group = battle.groups[1][Config.GROUP_ARCHERS]
	if inside > Config.SIEGE_INFANTRY_ATTACKERS_INSIDE or elapsed > Config.SIEGE_INFANTRY_FORCE_CHARGE_SECONDS:
		infantry.order = Config.ORDER_CHARGE
	if cavalry.order != Config.ORDER_CHARGE and (inside > Config.SIEGE_CAVALRY_ATTACKERS_INSIDE or elapsed > Config.SIEGE_CAVALRY_FORCE_CHARGE_SECONDS):
		cavalry.order = Config.ORDER_CHARGE
		battle.record_notice(Event.Kind.GARRISON_CAVALRY)
	if inside > Config.SIEGE_ARCHERS_ATTACKERS_INSIDE or not infantry.has_active():
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

static func _nearest_foe_distance(battle: State, point: Vector2, side: int) -> float:
	if not NativeSwitch.on:
		return nearest_foe_distance_reference(battle, point, side)
	return BattleCore.nearest_foe_distance(battle.units, point, side)

## The GDScript reference of _nearest_foe_distance (kept for differential tests).
static func nearest_foe_distance_reference(battle: State, point: Vector2, side: int) -> float:
	var closest := INF
	for unit: Unit in battle.units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			closest = minf(closest, point.distance_to(unit.position))
	return closest

static func _advance(group: Group, foe: Vector2, speed: float, dt: float) -> void:
	var angle := (foe - group.center).angle()
	group.direction = angle
	group.center += Vector2(cos(angle), sin(angle)) * speed * dt
