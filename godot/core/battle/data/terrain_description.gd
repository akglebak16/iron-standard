extends RefCounted
## Battle terrain description (TERRAIN.md 4.1, stage Р0б): what the place of a battle looks like, not a ready field.
## BattleSetup.terrain holds it; an empty Dictionary is the open field of the browser battle.
##
## The description is built from a map window: WINDOW x WINDOW cells around the battle, given as plain values so the
## source of the map can change (the campaign map today, the new world map engine later) without touching the battle.
## The campaign reads its map into a window in core/campaign/application/battle_terrain_window.gd; this file turns
## any window into a description. There are no swamps in the game.
##
## Window: {"cells": PackedByteArray of WINDOW * WINDOW map codes (row-major, map y down), "elevation":
## PackedFloat32Array (map height per cell), "road": PackedByteArray (1 = road), "bridge": PackedByteArray (1 = bridge),
## "biome": String, "settlement": "" | "village" | "town" | "castle", "facing": float (map angle from the player's
## army to the enemy)}.
##
## Description: shares of the window "plain", "forest", "hills", "water" (sea and river), "mountains"; "relief" (highest
## minus lowest map height); "high" and "forest_side" (unit directions in the battle frame, ZERO when there is none:
## +x points at the enemy, +y to the player's right); "river", "bridge", "road" (bool); "settlement"; "biome"; "facing".
const WINDOW := 7
enum MapCell { WATER, PLAIN, FOREST, HILLS, MOUNTAINS, RIVER } # The campaign map codes (terrain_generator.gd cells).
const SETTLEMENTS := ["", "village", "town", "castle"]
const SHARES := ["plain", "forest", "hills", "water", "mountains"]
const FLAT_RELIEF := 0.02 # Less relief than this has no high side.
const SIDE_MIN_SHARE := 0.05 # Fewer forest cells than this have no forest side.

static func is_empty(description: Dictionary) -> bool:
	return description.is_empty()

## The description of a window, or an empty Dictionary when the window is malformed.
static func from_window(window: Dictionary) -> Dictionary:
	var count := WINDOW * WINDOW
	var cells = window.get("cells")
	var heights = window.get("elevation")
	var roads = window.get("road")
	var bridges = window.get("bridge")
	if not (cells is PackedByteArray and heights is PackedFloat32Array and roads is PackedByteArray and bridges is PackedByteArray):
		return {}
	if cells.size() != count or heights.size() != count or roads.size() != count or bridges.size() != count:
		return {}
	var facing := float(window.get("facing", 0.0))
	var settlement := str(window.get("settlement", ""))
	if not is_finite(facing) or not settlement in SETTLEMENTS:
		return {}
	var tally := {"plain": 0, "forest": 0, "hills": 0, "water": 0, "mountains": 0}
	var river := false
	var lowest := INF
	var highest := -INF
	var mean := 0.0
	for k in count:
		match cells[k]:
			MapCell.PLAIN: tally.plain += 1
			MapCell.FOREST: tally.forest += 1
			MapCell.HILLS: tally.hills += 1
			MapCell.MOUNTAINS: tally.mountains += 1
			MapCell.RIVER:
				tally.water += 1
				river = true
			_: tally.water += 1
		lowest = minf(lowest, heights[k])
		highest = maxf(highest, heights[k])
		mean += heights[k]
	mean /= count
	var high := Vector2.ZERO
	var forest_side := Vector2.ZERO
	var half := WINDOW / 2
	for k in count:
		var offset := Vector2(k % WINDOW - half, k / WINDOW - half)
		high += offset * (heights[k] - mean)
		if cells[k] == MapCell.FOREST: forest_side += offset
	var description := {"biome": str(window.get("biome", "")), "settlement": settlement, "facing": facing,
		"relief": highest - lowest, "river": river, "bridge": bridges.count(1) > 0, "road": roads.count(1) > 0}
	for key in SHARES:
		description[key] = float(tally[key]) / count
	description.high = to_battle(high, facing) if highest - lowest >= FLAT_RELIEF else Vector2.ZERO
	description.forest_side = to_battle(forest_side, facing) if description.forest >= SIDE_MIN_SHARE else Vector2.ZERO
	return description

## A map direction in the battle frame: the enemy's direction becomes +x. Unit length, or ZERO.
static func to_battle(direction: Vector2, facing: float) -> Vector2:
	if direction.length() < 0.000001:
		return Vector2.ZERO
	return direction.rotated(-facing).normalized()
