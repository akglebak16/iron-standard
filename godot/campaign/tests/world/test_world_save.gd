extends SceneTree
const WorldSave = preload("res://campaign/world/world_save.gd")
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const SaveStore = preload("res://app/save_store.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var a := WorldState.create(7, data, "kin")
	a.player.gold = 1234
	a.player.hero.name = "Тест"
	a.player.hero.str = 4
	a.player.rel["nord"] = -42.5
	for i in 300:
		a.step(0.2)
		if i % 5 == 4:
			a.clock.hour = (a.clock.hour + 1) % 24
			a.hour_tick()
	a.player.busy = ""
	assert(SaveStore.save(a, "user://test_save.json"))
	var b = SaveStore.load_state(data, "user://test_save.json")
	assert(b != null)
	assert(b.seed_value == 7 and b.player.culture == "kin")
	assert(b.player.gold == a.player.gold and b.player.hero.name == "Тест" and b.player.hero.str == 4 and b.player.rel["nord"] == a.player.rel["nord"])
	assert(b.clock.day == a.clock.day and b.clock.hour == a.clock.hour)
	assert(b.roster.parties.size() == a.roster.parties.size())
	for i in a.roster.parties.size():
		var x: Dictionary = a.roster.parties[i]
		var y: Dictionary = b.roster.parties[i]
		assert(x.id == y.id and x.kind == y.kind and x.troops == y.troops and absf(x.x - y.x) < 0.001 and x.path.size() == y.path.size(), "party %d" % i)
	for i in a.map.settles.size():
		assert(a.map.settles[i].recruits == b.map.settles[i].recruits and a.map.settles[i].fac == b.map.settles[i].fac)
	# the loaded world keeps running
	for i in 50:
		b.step(0.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	print("World save tests passed")
	quit(0)
