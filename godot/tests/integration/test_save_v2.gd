extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const World = preload("res://core/campaign/world/world_state.gd")
const Save = preload("res://core/campaign/world/world_save.gd")
const Checkpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const Store = preload("res://adapters/persistence/save_store.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	var europe := Europe.new()
	assert(ContentLoader.populate(europe))
	var first := World.create(4242, europe, "emp", ContentLoader.registry())
	first.player.away = true
	first.player.hero.banner = 4
	first.player.path = [Vector2(first.player.x + 10.12345, first.player.y + 4.56789)]
	first.advance(0.137)
	assert(first.clock._acc > 0.0)
	var encoded := Save.to_dict(first)
	assert(encoded.version == 2)
	var second := Save.from_dict(JSON.parse_string(JSON.stringify(encoded)), europe, ContentLoader.registry())
	assert(second != null)
	assert(second.player.hero.banner == 4)
	assert(Checkpoint.capture(first) == Checkpoint.capture(second), "checkpoint must retain types and full float/RNG precision")
	# Waiting is not saved (G.wait); both copies wait so hours keep running after the short walk.
	first.waiting = true
	second.waiting = true
	for i in 300:
		first.advance(0.137)
		second.advance(0.137)
	assert(Checkpoint.capture(first) == Checkpoint.capture(second), "loading must reproduce continuation, including hour work")
	var captured := Checkpoint.capture(first)
	captured.player.gold = -123
	assert(first.player.gold != -123)
	var corrupt := encoded.duplicate(true)
	corrupt.payload += "broken"
	assert(Save.from_dict(corrupt, europe, ContentLoader.registry()) == null)
	assert(Save.from_dict({"version": 1}, europe, ContentLoader.registry()) == null)
	assert(Save.from_dict({"version": 999}, europe, ContentLoader.registry()) == null)
	var legacy := Save.to_v1_dict(first)
	var migrated := Save.from_dict(JSON.parse_string(JSON.stringify(legacy)), europe, ContentLoader.registry())
	assert(migrated != null and migrated.player.troops == first.player.troops)
	assert(migrated.player.gold == first.player.gold and migrated.player.hero == first.player.hero)
	assert(Save.to_dict(migrated).version == 2)
	# v1 from before stage 2a: no AI goals in parties, no alarms in settlements; loads as "no goal" and runs on
	var pre_goals := legacy.duplicate(true)
	for q in pre_goals.parties:
		for k in ["goal", "gid", "ga", "gs"]:
			q.erase(k)
	var pre_migrated := Save.from_dict(JSON.parse_string(JSON.stringify(pre_goals)), europe, ContentLoader.registry())
	assert(pre_migrated != null and pre_migrated.roster.parties.all(func(q): return not q.has("goal")))
	pre_migrated.waiting = true  # the world only runs while the party travels or waits (WorldState.advance)
	for i in 40:
		pre_migrated.advance(0.137)
	assert(pre_migrated.roster.parties.any(func(q): return q.get("goal", "") != ""), "old parties get new goals")
	assert(Save.to_dict(pre_migrated).version == 2)
	pre_migrated.dispose()
	var with_goals := Save.from_dict(JSON.parse_string(JSON.stringify(legacy)), europe, ContentLoader.registry())
	for i in with_goals.roster.parties.size():
		var q: Dictionary = with_goals.roster.parties[i]
		assert(q.get("gid") == null or q.gid is int, "v1 goal targets come back as ids")
		assert(q.get("goal", "") == first.roster.parties[i].get("goal", ""))
	with_goals.dispose()
	# v1 with two campaigns under way: one from before stage 2b (no marshal, start strength or lords left home) goes on,
	# one written with the stage 2b fields gets its ids back as ints; one load checks both
	var pre_ops := legacy.duplicate(true)
	var war_key: String = first.wars.wars.keys()[0]
	var fac: String = war_key.split("|")[0]
	var foe: String = war_key.split("|")[1]
	var host: Array = pre_ops.parties.filter(func(q): return q.kind == "lord" and q.fac == fac and not q.get("ruler", false)).slice(0, 2)
	var foe_host: Array = pre_ops.parties.filter(func(q): return q.kind == "lord" and q.fac == foe and not q.get("ruler", false)).slice(0, 2)
	for q in host + foe_host:
		q.army = true
	var goal_town: Dictionary = first.map.settles.filter(func(st): return st.fac == foe and st.kind == "town")[0]
	var rally_town: Dictionary = first.map.settles.filter(func(st): return st.fac == fac and st.kind != "camp")[0]
	var foe_goal: Dictionary = first.map.settles.filter(func(st): return st.fac == fac and st.kind == "town")[0]
	var foe_rally: Dictionary = first.map.settles.filter(func(st): return st.fac == foe and st.kind != "camp")[0]
	pre_ops.campaigns = {fac: {"tid": goal_town.id, "gid": rally_town.id, "state": "march", "t0": first.wars.now_h(), "t1": first.wars.now_h(), "army": host.map(func(q): return q.id)},
		foe: {"tid": foe_goal.id, "gid": foe_rally.id, "state": "muster", "t0": first.wars.now_h(), "army": foe_host.map(func(q): return q.id),
			"marshal": foe_host[0].id, "s0": 500, "keep": [foe_host[1].id]}}
	var ops_migrated := Save.from_dict(JSON.parse_string(JSON.stringify(pre_ops)), europe, ContentLoader.registry())
	assert(ops_migrated != null and ops_migrated.wars.campaigns[fac].army.all(func(id): return id is int))
	assert(ops_migrated.wars.campaigns[fac].get("marshal") == null)
	var typed: Dictionary = ops_migrated.wars.campaigns[foe]
	assert(typed.marshal is int and typed.keep[0] is int and typed.s0 is float, "v1 stage 2b fields come back typed")
	ops_migrated.wars.hour = 2
	ops_migrated.wars._campaign(fac)
	assert(ops_migrated.wars.campaigns.has(fac) and ops_migrated.wars.campaigns[fac].marshal is int, "an old campaign gets a marshal and goes on")
	assert(Checkpoint.valid(Checkpoint.capture(ops_migrated)))
	ops_migrated.dispose()
	pre_ops.campaigns[foe].marshal = "x"
	assert(Save.from_dict(JSON.parse_string(JSON.stringify(pre_ops)), europe, ContentLoader.registry()) == null, "a v1 marshal must be a number")
	var banner_legacy := legacy.duplicate(true)
	banner_legacy.player.banner = 3
	var banner_migrated := Save.from_dict(banner_legacy, europe, ContentLoader.registry())
	assert(banner_migrated != null and banner_migrated.player.hero.banner == 3)
	banner_migrated.dispose()
	var malformed := legacy.duplicate(true)
	malformed.parties = [{"id": 123}]
	assert(Save.from_dict(malformed, europe, ContentLoader.registry()) == null)
	malformed = legacy.duplicate(true)
	malformed.player.troops = ["invalid"]
	assert(Save.from_dict(malformed, europe, ContentLoader.registry()) == null)
	# A torn new generation cannot destroy the previous committed save.
	var path := "user://v2-recovery.json"
	first.player.gold = 111
	assert(Store.save(first, path))
	first.player.gold = 222
	assert(Store.save(first, path))
	var generations := Store._generations(path)
	var file := FileAccess.open(generations[0].path, FileAccess.WRITE)
	file.store_string("{truncated")
	file.close()
	var recovered := Store.load_state(europe, path)
	assert(recovered != null and recovered.player.gold == 111)
	first.player.gold = 333
	assert(Store.save(first, path))
	var newest := Store.load_state(europe, path)
	assert(newest != null and newest.player.gold == 333)
	assert(Store.save(first, path))
	assert(Store._generations(path).size() <= Store.KEEP_GENERATIONS)
	for state in [first, second, migrated, recovered, newest]: state.dispose()
	print("Save v2 tests passed")
	quit(0)
