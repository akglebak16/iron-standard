extends RefCounted
## Optional observation port. The adapter supplies a monotonic clock; no engine clock in rules.
var clock := Callable()
var samples: Dictionary = {}
var _last := 0
var detailed := false
var sample_lane := 0
const SAMPLE_STRIDE := 32

func begin() -> void:
	if not clock.is_valid(): return
	samples.clear()
	sample_lane = (sample_lane + 1) % SAMPLE_STRIDE
	_last = clock.call()

## Rotating 1/32 sampling limits observer overhead; these are estimates, not budgets.
func probe(phase: String, since: int) -> int:
	var now: int = clock.call()
	samples[phase] = int(samples.get(phase, 0)) + (now - since) * SAMPLE_STRIDE
	return now

func mark(phase: String) -> void:
	if not clock.is_valid(): return
	var now: int = clock.call()
	samples[phase] = int(samples.get(phase, 0)) + now - _last
	_last = now
