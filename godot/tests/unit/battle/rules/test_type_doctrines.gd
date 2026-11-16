extends SceneTree
## Stage 1v (DESIGN.md 4.3, 4.4, decision 14): fighter rules of the troop type doctrines, the same for both sides.
## Formed line (front ranks fight, rear ranks keep their places, no leash), rallying riders, spearmen bracing and
## screening the archers, archers falling back towards their infantry, and the target priorities: shooters prefer men
## without shields, riders avoid the points of a spearman facing them. Synthetic units with unrelated IDs; properties
## (anti_cavalry, shield_block, mounted, attack_range), never troop IDs; plain scan and spatial index agree.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const AiDecision = preload("res://core/battle/rules/ai_decision.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")

const CENTER := Vector2(1300, 850)

func _initialize() -> void:
	for side in 2:
		_check_formed(side)
		_check_rally(side)
		_check_brace(side)
		_check_screen(side)
		_check_fallback(side)
		_check_shield_priority(side)
		_check_spear_priority(side)
	print("Type doctrine tests passed")
	quit(0)

func _unit(state: State, id: int, side: int, kind: int, at: Vector2) -> Unit:
	var unit := Unit.new(id, side, at, 100, 0, 1)
	unit.speed = 50.0
	state.add_grouped_unit(unit, kind)
	return unit

func _state() -> State:
	var state := State.new()
	state.setup_groups()
	return state

## Direction of side 0 is east (0), of side 1 west (PI); `ahead` is a point that far in front of `at`.
func _ahead(side: int, at: Vector2, distance: float, lateral := 0.0) -> Vector2:
	var forward := 1.0 if side == 0 else -1.0
	return at + Vector2(distance * forward, lateral)

func _plan(state: State, unit: Unit, foe: Unit, center := Vector2.INF, cover := Vector2.INF, wall_x := INF) -> void:
	var group = state.groups[unit.side][unit.group_kind]
	AiDecision.plan_into(unit, group, foe, state.arena_size, group.slot_position(unit, state.arena_size), center, 0.1, cover, wall_x)

func _check_formed(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.direction = 0.0 if side == 0 else PI
	group.center = CENTER
	group.order = Config.ORDER_CHARGE
	group.formed = true
	var front := _unit(state, 7001, side, Config.GROUP_INFANTRY, CENTER)
	var rear := _unit(state, 913, side, Config.GROUP_INFANTRY, CENTER)
	rear.slot_offset = Vector2(0, -Config.FORMATION_SPACING[0] * Config.FORMATION_ROW_DEPTH * 2.0)
	rear.position = group.slot_position(rear, state.arena_size)
	var foe := _unit(state, 55, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 60))
	_plan(state, front, foe, CENTER)
	assert(front.ai_mode == Config.AI_MODE_MELEE and front.plan_destination == foe.position, "the front rank steps out to fight")
	foe.position = _ahead(side, rear.position, 60)
	_plan(state, rear, foe, CENTER)
	assert(rear.ai_mode == Config.AI_MODE_RANK and rear.plan_destination == group.slot_position(rear, state.arena_size), "a rear rank keeps his place")
	foe.position = _ahead(side, rear.position, front.collision_radius + foe.collision_radius + rear.melee_reach + 5.0)
	_plan(state, rear, foe, CENTER)
	assert(rear.ai_mode == Config.AI_MODE_MELEE, "in contact the rear rank fights")
	foe.position = _ahead(side, CENTER, 400)
	_plan(state, front, foe, CENTER)
	assert(front.ai_mode == Config.AI_MODE_RANK and front.plan_face == group.direction, "out of reach the front marches with the line")
	# No leash in a formed line: its state stays clear even far from the fitted centre in a chase.
	front.position = _ahead(side, CENTER, Config.AI_CHARGE_FOOT_HARD_LEASH + 50.0)
	foe.position = _ahead(side, front.position, 150)
	foe.velocity = _ahead(side, Vector2.ZERO, 45)
	_plan(state, front, foe, CENTER)
	assert(not front.leashed and front.chase_seconds == 0.0)
	# Loose: the old charge, man for man, with the leash.
	group.formed = false
	_plan(state, front, foe, CENTER)
	assert(front.leashed, "a loose charge keeps the stage 1a leash")
	front.leashed = false
	foe.position = _ahead(side, CENTER, 400)
	foe.velocity = Vector2.ZERO
	front.position = CENTER
	_plan(state, rear, foe, CENTER)
	assert(rear.ai_mode == Config.AI_MODE_MELEE and rear.plan_destination == foe.position, "loose, every man charges")
	# Holding is untouched by `formed`.
	group.order = Config.ORDER_HOLD
	group.formed = true
	_plan(state, rear, foe, CENTER)
	assert(rear.ai_mode == Config.AI_MODE_SLOT)

