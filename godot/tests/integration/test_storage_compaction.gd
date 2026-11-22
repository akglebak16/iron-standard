extends SceneTree
## #322: storage compaction without lambda filters and without column copies. The lists must drop exactly the
## units the old filters dropped, the columns must move exactly like the reference backend, and the native
## compaction writes in place: a column held outside the store keeps its old rows.
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	var reference := _run(false)
	var native := _run(true)
	assert(native == reference, "native and reference compaction must leave the same storage")
	_check_rejection()
	print("Storage compaction tests passed")
	quit(0)

## Random deaths and departures over many compactions; returns a digest of every round.
func _run(native: bool) -> Array:
	var state := State.new()
	state.column_backend = Columns.create() if native else null
	assert(not native or state.column_backend != null)
	state.setup_groups(1, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 322
	for i in 360:
		var command := i % 3
		var unit := Unit.new(state.allocate_unit_id(), State.side_of(command), Vector2(10 + i * 3, 50 + i % 40), 50 + i, 0, 1)
		unit.command = command
		unit.velocity = Vector2(i % 7, -(i % 5))
		unit.companion = i % 37 == 5
		state.add_grouped_unit(unit, i % Config.GROUP_KINDS)
		unit.speed = 20.0 + i
	# Named fighters outside the groups, as the hero is.
	for i in 3:
		var named := Unit.new(state.allocate_unit_id(), i % 2, Vector2(900, 100 + i * 50), 200, 0, 1)
		state.add_unit(named)
		named.hero = true
	var digest := []
	var tick := 0
	while state.active_units.size() > 4:
		tick += 1
		for unit: Unit in state.active_units.duplicate():
			var roll := rng.randf()
			# Round 3: a mass loss, as when the undead crumble with their necromancer (State.BULK_DROP path).
			if roll < (0.4 if tick == 3 else 0.04): state.kill(unit)
			elif roll < (0.45 if tick == 3 else 0.06): state.mark_gone(unit)
		# Named casualties walk off the field later: the next compaction must hide them.
		for unit: Unit in state.retired_render_units.duplicate():
			if rng.randf() < 0.3: state.mark_gone(unit)
		var visible: Array[Unit] = state.render_units().duplicate()
		var listed := []
		for command_groups in state.groups:
			for group: Group in command_groups: listed.append(group.units.duplicate())
		var active: Array[Unit] = state.active_units.duplicate()
		var saved := {}
		for unit in active: saved[unit] = [unit.position, unit.velocity, unit.hp, unit.speed, unit.id, unit.unit_handle, unit.history_index]
		var held_reals := state.motion.real_fields
		var held_copy := held_reals.duplicate()
		var removed := state.compact_inactive(tick)
		if tick == 3: assert(removed > State.BULK_DROP, "the mass loss takes the bulk path")
		# The old filters, applied to the lists as they were.
		if removed > 0:
			visible = visible.filter(func(u: Unit): return u.battle_index >= 0 or (not u.gone and (u.hero or u.companion)))
		assert(state.render_units() == visible, "visible units: the old filter's result")
		var at := 0
		for command_groups in state.groups:
			for group: Group in command_groups:
				var expected: Array = listed[at].filter(func(u: Unit): return u.battle_index >= 0)
				assert(group.units == expected, "group units: the old filter's result")
				at += 1
		assert(state.active_units == active.filter(func(u: Unit): return u.battle_index >= 0))
		assert(removed == active.size() - state.active_units.size())
		for row in state.active_units.size():
			assert(state.active_units[row].battle_index == row)
			assert(state.handles.resolve(state.active_units[row].unit_handle) == row)
		for unit in active:
			assert([unit.position, unit.velocity, unit.hp, unit.speed, unit.id, unit.unit_handle, unit.history_index] == saved[unit], "rows move whole; retired rows keep their values")
		if native and removed > 0:
			assert(held_reals == held_copy, "a column held outside the store keeps its rows (COW)")
			assert(state.motion.real_fields != held_copy)
		var round := [removed, state.motion.positions.duplicate(), state.motion.velocities.duplicate()]
		for unit in state.active_units: round.append([unit.id, unit.hp, unit.speed])
		digest.append(round)
	assert(tick > 10)
	return digest

## A rejected native compaction leaves its packet untouched.
func _check_rejection() -> void:
	var kernel = ClassDB.instantiate("IronColumnKernel")
	var state := State.new()
	for i in 4: state.add_unit(Unit.new(i, i % 2, Vector2(i, i), 100, 0, 1))
	var packet := [state.motion.capacity, state.motion.positions, state.motion.velocities, state.motion.real_fields, state.motion.integer_fields, state.motion.vector_fields]
	var before := packet.duplicate(true)
	assert(kernel.drop_rows(packet, PackedInt32Array([2, 1])).is_empty(), "rows out of order are rejected")
	assert(kernel.drop_rows(packet, PackedInt32Array([4])).is_empty(), "rows past the end are rejected")
	assert(packet == before, "a rejection keeps every column in the packet")
	state.kill(state.active_units[1])
	state.mark_gone(state.active_units[3])
	assert(kernel.retired_rows(Columns._values(state.motion)) == PackedInt32Array([1, 3]))
