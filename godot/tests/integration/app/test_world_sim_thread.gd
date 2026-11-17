extends SceneTree
## The world simulation on a worker thread (world_sim_thread.gd, ADR-024): one step at a time is handed to the worker and
## the world it leaves is exactly the world of the plain loop. Then the map scene itself runs with the thread: time goes
## on, the world stays readable from the main thread and the scene closes cleanly.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldClock = preload("res://core/campaign/world/world_clock.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const WorldSimThread = preload("res://apps/godot/composition/world_sim_thread.gd")
const World = preload("res://apps/godot/composition/world_demo.tscn")
const SEED := 4242
const STEPS := 150  # 30 game hours
const STEP_SECONDS := WorldClock.STEP / 1.2

func _initialize() -> void:
	Engine.max_fps = 0
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var plain := WorldState.create(SEED, data, "emp", ContentLoader.registry())
	var threaded := WorldState.create(SEED, data, "emp", ContentLoader.registry())
	for s in [plain, threaded]:
		s.waiting = true
		s.player.away = true
	for i in STEPS:
		plain.tick_time(STEP_SECONDS + 0.0001)
		assert(plain.advance_one(), "a step is due")
	assert(not plain.advance_one(), "and only one")
	var sim := WorldSimThread.new()
	assert(sim.start(threaded))
	var waited := 0
	for i in STEPS:
		threaded.tick_time(STEP_SECONDS + 0.0001)
		sim.give()
		while not sim.poll():
			waited += 1
			await process_frame
	assert(sim.steps_done == STEPS and waited > 0, "the worker ran the steps while frames went on: %d frames" % waited)
	assert(plain.clock.day == threaded.clock.day and plain.clock.hour == threaded.clock.hour and plain.hours_passed == 30)
	assert(_fingerprint(plain) == _fingerprint(threaded), "the same world with and without the thread")
	assert(plain.roster.rng.state == threaded.roster.rng.state, "the random stream went the same way")
	# take() waits for the running step; a job runs instead of a step
	threaded.tick_time(STEP_SECONDS + 0.0001)
	sim.give()
	sim.take()
	assert(not sim.given and sim.steps_done == STEPS + 1)
	var ran := [false]
	sim.give(func() -> void: ran[0] = true)
	sim.take()
	assert(ran[0] and sim.steps_done == STEPS + 1, "a job is not a step")
	sim.stop()
	plain.dispose()
	threaded.dispose()
	# the map scene with the thread
	var world = World.instantiate()
	world.sim_thread = true
	root.add_child(world)
	while not world._ready_to_play:
		await process_frame
	assert(world._sim != null, "the scene started the simulation thread")
	world.state.player.away = true
	world.state.waiting = true
	world.state.clock.speed = 4
	world.state.clock.paused = false
	var hour0: int = world.state.hours_passed
	var frames := 0
	while world.state.hours_passed < hour0 + 3 and frames < 4000:
		frames += 1
		await process_frame
	assert(world.state.hours_passed >= hour0 + 3, "time goes on with the thread: %d frames" % frames)
	assert(not world._sim.given, "reading the world took it back")
	assert(world._sim.steps_done >= 15)
	world.state.clock.paused = true
	var steps: int = world._sim.steps_done
	for i in 20:
		await process_frame
	assert(world._sim.steps_done == steps, "a paused world gets no steps")
	world.queue_free()
	await process_frame
	await process_frame
	print("World simulation thread tests passed (%d frames waited, %d scene frames)" % [waited, frames])
	quit(0)

func _fingerprint(state: RefCounted) -> int:
	var h := 0
	for p in state.roster.parties:
		h = hash([h, p.id, snappedf(p.x, 0.001), snappedf(p.y, 0.001), p.fac, p.troops.size(), p.get("goal", ""), p.state])
	for s in state.map.settles:
		h = hash([h, s.id, s.fac, s.get("siege") != null])
	return hash([h, state.wars.campaigns.size(), state.journal.size(), state.hours_passed])
