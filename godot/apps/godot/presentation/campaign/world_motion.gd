extends RefCounted
## Smooth movement on the world map between simulation steps (snapWorld and rpos in the browser version).
## The world advances in 0.2-hour steps, about one per 0.8 s at speed 1, so drawing raw positions jumps.
## Each figure is drawn between its previous and current step position by the clock's step fraction.
const SNAP_DISTANCE := 80.0 # a jump this long (flight, respawn) is shown at once, not slid across the map
const SETTLE_RATE := 6.0 # how fast the last step finishes once the world stops (WA in worldUpdate)

var alpha := 1.0
var _prev := {}
var _cur := {}

## Call once per frame after the world advanced.
func tick(dt: float, running: bool, fraction: float, speed: int) -> void:
	if running:
		alpha = clampf(fraction, 0.0, 1.0)
	else:
		alpha = minf(1.0, alpha + dt * SETTLE_RATE * maxf(1.0, float(speed)))

## Where to draw `key` (party id, -1 for the player) that is now at `p` in the simulation.
func at(key: int, p: Vector2) -> Vector2:
	if not _cur.has(key) or (_cur[key] as Vector2).distance_to(p) > SNAP_DISTANCE:
		_cur[key] = p
		_prev[key] = p
		return p
	if _cur[key] != p:
		_prev[key] = _cur[key]
		_cur[key] = p
	return (_prev[key] as Vector2).lerp(p, alpha)

func forget(key: int) -> void:
	_prev.erase(key)
	_cur.erase(key)
