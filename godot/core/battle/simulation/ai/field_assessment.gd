extends RefCounted
## Field assessment of DESIGN.md 4.1: a summary of every group of both sides for commander decisions, the
## arena and the debug overlay. Computed only on request, in one pass over the packed unit columns plus a
## pass over the six group summaries. Reads the state, mutates nothing and draws no RNG.
##
## Input: State columns (side, group, flags, mode, health, weight, range, target distance, position, facing) and the
## unit fields morale, base_morale, tier, anti_cavalry and wavering. Output: detached dictionaries.
## Frequency: once per morale check (rules/morale.gd, stage 1b) and per commander decision. Thread safety: call
## between ticks.
##
## Sectors of the threat are taken against the group's front: its direction while it keeps a formation (holding,
## following, a formed line, stage 1v), the mean facing of its men in a loose charge, where the group direction is
## only the heading of the order.
##
## Terrain layer (stage Р3, TERRAIN.md 7), for the commander (stage 1g) and the debug overlay; the threat and morale do
## not read it yet. Per group: mean height byte and the shares of its men in the forest, the brush and wading (ford or
## water). Per field ("terrain"): the static survey of the grid — hill tops, forests and crossings (fords, bridges),
## the narrow places — built once per field (survey_of: the factory builds it with the field, never in a tick).
##
## Unit classes come from properties (mounted, attack_range, anti_cavalry), never from troop IDs.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")

static func unit_class(mounted: bool, ranged: bool, anti_cavalry: bool) -> int:
	if mounted:
		return Config.AI_CLASS_HORSE_ARCHER if ranged else Config.AI_CLASS_CAVALRY
	if ranged:
		return Config.AI_CLASS_ARCHER
	return Config.AI_CLASS_SPEAR if anti_cavalry else Config.AI_CLASS_FOOT

