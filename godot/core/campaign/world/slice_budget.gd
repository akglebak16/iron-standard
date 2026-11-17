extends RefCounted
## Per-frame time budget of the world simulation. The core stays pure: the app injects the clock (now_us: Callable -> int µs)
## and the frame wait (next_frame_signal: Callable -> Signal to await). Without them (tests, loading) nothing is ever "due".
var budget_us := 0
var active := false
var now_us: Callable = Callable()
var frame_signal: Callable = Callable()
var hold: Callable = Callable()  # true while the world must stand still (a battle, a closed game): the run waits for it to end
var _from := 0
var _used := 0

func begin() -> void:
	active = budget_us > 0 and now_us.is_valid() and frame_signal.is_valid()
	if active: _from = now_us.call()

func end() -> void:
	if active: _used += int(now_us.call()) - _from
	active = false

func due() -> bool:
	return active and int(now_us.call()) - _from >= budget_us

## True when the budget would be spent by a piece of work of est_us µs that starts now.
func due_in(est_us: int) -> bool:
	return active and int(now_us.call()) - _from + est_us >= budget_us

func now() -> int:
	return int(now_us.call()) if now_us.is_valid() else 0

## Rest until the next frame; the time spent so far is booked.
func next_frame() -> void:
	_used += int(now_us.call()) - _from
	await frame_signal.call()
	while hold.is_valid() and hold.call():
		await frame_signal.call()
	_from = now_us.call()

func take_used_us() -> int:
	var v := _used
	_used = 0
	return v
