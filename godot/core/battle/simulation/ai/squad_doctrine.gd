extends RefCounted
## Stage 1v (DESIGN.md 4.3, decision 14): doctrines of troop types at the group level. The same for both sides, for
## any AI profile and for player orders: a squad of the player and of the AI executes the same order the same way.
## Every group decides every AI_SQUAD_PERIOD_SECONDS, staggered by group number, and at once when its order changes;
## the decisions are inputs the fighter rules read every tick (ai_decision.gd, movement_kernel.hpp):
## - infantry in a charge: formed (a line that keeps its formation and moves its centre) or loose (the old charge);
## - infantry holding: a screen point where its spearmen cover the own archers against closing riders;
## - cavalry in a charge: the shock cycle, run-up and impact, then a rally behind or beyond the target and a new run-up.
## Fighters are sampled with a fixed stride (at most AI_SQUAD_SAMPLE_LIMIT), from the motion columns.
## Stage Р3 (TERRAIN.md 7), only on a field with terrain rules (State.terrain_rules; the open field is untouched):
## - infantry in the forest charges loose;
## - shock cavalry rallies where its run-up crosses no forest or ford, and an AI flank waypoint moves to open ground;
## - AI archers standing in range take the nearest high ground or forest edge (the player's stand where he ordered).
## The terrain is read cell by cell from the grid, without allocating.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const MELEE_MODE := 2 # MotionStore.MODES.find(Config.AI_MODE_MELEE), checked in the doctrine test.
const RANK_MODE := 6 # MotionStore.MODES.find(Config.AI_MODE_RANK).

## Group sample: ready fighters, sums of positions, formation offsets and target positions, fleeing targets, melee
## riders and those of them in contact with foot melee, sum of distances to the slots, melee riders' velocity sum.
class Sample:
	var ready := 0
	var position_sum := Vector2.ZERO
	var offset_sum := Vector2.ZERO
	var aimed := 0
	var fleeing := 0
	var riders := 0
	var contact := 0
	var slot_distance_sum := 0.0
	var velocity_sum := Vector2.ZERO
	var engaged := 0 # In melee mode within AI_FIELD_CONTACT_DISTANCE of the target.
	var waiting := 0 # Keeping a place in a formed line (rank mode).
	var forest := 0 # Standing in a forest cell (stage Р3; counted only on a field with terrain rules).
	var targets := PackedVector2Array()
	var points := PackedVector2Array() # Sampled fighter positions.

	func mean_position() -> Vector2:
		return position_sum / ready

	## Where the group's fighters want to fight: the cluster of their targets around the one nearest to the group's
	## middle (within AI_FORMATION_AIM_RADIUS), not the mean of all targets, which falls between two squads apart.
	func aim() -> Vector2:
		return cluster(targets, mean_position())

	## Mean of the points within AI_FORMATION_AIM_RADIUS of the one nearest to `middle`; INF without points.
	static func cluster(of: PackedVector2Array, middle: Vector2) -> Vector2:
		if of.is_empty():
			return Vector2.INF
		var nearest := of[0]
		for point in of:
			if point.distance_squared_to(middle) < nearest.distance_squared_to(middle):
				nearest = point
		var total := Vector2.ZERO
		var count := 0
		for point in of:
			if point.distance_to(nearest) < Config.AI_FORMATION_AIM_RADIUS:
				total += point
				count += 1
		return total / count

	## Formation centre that fits the sampled fighters for a group facing `direction`.
	func fitted(direction: float) -> Vector2:
		var offset := offset_sum / ready
		return position_sum / ready - Vector2(-sin(direction), cos(direction)) * offset.x - Vector2(cos(direction), sin(direction)) * offset.y

## `ai0`, `ai1`: the player's and the enemy command are led by an AI brain (their hold points are the brain's, not the
## player's orders); the allies (#243) always have their own AI commander.
static func step(battle: State, dt: float, ai0 := false, ai1 := false) -> void:
	if battle.groups.size() < 2:
		return
	for command in battle.groups.size(): # the player, the enemy and the player's allies (#243)
		for kind in battle.groups[command].size():
			var group: Group = battle.groups[command][kind]
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
				Config.GROUP_INFANTRY: _infantry(battle, group, command)
				Config.GROUP_ARCHERS: _archers(battle, group, command, ai0 if command == Config.COMMAND_PLAYER else ai1 if command == Config.COMMAND_ENEMY else true)
				Config.GROUP_CAVALRY: _cavalry(battle, group, command)