## {"sides": [side 0, side 1]}; each side has totals and "groups" indexed by group kind.
static func assess(battle: State) -> Dictionary:
	var kinds := Config.GROUP_KINDS
	var slots := 2 * kinds
	var count := PackedInt32Array(); count.resize(slots)
	var fleeing := PackedInt32Array(); fleeing.resize(slots)
	var wavering := PackedInt32Array(); wavering.resize(slots)
	var engaged := PackedInt32Array(); engaged.resize(slots)
	var power := PackedFloat64Array(); power.resize(slots)
	var class_power := PackedFloat64Array(); class_power.resize(slots * Config.AI_CLASSES)
	var class_count := PackedInt32Array(); class_count.resize(slots * Config.AI_CLASSES)
	var morale := PackedFloat64Array(); morale.resize(slots)
	var base_morale := PackedFloat64Array(); base_morale.resize(slots)
	var position_sum := PackedVector2Array(); position_sum.resize(slots)
	var lateral_min := PackedFloat64Array(); lateral_min.resize(slots)
	var lateral_max := PackedFloat64Array(); lateral_max.resize(slots)
	var laterals := PackedVector2Array(); laterals.resize(slots)
	var facings := PackedVector2Array(); facings.resize(slots)
	var loose := PackedByteArray(); loose.resize(slots) # Loose charge: the front is the men's mean facing.
	var grid: TerrainGrid = battle.terrain_rules
	var height_sum := PackedFloat64Array(); height_sum.resize(slots)
	var forest := PackedInt32Array(); forest.resize(slots)
	var brush := PackedInt32Array(); brush.resize(slots)
	var wading := PackedInt32Array(); wading.resize(slots)
	for slot in slots:
		lateral_min[slot] = INF
		lateral_max[slot] = -INF
		var group = _group(battle, slot / kinds, slot % kinds)
		var direction: float = group.direction if group != null else 0.0
		laterals[slot] = Vector2(-sin(direction), cos(direction))
		loose[slot] = int(group != null and group.order == Config.ORDER_CHARGE and not group.formed)
	var motion := battle.motion
	var capacity := motion.capacity
	var flags := motion.integer_fields
	var reals := motion.real_fields
	var positions := motion.positions
	var I = MotionStore.I
	var R = MotionStore.R
	var melee_mode := MotionStore.MODES.find(Config.AI_MODE_MELEE)
	for row in battle.active_units.size():
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var kind: int = flags[I.GROUP_KIND * capacity + row]
		if kind < 0 or kind >= kinds:
			continue
		var slot: int = flags[I.SIDE * capacity + row] * kinds + kind
		if flags[I.FLEEING * capacity + row]:
			fleeing[slot] += 1
			continue
		var unit: Unit = battle.active_units[row]
		var max_hp: float = reals[R.MAX_HP * capacity + row]
		var health: float = clampf(reals[R.HP * capacity + row] / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
		var unit_power: float = reals[R.WEIGHT * capacity + row] * health * (1.0 + Config.AI_FIELD_TIER_POWER * unit.tier)
		var klass := unit_class(bool(flags[I.MOUNTED * capacity + row]), reals[R.ATTACK_RANGE * capacity + row] > 0.0, bool(flags[I.ANTI_CAVALRY * capacity + row]))
		count[slot] += 1
		power[slot] += unit_power
		class_power[slot * Config.AI_CLASSES + klass] += unit_power
		class_count[slot * Config.AI_CLASSES + klass] += 1
		morale[slot] += unit.morale
		base_morale[slot] += unit.base_morale
		if flags[I.WAVERING * capacity + row]: wavering[slot] += 1
		if flags[I.MODE * capacity + row] == melee_mode and reals[R.PLAN_DISTANCE * capacity + row] <= Config.AI_FIELD_CONTACT_DISTANCE:
			engaged[slot] += 1
		var at := positions[row]
		if loose[slot]:
			var facing: float = reals[R.FACING * capacity + row]
			facings[slot] += Vector2(cos(facing), sin(facing))
		position_sum[slot] += at
		if grid != null:
			var cell := grid.index(at)
			height_sum[slot] += grid.elevation[cell]
			match grid.cover[cell]:
				TerrainGrid.Cover.FOREST: forest[slot] += 1
				TerrainGrid.Cover.BRUSH: brush[slot] += 1
				TerrainGrid.Cover.FORD, TerrainGrid.Cover.WATER: wading[slot] += 1
		var lateral := at.dot(laterals[slot])
		lateral_min[slot] = minf(lateral_min[slot], lateral)
		lateral_max[slot] = maxf(lateral_max[slot], lateral)
	var centers := PackedVector2Array(); centers.resize(slots)
	for slot in slots:
		centers[slot] = position_sum[slot] / count[slot] if count[slot] > 0 else Vector2.INF
	# matchup[slot][foe kind]: own strength against that enemy group's mix of classes.
	var matchups: Array[PackedFloat64Array] = []
	for slot in slots:
		var side := slot / kinds
		var row := PackedFloat64Array(); row.resize(kinds)
		for foe_kind in kinds:
			row[foe_kind] = _matchup(class_power, power, slot, (1 - side) * kinds + foe_kind)
		matchups.append(row)
	var sides: Array[Dictionary] = []
	for side in 2:
		var groups: Array[Dictionary] = []
		var side_count := 0
		var side_power := 0.0
		var side_fleeing := 0
		var side_sum := Vector2.ZERO
		for kind in kinds:
			var slot := side * kinds + kind
			side_count += count[slot]
			side_power += power[slot]
			side_fleeing += fleeing[slot]
			side_sum += position_sum[slot]
			var classes := PackedInt32Array()
			var class_strength := PackedFloat64Array()
			for klass in Config.AI_CLASSES:
				classes.append(class_count[slot * Config.AI_CLASSES + klass])
				class_strength.append(class_power[slot * Config.AI_CLASSES + klass])
			var group = _group(battle, side, kind)
			var frame := _frame(group, facings[slot])
			var threat := _threat(slot, kinds, count, centers, matchups, frame)
			var ready: int = count[slot]
			groups.append({"side": side, "kind": kind, "count": ready, "fleeing": fleeing[slot], "wavering": wavering[slot],
				"strength": power[slot], "classes": classes, "class_strength": class_strength, "center": centers[slot],
				"direction": group.direction if group != null else 0.0, "frame": frame,
				"front_width": lateral_max[slot] - lateral_min[slot] if ready > 0 else 0.0,
				"engaged_share": float(engaged[slot]) / ready if ready > 0 else 0.0,
				"engaged": ready > 0 and float(engaged[slot]) / ready >= Config.AI_FIELD_ENGAGED_SHARE,
				"morale": morale[slot] / ready if ready > 0 else 0.0,
				"morale_share": morale[slot] / base_morale[slot] if base_morale[slot] > 0.0 else 0.0,
				"matchup": matchups[slot], "threat_front": threat.x, "threat_flank": threat.y, "threat_rear": threat.z,
				"height": height_sum[slot] / ready if ready > 0 else 0.0,
				"forest_share": float(forest[slot]) / ready if ready > 0 else 0.0,
				"brush_share": float(brush[slot]) / ready if ready > 0 else 0.0,
				"wading_share": float(wading[slot]) / ready if ready > 0 else 0.0})
		sides.append({"side": side, "count": side_count, "strength": side_power, "fleeing": side_fleeing,
			"center": side_sum / side_count if side_count > 0 else Vector2.INF, "groups": groups})
	return {"sides": sides, "terrain": survey_of(battle).duplicate(true)}

## The static terrain layer of the field (stage Р3), cached in the state for the grid of the terrain rules.
static func survey_of(battle: State) -> Dictionary:
	if battle.terrain_survey.is_empty() or battle.terrain_survey_grid != battle.terrain_rules:
		battle.terrain_survey = survey(battle.terrain_rules)
		battle.terrain_survey_grid = battle.terrain_rules
	return battle.terrain_survey

## Hill tops (highest first, {at, height}), forests and crossings ({center, rect, cells}; a crossing also has
## "bridge"), largest first, and the shares of forest, brush and water of the field. `grid` null: the open field.
static func survey(grid: TerrainGrid) -> Dictionary:
	var result := {"relief": false, "tops": [], "forests": [], "crossings": [], "forest_share": 0.0, "brush_share": 0.0, "water_share": 0.0}
	if grid == null:
		return result
	var total := float(grid.width * grid.height)
	result.relief = grid.relief
	result.forest_share = grid.count(TerrainGrid.Cover.FOREST) / total
	result.brush_share = grid.count(TerrainGrid.Cover.BRUSH) / total
	result.water_share = grid.count(TerrainGrid.Cover.WATER) / total
	if grid.relief:
		result.tops = _tops(grid)
	result.forests = _patches(grid, TerrainGrid.Cover.FOREST, TerrainGrid.Cover.FOREST)
	result.crossings = _patches(grid, TerrainGrid.Cover.FORD, TerrainGrid.Cover.BRIDGE)
	return result

## Local maxima of the height at least AI_TERRAIN_SURVEY_HILL, highest first, AI_TERRAIN_SURVEY_TOP_SPACING apart.
static func _tops(grid: TerrainGrid) -> Array:
	var width := grid.width
	var heights := grid.elevation
	var candidates: Array[Vector3i] = []
	for y in grid.height:
		for x in width:
			var level: int = heights[y * width + x]
			if level < Config.AI_TERRAIN_SURVEY_HILL:
				continue
			var top := true
			for ny in range(maxi(0, y - 1), mini(grid.height, y + 2)):
				for nx in range(maxi(0, x - 1), mini(width, x + 2)):
					if heights[ny * width + nx] > level:
						top = false
			if top:
				candidates.append(Vector3i(x, y, level))
	candidates.sort_custom(func(a: Vector3i, b: Vector3i): return a.z > b.z or a.z == b.z and a.y * width + a.x < b.y * width + b.x)
	var tops := []
	for candidate in candidates:
		var at: Vector2 = grid.cell_center(candidate.x, candidate.y)
		var apart := true
		for top: Dictionary in tops:
			if at.distance_to(top.at) < Config.AI_TERRAIN_SURVEY_TOP_SPACING:
				apart = false
				break
		if apart:
			tops.append({"at": at, "height": candidate.z})
			if tops.size() >= Config.AI_TERRAIN_SURVEY_TOPS:
				break
	return tops

## Patches of cells of cover `kind` or `other` joined by their sides, at least AI_TERRAIN_SURVEY_PATCH cells, the
## largest AI_TERRAIN_SURVEY_PATCHES of them (equal ones in grid order).
static func _patches(grid: TerrainGrid, kind: int, other: int) -> Array:
	var width := grid.width
	var cover := grid.cover
	var seen := PackedByteArray(); seen.resize(cover.size())
	var queue := PackedInt32Array()
	var patches := []
	for start in cover.size():
		if seen[start] or (cover[start] != kind and cover[start] != other):
			continue
		seen[start] = 1
		queue.resize(1)
		queue[0] = start
		var head := 0
		var lower := Vector2i(width, grid.height)
		var upper := Vector2i(-1, -1)
		var sum := Vector2.ZERO
		var bridge := false
		while head < queue.size():
			var cell: int = queue[head]
			head += 1
			var x := cell % width
			var y := cell / width
			lower = Vector2i(mini(lower.x, x), mini(lower.y, y))
			upper = Vector2i(maxi(upper.x, x), maxi(upper.y, y))
			sum += grid.cell_center(x, y)
			bridge = bridge or cover[cell] == TerrainGrid.Cover.BRIDGE
			for next in [cell - 1 if x > 0 else -1, cell + 1 if x + 1 < width else -1, cell - width, cell + width]:
				if next >= 0 and next < cover.size() and not seen[next] and (cover[next] == kind or cover[next] == other):
					seen[next] = 1
					queue.append(next)
		if queue.size() < Config.AI_TERRAIN_SURVEY_PATCH:
			continue
		var cell_size := Config.TERRAIN_CELL
		var patch := {"center": sum / queue.size(), "cells": queue.size(),
			"rect": Rect2(Vector2(lower) * cell_size, Vector2(upper - lower + Vector2i.ONE) * cell_size)}
		if kind != other:
			patch.bridge = bridge
		patches.append(patch)
	patches.sort_custom(func(a: Dictionary, b: Dictionary): return a.cells > b.cells)
	return patches.slice(0, Config.AI_TERRAIN_SURVEY_PATCHES)

static func _group(battle: State, side: int, kind: int):
	if battle.groups.size() <= side or battle.groups[side].size() <= kind: return null
	return battle.groups[side][kind]

## The front the threat sectors are measured from: the group direction while the group keeps a formation, the mean
## facing of its ready men in a loose charge.
static func _frame(group, facing_sum: Vector2) -> float:
	if group == null:
		return 0.0
	if group.order == Config.ORDER_CHARGE and not group.formed and facing_sum != Vector2.ZERO:
		return facing_sum.angle()
	return group.direction

## Own class strengths, each weighted by the matrix against the enemy group's class shares.
static func _matchup(class_power: PackedFloat64Array, power: PackedFloat64Array, slot: int, foe_slot: int) -> float:
	if power[foe_slot] <= 0.0: return 0.0
	var total := 0.0
	for klass in Config.AI_CLASSES:
		var own := class_power[slot * Config.AI_CLASSES + klass]
		if own <= 0.0: continue
		var factor := 0.0
		for foe_class in Config.AI_CLASSES:
			factor += class_power[foe_slot * Config.AI_CLASSES + foe_class] / power[foe_slot] * Config.AI_MATCHUP[klass][foe_class]
		total += own * factor
	return total

## Enemy strength against this group, fading with distance, split by the sector it comes from:
## x front, y flanks, z rear, relative to the group's facing.
static func _threat(slot: int, kinds: int, count: PackedInt32Array, centers: PackedVector2Array, matchups: Array[PackedFloat64Array], direction: float) -> Vector3:
	var threat := Vector3.ZERO
	if count[slot] == 0: return threat
	var foe_side := 1 - slot / kinds
	for foe_kind in kinds:
		var foe_slot := foe_side * kinds + foe_kind
		if count[foe_slot] == 0: continue
		var offset := centers[foe_slot] - centers[slot]
		var distance := offset.length()
		if distance >= Config.AI_FIELD_THREAT_RADIUS: continue
		var weight: float = matchups[foe_slot][slot % kinds] * (1.0 - distance / Config.AI_FIELD_THREAT_RADIUS)
		var angle := absf(wrapf(offset.angle() - direction, -PI, PI)) if distance > 0.0 else 0.0
		if angle <= Config.AI_FIELD_FRONT_ARC: threat.x += weight
		elif angle < Config.AI_FIELD_REAR_ARC: threat.y += weight
		else: threat.z += weight
	return threat
