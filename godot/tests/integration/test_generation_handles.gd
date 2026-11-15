extends SceneTree
const Handles = preload("res://runtime/simulation/generation_handles.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Config = preload("res://core/battle/config.gd")
const CombatStep = preload("res://core/battle/rules/combat_step.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")

func _initialize() -> void:
	var pool := Handles.new()
	assert(pool.resolve(0) == -1 and pool.resolve(-1) == -1 and pool.resolve(0x7fffffffffffffff) == -1)
	var first := pool.allocate(0)
	var second := pool.allocate(1)
	assert(first != 0 and second != 0 and first != second)
	assert(pool.allocate(0) == 0 and not pool.relocate(first,1))
	assert(pool.release(first) and not pool.release(first))
	assert(pool.relocate(second,0) and pool.resolve(second) == 0 and pool.handle_at(1) == 0)
	for i in 2000:
		var current := pool.allocate(1)
		assert(current != first and pool.resolve(first) == -1 and pool.resolve(current) == 1)
		assert(pool.release(current))
	assert(pool.size() == 1 and pool.resolve(second) == 0)
	# Exhausted generations are retired permanently, never wrapped into old handles.
	var exhausted := Handles.new()
	exhausted.allocate(0)
	exhausted._generations[0] = Handles.MAX_GENERATION
	var last := exhausted.handle_at(0)
	assert(exhausted.release(last))
	var fresh := exhausted.allocate(0)
	assert((fresh & Handles.SLOT_MASK) != (last & Handles.SLOT_MASK) and exhausted.resolve(last) == -1)
	var other := Handles.new()
	var other_handle := other.allocate(0)
	assert(pool.resolve(first) == -1 and other.resolve(other_handle) == 0)
	_check_attack_after_reuse()
	_check_batch_compaction()
	print("Generation handles tests passed")
	quit(0)

func _check_attack_after_reuse() -> void:
	var state := State.new()
	var attacker := Unit.new(1,0,Vector2(100,100),100,0,1)
	var victim := Unit.new(2,1,Vector2(120,100),100,0,1)
	state.add_unit(attacker)
	state.add_unit(victim)
	assert(not state.add_unit(victim) and state.units.size() == 2, "duplicate insertion must be rejected in release too")
	var another := State.new()
	assert(not another.add_unit(victim) and another.units.is_empty(), "one Unit cannot belong to two battles")
	attacker.ai_mode = Config.AI_MODE_MELEE
	attacker.damage = 100
	attacker.target_handle = victim.unit_handle
	attacker.ai_wind_target_handle = victim.unit_handle
	attacker.ai_windup = 0.01
	attacker.attack_cooldown = 10.0
	var stale := victim.unit_handle
	state.kill(victim)
	var replacement := Unit.new(3,1,Vector2(120,100),100,0,1)
	state.add_unit(replacement)
	assert((stale & Handles.SLOT_MASK) == (replacement.unit_handle & Handles.SLOT_MASK), "test must reuse the released slot")
	assert(state.unit_for(stale) == null and Targeting.current(state,attacker) == null)
	var rng := RandomNumberGenerator.new()
	CombatStep.advance_unit(state,attacker,null,INF,0.02,rng)
	assert(replacement.hp == 100 and attacker.ai_wind_target_handle == 0, "old attack must never hit a replacement")
	var selected := Targeting.refresh(state,attacker,0.01,rng)
	assert(selected == replacement and attacker.target_handle == replacement.unit_handle)
	state.mark_gone(replacement)
	assert(state.unit_for(replacement.unit_handle) == null)

func _check_batch_compaction() -> void:
	var pool := Handles.new()
	assert(pool.compact_dense() == 0)
	var identities := PackedInt64Array()
	for i in 2000: identities.append(pool.allocate(i))
	for i in 2000:
		if i % 3 != 1: assert(pool.release(identities[i]))
	assert(pool.compact_dense() == 667 and pool.size() == 667)
	var dense := 0
	for i in 2000:
		if i % 3 == 1:
			assert(pool.resolve(identities[i]) == dense and pool.handle_at(dense) == identities[i])
			dense += 1
		else: assert(pool.resolve(identities[i]) == -1)
	assert(pool.handle_at(667) == 0 and pool.handle_at(1999) == 0)
	var new_handle := pool.allocate(667)
	assert(new_handle != 0 and pool.resolve(new_handle) == 667)
	assert(pool.compact_dense() == 668 and pool.resolve(new_handle) == 667)
	for handle in identities:
		if pool.resolve(handle) >= 0: assert(pool.release(handle))
	assert(pool.compact_dense() == 1 and pool.resolve(new_handle) == 0)
	assert(pool.release(new_handle) and pool.compact_dense() == 0)
