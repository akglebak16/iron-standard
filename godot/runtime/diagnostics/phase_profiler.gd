extends RefCounted
## Optional observation port. The adapter supplies a monotonic clock; no engine clock in rules.
var clock := Callable()
var samples: Dictionary = {}
var _last := 0

func begin() -> void:
	if not clock.is_valid(): return
	samples.clear()
	_last = clock.call()

func mark(phase: String) -> void:
	if not clock.is_valid(): return
	var now: int = clock.call()
	samples[phase] = int(samples.get(phase, 0)) + now - _last
	_last = now
