extends RefCounted
## Field size by the number of fighters and army placement as shares of the field (TERRAIN.md 5, stage Р0а).
## The base field (Config.ARENA_SIZE) keeps the exact numbers of the browser battle, so a battle up to
## ARENA_TIERS[0] fighters a side is bit for bit the same as before. On a larger field the placement grows with the
## field, but the infantry front stands nearer the middle (the tier's front share), so the approach does not drag.
const Config = preload("res://core/battle/config.gd")

## The field for the larger army: `fighters` is the number of figures a side puts on the field at the start.
static func size_for(fighters: int) -> Vector2:
	for tier in Config.ARENA_TIERS:
		if fighters <= int(tier[0]):
			return tier[1]
	return Config.ARENA_TIERS[-1][1]

## Field size over the base field, per axis: exactly (1, 1) on the base field.
static func scale(arena: Vector2) -> Vector2:
	return arena / Config.ARENA_SIZE

## X of side 0's infantry front; side 1 stands mirrored at arena.x - front_x.
static func front_x(arena: Vector2) -> float:
	if arena == Config.ARENA_SIZE:
		return Config.FRONT_X
	var share: float = Config.FRONT_X / Config.ARENA_SIZE.x
	for tier in Config.ARENA_TIERS:
		if tier[1] == arena:
			share = tier[2]
	return roundf(arena.x * share)

## Y of the battle line: the middle of the field.
static func center_y(arena: Vector2) -> float:
	return Config.CENTER_Y if arena == Config.ARENA_SIZE else arena.y * 0.5

## A point given for the base field (the hero's start in BattleSetup) moved with side 0's front to `arena`.
static func from_base(point: Vector2, arena: Vector2) -> Vector2:
	if arena == Config.ARENA_SIZE:
		return point
	return Vector2(front_x(arena), center_y(arena)) + (point - Vector2(Config.FRONT_X, Config.CENTER_Y)) * scale(arena)