static func _infantry(battle: State, group: Group, command: int) -> void:
	if group.order != Config.ORDER_CHARGE or group.backing:
		group.formed = false
		group.mingled = false
		group.contact_seconds = 0.0
		group.doctrine_seconds = maxf(group.doctrine_seconds, Config.AI_FORMATION_SWITCH_SECONDS)
		_screen(battle, group, command)
		return
	group.screen = Vector2.INF
	var sample := sample_group(battle, group)
	if sample.ready == 0:
		group.formed = false
		return
	# A line long in melee with many men waiting out of reach mingles into a general melee (its wings join in);
	# it forms again when the contact is over.
	var in_contact := sample.engaged >= sample.ready * Config.AI_FORMATION_CONTACT_SHARE
	if group.formed:
		group.contact_seconds = group.contact_seconds + Config.AI_SQUAD_PERIOD_SECONDS if in_contact else 0.0
		if group.contact_seconds >= Config.AI_FORMATION_MELEE_SECONDS and sample.waiting >= sample.ready * Config.AI_FORMATION_WAITING_SHARE:
			group.mingled = true
	elif group.mingled and not in_contact:
		group.mingled = false
	var wanted := formed_wanted(battle, group, sample)
	if wanted != group.formed and group.doctrine_seconds >= Config.AI_FORMATION_SWITCH_SECONDS:
		group.formed = wanted
		group.doctrine_seconds = 0.0
		group.contact_seconds = 0.0
		if wanted:
			# Re-form where the men stand, facing the enemy squad to fight.
			var aim := _line_aim(battle, group, command, sample)
			var fitted := sample.fitted(group.direction)
			if aim != Vector2.INF and aim != fitted:
				group.direction = (aim - fitted).angle()
			group.layout()
			group.center = _fitted_center(group)
			return
	if group.formed:
		_march(group, sample, _line_aim(battle, group, command, sample))

## Loose by order, mingled in a long melee, near a siege wall or with the targets across it, in a pursuit and with too
## few fighters; formed otherwise.
static func formed_wanted(battle: State, group: Group, sample: Sample) -> bool:
	if group.loose or group.mingled or sample.ready < Config.AI_FORMATION_MIN_UNITS:
		return false
	# Stage Р3: a line does not hold together among the trees.
	if sample.forest > 0 and sample.forest >= sample.ready * Config.AI_TERRAIN_FOREST_LOOSE_SHARE:
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

## The line marches on the nearest enemy squad (AI_SQUAD_MIN_UNITS ready fighters; a lone hero or companions are no
## squad, as in the stage K decisions of tactics.gd), at the cluster of that squad nearest to it; without squads, on the
## cluster of its fighters' targets.
static func _line_aim(battle: State, group: Group, command: int, sample: Sample) -> Vector2:
	var middle := sample.mean_position()
	var best := Vector2.INF
	var best_distance := INF
	for foe: Group in battle.foe_groups(command):
		var squad := sample_group(battle, foe, false, true)
		if squad.ready < Config.AI_SQUAD_MIN_UNITS:
			continue
		var at := Sample.cluster(squad.points, middle)
		if at.distance_to(middle) < best_distance:
			best_distance = at.distance_to(middle)
			best = at
	return best if best != Vector2.INF else sample.aim()

## The line turns towards its aim at AI_FORMATION_TURN_RATE around its own middle and keeps its slots
## AI_FORMATION_LEAD ahead of where it stands, less when the targets are off its front (none when behind).
static func _march(group: Group, sample: Sample, aim: Vector2) -> void:
	var fitted := sample.fitted(group.direction)
	var heading := group.direction if aim == Vector2.INF or aim == fitted else (aim - fitted).angle()
	var turn := wrapf(heading - group.direction, -PI, PI)
	var limit := Config.AI_FORMATION_TURN_RATE * Config.AI_SQUAD_PERIOD_SECONDS
	group.direction = wrapf(group.direction + clampf(turn, -limit, limit), -PI, PI)
	var lead := Config.AI_FORMATION_LEAD * maxf(0.0, cos(heading - group.direction))
	group.center = sample.fitted(group.direction) + Vector2(cos(group.direction), sin(group.direction)) * lead

