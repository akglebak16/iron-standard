extends "res://core/battle/api/battle_simulation.gd"
## One owner of the simulation while a batch runs. No Node, input or resources
## are touched by the worker. Semaphore completion publishes the detached frame.
const Simulation = preload("res://core/battle/api/battle_simulation.gd")
const Clock = preload("res://runtime/scheduling/fixed_step_clock.gd")
var _backend: Simulation
var _thread := Thread.new()
var _wake := Semaphore.new()
var _done := Semaphore.new()
var _queued: Array[Dictionary] = [] # Main-thread only; never read by the worker.
var _pending := 0
var _running := false
var _stopping := false
var _closed := false
var _published: Dictionary = {}
var _profile: Dictionary = {}
var _thread_started := false

func _init(session: Session) -> void:
	super(null)
	_backend = Simulation.new(session)
	_thread_started = _thread.start(_run) == OK

func supports_async() -> bool: return _thread_started

func submit(commands: Array[Dictionary]) -> bool:
	if _closed or not Simulation.commands_valid(commands): return false
	_queued.append_array(commands.duplicate(true))
	return true

func _flush() -> void:
	if not _queued.is_empty():
		_backend.submit(_queued)
		_queued.clear()

func start_batch(count: int) -> void:
	assert(not _closed and _pending == 0 and count > 0 and count <= Clock.MAX_STEPS)
	if _closed or _pending != 0 or count <= 0 or count > Clock.MAX_STEPS: return
	_flush()
	_pending = count
	_running = true
	_wake.post()

func _run() -> void:
	while true:
		_wake.wait()
		if _stopping: return
		var started := Time.get_ticks_usec()
		for tick in _pending: _backend.step()
		var snapshot_started := Time.get_ticks_usec()
		_published = _backend.render_snapshot()
		_profile = {"worker_simulation_us": snapshot_started - started, "worker_snapshot_us": Time.get_ticks_usec() - snapshot_started}
		_done.post()

func _join() -> void:
	if _running:
		_done.wait()
		_running = false

func finish_batch() -> int:
	var count := _pending
	_join()
	_pending = 0
	return count

func batch_profile() -> Dictionary:
	_join()
	return _profile.duplicate()

func step() -> void:
	finish_batch()
	_flush()
	_backend.step()
	_published = {}

func snapshot() -> Dictionary:
	_join()
	return _backend.snapshot() if not _closed else {}

func render_snapshot() -> Dictionary:
	_join()
	return _published if not _published.is_empty() else (_backend.render_snapshot() if not _closed else {})

func take_events() -> Array[Dictionary]:
	_join()
	return _backend.take_events() if not _closed else []

func result() -> Dictionary:
	_join()
	return _backend.result() if not _closed else {}

func dispose() -> void:
	if _closed: return
	finish_batch()
	_closed = true
	if _thread_started:
		_stopping = true
		_wake.post()
		_thread.wait_to_finish()
	_backend.dispose()
	_queued.clear()
	_published = {}
