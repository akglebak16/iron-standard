extends RefCounted
## World time: 0.2 "hour" steps, 1.2 steps per real second at speed 1 (the loop in src/07_main.js).
const STEP := 0.2

var day := 1
var hour := 8
var speed := 1
var paused := false
var _acc := 0.0
var _hour_acc := 0.0

## Runs the steps due after `dt` real seconds. `on_step(dh)` runs every step, `on_hour()` after each full hour.
## Returns how many steps ran.
func advance(dt: float, on_step: Callable, on_hour: Callable) -> int:
	if paused:
		return 0
	_acc += dt * 1.2 * speed
	var steps := 0
	while _acc >= STEP and steps < 40:
		_acc -= STEP
		steps += 1
		on_step.call(STEP)
		_hour_acc += STEP
		if _hour_acc >= 1.0:
			_hour_acc -= 1.0
			_next_hour()
			on_hour.call()
	return steps

## How far the next step has progressed, 0..1 (drawing interpolates between steps with it).
func step_fraction() -> float:
	return clampf(_acc / STEP, 0.0, 1.0)

func _next_hour() -> void:
	hour += 1
	if hour >= 24:
		hour = 0
		day += 1

## Darkness 0..0.34 for the night overlay (drawWorld in src/07_main.js).
func night_level() -> float:
	var h := hour
	if h >= 21 or h < 4:
		return 0.34
	if h >= 19:
		return (h - 18) * 0.1
	if h < 6:
		return (6 - h) * 0.1
	return 0.0