func _check_rally(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_CAVALRY]
	group.direction = 0.0 if side == 0 else PI
	group.center = CENTER
	group.order = Config.ORDER_CHARGE
	var rider := _unit(state, 4242, side, Config.GROUP_CAVALRY, _ahead(side, CENTER, 300))
	rider.mounted = true
	var foe := _unit(state, 77, 1 - side, Config.GROUP_INFANTRY, _ahead(side, rider.position, 20))
	_plan(state, rider, foe, CENTER)
	assert(rider.ai_mode == Config.AI_MODE_MELEE)
	group.rally = true
	_plan(state, rider, foe, CENTER)
	assert(rider.ai_mode == Config.AI_MODE_SLOT and rider.plan_destination == group.slot_position(rider, state.arena_size), "a rallying rider rides to the rally point, even in contact")
	assert(not rider.leashed and rider.chase_seconds == 0.0)
	# The rally belongs to melee riders: a horse archer keeps skirmishing, foot ignores it.
	rider.attack_range = 600.0
	_plan(state, rider, foe, CENTER)
	assert(rider.ai_mode == Config.AI_MODE_SKIRMISH)
	var footman := _unit(state, 31337, side, Config.GROUP_CAVALRY, _ahead(side, CENTER, 300, 40))
	foe.position = _ahead(side, footman.position, 20)
	_plan(state, footman, foe, CENTER)
	assert(footman.ai_mode == Config.AI_MODE_MELEE)