## Spearmen of a holding infantry group cover the own archers when enemy riders close in on them.
static func _screen(battle: State, group: Group, command: int) -> void:
	group.screen = Vector2.INF
	# Cheapest checks first: most decisions end here without sampling (no archers, no riders, no infantry).
	var archer_group: Group = battle.groups[command][Config.GROUP_ARCHERS]
	var rider_group: Group = battle.foe_groups(command)[Config.GROUP_CAVALRY]
	if group.units.is_empty() or archer_group.units.is_empty() or rider_group.units.is_empty():
		return
	var archers := sample_group(battle, archer_group, false)
	if archers.ready == 0:
		return
	var riders := sample_group(battle, rider_group, false)
	if riders.riders == 0:
		return
	var archer_center := archers.mean_position()
	var rider_center := riders.mean_position()
	var threat := rider_center - archer_center
	if threat.length() >= Config.AI_SCREEN_THREAT_DISTANCE or riders.velocity_sum.dot(-threat) <= 0.0:
		return
	var own := sample_group(battle, group, false)
	if own.ready == 0 or own.mean_position().distance_to(archer_center) >= Config.AI_SCREEN_RANGE:
		return
	var toward := threat.normalized()
	group.screen = archer_center + toward * Config.AI_SCREEN_OFFSET
	group.screen_lateral = Vector2(-toward.y, toward.x)

## Shock cavalry: after AI_CAVALRY_MELEE_SECONDS stuck in foot melee, rally away from the targets and charge again.
static func _cavalry(battle: State, group: Group, command: int) -> void:
	if group.order != Config.ORDER_CHARGE or group.backing:
		group.rally = false
		group.contact_seconds = 0.0
		if battle.terrain_rules != null and group.tactic_state == Config.AI_TACTIC_FLANK and group.waypoint != group.open_waypoint:
			_open_waypoint(battle, group, command)
		return
	var sample := sample_group(battle, group, true, false, group.rally)
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
	if battle.terrain_rules != null:
		rally_point = _open_rally(battle.terrain_rules, at, away, aim, rally_point, battle.arena_size - edge)
	group.center = rally_point
	if aim != Vector2.INF and aim != group.center:
		group.direction = (aim - group.center).angle()
	group.rally = true
	group.contact_seconds = 0.0
	group.doctrine_seconds = 0.0
	group.layout()

## Stage Р3: the first of the turned ways away whose rally point and run-up to `aim` are open ground; `plain` (the
## straight way away) when none is.
static func _open_rally(grid: TerrainGrid, at: Vector2, away: Vector2, aim: Vector2, plain: Vector2, far_edge: Vector2) -> Vector2:
	var edge := Vector2.ONE * Config.AI_CAVALRY_RALLY_EDGE
	for turn: float in Config.AI_TERRAIN_RALLY_TURNS:
		var point := (at + away.rotated(turn) * Config.AI_CAVALRY_RALLY_DISTANCE).clamp(edge, far_edge)
		if open_run(grid, point, aim, INF):
			return point
	return plain

## Stage Р3: the flank waypoint of an AI cavalry group moves towards the middle of the field until the riders can
## charge from it: open ground there and on the run-up of AI_CAVALRY_CHARGE_DISTANCE towards the enemy. Checked once per
## waypoint the brain sets; it stays where it was when no cell within AI_TERRAIN_WAYPOINT_SHIFTS will do.
static func _open_waypoint(battle: State, group: Group, command: int) -> void:
	var grid := battle.terrain_rules
	var foe := battle.centroid(1 - State.side_of(command))
	var start := group.waypoint
	var toward := signf(battle.arena_size.y * 0.5 - start.y)
	for shift in Config.AI_TERRAIN_WAYPOINT_SHIFTS + 1:
		var point := Vector2(start.x, start.y + toward * shift * Config.TERRAIN_CELL)
		if open_run(grid, point, foe, Config.AI_CAVALRY_CHARGE_DISTANCE):
			group.waypoint = point
			break
	group.open_waypoint = group.waypoint

## Stage Р3: no forest, ford or water (no charge there, TerrainRules.no_charge) at `from` and every TERRAIN_CELL on the
## straight way to `to`, at most `length` of it (INF: the whole way; `to` INF: only `from`).
static func open_run(grid: TerrainGrid, from: Vector2, to: Vector2, length: float) -> bool:
	if _no_charge(grid.cover[grid.index(from)]):
		return false
	if not to.is_finite() or to == from:
		return true
	var way := to - from
	var reach := minf(way.length(), length)
	var step := way.normalized() * Config.TERRAIN_CELL
	for k in range(1, floori(reach / Config.TERRAIN_CELL) + 1):
		if _no_charge(grid.cover[grid.index(from + step * k)]):
			return false
	return true

