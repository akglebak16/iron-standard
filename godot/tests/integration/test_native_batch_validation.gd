extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
func _initialize() -> void:
	var state := State.new()
	state.setup_groups()
	state.add_unit(Unit.new(0, 0, Vector2(80, 100), 100, 0, 1))
	state.add_unit(Unit.new(1, 1, Vector2(180, 100), 100, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var port := Movement.create()
	assert(port.is_valid())
	var original_reals := state.motion.real_fields.duplicate()
	var original_integers := state.motion.integer_fields.duplicate()
	var original_rng := rng.state
	assert(port.call(state.motion, {}, rng, 1.0 / 60.0, true).is_empty())
	assert(state.motion.real_fields == original_reals and state.motion.integer_fields == original_integers)
	assert(rng.state == original_rng, "Rejected batches cannot consume RNG or abandon columns")
	var groups := PackedFloat64Array()
	for side in state.groups:
		# Movement._step_batch: frame, order flags, stage 1v doctrine (formed, rally, screen point and line).
		for group in side: groups.append_array(PackedFloat64Array([100,100,0,1,1,0,0,0,0, 0,0,INF,INF,0,1]))
	var context := {"groups":groups,"arena":state.arena_size}
	# Retaining a value across handoff must trigger COW, not alias later native writes.
	var retained_reals := state.motion.real_fields
	var retained_integers := state.motion.integer_fields
	var result: Array = port.call(state.motion, context, rng, 1.0 / 60.0, true)
	assert(result.size() == 3 and result[0] == 0)
	assert(retained_reals == original_reals and retained_integers == original_integers)
	assert(state.motion.real_fields != original_reals)
	print("Native batch validation tests passed")
	quit(0)
