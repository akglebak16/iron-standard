extends SceneTree
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const AiDecision = preload("res://core/battle/rules/ai_decision.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const CombatStep = preload("res://core/battle/rules/combat_step.gd")

func _initialize() -> void:
	_check_target_weights()
	_check_retarget_timer()
	_check_modes()
	_check_live_shoot_mode()
	print("AI targeting and mode tests passed")
	quit(0)

func _check_target_weights() -> void:
	var state := State.new()
	var fighter := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	var fleeing := Unit.new(1, 1, Vector2(60, 0), 100, 0, 1)
	fleeing.fleeing = true
	var steady := Unit.new(2, 1, Vector2(65, 0), 100, 0, 1)
	for unit in [fighter, fleeing, steady]:
		state.add_unit(unit)
	assert(Targeting.choose(state, fighter) == steady) # 60 × 1.7 > 65.
	fighter.target_handle = fleeing.unit_handle
	assert(Targeting.choose(state, fighter) == steady)
	fleeing.fleeing = false
	assert(Targeting.choose(state, fighter) == fleeing) # Current target gets × 0.85.
	fighter.target_handle = steady.unit_handle
	assert(Targeting.choose(state, fighter) == steady) # Sticky target beats closer enemy.
	fighter.mounted = true
	steady.attack_range = 200
	assert(Targeting.choose(state, fighter) == steady) # Mounted melee prefers foot archer.
	steady.dead = true
	assert(Targeting.choose(state, fighter) == fleeing)
	fleeing.gone = true
	assert(Targeting.choose(state, fighter) == null)

func _check_retarget_timer() -> void:
	var state := State.new()
	var fighter := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	var first := Unit.new(101, 1, Vector2(30, 0), 100, 0, 1)
	var second := Unit.new(102, 1, Vector2(40, 0), 100, 0, 1)
	for unit in [fighter, first, second]:
		state.add_unit(unit)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	assert(Targeting.refresh(state, fighter, 0.01, rng) == first)
	var timer := fighter.target_timer
	first.position = Vector2(1000, 0)
	assert(Targeting.refresh(state, fighter, 0.01, rng) == first) # Hold current target until timer expires.
	assert(is_equal_approx(fighter.target_timer, timer - 0.01))
	assert(Targeting.refresh(state, fighter, timer, rng) == second)
	second.dead = true
	assert(Targeting.refresh(state, fighter, 0.01, rng) == first) # Dead target triggers immediate refresh.

func _check_modes() -> void:
	var foot := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	var foe := Unit.new(1, 1, Vector2(300, 100), 100, 0, 1)
	var group := Group.new(0, Config.GROUP_INFANTRY, foot.position, 0.0)
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_SLOT)
	group.order = Config.ORDER_CHARGE
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_MELEE)
	foot.attack_range = 300
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_SHOOT)
	group.order = Config.ORDER_HOLD
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_SHOOT_SLOT)
	foe.position = Vector2(130, 100)
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_MELEE)
	group.backing = true
	group.center = Vector2(600, 100)
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).mode == Config.AI_MODE_SLOT)
	group.backing = false
	group.center = foot.position
	foot.mounted = true
	foe.position = Vector2(200, 100)
	var skirm := AiDecision.plan(foot, group, foe, Config.ARENA_SIZE)
	assert(skirm.mode == Config.AI_MODE_SKIRMISH)
	assert(skirm.destination != foe.position and skirm.speed_scale == Config.AI_SKIRMISH_SPEED_MULTIPLIER)
	foe.position = foot.position
	assert(AiDecision.plan(foot, group, foe, Config.ARENA_SIZE).destination.is_finite())

func _check_live_shoot_mode() -> void:
	var state := State.new()
	state.setup_groups()
	var archer := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	archer.speed = 50
	archer.damage = 20
	archer.attack_range = 300
	archer.attack_interval = 1
	var foe := Unit.new(1, 1, Vector2(200, 100), 100, 0, 1)
	state.add_grouped_unit(archer, Config.GROUP_ARCHERS)
	state.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	state.groups[0][Config.GROUP_ARCHERS].center = archer.position
	var rng := RandomNumberGenerator.new()
	Movement.step(state, 0.01, rng)
	assert(archer.ai_mode == Config.AI_MODE_SHOOT_SLOT and archer.target_handle == foe.unit_handle)
	assert(state.projectiles.size() == 1)
