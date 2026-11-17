extends RefCounted
## AI debug snapshot (ADR-022): plan, order and last decision of every group, field assessment and the mode
## of every fighter, for the debug overlay and tools. Separate from the battle state and from RenderSnapshot
## (ADR-003): built only on request while debugging is on, every value detached, nothing here feeds rules.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Group = preload("res://core/battle/model/group.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")
const DecisionTrace = preload("res://core/battle/simulation/ai/decision_trace.gd")
const FLEEING := 1
const HERO := 2
const WAVERING := 4

static func build(battle: State, trace: DecisionTrace, assessment: Dictionary, assessment_tick: int, profiles: Array[String], tick: int, elapsed: float) -> Dictionary:
	var recorded := trace.snapshot()
	var assessed: Array = assessment.get("sides", [])
	var sides: Array[Dictionary] = []
	for side in 2:
		var groups: Array[Dictionary] = []
		for kind in Config.GROUP_KINDS:
			var group: Group = battle.groups[side][kind] if battle.groups.size() > side else null
			if group == null: continue
			var entry := {"kind": kind, "order": group.order, "backing": group.backing, "tactic_state": group.tactic_state,
				"center": group.center, "direction": group.direction, "waypoint": group.waypoint,
				"kited": group.kited, "focus_kind": group.focus_kind, "last": recorded.last[side][kind],
				"morale_state": group.morale_state, "morale_pressure": group.morale_pressure, "fleeing_share": group.morale_fleeing_share}
			if assessed.size() > side:
				entry.assessment = assessed[side].groups[kind].duplicate(true)
			groups.append(entry)
		var side_entry := {"side": side, "profile": profiles[side], "plan": recorded.plans[side], "groups": groups,
			"missile_losses": battle.missile_losses[side]}
		if assessed.size() > side:
			side_entry.assessment = {"count": assessed[side].count, "strength": assessed[side].strength,
				"fleeing": assessed[side].fleeing, "center": assessed[side].center}
		sides.append(side_entry)
	return {"tick": tick, "elapsed_seconds": elapsed, "assessment_tick": assessment_tick, "sides": sides,
		"recent": recorded.recent, "records": recorded.records, "units": _units(battle)}

## Fighter positions, sides and decision modes (MotionStore.MODES indices) of the current tick, without
## interpolation: the overlay marks modes, it does not replace the figures.
static func _units(battle: State) -> Dictionary:
	var positions := PackedVector2Array()
	var sides := PackedInt32Array()
	var modes := PackedInt32Array()
	var flags := PackedInt32Array()
	var motion := battle.motion
	var capacity := motion.capacity
	var columns := motion.integer_fields
	var I = MotionStore.I
	for row in battle.active_units.size():
		if columns[I.DEAD * capacity + row] or columns[I.GONE * capacity + row]:
			continue
		positions.append(motion.positions[row])
		sides.append(columns[I.SIDE * capacity + row])
		modes.append(columns[I.MODE * capacity + row])
		flags.append(int(columns[I.FLEEING * capacity + row]) * FLEEING | int(columns[I.HERO * capacity + row]) * HERO | int(columns[I.WAVERING * capacity + row]) * WAVERING)
	return {"positions": positions, "sides": sides, "modes": modes, "flags": flags, "mode_names": MotionStore.MODES.duplicate()}
