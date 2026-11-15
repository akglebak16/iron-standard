extends SceneTree

const Unit = preload("res://core/battle/model/unit.gd")
const BattleState = preload("res://core/battle/model/state.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	var battle = BattleState.new()
	battle.setup_groups(1)
	for i in 8:
		battle.add_grouped_unit(Unit.new(i, 0, Vector2.ZERO, 50, 10, 1), 0)
	battle.add_grouped_unit(Unit.new(8, 0, Vector2.ZERO, 50, 10, 1), 1)
	battle.add_grouped_unit(Unit.new(9, 0, Vector2.ZERO, 50, 10, 1), 2)
	battle.add_grouped_unit(Unit.new(10, 1, Vector2(1900, 850), 50, 10, 1), 0)
	battle.place_units()
	assert(battle.groups[0][0].active_units().size() == 8)
	assert(battle.groups[0][1].center == Vector2(535, 850))
	assert(battle.groups[0][2].center == Vector2(620, 1230))
	assert(battle.units[0].position != battle.units[1].position)
	assert(battle.units[0].position.x >= 30 and battle.units[0].position.x <= 2570)
	assert(battle.give_order("charge", Vector2.ZERO, 0))
	assert(battle.groups[0][0].order == "charge")
	assert(battle.groups[0][1].order == "hold")
	assert(not battle.give_order("invalid", Vector2.ZERO))
	assert(battle.give_order("hold", Vector2(1000, 850)))
	assert(battle.groups[0][0].center == Vector2(1000, 850))
	assert(battle.groups[0][1].center == Vector2(905, 850))
	assert(battle.groups[0][2].center == Vector2(1000, 610))
	assert(battle.give_order("back", Vector2.ZERO, 2))
	assert(battle.groups[0][2].backing)
	assert(battle.groups[0][2].order == "hold")
	assert(battle.give_order("follow", Vector2.ZERO, 2))
	assert(not battle.groups[0][2].backing)
	assert(battle.groups[0][2].order == "follow")
	_check_initial_type_order()
	print("Group tests passed")
	quit(0)

func _check_initial_type_order() -> void:
	var battle := BattleState.new()
	battle.setup_groups()
	var types := ["n2s", "n2", "n3", "n2s", "n2", "n1"]
	var tiers := [2, 2, 3, 2, 2, 1]
	for i in types.size():
		var unit := Unit.new(i, 0, Vector2.ZERO, 100, 0, tiers[i])
		unit.troop_id = types[i]
		battle.add_grouped_unit(unit, 0)
	battle.place_units()
	# Browser layout(g, true): tier descending, then troop type ID ascending;
	# identical troop types retain their spawn order.
	var expected_ids := [2, 1, 4, 0, 3, 5]
	var spacing: float = Config.FORMATION_SPACING[Config.GROUP_INFANTRY]
	var rear: float = -spacing * Config.FORMATION_ROW_DEPTH
	var expected_offsets := [Vector2(-spacing, 0), Vector2(0, 0), Vector2(spacing, 0), Vector2(-spacing, rear), Vector2(0, rear), Vector2(spacing, rear)]
	for i in expected_ids.size():
		var unit: Unit = battle.units[expected_ids[i]]
		assert(unit.slot_offset.is_equal_approx(expected_offsets[i]))
		assert(unit.position.is_equal_approx(battle.groups[0][0].slot_position(unit, battle.arena_size)))