static func _no_charge(cover: int) -> bool:
	return cover == TerrainGrid.Cover.FOREST or cover == TerrainGrid.Cover.FORD or cover == TerrainGrid.Cover.WATER

## Stage Р3: AI archers holding in range of the enemy take the nearest high ground or forest edge. The post is sought
## once, when the brain's hold point has stood still for one decision (with no such ground they stay posted where they
## stand); the brain moves the centre again when it advances or charges, and the post is sought anew where it stops.
static func _archers(battle: State, group: Group, command: int, ai: bool) -> void:
	if battle.terrain_rules == null or battle.wall != null or not ai or group.order != Config.ORDER_HOLD or group.backing:
		group.post = Vector2.INF
		group.post_anchor = Vector2.INF
		return
	if group.post.is_finite() and group.center == group.post:
		return
	group.post = Vector2.INF
	if group.center != group.post_anchor:
		group.post_anchor = group.center
		return
	var post := _post(battle, group, command)
	if post.is_finite():
		group.center = post
	group.post = group.center

## The nearest cell within AI_TERRAIN_POST_RADIUS higher than the nearest enemy by TERRAIN_HIGHER_STEP, else the nearest
## forest edge, keeping the brain's distance to the enemy (it neither advances nor charges from there); INF when the
## archers already stand on such ground or there is none.
static func _post(battle: State, group: Group, command: int) -> Vector2:
	var grid := battle.terrain_rules
	var foe_groups: Array = battle.foe_groups(command)
	var anchor := group.center
	var near := _nearest_foe(foe_groups, anchor)
	if not near.is_finite():
		return Vector2.INF
	var distance := anchor.distance_to(near)
	if distance > Config.AI_ARCHER_ADVANCE_DISTANCE or distance < Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE:
		return Vector2.INF
	var wanted := grid.elevation[grid.index(near)] + Config.TERRAIN_HIGHER_STEP
	var home := grid.index(anchor)
	if grid.relief and grid.elevation[home] >= wanted:
		return Vector2.INF
	var in_forest: bool = grid.cover[home] == TerrainGrid.Cover.FOREST
	var cells := ceili(Config.AI_TERRAIN_POST_RADIUS / Config.TERRAIN_CELL)
	var cx := clampi(floori(anchor.x / Config.TERRAIN_CELL), 0, grid.width - 1)
	var cy := clampi(floori(anchor.y / Config.TERRAIN_CELL), 0, grid.height - 1)
	var best_high := Vector2.INF
	var best_high_distance := INF
	var best_edge := Vector2.INF
	var best_edge_distance := INF
	for y in range(maxi(0, cy - cells), mini(grid.height, cy + cells + 1)):
		for x in range(maxi(0, cx - cells), mini(grid.width, cx + cells + 1)):
			var point: Vector2 = grid.cell_center(x, y)
			var away := anchor.distance_to(point)
			if away > Config.AI_TERRAIN_POST_RADIUS or (away >= best_high_distance and away >= best_edge_distance):
				continue
			var cell := y * grid.width + x
			var cover: int = grid.cover[cell]
			if cover == TerrainGrid.Cover.WATER or cover == TerrainGrid.Cover.FORD or cover == TerrainGrid.Cover.ROCK:
				continue
			var high: bool = grid.relief and grid.elevation[cell] >= wanted and away < best_high_distance
			if not high and (in_forest or cover != TerrainGrid.Cover.FOREST or away >= best_edge_distance or not _edge(grid, x, y)):
				continue
			# The brain's distance to the enemy, measured to the enemy man nearest to the hold point.
			var reach := point.distance_to(near)
			if reach > Config.AI_ARCHER_ADVANCE_DISTANCE or reach < Config.AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE:
				continue
			if high:
				best_high = point
				best_high_distance = away
			else:
				best_edge = point
				best_edge_distance = away
	return best_high if best_high.is_finite() else best_edge

