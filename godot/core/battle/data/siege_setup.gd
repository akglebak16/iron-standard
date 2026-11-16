extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Wall = preload("res://core/battle/model/siege_wall.gd")
const Group = preload("res://core/battle/model/group.gd")

const Defense = preload("res://core/battle/model/siege_defense.gd")

## `castle` comes from the settlement kind (B.cfg.fort); `seed_value` places a breach in a battered wall.
static func apply(state: State, skill: float, wall_damage: float = 0.0, supplies: Dictionary = {}, castle: bool = false, seed_value: int = 7) -> void:
	state.siege_skill = clampf(skill, 0.0, Config.SIEGE_SKILL_MAX)
	state.wall = Wall.new(state.arena_size, wall_damage, castle, state.siege_skill, seed_value)
	state.siege_defense = Defense.new(state.wall.all_gaps(), supplies, wall_damage)
	var centers := [state.wall.x + Config.SIEGE_INFANTRY_OFFSET, state.wall.x + Config.SIEGE_ARCHER_OFFSET, state.arena_size.x - Config.SIEGE_CAVALRY_RIGHT_OFFSET]
	for group: Group in state.groups[1]:
		group.center = Vector2(centers[group.kind], state.arena_size.y * 0.5)
		group.direction = PI
		group.order = Config.ORDER_HOLD
		group.tactic_state = Config.AI_TACTIC_SIEGE
