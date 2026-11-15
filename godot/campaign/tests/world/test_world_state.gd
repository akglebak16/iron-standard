extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const WorldClock = preload("res://campaign/world/world_clock.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	_check_clock()
	_check_walking()
	print("World state tests passed")
	quit(0)

func _check_clock() -> void:
	var clock := WorldClock.new()
	var counts := [0, 0]
	var on_step := func(_dh): counts[0] += 1
	var on_hour := func(): counts[1] += 1
	# 1 real second at speed 1 is 1.2 steps' worth of 0.2 hours: 6 steps, i.e. 1.2 hours
	assert(clock.advance(1.0, on_step, on_hour) == 6)
	assert(counts == [6, 1] and clock.hour == 9)
	clock.speed = 4
	var guard := 0
	while clock.day < 2 and guard < 2000:   # at most 40 steps per call, like the browser loop
		clock.advance(0.1, on_step, on_hour)
		guard += 1
	assert(clock.day == 2 and clock.hour == 0, "day rolled over: %d %d" % [clock.day, clock.hour])
	clock.paused = true
	assert(clock.advance(10.0, on_step, on_hour) == 0)
	clock.hour = 23
	assert(is_equal_approx(clock.night_level(), 0.34))
	clock.hour = 5
	assert(is_equal_approx(clock.night_level(), 0.1))
	clock.hour = 12
	assert(clock.night_level() == 0.0)

func _check_walking() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var state := WorldState.create(12345, data, "emp")
	assert(state.map.paths.passable_type(state.map.paths.terr_at(state.player.x, state.player.y)), "player starts on land")
	var target: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.id != state.home_id and s.fac == "emp":
			target = s
			break
	assert(not target.is_empty())
	assert(state.player.path_to(state.map.paths, target.x, target.y), "route exists")
	var start := Vector2(state.player.x, state.player.y)
	state.step(1.0)
	var moved := Vector2(state.player.x, state.player.y).distance_to(start)
	assert(moved > 5.0 and moved < 40.0, "one hour is a plausible distance: %f" % moved)
	var guard := 0
	while state.player.has_route() and guard < 4000:
		state.step(1.0)
		guard += 1
	assert(not state.player.has_route(), "arrived")
	assert(Vector2(state.player.x, state.player.y).distance_to(Vector2(target.x, target.y)) < 45.0)
	assert(state.settlement_near(state.player.x, state.player.y, 46.0).get("id", -1) == target.id)
