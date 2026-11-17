extends RefCounted
## The world simulation on its own thread (ADR-024). The world has one owner at a time: the main thread hands it over for
## exactly one world step (give), draws from frozen copies meanwhile and gets it back when the step is done (poll / take).
## Nothing is shared while a step runs, so the step is the plain synchronous one and the result is the same as without a thread.
var given := false       # the worker owns the world now
var last_step_us := 0    # duration of the last step, read by the main thread after it got the world back
var steps_done := 0
var _thread := Thread.new()
var _go := Semaphore.new()
var _done := Semaphore.new()
var _state: RefCounted
var _quit := false
var _job := Callable()

func start(state: RefCounted) -> bool:
	_state = state
	return _thread.start(_run) == OK

## Hands the world to the worker for one step. Only when the main thread owns it.
## With `job` the worker runs it instead of a step (a save of the whole world, for one).
func give(job := Callable()) -> void:
	_job = job
	given = true
	_go.post()

## True when the main thread owns the world (the step, if any, has finished). Never waits.
func poll() -> bool:
	if given and _done.try_wait():
		given = false
	return not given

## Waits for the running step, if any: after it the main thread owns the world.
func take() -> void:
	if given:
		_done.wait()
		given = false

func stop() -> void:
	if not _thread.is_started():
		return
	take()
	_quit = true
	_go.post()
	_thread.wait_to_finish()

func _run() -> void:
	while true:
		_go.wait()
		if _quit:
			return
		if _job.is_valid():
			_job.call()
			_job = Callable()
		else:
			var from := Time.get_ticks_usec()
			_state.advance_one()
			last_step_us = Time.get_ticks_usec() - from
			steps_done += 1
		_done.post()
