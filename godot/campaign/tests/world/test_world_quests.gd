extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const WorldSave = preload("res://campaign/world/world_save.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const TownWindow = preload("res://campaign/presentation/town_window.gd")
const PartyWindow = preload("res://campaign/presentation/party_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var s := WorldState.create(5, data, "emp")
	var p = s.player
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "emp":
			town = t
			break
	assert(town.board.size() == 3, "every town board has three offers")
	var types := {}
	for t in s.map.settles:
		if t.kind == "town" and t.has("board"):
			for q in t.board:
				types[q.type] = true
				assert(s.quests.text(q) != "")
	assert(types.size() >= 4, "several quest kinds: %s" % str(types.keys()))
	# deliver quest: take it, walk into the target, get paid
	var deliver := {"id": 999, "from": town.id, "fac": "emp", "day": 1, "type": "deliver", "sid": town.id, "reward": 120, "dl": 10}
	town.board.append(deliver)
	assert(s.quests.accept(p, town, 999) == "")
	assert(p.quests.size() == 1 and not deliver in town.board)
	var gold: int = p.gold
	s.quests.on_enter(p, town, 0.0)
	assert(p.quests.is_empty() and p.gold == gold + 120)
	# supply quest needs the goods
	var supply := {"id": 1000, "from": town.id, "fac": "emp", "day": 1, "type": "supply", "sid": town.id, "item": "grain", "n": 12, "reward": 200, "dl": 10}
	p.quests.append(supply)
	p.inv = {"grain": 5}
	s.quests.on_enter(p, town, 0.0)
	assert(p.quests.size() == 1)
	p.inv = {"grain": 15}
	s.quests.on_enter(p, town, 0.0)
	assert(p.quests.is_empty() and p.inv.grain == 3)
	# scouting marks a camp when close
	var camp: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "camp":
			camp = t
			break
	var scout := {"id": 1001, "from": town.id, "fac": "emp", "day": 1, "type": "scout", "sid": camp.id, "seen": false, "reward": 150, "dl": 10}
	p.quests.append(scout)
	p.x = camp.x
	p.y = camp.y
	s.quests.scout_tick(p)
	assert(scout.seen)
	s.quests.on_enter(p, town, 0.0)
	assert(p.quests.is_empty())
	# muster moves tier-2 men into the garrison
	var castle: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "emp":
			castle = t
			break
	p.troops = [{"type": "e1", "n": 5}, {"type": "e2a", "n": 8}]
	p.quests.append({"id": 1002, "from": town.id, "fac": "emp", "day": 1, "type": "muster", "sid": castle.id, "n": 6, "reward": 300, "dl": 10})
	s.quests.on_enter(p, castle, 0.0)
	assert(p.quests.is_empty() and p.troops.size() == 2 and int(p.troops[1].n) == 2)
	# deadlines fail quests
	p.quests.append({"id": 1003, "from": town.id, "fac": "emp", "day": 1, "type": "deliver", "sid": town.id, "reward": 120, "dl": 3})
	s.quests.deadline_day(p, 4)
	assert(p.quests.is_empty())
	# taverns: every companion sits somewhere, hire and fire
	var total := 0
	var where: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town":
			for c in s.companions.at(p, t):
				total += 1
				where = t
	assert(total == s.companion_catalog.size(), "all companions wait in taverns")
	var here: Array = s.companions.at(p, where)
	p.gold = 5000
	assert(s.companions.hire(p, where, here[0].id) == "")
	assert(p.comps.size() == 1 and s.companions.at(p, where).size() == here.size() - 1)
	assert(s.player_effects().size() > 0)
	assert(s.companions.wage(p) >= 0)
	assert(s.companions.fire(p, here[0].id) and p.comps.is_empty())
	s.companions.hire(p, s.map.settlement_by_id(s.companions.pos[here[0].id]), here[0].id)
	# save keeps quests, boards and companions
	p.quests.append({"id": 1004, "from": town.id, "fac": "emp", "day": 1, "type": "deliver", "sid": town.id, "reward": 120, "dl": 30})
	var d := WorldSave.to_dict(s)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)), data)
	assert(back.player.quests.size() == 1 and back.player.quests[0].sid is int)
	assert(back.player.comps.size() == 1 and back.player.comps[0].lvl is int)
	assert(back.companions.pos.size() == s.companions.pos.size())
	assert(back.map.settlement_by_id(town.id).board.size() == town.board.size())
	# windows render the new tabs
	var tw := TownWindow.new()
	root.add_child(tw)
	await process_frame
	tw.open_for(s, where)
	for tab in ["tavern", "quests"]:
		tw.current_tab = tab
		tw.render()
		assert(tw.body.get_child_count() >= 1, tab)
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	for tab in ["comps", "quests"]:
		pw.open_for(s, tab)
		assert(pw.body.get_child_count() >= 1, tab)
	# a day passes with companions and quests
	s.clock.day = 8
	s._day_tick()
	print("World quests and companions tests passed")
	quit(0)
