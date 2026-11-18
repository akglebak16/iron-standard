extends RefCounted
## The one place where the campaign map becomes the place of a battle (TERRAIN.md 4.1, stage Р0б): the map window
## around the battle, read into the plain values TerrainDescription takes. When the world map engine changes (#184-#189),
## only `read` changes; the battle and its templates stay as they are.
const TerrainDescription = preload("res://core/battle/data/terrain_description.gd")

const SETTLEMENT_RADIUS := 80.0 # A village, town or castle this close to the battle stands by the field.
const SETTLEMENT_KINDS := ["village", "town", "castle"]

## The description of the battle at `at` with the enemy coming from `toward` (map units).
static func describe(map: RefCounted, at: Vector2, toward: Vector2) -> Dictionary:
	return TerrainDescription.from_window(read(map, at, toward))

## The TerrainDescription window: WINDOW x WINDOW map cells centred on the cell of `at`. Cells off the map read as
## the nearest edge cell, like the map's own point queries.
static func read(map: RefCounted, at: Vector2, toward: Vector2) -> Dictionary:
	var terrain = map.terrain
	var size := TerrainDescription.WINDOW
	var half := size / 2
	var step: float = terrain.GC
	var cells := PackedByteArray()
	var heights := PackedFloat32Array()
	var roads := PackedByteArray()
	var bridges := PackedByteArray()
	var road: PackedByteArray = map.paths.road if map.paths != null else PackedByteArray()
	for row in size:
		for column in size:
			var point := at + Vector2(column - half, row - half) * step
			var k: int = terrain.cell_of(point.x, point.y)
			cells.append(terrain.cells[k] if k < terrain.cells.size() else TerrainDescription.MapCell.PLAIN)
			heights.append(terrain.elevation(point.x, point.y))
			roads.append(1 if k < road.size() and road[k] != 0 else 0)
			bridges.append(1 if k < terrain.bridge.size() and terrain.bridge[k] != 0 else 0)
	return {"cells": cells, "elevation": heights, "road": roads, "bridge": bridges,
		"biome": terrain.biome_name(at.x, at.y), "settlement": _settlement(map, at),
		"facing": (toward - at).angle() if toward != at else 0.0}

static func _settlement(map: RefCounted, at: Vector2) -> String:
	var best := ""
	var nearest := SETTLEMENT_RADIUS
	for s in map.settles:
		if not s.get("kind") in SETTLEMENT_KINDS: continue
		var d := at.distance_to(Vector2(float(s.x), float(s.y)))
		if d <= nearest:
			nearest = d
			best = s.kind
	return best
