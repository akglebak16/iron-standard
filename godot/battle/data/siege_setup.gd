extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Wall = preload("res://battle/model/siege_wall.gd")
const Group = preload("res://battle/model/group.gd")

static func apply(state: State, skill: float) -> void:
	state.wall = Wall.new(state.arena_size)
	state.siege_skill = clampf(skill, 0.0, Config.SIEGE_SKILL_MAX)
	var centers := [state.wall.x + Config.SIEGE_INFANTRY_OFFSET, state.wall.x + Config.SIEGE_ARCHER_OFFSET, state.arena_size.x - Config.SIEGE_CAVALRY_RIGHT_OFFSET]
	for group: Group in state.groups[1]:
		group.center = Vector2(centers[group.kind], state.arena_size.y * 0.5)
		group.direction = PI
		group.order = Config.ORDER_HOLD
		group.tactic_state = Config.AI_TACTIC_SIEGE
