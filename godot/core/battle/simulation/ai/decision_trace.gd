extends RefCounted
## "What was chosen and why" (DESIGN.md 3.7, ADR-022). Brains write short records; no rule ever reads them, so a
## battle with the trace on and off is the same battle. The session owns the trace only while the debug
## overlay or a tool asks for it; otherwise State.ai_trace is null and the brains skip every record.
##
## Records hold codes and numbers, never player-facing text: presentation translates the codes.
## Input: decisions of tactics.gd. Output: snapshot(). Mutates only itself. Frequency: on decision changes.
## Thread safety: written by the battle worker during a batch, read by the main thread after the batch.
const Config = preload("res://core/battle/config.gd")

var tick := 0
var elapsed_seconds := 0.0
var plans: Array[String] = ["", ""]
## Per side: why the plan was chosen (commander, stage 1g): the two best plan scores and a reason code; empty for the
## reference brain, which has no plans to weigh.
var plan_details: Array[Dictionary] = [{}, {}]
var _last: Array = []
var _recent: Array[Dictionary] = []
var _count := 0

func _init() -> void:
	for side in 2:
		var groups := []
		for group in Config.GROUP_KINDS: groups.append({})
		_last.append(groups)

func begin_tick(at_tick: int, elapsed: float) -> void:
	tick = at_tick
	elapsed_seconds = elapsed

func set_plan(side: int, plan: String, details: Dictionary = {}) -> void:
	plans[side] = plan
	plan_details[side] = details

## A repeated decision with the same reason is the same decision still in force and is not recorded again.
func record(side: int, group: int, decision: String, reason: String, values: Dictionary = {}) -> void:
	var previous: Dictionary = _last[side][group]
	if previous.get("decision", "") == decision and previous.get("reason", "") == reason:
		return
	var entry := {"tick": tick, "elapsed_seconds": elapsed_seconds, "side": side, "group": group,
		"decision": decision, "reason": reason, "values": values.duplicate(true)}
	_last[side][group] = entry
	_recent.append(entry)
	if _recent.size() > Config.AI_TRACE_RECENT:
		_recent.pop_front()
	_count += 1

func last(side: int, group: int) -> Dictionary:
	return _last[side][group].duplicate(true)

func record_count() -> int:
	return _count

## Detached copy; changing it does not change the trace.
func snapshot() -> Dictionary:
	return {"tick": tick, "elapsed_seconds": elapsed_seconds, "plans": plans.duplicate(), "plan_details": plan_details.duplicate(true),
		"last": _last.duplicate(true), "recent": _recent.duplicate(true), "records": _count}
