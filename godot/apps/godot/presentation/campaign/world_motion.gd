extends RefCounted
## Smooth movement on the world map between simulation steps (snapWorld and rpos in the browser version).
## The world advances in 0.2-hour steps, about one per 0.8 s at speed 1, and a step may be spread over several frames
## (slice_budget.gd), so positions change at irregular moments. Every figure therefore slides from where it is drawn now
## to its new simulation position in the time one step takes, whenever that position changes: the drawing never waits for
## the simulation and never jumps.
const SNAP_DISTANCE := 80.0 # a jump this long (flight, respawn) is shown at once, not slid across the map
const SETTLE_TIME := 0.15 # seconds a stopped world takes to finish the last slide (WA in worldUpdate)
const STEP_SECONDS := 0.2 / 1.2 # a world step at speed 1

var alpha := 1.0 # kept for callers: 1 when the figures have settled
var _now := 0.0
var _dur := STEP_SECONDS
var _from := {}
var _to := {}
var _t0 := {}

## Call once per frame after the world advanced.
func tick(dt: float, running: bool, _fraction: float, speed: int) -> void:
	_now += dt
	_dur = STEP_SECONDS / maxf(1.0, float(speed)) if running else SETTLE_TIME
	alpha = 1.0 if not running else 0.0

## Where to draw `key` (party id, -1 for the player) that is now at `p` in the simulation.
func at(key: int, p: Vector2) -> Vector2:
	if not _to.has(key) or (_to[key] as Vector2).distance_to(p) > SNAP_DISTANCE:
		_from[key] = p
		_to[key] = p
		_t0[key] = _now
		return p
	if _to[key] != p:
		_from[key] = _shown(key)
		_to[key] = p
		_t0[key] = _now
	return _shown(key)

func _shown(key: int) -> Vector2:
	var k := clampf((_now - float(_t0[key])) / maxf(0.001, _dur), 0.0, 1.0)
	return (_from[key] as Vector2).lerp(_to[key], k)

func forget(key: int) -> void:
	_from.erase(key)
	_to.erase(key)
	_t0.erase(key)
