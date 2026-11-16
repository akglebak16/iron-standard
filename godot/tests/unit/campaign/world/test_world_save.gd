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
	_check_old_campaign(a, data)
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

## A save made before stage 2b: a campaign under way has no marshal, no strength at the muster and no lords left home.
## It loads, picks the strongest lord as its marshal and goes on from its present strength instead of retreating.
func _check_old_campaign(a: RefCounted, data: EuropeData) -> void:
	var old := Checkpoint.capture(a)
	var f := ""
	var foe := ""
	for k in old.wars.wars:
		var parts: PackedStringArray = String(k).split("|")
		if a.wars.alive(parts[0]) and a.wars.alive(parts[1]):
			f = parts[0]
			foe = parts[1]
			break
	assert(f != "", "a war to campaign in")
	var lords: Array = old.roster.parties.filter(func(q): return q.kind == "lord" and q.fac == f and not q.get("ruler", false) and not q.get("lock", false) and q.get("fight") == null)
	assert(lords.size() >= 2)
	var target: Dictionary = old.map.settles.filter(func(st): return st.fac == foe and st.kind == "town")[0]
	var rally: Dictionary = old.map.settles.filter(func(st): return st.fac == f and st.kind != "camp")[0]
	var army: Array = []
	for q in lords.slice(0, 2):
		q.army = true
		q.erase("relief")
		army.append(q.id)
	old.wars.campaigns[f] = {"tid": target.id, "gid": rally.id, "state": "march", "t0": a.wars.now_h(), "t1": a.wars.now_h(), "army": army}
	assert(Checkpoint.valid(old), "a campaign without stage 2b fields is valid")
	var payload := Marshalls.raw_to_base64(var_to_bytes(old))
	var c = WorldSave.from_dict({"version": 2, "encoding": "godot-variant-values-v1", "payload": payload, "sha256": payload.sha256_text()}, data, ContentLoader.registry())
	assert(c != null, "a save with an old campaign loads")
	assert(c.wars.campaigns[f].get("marshal") == null)
	c.wars.hour = 2
	c.wars._campaign(f)
	assert(c.wars.campaigns.has(f), "the old campaign goes on instead of retreating")
	var camp: Dictionary = c.wars.campaigns[f]
	assert(camp.marshal is int and camp.marshal in army, "the old campaign gets a marshal")
	assert(float(camp.s0) > 0.0, "its present strength becomes the start")
	var saved := Checkpoint.capture(c)
	assert(Checkpoint.valid(saved) and saved.wars.campaigns[f] == camp, "the new fields are saved")
	var bad := Checkpoint.capture(c)
	bad.wars.campaigns[f].marshal = "x"
	assert(not Checkpoint.valid(bad), "a marshal must be an id")
	bad = Checkpoint.capture(c)
	bad.wars.campaigns[f].keep = ["x"]
	assert(not Checkpoint.valid(bad), "lords left home are ids")
	c.dispose()
