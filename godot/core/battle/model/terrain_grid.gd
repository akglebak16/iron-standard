extends RefCounted
## Terrain of the battlefield (TERRAIN.md 3.4, stage Р0б): a grid of TERRAIN_CELL cells, one cover byte and one
## height byte per cell, read in O(1). The same layout is read by C++ (core/battle/api/native/terrain_grid.hpp);
## test_native_terrain_grid.gd compares them. The rules that read it are rules/terrain_rules.gd (stage Р1а).
const Config = preload("res://core/battle/config.gd")

## Cover of a cell. The order is the byte stored in the grid and in C++; append, never reorder. There are no swamps.
enum Cover { OPEN, BRUSH, FOREST, FIELD, ROAD, FORD, BRIDGE, WATER, ROCK }

var width := 0 # Cells along x.
var height := 0 # Cells along y.
var cover := PackedByteArray()
var elevation := PackedByteArray() # 0 is the lowest ground of the field, 255 the highest.
var relief := false # Some height byte is set: the slope and height rules read the grid. refresh() sets it.

## An open, flat grid covering `arena`.
static func create(arena: Vector2) -> RefCounted:
	var grid = new()
	grid.width = maxi(1, ceili(arena.x / Config.TERRAIN_CELL))
	grid.height = maxi(1, ceili(arena.y / Config.TERRAIN_CELL))
	grid.cover.resize(grid.width * grid.height)
	grid.elevation.resize(grid.width * grid.height)
	return grid

## Cell index of a field point; points off the field read the nearest edge cell.
func index(at: Vector2) -> int:
	var x := clampi(floori(at.x / Config.TERRAIN_CELL), 0, width - 1)
	var y := clampi(floori(at.y / Config.TERRAIN_CELL), 0, height - 1)
	return y * width + x

func cover_at(at: Vector2) -> int:
	return cover[index(at)]

func height_at(at: Vector2) -> int:
	return elevation[index(at)]

## Centre of cell (x, y) in field units.
func cell_center(x: int, y: int) -> Vector2:
	return (Vector2(x, y) + Vector2(0.5, 0.5)) * Config.TERRAIN_CELL

## Call after filling: caches what the rules ask on every tick.
func refresh() -> void:
	relief = elevation.count(0) != elevation.size()

## True when nothing is set: the open, flat field of the browser battle.
func is_open() -> bool:
	for value in cover:
		if value != Cover.OPEN: return false
	for value in elevation:
		if value != 0: return false
	return true

func count(kind: int) -> int:
	return cover.count(kind)