## A forest cell with open ground (not forest) next to it.
static func _edge(grid: TerrainGrid, x: int, y: int) -> bool:
	var forest := TerrainGrid.Cover.FOREST
	var row := y * grid.width
	return (x + 1 < grid.width and grid.cover[row + x + 1] != forest) or (x > 0 and grid.cover[row + x - 1] != forest) \
		or (y + 1 < grid.height and grid.cover[row + grid.width + x] != forest) or (y > 0 and grid.cover[row - grid.width + x] != forest)

## The enemy squads' sampled fighter nearest to `point` (the brain's squad picture, tactics.gd _scan); INF without one.
static func _nearest_foe(foe_groups: Array, point: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for foe: Group in foe_groups:
		if foe.scan_count < Config.AI_SQUAD_MIN_UNITS:
			continue
		for at in foe.scan_points:
			var d := point.distance_squared_to(at)
			if d < best_distance:
				best_distance = d
				best = at
	return best

## Both points on one side of the siege wall and at least AI_FORMATION_WALL_DISTANCE from it.
static func _clear_of_wall(battle: State, a: Vector2, b: Vector2) -> bool:
	var x: float = battle.wall.x
	var reach := Config.AI_FORMATION_WALL_DISTANCE
	return absf(a.x - x) >= reach and absf(b.x - x) >= reach and (a.x < x) == (b.x < x)

## `targets` false: positions, offsets and riders only, without looking up targets (other squads, the screen).
## `points` keeps every sampled position (the aim at another squad), `slots` sums the distances to the slots (a rally).
static func sample_group(battle: State, group: Group, targets := true, points := false, slots := false) -> Sample:
	var sample := Sample.new()
	var motion = battle.motion
	var flags: PackedInt64Array = motion.integer_fields
	var reals: PackedFloat64Array = motion.real_fields
	var grid: TerrainGrid = battle.terrain_rules if targets else null
	var vectors: PackedVector2Array = motion.vector_fields
	var positions: PackedVector2Array = motion.positions
	var velocities: PackedVector2Array = motion.velocities
	var capacity: int = motion.capacity
	var fields = motion.I
	var count := group.units.size()
	var stride := maxi(1, ceili(float(count) / Config.AI_SQUAD_SAMPLE_LIMIT))
	for index in range(0, count, stride):
		var row: int = group.units[index].battle_index
		if row < 0 or flags[fields.DEAD * capacity + row] or flags[fields.GONE * capacity + row] or flags[fields.FLEEING * capacity + row] or flags[fields.HERO * capacity + row]:
			continue
		var at := positions[row]
		var offset := vectors[motion.V.SLOT_OFFSET * capacity + row]
		sample.ready += 1
		if points:
			sample.points.append(at)
		sample.position_sum += at
		sample.offset_sum += offset
		if slots:
			sample.slot_distance_sum += at.distance_to(group.formation_point(offset, group.center, battle.arena_size))
		var melee_rider := reals[motion.R.ATTACK_RANGE * capacity + row] <= 0.0 and flags[fields.MOUNTED * capacity + row] != 0
		if melee_rider:
			sample.riders += 1
			sample.velocity_sum += velocities[row]
		if not targets:
			continue
		if grid != null and grid.cover[grid.index(at)] == TerrainGrid.Cover.FOREST:
			sample.forest += 1
		var mode: int = flags[fields.MODE * capacity + row]
		if mode == RANK_MODE:
			sample.waiting += 1
		var target := battle.unit_for(flags[fields.TARGET_HANDLE * capacity + row])
		var other: int = target.battle_index if target != null else -1
		if other < 0 or flags[fields.DEAD * capacity + other] or flags[fields.GONE * capacity + other] or flags[fields.SIDE * capacity + other] == group.side:
			continue
		var target_at := positions[other]
		if mode == MELEE_MODE and at.distance_to(target_at) < Config.AI_FIELD_CONTACT_DISTANCE:
			sample.engaged += 1
		sample.targets.append(target_at)
		sample.aimed += 1
		if flags[fields.FLEEING * capacity + other]:
			sample.fleeing += 1
		if melee_rider and not flags[fields.MOUNTED * capacity + other] and reals[motion.R.ATTACK_RANGE * capacity + other] <= 0.0:
			var reach: float = reals[motion.R.COLLISION_RADIUS * capacity + row] + reals[motion.R.COLLISION_RADIUS * capacity + other] + reals[motion.R.MELEE_REACH * capacity + row]
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