func _check_brace(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.direction = 0.0 if side == 0 else PI
	group.center = CENTER
	var spear := _unit(state, 1234, side, Config.GROUP_INFANTRY, CENTER)
	spear.anti_cavalry = true
	var rider := _unit(state, 98, 1 - side, Config.GROUP_CAVALRY, _ahead(side, CENTER, 200))
	rider.mounted = true
	rider.velocity = _ahead(side, Vector2.ZERO, -120) # Towards the spearman.
	for order in [Config.ORDER_CHARGE, Config.ORDER_HOLD]:
		group.order = order
		_plan(state, spear, rider, CENTER)
		assert(spear.ai_mode == Config.AI_MODE_BRACE and spear.plan_destination == spear.position, "%s: he stands" % order)
		assert(spear.plan_face == (rider.position - spear.position).angle(), "and faces the rider")
	group.order = Config.ORDER_CHARGE
	rider.position = _ahead(side, CENTER, spear.collision_radius + rider.collision_radius + spear.melee_reach - 2.0)
	_plan(state, spear, rider, CENTER)
	assert(spear.ai_mode == Config.AI_MODE_MELEE, "in reach he strikes")
	rider.position = _ahead(side, CENTER, 200)
	rider.velocity = _ahead(side, Vector2.ZERO, 120) # Riding away.
	_plan(state, spear, rider, CENTER)
	assert(spear.ai_mode == Config.AI_MODE_MELEE, "a rider riding away is no charge")
	rider.velocity = _ahead(side, Vector2.ZERO, -120)
	rider.position = _ahead(side, CENTER, Config.AI_BRACE_DISTANCE + 20.0)
	_plan(state, spear, rider, CENTER)
	assert(spear.ai_mode == Config.AI_MODE_MELEE, "too far to brace")
	rider.position = _ahead(side, CENTER, 200)
	rider.mounted = false
	_plan(state, spear, rider, CENTER)
	assert(spear.ai_mode == Config.AI_MODE_MELEE, "foot is no rider")
	rider.mounted = true
	spear.anti_cavalry = false
	_plan(state, spear, rider, CENTER)
	assert(spear.ai_mode == Config.AI_MODE_MELEE, "only spearmen brace")

func _check_screen(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.direction = 0.0 if side == 0 else PI
	group.center = CENTER
	group.order = Config.ORDER_HOLD
	var spear := _unit(state, 606, side, Config.GROUP_INFANTRY, CENTER)
	spear.anti_cavalry = true
	spear.slot_offset = Vector2(30, 0)
	var other := _unit(state, 607, side, Config.GROUP_INFANTRY, CENTER + Vector2(0, 30))
	other.slot_offset = Vector2(30, 0)
	var foe := _unit(state, 15, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 600))
	group.screen = CENTER + Vector2(0, 150)
	group.screen_lateral = Vector2(1, 0)
	_plan(state, spear, foe)
	assert(spear.ai_mode == Config.AI_MODE_SLOT and spear.plan_destination == group.screen + group.screen_lateral * (30.0 * Config.AI_SCREEN_SPREAD), "the spearman takes his place in the screen line")
	assert(spear.plan_face == Vector2(0, -1).angle())
	_plan(state, other, foe)
	assert(other.plan_destination == group.slot_position(other, state.arena_size), "other men stay in the formation")
	group.order = Config.ORDER_CHARGE
	_plan(state, spear, foe)
	assert(spear.plan_destination != group.screen + group.screen_lateral * (30.0 * Config.AI_SCREEN_SPREAD), "a charging group does not screen")
	group.order = Config.ORDER_HOLD
	group.screen = CENTER + Vector2(0, Config.AI_SCREEN_RADIUS + 10.0)
	_plan(state, spear, foe)
	assert(spear.plan_destination == group.slot_position(spear, state.arena_size), "too far from the screen point")

func _check_fallback(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_ARCHERS]
	group.direction = 0.0 if side == 0 else PI
	group.center = CENTER
	group.order = Config.ORDER_HOLD
	var archer := _unit(state, 8080, side, Config.GROUP_ARCHERS, CENTER)
	archer.attack_range = 700.0
	archer.damage = 10.0
	var cover := _ahead(side, CENTER, -150) # Own infantry behind him.
	var foe := _unit(state, 21, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 120))
	foe.velocity = _ahead(side, Vector2.ZERO, -55) # Running at him.
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode == Config.AI_MODE_FALLBACK, "he steps back")
	assert(archer.plan_destination.is_equal_approx(_ahead(side, CENTER, -Config.AI_ARCHER_FALLBACK_STEP)))
	assert(archer.plan_speed == Config.AI_ARCHER_FALLBACK_SPEED_MULTIPLIER and archer.plan_speed * archer.speed < foe.speed, "slower than the infantry: no endless kite")
	assert(archer.plan_face == (foe.position - archer.position).angle(), "facing the threat")
	_plan(state, archer, foe, Vector2.INF, Vector2.INF)
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "no own infantry, no falling back")
	_plan(state, archer, foe, Vector2.INF, _ahead(side, CENTER, -Config.AI_ARCHER_FALLBACK_COVER_DISTANCE - 10.0))
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "own infantry too far")
	_plan(state, archer, foe, Vector2.INF, _ahead(side, CENTER, 0.0, Config.AI_ARCHER_FALLBACK_COVER_DISTANCE - 1.0))
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "the step would leave his infantry")
	_plan(state, archer, foe, Vector2.INF, cover, _ahead(side, CENTER, -20).x)
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "never across the siege wall")
	_plan(state, archer, foe, Vector2.INF, cover, _ahead(side, CENTER, -200).x)
	assert(archer.ai_mode == Config.AI_MODE_FALLBACK, "a wall farther than the step does not matter")
	foe.velocity = Vector2.ZERO
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode == Config.AI_MODE_SHOOT_SLOT, "a standing enemy: he shoots")
	foe.velocity = _ahead(side, Vector2.ZERO, -55)
	foe.mounted = true
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "no backing off from riders")
	foe.mounted = false
	foe.attack_range = 300.0
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "nor from shooters")
	foe.attack_range = 0.0
	foe.position = _ahead(side, CENTER, Config.AI_ARCHER_FALLBACK_DISTANCE + 10.0)
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "still far")
	# The field edge: no room behind him.
	archer.position = Vector2(Config.AI_ARCHER_FALLBACK_EDGE + 20.0, 850) if side == 0 else Vector2(state.arena_size.x - Config.AI_ARCHER_FALLBACK_EDGE - 20.0, 850)
	foe.position = _ahead(side, archer.position, 100)
	_plan(state, archer, foe, Vector2.INF, archer.position + _ahead(side, Vector2.ZERO, -20))
	assert(archer.ai_mode != Config.AI_MODE_FALLBACK, "no room at the edge")
	# Mounted shooters keep skirmishing.
	archer.position = CENTER
	foe.position = _ahead(side, CENTER, 120)
	archer.mounted = true
	_plan(state, archer, foe, Vector2.INF, cover)
	assert(archer.ai_mode == Config.AI_MODE_SKIRMISH)

