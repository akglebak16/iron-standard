extends RefCounted

const Damage = preload("res://core/battle/rules/damage.gd")
const Group = preload("res://core/battle/model/group.gd")
const Config = preload("res://core/battle/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const SiegeWall = preload("res://core/battle/model/siege_wall.gd")
const SiegeDefense = preload("res://core/battle/model/siege_defense.gd")
const Plant = preload("res://core/battle/model/plant.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Equipment = preload("res://core/equipment/config.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")
const CollisionGrid = preload("res://core/battle/rules/collision_grid.gd")
const PhaseProfiler = preload("res://runtime/diagnostics/phase_profiler.gd")
const ContactWorkspace = preload("res://runtime/spatial/contact_workspace.gd")
const StaticObstacleIndex = preload("res://runtime/spatial/static_obstacle_index.gd")
const BLUNT_LOOK_WEAPONS := ["club", "mace"]

var wall: SiegeWall
var siege_defense: SiegeDefense
var plants: Array[Plant] = []
var trunks: Array[Plant] = []
var siege_skill := 0.0

var units: Array[Unit] = []
var profiler := PhaseProfiler.new()
## Phase workspaces belong to this battle; differential tests may disable its index.
var use_spatial_index := true
var movement_index: SpatialIndex
var projectile_index: SpatialIndex
var collision_grid: CollisionGrid
var collision_candidates: Array[int] = []
var projectile_candidates: Array[int] = []
var contacts := ContactWorkspace.new()
## Optional batch port injected by composition. The reference solver needs no engine adapter.
var contact_solver := Callable()
var native_contact_steps := 0
var native_contact_failures := 0
var _contact_geometry: Dictionary = {}
var _contact_revision := -1
var _contact_wall: SiegeWall
var _contact_arena := Vector2.ZERO
var _contact_wall_shape := Vector2.INF
var static_obstacles := StaticObstacleIndex.new()
var arena_size := Config.ARENA_SIZE
var groups: Array = []
var projectiles: Array = []
var starting_units := [0, 0]
var morale_timer := 0.0
var formation_timer := 0.0
var siege_alerted := false
## Figures above the cap that enter later in waves (browser B.reserve / B.cap / B.resDead).
var reserve: Array = [[], []]
var reserve_definitions: Dictionary = {}
var side_factions := ["", ""]
var reserve_caps := [0, 0]
var reserve_lost := [0, 0]
var active_counts := [0, 0] # Combat-ready units at the latest morale check.
var _events: Array[Dictionary] = []

func contact_geometry() -> Dictionary:
	var wall_shape := Vector2(wall.x, wall.half_width) if wall != null else Vector2.INF
	if _contact_revision == static_obstacles.revision and _contact_wall == wall and _contact_wall_shape == wall_shape and _contact_arena == arena_size and not _contact_geometry.is_empty():
		return _contact_geometry
	var positions := PackedVector2Array()
	var radii := PackedFloat64Array()
	for trunk in trunks:
		positions.append(trunk.position)
		radii.append(trunk.trunk_radius)
	_contact_geometry = {
		"parameters": PackedFloat64Array([arena_size.x, arena_size.y, CollisionGrid.PAD, CollisionGrid.CELL,
			Config.CONTACT_QUERY_SLACK, Config.MIN_COLLISION_DISTANCE, Config.FRIEND_COLLISION_PUSH, Config.ENEMY_COLLISION_PUSH,
			Config.FIELD_LEFT_RIGHT_MARGIN, Config.FIELD_TOP_MARGIN, Config.FIELD_BOTTOM_MARGIN,
			wall.x if wall != null else INF, wall.half_width if wall != null else 0.0,
			Config.SIEGE_WALL_RADIUS_PADDING, Config.SIEGE_GAP_RADIUS_PADDING]),
		"positions": positions, "radii": radii,
		"gaps": PackedVector2Array(wall.gaps()) if wall != null else PackedVector2Array(),
	}
	_contact_revision = static_obstacles.revision
	_contact_wall = wall
	_contact_wall_shape = wall_shape
	_contact_arena = arena_size
	return _contact_geometry

func set_plants(layout: Array[Plant]) -> void:
	plants = layout
	trunks.assign(plants.filter(func(plant: Plant): return plant.trunk_radius > 0.0))
	var positions := PackedVector2Array()
	var radii := PackedFloat64Array()
	for trunk in trunks:
		positions.append(trunk.position)
		radii.append(trunk.trunk_radius)
	static_obstacles.rebuild(positions, radii)

func record_notice(kind: Event.Kind, details: Dictionary = {}) -> void:
	var notice := {"kind": kind}
	notice.merge(details)
	_events.append(notice)

func record_unit_notice(kind: Event.Kind, unit: Unit) -> void:
	record_notice(kind, {"side": unit.side, "target_id": unit.id, "target_name": unit.name, "position": unit.position})

func launch_projectile(shot: Dictionary) -> void:
	projectiles.append(shot)
	record_event(Event.Kind.SHOT, shot.source, null, Event.Attack.PROJECTILE)

func record_event(kind: Event.Kind, target: Unit, source: Unit = null, attack: Event.Attack = Event.Attack.NONE, amount: int = 0, contact_offset: Vector2 = Vector2.ZERO) -> void:
	var event := {
		"kind": kind, "attack": attack, "amount": amount,
		"position": target.position, "contact_offset": contact_offset, "target_id": target.id,
		"target_hero": target.hero, "target_companion": target.companion,
		"target_leader": target.leader, "target_name": target.name,
		"target_side": target.side, "target_bonded": not target.leader_bond.is_empty(),
		"source_hero": source != null and source.hero,
		"source_id": source.id if source != null else -1,
		"source_alive": source != null and not source.dead,
		"impact_style": target.impact_style,
		"damage_fraction": float(amount) / maxf(target.max_hp, 1.0),
		"lethal": target.hp <= 0.0,
		"impact_direction": Vector2.ZERO if source == null else target.position - source.position,
	}
	if kind == Event.Kind.DOWN:
		event.melee_impact = _melee_impact(attack, source)
		event.target_visual = {
			"look": target.appearance.duplicate(true), "side": target.side, "faction": target.faction,
			"mounted": target.mounted, "facing": target.facing, "hero": target.hero, "companion": target.companion,
			"id": target.id, "position": target.position, "radius": target.collision_radius,
			"dead": true, "gone": false, "speed": 0.0, "windup": -1.0, "blocking": false,
			"fleeing": false, "leader": target.leader, "group_kind": target.group_kind, "health_fraction": 0.0,
		}
	_events.append(event)

static func _melee_impact(attack: Event.Attack, source: Unit) -> Event.MeleeImpact:
	if attack != Event.Attack.MELEE:
		return Event.MeleeImpact.NONE
	if source != null:
		match source.damage_type:
			Equipment.DAMAGE_TYPE_BLUNT: return Event.MeleeImpact.BLUNT
			Equipment.DAMAGE_TYPE_PIERCE: return Event.MeleeImpact.PIERCE
			"":
				if source.weapon_kind in BLUNT_LOOK_WEAPONS:
					return Event.MeleeImpact.BLUNT
	return Event.MeleeImpact.CUT

func take_events() -> Array[Dictionary]:
	var batch := _events
	_events = []
	return batch

func setup_groups(cavalry_flank: int = 1) -> void:
	groups.clear()
	for side in 2:
		var forward := -1.0 if side == 1 else 1.0
		var facing := PI if side == 1 else 0.0
		var x := arena_size.x - Config.FRONT_X if side == 1 else Config.FRONT_X
		groups.append([
			Group.new(side, Config.GROUP_INFANTRY, Vector2(x, Config.CENTER_Y), facing),
			Group.new(side, Config.GROUP_ARCHERS, Vector2(x - forward * Config.ARCHER_REAR_OFFSET, Config.CENTER_Y), facing),
			Group.new(side, Config.GROUP_CAVALRY, Vector2(x - forward * Config.CAVALRY_REAR_OFFSET, Config.CENTER_Y + cavalry_flank * Config.CAVALRY_FLANK_OFFSET), facing),
		])

func add_grouped_unit(unit: Unit, kind: int) -> void:
	unit.group_kind = kind
	add_unit(unit)
	groups[unit.side][kind].units.append(unit)

func place_units() -> void:
	for side_groups in groups:
		for group in side_groups:
			group.layout(true)
			for unit in group.active_units():
				unit.position = group.slot_position(unit, arena_size)

func give_order(order: String, point: Vector2, selection: int = Config.ALL_GROUPS) -> bool:
	if not order in [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT] or selection < 0 or selection > Config.ALL_GROUPS:
		return false
	var foe := centroid(1)
	var changed := false
	for group in groups[0]:
		if selection != Config.ALL_GROUPS and group.kind != selection or group.active_units().is_empty():
			continue
		changed = true
		if order == Config.ORDER_HOLD:
			group.order = Config.ORDER_HOLD
			group.center = point
			if selection == Config.ALL_GROUPS:
				var face: float = (foe - point).angle() if foe != Vector2.INF else 0.0
				group.center -= Vector2(cos(face), sin(face)) * (Config.HOLD_ARCHER_OFFSET if group.kind == Config.GROUP_ARCHERS else 0.0)
				group.center += Vector2(sin(face), -cos(face)) * (Config.HOLD_CAVALRY_OFFSET if group.kind == Config.GROUP_CAVALRY else 0.0)
			if foe != Vector2.INF:
				group.direction = (foe - group.center).angle()
			group.layout()
		elif order == Config.ORDER_RETREAT:
			group.order = Config.ORDER_HOLD
			group.backing = true
			var face: float = (foe - group.center).angle() if foe != Vector2.INF else 0.0
			group.center = (group.centroid() - Vector2(cos(face), sin(face)) * Config.RETREAT_DISTANCE).clamp(Vector2.ONE * Config.RETREAT_EDGE, arena_size - Vector2.ONE * Config.RETREAT_EDGE)
			group.layout()
		else:
			group.order = order
			if order == Config.ORDER_FOLLOW:
				group.layout()
		if order != Config.ORDER_RETREAT:
			group.backing = false
	return changed

func centroid(side: int) -> Vector2:
	var count := 0
	var total := Vector2.ZERO
	for unit: Unit in units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			total += unit.position
			count += 1
	return total / count if count else Vector2.INF

func add_unit(unit: Unit) -> void:
	assert(unit.battle_index == -1, "A battle unit can only be inserted once")
	unit.battle_index = units.size()
	units.append(unit)
	starting_units[unit.side] += 1

func hurt(target: Unit, raw_damage: float, source: Unit = null, pierce: float = 0.0, rng: RandomNumberGenerator = null, attack: Event.Attack = Event.Attack.NONE) -> int:
	if target.dead:
		return 0
	var amount: int = Damage.after_armor(raw_damage, target.armor, pierce)
	target.hp -= amount
	target.morale -= amount * Config.HIT_MORALE_PER_DAMAGE
	record_event(Event.Kind.HIT, target, source, attack, amount)
	if target.hp <= 0.0 and target.hero and not target.last_stand_used:
		var recovery: float = float(target.perk_effects.get("lastStand", 0.0))
		if recovery > 0.0:
			target.last_stand_used = true
			target.hp = maxf(1.0, target.max_hp * recovery)
			record_event(Event.Kind.LAST_STAND, target, source, attack)
	if target.hp <= 0.0:
		kill(target, source, rng, attack, amount)
	return amount

func kill(target: Unit, source: Unit = null, rng: RandomNumberGenerator = null, attack: Event.Attack = Event.Attack.NONE, amount: int = 0) -> void:
	if target.dead:
		return
	target.dead = true
	target.hp = 0.0
	record_event(Event.Kind.DOWN, target, source, attack, amount)
	if source != null:
		source.kills += 1
		source.morale = minf(source.base_morale, source.morale + Config.KILL_MORALE_BONUS)
		if source.hero:
			var heal: float = float(source.perk_effects.get("killHeal", 0.0))
			if heal > 0.0:
				source.hp = minf(source.max_hp, source.hp + source.max_hp * heal)
	for unit: Unit in units:
		if unit.dead or unit.gone or unit.position.distance_to(target.position) > Config.DEATH_MORALE_RADIUS:
			continue
		if unit.side == target.side:
			unit.morale -= Config.LEADER_DEATH_MORALE if target.leader or target.hero else Config.ALLY_DEATH_MORALE + target.tier * Config.ALLY_DEATH_MORALE_PER_TIER
		else:
			unit.morale = minf(unit.base_morale, unit.morale + Config.ENEMY_DEATH_MORALE_BONUS)
	if target.companion:
		for unit: Unit in units:
			if unit.side == target.side and unit.position.distance_to(target.position) < Config.DEATH_MORALE_RADIUS:
				unit.morale -= Config.COMPANION_DOWN_MORALE_LOSS
	if target.hero and target.side == 0 and not target.companion:
		if not groups.is_empty():
			for group: Group in groups[0]:
				group.order = Config.ORDER_CHARGE
		for unit: Unit in units:
			if unit.side == target.side:
				unit.morale -= Config.HERO_DOWN_MORALE_LOSS
		return
	if target.hero or target.companion or not target.leader:
		return
	if not target.leader_bond.is_empty():
		if rng == null:
			push_error("Leader loss requires the battle RNG")
			return
		for unit: Unit in units:
			if unit.side == target.side and not unit.dead and not unit.gone and unit.leader_bond == target.leader_bond and unit.leader_loss_chance > 0.0 and rng.randf() < unit.leader_loss_chance:
				unit.leader = false
				kill(unit, null, rng)
		var waiting: Array = reserve[target.side]
		if not waiting.is_empty():
			var lost := roundi(waiting.size() * Config.LEADER_BOND_RESERVE_LOSS)
			waiting.assign(waiting.slice(lost))
			reserve_lost[target.side] += lost
	else:
		for unit: Unit in units:
			if unit.side == target.side:
				unit.morale -= Config.LEADER_GLOBAL_MORALE_LOSS
