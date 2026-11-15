extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://campaign/world/world_state.gd")
const WorldSave = preload("res://campaign/world/world_save.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const Marks = preload("res://apps/godot/presentation/campaign/world_marks_layer.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var w = s.wars
	var p = s.player
	var news: Array = []
	w.announced.connect(func(t): news.append(t))
	# an AI siege: walls get battered, a sortie happens, relief comes from lords nearby
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "nord":
			town = t
			break
	var army: Array = []
	for i in 3:
		army.append(s.roster.make_party("lord", "emp", "Легат %d" % i, town.x + 10 * i, town.y + 30, [{"type": "e2a", "n": 120}], {"army": true}))
	town.siege = {"f": "emp", "t0": w.now_h() - 20, "a0": 1.0, "g0": 100}
	var helper: Dictionary = s.roster.make_party("lord", "nord", "Ярл Подмога", town.x + 200, town.y, [{"type": "n2a", "n": 200}])
	var a_str := 0.0
	for a in army:
		a_str += s.roster.strength_of(a)
	for i in 30:
		if town.get("siege") == null:
			break
		w._sg_tick(town, town.siege, army.filter(func(x): return x in s.roster.parties), a_str, 1.0)
	assert(float(town.get("dmg", 0.0)) > 0.0, "walls take damage")
	assert(helper.get("relief") == town.id or town.get("siege") == null or news.any(func(t): return "подмога" in t.to_lower()), "relief was called")
	# fires burn out and walls are repaired hour by hour
	town.siege = null
	town.fire = 2
	var dmg: float = town.dmg
	w._sg_hour()
	assert(int(town.fire) == 1 and float(town.dmg) < dmg)
	assert(helper.get("relief") == null, "relief lords go home after the siege")
	# lords sometimes sack a taken town
	var sacked := false
	for i in 20:
		town.recruits = [{"type": "n1", "n": 3}]
		w._sack_ai(town)
		if town.recruits.is_empty():
			sacked = true
			break
	assert(sacked and float(town.dmg) >= 0.5)
	# the player's blockade starves a garrison into surrender
	p.rel["nord"] = -60
	var other: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "nord":
			other = t
			break
	p.x = other.x
	p.y = other.y
	assert("блокаду" in s.siege.block_start(p, other))
	other.food = 0.01
	var hours := 0
	while other.fac != "player" and hours < 24 * 20:
		s.siege.block_hour(p, hours % 24)
		hours += 1
	assert(other.fac == "player" and not other.has("blk"), "hunger makes the town give up")
	# fights that last hours
	var a: Dictionary = s.roster.make_party("lord", "emp", "Легат А", 2000, 1500, [{"type": "e2a", "n": 60}])
	var b: Dictionary = s.roster.make_party("lord", "nord", "Ярл Б", 2005, 1500, [{"type": "n2a", "n": 60}])
	s.skirmish.contact(a, b, s.ai.auto_fight)
	assert(s.skirmish.fights.size() == 1 and a.fight == b.fight)
	var join: Dictionary = s.roster.make_party("lord", "emp", "Легат В", 2030, 1500, [{"type": "e2a", "n": 60}])
	for i in 40:
		if s.skirmish.fights.is_empty():
			break
		s.skirmish.hour_tick()
	assert(s.skirmish.fights.is_empty(), "the fight ends")
	assert(join.get("fight") == null)
	# small bands settle it at once
	var c1: Dictionary = s.roster.make_party("bandit", "bandit", "Шайка", 3000, 1500, [{"type": "b1", "n": 5}])
	var c2: Dictionary = s.roster.make_party("caravan", "emp", "Караван", 3002, 1500, [{"type": "e1", "n": 5}])
	s.skirmish.contact(c1, c2, s.ai.auto_fight)
	assert(s.skirmish.fights.is_empty())
	# allies of the enemy join the player's battle and get their survivors back
	p.x = 4000.0
	p.y = 1500.0
	var foe: Dictionary = s.roster.make_party("lord", "nord", "Ярл Враг", 4010, 1500, [{"type": "n2a", "n": 30}])
	var friend: Dictionary = s.roster.make_party("lord", "nord", "Ярл Друг", 4050, 1500, [{"type": "n2a", "n": 30}])
	var help: Array = s.skirmish.helpers(p, foe)
	assert(friend in help)
	s.skirmish.merge(foe, help)
	assert(Rules.troop_count(foe.troops) == 60 and not friend in s.roster.parties)
	foe.troops = [{"type": "n2a", "n": 20}]
	s.skirmish.split(foe)
	assert(friend in s.roster.parties and Rules.troop_count(friend.troops) == 10 and Rules.troop_count(foe.troops) == 10)
	# a fallen state's houses go to the winner
	var houses: int = s.clans.of_faction("khan").size()
	w._fall("khan", "emi")
	assert(s.clans.of_faction("khan").is_empty() and s.clans.of_faction("emi").size() >= houses)
	# save keeps fights, sieges and blockades
	s.skirmish.contact(a if a in s.roster.parties else s.roster.make_party("lord", "emp", "Г", 100, 100, [{"type": "e2a", "n": 60}]), s.roster.make_party("lord", "nord", "Д", 102, 100, [{"type": "n2a", "n": 60}]), s.ai.auto_fight)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back.skirmish.fights.size() == s.skirmish.fights.size())
	# windows and marks
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	pw.open_for(s, "factions")
	assert(pw.body.get_child_count() > 6)
	p.quests.append({"id": 1, "from": town.id, "fac": "emp", "day": 1, "type": "deliver", "sid": town.id, "reward": 100, "dl": 30})
	pw.open_for(s, "quests")
	var marks := Marks.new()
	root.add_child(marks)
	marks.build(s)
	town.siege = {"f": "emp", "t0": 0, "a0": 1.0, "g0": 1}
	town.fire = 5
	marks.show_quest_target(town.x, town.y)
	await process_frame
	await process_frame
	# declaring war to besiege a peaceful town, and the hostility notice
	var logged: Array = []
	s.log_added.connect(func(t): logged.append(t))
	p.rel["kin"] = 10
	s.rel_watch()
	var asked: Array = []
	s.siege_requested.connect(func(t): asked.append(t.id))
	s.declare_war("kin")
	assert(float(p.rel["kin"]) <= -45.0 and logged.any(func(t): return "враг" in t))
	print("War extras tests passed")
	quit(0)
