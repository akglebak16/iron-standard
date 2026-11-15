extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var c = s.clans
	var p = s.player
	assert(c.clans.size() == 4 * s.wars.factions_alive().size(), "four houses per state")
	for f in s.wars.factions_alive():
		var r: Dictionary = c.ruler_of(f)
		assert(not r.is_empty() and String(r.name).begins_with(c.RTITLE[f]), "ruler for %s" % f)
		assert(not c.kingless(f))
	assert(c.label("Эйнар") == "Дом Эйнара" and c.label("Юрий") == "Дом Юрия")
	# the houses refill to two lords
	s.wars.day = 3
	for i in 3:
		c.refill()
	var house: Dictionary = c.of_faction("nord")[1]
	assert(c.members(house).size() == 2, "a house gets its lords")
	# the ruler falls: interregnum, then a new one
	var ruler: Dictionary = c.ruler_of("nord")
	s.roster.remove(ruler)
	c.ruler_day()
	assert(c.kingless("nord"))
	s.wars.day = 10
	c.ruler_day()
	assert(not c.kingless("nord") and not c.ruler_of("nord").is_empty())
	# the oath
	assert(c.oath_why("emp") != "", "level 1 hero cannot swear")
	p.hero.lvl = 3
	p.rel["emp"] = 40
	assert(c.swear("emp") == "")
	assert(p.liege == "emp")
	for f in Rules.REAL_FACTIONS:
		if f != "emp" and s.wars.at_war("emp", f):
			assert(float(p.rel[f]) <= -25.0)
	var gold: int = p.gold
	c.vassal_day()
	assert(p.gold == gold + c.pay())
	# a missed summons costs a strike
	p.summons = {"tid": 1, "until": 0, "joined": false}
	c.vassal_day()
	assert(p.strikes == 1 and p.summons == null)
	# luring a house of an enemy state
	var enemy := ""
	for f in Rules.REAL_FACTIONS:
		if f != "emp" and s.wars.at_war("emp", f):
			enemy = f
			break
	var target: Dictionary = {}
	for h in c.of_faction(enemy):
		if not h.rule and not c.members(h).is_empty():
			target = c.members(h)[0]
			break
	assert(not target.is_empty())
	assert(c.lure_why(target) == "")
	p.gold = 100000
	var tries := 0
	var moved := false
	while tries < 200 and not moved:
		p.lure_day = -99
		var r: Dictionary = c.lure_try(target)
		moved = r.ok
		tries += 1
	assert(moved and target.fac == "emp", "a house changes sides")
	# a captured settlement unsettles the loser's houses
	var loy: int = c.of_faction(enemy)[0].loy
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.fac == enemy and t.kind == "castle":
			town = t
	c.on_capture(town, enemy, "emp")
	assert(int(c.of_faction(enemy)[0].loy) < loy)
	# leaving the service
	c.leave()
	assert(p.liege == "")
	# a day runs
	c.day_tick()
	# save keeps houses, rulers and the oath
	c.swear("emp")
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back.clans.clans.size() == c.clans.size() and back.player.liege == p.liege)
	assert(back.clans.clans[0].id is int)
	var lord: Dictionary = back.roster.parties.filter(func(q): return q.get("clan") != null)[0]
	assert(lord.clan is int)
	# the service tab renders
	var tw := TownWindow.new()
	root.add_child(tw)
	await process_frame
	var emp_town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "emp":
			emp_town = t
			break
	tw.open_for(s, emp_town)
	tw.current_tab = "oath"
	tw.render()
	assert(tw.body.get_child_count() > 4)
	print("Clans tests passed")
	quit(0)
