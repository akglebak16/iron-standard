extends RefCounted
## Rules of the battle terrain (TERRAIN.md 4.4, stage Р1а), read from the terrain grid in O(1) and without allocating.
## The fighter-level part (speed, charge, shooting range, sight) is mirrored bit for bit in movement_kernel.hpp
## (terrain_speed, no_charge, range_scale, hidden), and so is the AI's use of it in target choice (stage Р3: aim_weight
## and the cell speed in "I will not catch him"); test_native_movement.gd compares them on a field with terrain.
## The blow-level part (higher ground, the bank of a ford, cover from arrows) runs only here, for both backends.
## Every function takes State.terrain_rules: null on an open, flat field, where no rule changes anything.
const Config = preload("res://core/battle/config.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")

## Speed multiplier of a fighter at `at` walking along `delta` (`distance` = delta.length(), above zero): cover times
## slope, not below TERRAIN_MIN_SPEED. The slope is the height gradient of the cell (neighbour cells on both sides)
## along the way; the same arithmetic as terrain_speed() in movement_kernel.hpp.
static func speed_scale(grid: TerrainGrid, at: Vector2, delta: Vector2, distance: float) -> float:
	var x := clampi(floori(at.x / Config.TERRAIN_CELL), 0, grid.width - 1)
	var y := clampi(floori(at.y / Config.TERRAIN_CELL), 0, grid.height - 1)
	var scale: float = Config.TERRAIN_COVER_SPEED[grid.cover[y * grid.width + x]]
	if grid.relief:
		var heights := grid.elevation
		var gx: int = heights[y * grid.width + mini(x + 1, grid.width - 1)] - heights[y * grid.width + maxi(x - 1, 0)]
		var gy: int = heights[mini(y + 1, grid.height - 1) * grid.width + x] - heights[maxi(y - 1, 0) * grid.width + x]
		var along := float(gx) * delta.x + float(gy) * delta.y
		var step := Config.TERRAIN_SLOPE_STEP * distance
		if along >= step:
			scale *= Config.TERRAIN_UPHILL_SPEED
		elif along <= -step:
			scale *= Config.TERRAIN_DOWNHILL_SPEED
	return maxf(Config.TERRAIN_MIN_SPEED, scale)

## No charge from the forest, a ford or water: the horse cannot gather speed there.
static func no_charge(grid: TerrainGrid, at: Vector2) -> bool:
	if grid == null:
		return false
	var cover: int = grid.cover[grid.index(at)]
	return cover == TerrainGrid.Cover.FOREST or cover == TerrainGrid.Cover.FORD or cover == TerrainGrid.Cover.WATER

## A shooter at `at` higher than his target at `target` shoots TERRAIN_HIGH_RANGE_MULTIPLIER farther.
static func range_scale(grid: TerrainGrid, at: Vector2, target: Vector2) -> float:
	if grid == null or not grid.relief:
		return 1.0
	return Config.TERRAIN_HIGH_RANGE_MULTIPLIER if grid.elevation[grid.index(at)] - grid.elevation[grid.index(target)] >= Config.TERRAIN_HIGHER_STEP else 1.0

## A shooter does not see an enemy in the forest farther than TERRAIN_FOREST_SIGHT (`raw` is the plain distance).
static func hidden(grid: TerrainGrid, enemy_at: Vector2, raw: float) -> bool:
	return grid != null and raw > Config.TERRAIN_FOREST_SIGHT and grid.cover[grid.index(enemy_at)] == TerrainGrid.Cover.FOREST

## Damage multiplier of a melee blow or a charge: higher ground, and the bank against a man wading in a ford.
static func strike_scale(grid: TerrainGrid, at: Vector2, target: Vector2) -> float:
	if grid == null:
		return 1.0
	var from := grid.index(at)
	var to := grid.index(target)
	var scale := 1.0
	if grid.relief and grid.elevation[from] - grid.elevation[to] >= Config.TERRAIN_HIGHER_STEP:
		scale *= Config.TERRAIN_HIGH_STRIKE_MULTIPLIER
	if _wading(grid.cover[from]) and not _wading(grid.cover[to]):
		scale /= Config.TERRAIN_BANK_DEFENSE
	return scale

## Chance that an arrow landing on a man at `at` reaches him through the cover (1 in the open).
static func hit_chance(grid: TerrainGrid, at: Vector2) -> float:
	if grid == null:
		return 1.0
	match grid.cover[grid.index(at)]:
		TerrainGrid.Cover.FOREST: return Config.TERRAIN_FOREST_HIT_CHANCE
		TerrainGrid.Cover.BRUSH: return Config.TERRAIN_BRUSH_HIT_CHANCE
	return 1.0

## Stage Р3 (TERRAIN.md 7): a shooter's target weight with the terrain, only ever raised. A target in cover looks
## farther by the inverse of the arrow's chance to reach it (forest, brush), and on a field with relief a target the
## shooter does not stand higher than (TERRAIN_HIGHER_STEP) looks TERRAIN_HIGH_RANGE_MULTIPLIER farther: the same as a
## lower target being nearer in the range units of the higher-ground rule. consider() in movement_kernel.hpp does the same.
static func aim_weight(grid: TerrainGrid, at: Vector2, target: Vector2, weighted: float) -> float:
	var to := grid.index(target)
	var cover: int = grid.cover[to]
	if cover == TerrainGrid.Cover.FOREST:
		weighted /= Config.TERRAIN_FOREST_HIT_CHANCE
	elif cover == TerrainGrid.Cover.BRUSH:
		weighted /= Config.TERRAIN_BRUSH_HIT_CHANCE
	if grid.relief and grid.elevation[grid.index(at)] - grid.elevation[to] < Config.TERRAIN_HIGHER_STEP:
		weighted *= Config.TERRAIN_HIGH_RANGE_MULTIPLIER
	return weighted

static func _wading(cover: int) -> bool:
	return cover == TerrainGrid.Cover.FORD or cover == TerrainGrid.Cover.WATER
