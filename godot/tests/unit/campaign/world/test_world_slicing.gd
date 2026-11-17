extends SceneTree
## A world step or hour spread over frames (slice_budget.gd) must give exactly the world of the plain loop: the same
## calls in the same order, only paused between them. One seed runs both ways for a few game days; the pausing run gets
## a budget of 0.4 ms, so it rests many times in every step.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const SEED := 4242
const CALLS := 6         # advance calls of 8 s: up to 40 steps each, about one game day
const CALL_SECONDS := 8.0

func _initialize() -> void:
	Engine.max_fps = 0  # a sliced run waits for frames: do not pace them
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var plain := WorldState.create(SEED, data, "emp", ContentLoader.registry())
	var sliced := WorldState.create(SEED, data, "emp", ContentLoader.registry())
	plain.waiting = true
	sliced.waiting = true
	for i in CALLS:
		plain.clock.advance(CALL_SECONDS, plain.step, plain.hour_tick)
	var frames_before := Engine.get_process_frames()
	# The searching that rests between frames finds the very routes of the plain one.
	var paths = plain.map.paths
	var probe := RandomNumberGenerator.new()
	probe.seed = 7
	var probe_slicer = sliced.slicer
	probe_slicer.budget_us = 100
	probe_slicer.now_us = Time.get_ticks_usec
	probe_slicer.frame_signal = func() -> Signal: return (Engine.get_main_loop() as SceneTree).process_frame
	for i in 6:
		var x0 := probe.randf_range(100.0, 3000.0)
		var y0 := probe.randf_range(100.0, 2000.0)
		var x1 := probe.randf_range(100.0, 3000.0)
		var y1 := probe.randf_range(100.0, 2000.0)
		var want = paths.find_path(x0, y0, x1, y1)
		probe_slicer.begin()
		var got = await paths.find_path_co(x0, y0, x1, y1, false, probe_slicer)
		probe_slicer.end()
		assert(str(want) == str(got), "the same route with and without resting (%d)" % i)
	sliced.slicer.budget_us = 400
	sliced.slicer.now_us = Time.get_ticks_usec
	sliced.slicer.frame_signal = func() -> Signal: return (Engine.get_main_loop() as SceneTree).process_frame
	for i in CALLS:
		sliced.slicer.begin()
		assert(sliced.slicer.active)
		await sliced.clock.advance_async(CALL_SECONDS, sliced.step, sliced.hour_tick)
		sliced.slicer.end()
	var frames := Engine.get_process_frames() - frames_before
	assert(frames > 300, "the sliced run rested between frames: %d frames" % frames)
	assert(plain.clock.day == sliced.clock.day and plain.clock.hour == sliced.clock.hour, "the same time of the world")
	assert(plain.clock.day >= 2, "a few days passed: %d" % plain.clock.day)
	assert(_fingerprint(plain) == _fingerprint(sliced), "sliced %s, plain %s" % [_fingerprint(sliced), _fingerprint(plain)])
	assert(plain.roster.rng.state == sliced.roster.rng.state, "the random stream went the same way")
	print("World slicing tests passed (%d frames, day %d, %d parties)" % [frames, plain.clock.day, plain.roster.parties.size()])
	plain.dispose()
	sliced.dispose()
	quit(0)

func _fingerprint(state: RefCounted) -> int:
	var h := 0
	for p in state.roster.parties:
		h = hash([h, p.id, snappedf(p.x, 0.001), snappedf(p.y, 0.001), p.fac, p.troops.size(), p.get("goal", ""), p.state])
	for s in state.map.settles:
		h = hash([h, s.id, s.fac, s.get("siege") != null])
	return hash([h, state.wars.campaigns.size(), state.journal.size(), state.hours_passed])
