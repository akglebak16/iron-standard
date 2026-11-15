extends SceneTree
const Tactics = preload("res://core/battle/rules/tactics.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	_test_infantry_and_archers()
	_test_cavalry_flank()
	_test_follow()
	_test_relayout()
	print("Tactics tests passed")
	quit(0)

func _battle() -> State:
	var battle := State.new()
	battle.setup_groups()
	var foe := Unit.new(0, 0, Vector2(600, 800), 100, 0, 1)
	battle.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	return battle

func _enemy(battle: State, kind: int, at: Vector2) -> Unit:
	var unit := Unit.new(battle.units.size(), 1, at, 100, 0, 1)
	battle.add_grouped_unit(unit, kind)
	battle.groups[1][kind].center = at
	return unit

func _test_infantry_and_archers() -> void:
	var battle := _battle()
	_enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 800))
	_enemy(battle, Config.GROUP_ARCHERS, Vector2(1300, 800))
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	var archers = battle.groups[1][Config.GROUP_ARCHERS]
	Tactics.enemy_step(battle, 1, 2.5, 0.1)
	assert(infantry.center == Vector2(1200, 800))
	assert(archers.center == Vector2(1300, 800))
	Tactics.enemy_step(battle, 1, 2.6, 1.0)
	assert(is_equal_approx(infantry.center.x, 1160.0))
	assert(is_equal_approx(archers.center.x, 1260.0))
	battle.units[0].position = Vector2(1000, 800)
	Tactics.enemy_step(battle, 1, 2.7, 0.1)
	assert(infantry.order == Config.ORDER_CHARGE)
	assert(archers.order == Config.ORDER_HOLD)
	battle.units[0].position = Vector2(1156, 800)
	Tactics.enemy_step(battle, 1, 2.8, 0.1)
	assert(archers.order == Config.ORDER_CHARGE)
	var forced := _battle()
	_enemy(forced, Config.GROUP_INFANTRY, Vector2(1200, 800))
	Tactics.enemy_step(forced, 1, 80.0, 0.1)
	assert(forced.groups[1][0].order == Config.ORDER_HOLD)
	Tactics.enemy_step(forced, 1, 80.1, 0.1)
	assert(forced.groups[1][0].order == Config.ORDER_CHARGE)
	var archers_only := _battle()
	_enemy(archers_only, Config.GROUP_ARCHERS, Vector2(770, 800))
	Tactics.enemy_step(archers_only, 1, 1.0, 0.1)
	assert(archers_only.groups[1][1].order == Config.ORDER_CHARGE)

func _test_cavalry_flank() -> void:
	var battle := _battle()
	_enemy(battle, Config.GROUP_CAVALRY, Vector2(1300, 1100))
	var cavalry = battle.groups[1][Config.GROUP_CAVALRY]
	Tactics.enemy_step(battle, 1, 4.0, 0.1)
	assert(cavalry.tactic_state == Config.AI_TACTIC_WAIT)
	Tactics.enemy_step(battle, 1, 4.1, 0.1)
	assert(cavalry.tactic_state == Config.AI_TACTIC_FLANK)
	assert(cavalry.waypoint.y == 1230.0)
	var before: Vector2 = cavalry.center
	Tactics.enemy_step(battle, 1, 4.2, 1.0)
	assert(is_equal_approx(cavalry.center.distance_to(before), Config.AI_CAVALRY_FLANK_SPEED))
	cavalry.center = cavalry.waypoint + Vector2(50, 0)
	Tactics.enemy_step(battle, 1, 4.3, 0.1)
	assert(cavalry.order == Config.ORDER_CHARGE)

func _test_follow() -> void:
	var battle := _battle()
	battle.units[0].position = Vector2(1200, 800)
	var hero := Unit.new(1, 0, Vector2(900, 800), 100, 0, 1)
	hero.hero = true
	battle.add_unit(hero)
	for group in battle.groups[0]:
		group.order = Config.ORDER_FOLLOW
	Tactics.follow_hero(battle, hero)
	assert(battle.groups[0][0].center == Vector2(850, 800))
	assert(battle.groups[0][1].center == Vector2(765, 800))
	assert(battle.groups[0][2].center == Vector2(840, 970))
	hero.dead = true
	hero.position = Vector2(1000, 800)
	Tactics.follow_hero(battle, hero)
	assert(battle.groups[0][0].center == Vector2(850, 800))

func _test_relayout() -> void:
	var battle := _battle()
	var first: Unit = battle.units[0]
	var second := Unit.new(1, 0, Vector2(600, 900), 100, 0, 1)
	battle.add_grouped_unit(second, Config.GROUP_INFANTRY)
	var group = battle.groups[0][Config.GROUP_INFANTRY]
	first.position = Vector2(600, 700)
	Tactics.relayout(battle, 0.1)
	var first_slot: Vector2 = first.slot_offset
	var second_slot: Vector2 = second.slot_offset
	assert(is_equal_approx(battle.formation_timer, Config.FORMATION_RELAYOUT_SECONDS))
	first.position.y = 950
	second.position.y = 650
	Tactics.relayout(battle, 1.0)
	assert(first.slot_offset == first_slot and second.slot_offset == second_slot)
	Tactics.relayout(battle, Config.FORMATION_RELAYOUT_SECONDS - 1.0)
	assert(first.slot_offset == second_slot and second.slot_offset == first_slot)
	group.order = Config.ORDER_CHARGE
	first.position.y = 600
	second.position.y = 950
	Tactics.relayout(battle, Config.FORMATION_RELAYOUT_SECONDS)
	assert(first.slot_offset == second_slot and second.slot_offset == first_slot)
