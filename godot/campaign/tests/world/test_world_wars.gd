extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var s := WorldState.create(5, data, "emp")
	assert(s.wars.wars.size() >= 8, "default wars: %d" % s.wars.wars.size())
	assert(Rules.at_war("emp", "nord") and not Rules.at_war("emp", "kin"))
	var emp_before: int = s.wars.hold_of("emp").all
	var total_before := 0
	for f in Rules.REAL_FACTIONS:
		total_before += s.wars.hold_of(f).all
	var news: Array = []
	s.wars.announced.connect(func(t): news.append(t))
	s.player.rel = {"nord": 100, "emp": 100, "khan": 100, "kin": 100, "emi": 100, "dom": 100, "pact": 100, "bandit": -100}
	# three weeks of world time: campaigns muster, march and besiege
	for i in 24 * 10:
		s.clock.hour = (s.clock.hour + 1) % 24
		if s.clock.hour == 0:
			s.clock.day += 1
		s.step(1.0)
		s.hour_tick()
		s.player.busy = ""
		s.player.x = 100.0
		s.player.y = 100.0
	var sieges := news.filter(func(t): return "осаждает" in t).size()
	var captures := news.filter(func(t): return "берёт" in t).size()
	var total_after := 0
	for f in Rules.REAL_FACTIONS:
		total_after += s.wars.hold_of(f).all
	assert(total_after == total_before, "settlements are only handed over, never lost")
	assert(news.filter(func(t): return "созывает" in t).size() > 0, "campaigns happened")
	print("news %d, sieges %d, captures %d" % [news.size(), sieges, captures])
	for line in news.slice(0, 8):
		print(line)
	print("World wars tests passed")
	quit(0)