## Both searches must agree; returns their choice.
func _choose(state: State, fighter: Unit) -> Unit:
	var plain := Targeting.choose(state, fighter)
	var index := SpatialIndex.new(state.active_units, state.arena_size, state.motion)
	var indexed := index.best_target(fighter, Targeting.current(state, fighter))
	assert(plain == indexed, "plain scan and spatial index disagree")
	return plain

func _check_shield_priority(side: int) -> void:
	var state := _state()
	var archer := _unit(state, 5150, side, Config.GROUP_ARCHERS, CENTER)
	archer.attack_range = 900.0
	archer.damage = 10.0
	var shielded := _unit(state, 40001, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 300))
	shielded.shield_block = 0.12
	var weight := SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, shielded, false)
	shielded.shield_block = 0.0
	var bare := SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, shielded, false)
	assert(is_equal_approx(weight / bare, Config.TARGET_SHIELDED_MULTIPLIER), "a shield makes the man look farther")
	shielded.shield_block = 0.12
	shielded.attack_range = 500.0
	assert(SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, shielded, false) == bare, "a shooter with a shield is still a shooter")
	shielded.attack_range = 0.0
	assert(SpatialIndex.melee_weight(100.0, 100.0, CENTER, 50.0, shielded, shielded.position, false) == 100.0, "melee fighters ignore shields")
	# An enemy archer a bit farther, with the same front share as the shielded man (ids picked for it).
	var other_id := 40002
	while SpatialIndex.front_share(archer.id, other_id) != SpatialIndex.front_share(archer.id, shielded.id):
		other_id += 1
	var bowman := _unit(state, other_id, 1 - side, Config.GROUP_ARCHERS, _ahead(side, CENTER, 345))
	bowman.attack_range = 700.0
	assert(_choose(state, archer) == bowman, "the archer behind the shields comes first")
	shielded.shield_block = 0.0
	assert(_choose(state, archer) == shielded, "without the shield the nearer man is taken")

func _check_spear_priority(side: int) -> void:
	var state := _state()
	var rider := _unit(state, 777, side, Config.GROUP_CAVALRY, CENTER)
	rider.mounted = true
	var spear := _unit(state, 9001, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 100))
	spear.anti_cavalry = true
	spear.facing = (rider.position - spear.position).angle()
	var footman := _unit(state, 9002, 1 - side, Config.GROUP_INFANTRY, _ahead(side, CENTER, 150, 30))
	var facing_weight := SpatialIndex.melee_weight(100.0, 100.0, CENTER, rider.speed, spear, spear.position, false, true)
	assert(is_equal_approx(facing_weight, 100.0 * Config.TARGET_SPEAR_FRONT_MULTIPLIER))
	assert(SpatialIndex.melee_weight(100.0, 100.0, CENTER, rider.speed, spear, spear.position, false, false) == 100.0, "only riders mind the points")
	assert(_choose(state, rider) == footman, "the rider avoids the points facing him")
	spear.facing += PI
	assert(_choose(state, rider) == spear, "a spearman turned away is fair game")
	spear.facing -= PI
	spear.fleeing = true
	assert(SpatialIndex.melee_weight(100.0, 100.0, CENTER, rider.speed, spear, spear.position, false, true) == 100.0, "a fleeing spearman has no points")
	spear.fleeing = false
	spear.anti_cavalry = false
	assert(_choose(state, rider) == spear, "an ordinary footman in front is taken")
