extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var u = s.undead
	assert(int(u.crisis.day) >= 40 and int(u.crisis.day) <= 60 and not u.crisis.on)
	var news: Array = []
	u.announced.connect(func(t): news.append(t))
	u.day = int(u.crisis.day)
	u.day_tick()
	assert(u.crisis.on and u.crisis.src.size() == 2, "two barrows")
	var barrow: Dictionary = s.map.settlement_by_id(u.crisis.src[0])
	assert(barrow.barrow and barrow.fac == "undead" and barrow.name == "Чёрный курган")
	var armies: Array = s.roster.parties.filter(func(p): return p.kind == "dead")
	var raids: Array = s.roster.parties.filter(func(p): return p.kind == "raid")
	assert(armies.size() == 6 and raids.size() == 4, "%d armies, %d raids" % [armies.size(), raids.size()])
	assert(Rules.troop_count(armies[0].troops) >= 700)
	assert("Мёртвые восстали" in news[0])
	# a raid burns a village
	var village: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "village" and t.fac == "emp":
			village = t
			break
	u.arrive(raids[0], village)
	assert(int(village.burnt) > 0 and village.recruits.is_empty())
	# an army storms a castle into ruins
	var castle: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "nord":
			castle = t
			break
	var army: Dictionary = armies[0]
	army.troops = [{"type": "s3", "n": 2000}]
	u.arrive(army, castle)
	assert(castle.fac == "undead" and castle.ruinOf == "nord" and castle.gar.size() > 0)
	assert(u.ruins_for("nord") == [castle])
	# a strong lord takes it back
	var lord: Dictionary = s.roster.parties.filter(func(p): return p.kind == "lord" and p.fac == "nord")[0]
	lord.troops = [{"type": "n3a", "n": 900}] if s.roster.catalog.get_troop("n3a").size() > 0 else [{"type": "n2a", "n": 1500}]
	assert(u.noble_retake(lord, castle))
	assert(castle.fac == "nord" and int(castle.ruin) > 0)
	# undead win and raise their dead
	var before: int = Rules.troop_count(army.troops)
	u.raise(army, 10)
	assert(Rules.troop_count(army.troops) >= before)
	# AI idle sends the dead to a target
	var raid: Dictionary = raids[1]
	u.idle(raid)
	assert(raid.state == "travel" or raid.state == "roam")
	# hours rebuild villages
	village.burnt = 1
	u.hour_tick()
	assert(int(village.burnt) == 0)
	# barrow destroyed by the player
	u.barrow_destroyed(s.player, barrow)
	assert(not barrow.barrow and barrow.fac == "bandit" and int(u.crisis.left[str(barrow.id)]) == 0)
	# save keeps the crisis
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back.undead.crisis.on and back.undead.crisis.src[0] is int)
	assert(back.map.settlement_by_id(barrow.id).name == barrow.name)
	# a few world hours run with the dead on the map
	for i in 24:
		s.step(1.0)
		s.hour_tick()
	print("Undead tests passed: %d news" % news.size())
	quit(0)
