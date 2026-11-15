extends RefCounted
## Single-thread reference clock. The caller supplies scaled simulation seconds.
## Excess wall time is reported, never disguised as successful real-time simulation.
const STEP_SECONDS := 1.0 / 60.0
const MAX_STEPS := 4
const MAX_BACKLOG_SECONDS := 0.25
var accumulator := 0.0
var dropped_seconds := 0.0
var overloads := 0
var ticks := 0

func advance(seconds: float, step: Callable) -> int:
	if not is_finite(seconds) or seconds <= 0.0: return 0
	accumulator += seconds
	if accumulator > MAX_BACKLOG_SECONDS:
		dropped_seconds += accumulator - MAX_BACKLOG_SECONDS
		accumulator = MAX_BACKLOG_SECONDS
		overloads += 1
	var count := 0
	while accumulator + 1e-10 >= STEP_SECONDS and count < MAX_STEPS:
		step.call()
		accumulator = maxf(0.0, accumulator - STEP_SECONDS)
		count += 1
		ticks += 1
	return count

func alpha() -> float:
	return clampf(accumulator / STEP_SECONDS, 0.0, 1.0)

func reset() -> void:
	accumulator = 0.0
