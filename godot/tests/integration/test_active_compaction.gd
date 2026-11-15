extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Index = preload("res://core/battle/rules/spatial_index.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const Result = preload("res://core/battle/rules/result.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	var battle := State.new()
	battle.setup_groups()
	var records: Array[Unit] = []
	for i in 100:
		var u := Unit.new(battle.allocate_unit_id(),i % 2,Vector2(i*10,100),100,0,1)
		u.troop_id = "n1" if u.side == 0 else "e1"
		battle.add_grouped_unit(u,Config.GROUP_INFANTRY)
		records.append(u)
	var hero := records[0]
	hero.hero = true
	hero.target_handle = records[99].unit_handle
	var survivor_handle := records[99].unit_handle
	battle.movement_index = Index.new(battle.active_units)
	battle.projectile_index = Index.new(battle.active_units)
	for i in range(1,99):
		if i % 3 == 0: battle.mark_gone(records[i])
		else: battle.kill(records[i])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var before_result := Result.build(battle,hero,rng,1.0,true)
	var after_rng := rng.state
	assert(battle.compact_inactive(60) == 98)
	assert(battle.active_units == [hero,records[99]] and battle.units == records)
	assert(battle.handles.resolve(survivor_handle) == 1 and battle.unit_for(survivor_handle) == records[99])
	assert(Targeting.current(battle,hero) == records[99])
	assert(battle.movement_index.nearest_enemy(hero) == records[99])
	assert(battle.projectile_index.nearest_enemy(hero) == records[99])
	assert(battle.groups[0][0].units == [hero] and battle.groups[1][0].units == [records[99]])
	assert(battle.render_units() == [hero,records[99]])
	rng.seed = 4
	assert(Result.build(battle,hero,rng,1.0,true) == before_result and rng.state == after_rng, "compaction must preserve outcome RNG order")
	var reinforcement := Unit.new(battle.allocate_unit_id(),1,Vector2(125,100),100,0,1)
	assert(reinforcement.id == 100)
	battle.add_unit(reinforcement)
	assert(reinforcement.battle_index == 2 and reinforcement.history_index == 100)
	battle.movement_index.synchronize()
	assert(battle.movement_index.nearest_enemy(hero) == reinforcement)
	assert(battle.compact_inactive(61) == 0)
	battle.kill(hero)
	assert(battle.compact_inactive(62) == 1)
	assert(hero in battle.render_units(), "named casualties remain available to presentation")
	assert(battle.units.size() == 101 and battle.active_units.size() == 2)
	print("Active compaction tests passed")
	quit(0)
