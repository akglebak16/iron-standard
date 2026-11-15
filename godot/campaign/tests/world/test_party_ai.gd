extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var state := WorldState.create(1, data, "emp")
	_check_population(state)
	_check_rules(state)
	_check_simulation(state)
	print("Party AI tests passed")
	quit(0)

func _count(state, kind: String) -> int:
	return state.roster.parties.filter(func(p): return p.kind == kind).size()

func _check_population(state) -> void:
	assert(_count(state, "lord") == 35, "5 lords for each of 7 factions")
	assert(_count(state, "vassal") == 28)
	assert(_count(state, "caravan") >= 1 and _count(state, "caravan") <= 8)
	assert(_count(state, "camp") > 0, "every bandit camp has a garrison")
	for p in state.roster.parties:
		if p.kind == "lord":
			var n := Rules.troop_count(p.troops)
			assert(n > 200 and n < 400, "lord army scaled by MK: %d" % n)
			break

func _check_rules(state) -> void:
	var emp := {"kind": "lord", "fac": "emp"}
	assert(Rules.hostile(emp, {"kind": "lord", "fac": "nord"}))
	assert(not Rules.hostile(emp, {"kind": "lord", "fac": "kin"}), "empire and kingdom are not at war by default")
	assert(Rules.hostile(emp, {"kind": "bandit", "fac": "bandit"}))
	assert(not Rules.hostile(emp, {"kind": "caravan", "fac": "nord"}))
	assert(Rules.hostile_to_player({"kind": "bandit", "fac": "bandit"}, {}))
	assert(not Rules.hostile_to_player({"kind": "lord", "fac": "nord"}, {"nord": 0}))
	assert(Rules.hostile_to_player({"kind": "lord", "fac": "nord"}, {"nord": -30}))
	var list := [{"type": "e1", "n": 3}]
	Rules.add_troops(list, "e1", 2)
	Rules.add_troops(list, "e2a", 1)
	assert(list[0].n == 5 and list.size() == 2)
	Rules.remove_troops(list, "e2a", 1)
	assert(list.size() == 1)
	assert(state.roster.strength_of({"troops": [{"type": "e1", "n": 10}]}) > 0.0)

func _check_simulation(state) -> void:
	state.player.rel["emp"] = 0
	var met := []
	state.party_met.connect(func(p, forced): met.append(p))
	# a week of world time: parties walk, rest, spawn and fight without errors
	var start: Array = state.roster.parties.map(func(p): return Vector2(p.x, p.y))
	for i in 24 * 7 * 5:
		state.step(0.2)
		if i % 5 == 4:
			state.clock.hour = (state.clock.hour + 1) % 24
			state.hour_tick()
		if state.player.busy != "":
			state.player.busy = ""
			for p in state.roster.parties:
				p.cd = 6.0
	var moved := 0
	for i in mini(start.size(), state.roster.parties.size()):
		if Vector2(state.roster.parties[i].x, state.roster.parties[i].y) != start[i]:
			moved += 1
	assert(moved > 10, "parties moved: %d" % moved)
	assert(_count(state, "lord") >= 20, "lords survive and respawn: %d" % _count(state, "lord"))
	assert(_count(state, "bandit") > 0, "bandits spawn")
