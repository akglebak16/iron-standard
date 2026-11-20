extends RefCounted
## AIScheduler of Blueprint 6.2 / 9.4 (DESIGN.md 3.4, 4.2.7, 7.4). Says on which fixed tick a command's commander or a
## group decides. Deterministic: offsets come from the command and group number, never from RNG or wall time.
##
## Input: a tick number (BattleSession's, or a commander's own count of its steps). Output: due flags. Mutates nothing.
## Frequency: queried every tick. Dependencies: Config only. Thread safety: immutable after construction, safe to read
## from the battle worker.
##
## Contract for a replacement (requirement BATTLE-AI-NAVIGATION may supply another implementation): the
## public queries below and the two period fields. Callers must not assume a particular offset.
##
## Stage 1g: every command (the player's side, the enemy, the allies) decides on a tick of its own, spread over the
## commander period, so two commanders never land on one tick (DESIGN.md 4.2.7, the lesson on periodic AI work). The
## commanders share no assessment of their own any more: the morale check keeps one in State for all of them. Groups
## are spread over the ticks of the group period and never coincide with a commander tick.
const Config = preload("res://core/battle/config.gd")
const TICK_SECONDS := 1.0 / 60.0
const SIDES := 2

var commander_period_ticks: int
var squad_period_ticks: int
var groups_per_side: int
var commands: int
var _commander_offsets := PackedInt32Array()

func _init(groups: int = Config.GROUP_KINDS, commander_seconds: float = Config.AI_COMMANDER_PERIOD_SECONDS, squad_seconds: float = Config.AI_SQUAD_PERIOD_SECONDS, command_count: int = Config.AI_CMD_COMMANDS) -> void:
	groups_per_side = maxi(1, groups)
	commander_period_ticks = maxi(1, roundi(commander_seconds / TICK_SECONDS))
	squad_period_ticks = maxi(2, roundi(squad_seconds / TICK_SECONDS))
	commands = maxi(1, command_count)
	# Ticks of the commander period with no group decision, shared out evenly by command number.
	var free := PackedInt32Array()
	for tick in commander_period_ticks:
		if due_squads(tick).is_empty():
			free.append(tick)
	if free.is_empty():
		free.append(0)
	for command in commands:
		_commander_offsets.append(free[(command * free.size()) / commands])

func commander_due(command: int, tick: int) -> bool:
	return posmod(tick - commander_offset(command), commander_period_ticks) == 0

## Tick of the commander period on which `command` decides.
func commander_offset(command: int) -> int:
	return _commander_offsets[posmod(command, commands)]

func squad_due(side: int, group: int, tick: int) -> bool:
	return posmod(tick - squad_offset(side, group), squad_period_ticks) == 0

## Groups of both sides due on this tick, as side * groups_per_side + group, in ascending order.
func due_squads(tick: int) -> PackedInt32Array:
	var due := PackedInt32Array()
	for slot in SIDES * groups_per_side:
		if squad_due(slot / groups_per_side, slot % groups_per_side, tick):
			due.append(slot)
	return due

## Ticks 1 .. period-1 of the group period, shared out evenly by the global group number.
func squad_offset(side: int, group: int) -> int:
	var slots := SIDES * groups_per_side
	var slot := posmod(side, SIDES) * groups_per_side + posmod(group, groups_per_side)
	return 1 + (slot * (squad_period_ticks - 1)) / slots
