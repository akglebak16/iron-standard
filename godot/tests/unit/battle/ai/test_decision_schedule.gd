extends SceneTree
## DecisionSchedule (DESIGN.md 3.4, 7.4): commander every 0.5 s, group every 0.25 s, staggered by group number,
## deterministic and never on the commander tick.
const DecisionSchedule = preload("res://core/battle/simulation/ai/decision_schedule.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	_test_periods()
	_test_stagger()
	_test_determinism()
	_test_other_sizes()
	print("Decision schedule tests passed")
	quit(0)

func _test_periods() -> void:
	var schedule := DecisionSchedule.new()
	assert(schedule.commander_period_ticks == roundi(Config.AI_COMMANDER_PERIOD_SECONDS * 60.0))
	assert(schedule.squad_period_ticks == roundi(Config.AI_SQUAD_PERIOD_SECONDS * 60.0))
	var commander := 0
	var squads := {}
	for tick in 600:
		if schedule.commander_due(0, tick):
			commander += 1
		var deciding := 0
		for command in Config.AI_CMD_COMMANDS:
			if schedule.commander_due(command, tick): deciding += 1
		assert(deciding <= 1, "Commanders of different commands decide on different ticks (stage 1g)")
		for side in 2:
			for group in Config.GROUP_KINDS:
				if schedule.squad_due(side, group, tick):
					var key := side * Config.GROUP_KINDS + group
					squads[key] = int(squads.get(key, 0)) + 1
	assert(commander == 20, "Ten seconds hold twenty commander decisions")
	assert(squads.size() == 2 * Config.GROUP_KINDS)
	for key in squads:
		assert(squads[key] == 40, "Every group decides four times a second")

func _test_stagger() -> void:
	var schedule := DecisionSchedule.new()
	var offsets := {}
	for side in 2:
		for group in Config.GROUP_KINDS:
			var offset := schedule.squad_offset(side, group)
			assert(offset > 0 and offset < schedule.squad_period_ticks)
			assert(not offsets.has(offset), "Groups are spread over different ticks")
			offsets[offset] = true
	for tick in 120:
		var due := schedule.due_squads(tick)
		assert(due.size() <= 1, "At most one group decides per tick with six groups")
		for command in Config.AI_CMD_COMMANDS:
			if schedule.commander_due(command, tick):
				assert(due.is_empty(), "Group decisions never land on a commander tick")
		for slot in due:
			assert(schedule.squad_due(slot / Config.GROUP_KINDS, slot % Config.GROUP_KINDS, tick))

func _test_determinism() -> void:
	var first := DecisionSchedule.new()
	var second := DecisionSchedule.new()
	for tick in range(-30, 300):
		assert(first.due_squads(tick) == second.due_squads(tick))
		assert(first.commander_due(1, tick) == second.commander_due(1, tick))

## A replacement may use other group counts and periods; the contract still holds.
func _test_other_sizes() -> void:
	var schedule := DecisionSchedule.new(8, 1.0, 0.5)
	assert(schedule.commander_period_ticks == 60 and schedule.squad_period_ticks == 30)
	var seen := {}
	for tick in 30:
		for slot in schedule.due_squads(tick):
			assert(not seen.has(slot))
			seen[slot] = true
	assert(seen.size() == 16, "Every group of both sides decides once per period")
	var offsets := {}
	for command in schedule.commands:
		var offset := schedule.commander_offset(command)
		assert(offset >= 0 and offset < schedule.commander_period_ticks and schedule.due_squads(offset).is_empty())
		assert(not offsets.has(offset), "Every command decides on a tick of its own")
		offsets[offset] = true
		var decisions := 0
		for tick in 600:
			if schedule.commander_due(command, tick): decisions += 1
		assert(decisions == 10, "One decision per command and second")
