extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const Checkpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const GOAL_KEYS := ["goal", "gid", "ga", "gs"]

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var a := WorldState.create(7, data, "kin", ContentLoader.registry())
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
	assert(a.roster.parties.any(func(q): return q.get("goal", "") != ""), "parties have AI goals after a few days")
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
		for k in GOAL_KEYS:
			assert(x.get(k) == y.get(k), "party %d keeps its goal field %s" % [i, k])
	for i in a.map.settles.size():
		assert(a.map.settles[i].recruits == b.map.settles[i].recruits and a.map.settles[i].fac == b.map.settles[i].fac)
	# the loaded world keeps running
	for i in 50:
		b.step(0.2)
	_check_old_save(a, data)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_save.json"))
	print("World save tests passed")
	quit(0)

## A save made before stage 2a: parties have no AI goal and settlements no alarm. It loads as "no goal" and the AI
## picks new goals as the world runs on.
func _check_old_save(a: RefCounted, data: EuropeData) -> void:
	var old := Checkpoint.capture(a)
	for q in old.roster.parties:
		for k in GOAL_KEYS:
			q.erase(k)
	for st in old.map.settles:
		st.erase("alarm")
	var payload := Marshalls.raw_to_base64(var_to_bytes(old))
	var c = WorldSave.from_dict({"version": 2, "encoding": "godot-variant-values-v1", "payload": payload, "sha256": payload.sha256_text()}, data, ContentLoader.registry())
	assert(c != null, "a save without goal fields still loads")
	assert(c.roster.parties.all(func(q): return not q.has("goal")), "old parties load without a goal")
	for i in 30:
		c.step(0.2)
		if i % 5 == 4:
			c.clock.hour = (c.clock.hour + 1) % 24
			c.hour_tick()
	assert(c.roster.parties.any(func(q): return q.get("goal", "") != ""), "the AI picks new goals for old parties")
	var bad := Checkpoint.capture(a)
	bad.roster.parties[0].goal = 5
	assert(not Checkpoint.valid(bad), "a goal must be text")
	bad = Checkpoint.capture(a)
	bad.roster.parties[0].gid = "x"
	assert(not Checkpoint.valid(bad), "a goal target must be an id")
	c.dispose()
