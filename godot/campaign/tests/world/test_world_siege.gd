extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://campaign/world/world_state.gd")
const Siege = preload("res://campaign/world/world_siege.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	var p = s.player
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "nord":
			town = t
			break
	assert(not town.is_empty())
	assert(not Siege.hostile(town, p.rel), "no war while relations are fine")
	p.rel["nord"] = -50
	assert(Siege.hostile(town, p.rel))
	# walking into a hostile town asks for a siege, not a market
	p.x = town.x
	p.y = town.y
	var asked := []
	s.siege_requested.connect(func(t): asked.append(t.id))
	var entered := []
	s.settlement_entered.connect(func(t): entered.append(t.id))
	s.enter(town)
	assert(asked == [town.id] and entered.is_empty(), "hostile town opens the siege window")
	var party: Dictionary = s.siege.siege_party(town)
	assert(party.kind == "siege" and party.id == -town.id and party.troops.size() > 0)
	assert(Siege.def_k(town) > 1.5)
	var price: int = s.siege.bribe(town)
	assert(price > 200)
	p.troops = [{"type": "e2a", "n": 400}]
	assert(s.siege.talk_chance(p, town, true) > s.siege.talk_chance(p, town, false))
	# a refused talk closes talks for a day
	p.gold = 10
	assert(s.siege.talk(p, town, true) == null, "no gold, no bribe")
	p.gold = 5000
	var tries := 0
	while tries < 300 and town.fac != "player":
		p.gold = 5000
		var r: Variant = s.siege.talk(p, town, true)
		if r == null:
			assert(int(town.get("talkT", 0)) > s.siege.now_h())
			town.talkT = 0
		tries += 1
	assert(town.fac == "player", "a bribe eventually works")
	assert(town.owner == 0 and town.gar.size() > 0 and Siege.hostile(town, p.rel) == false)
	assert(p.rel["nord"] > -100)
	# holdings pay and cost
	assert(s.siege.income(town) > 100)
	var gold_before: int = p.gold
	var line: String = s.siege.holdings_day(p, 0.0)
	assert("Владения" in line and p.gold != gold_before)
	# garrison moves
	p.troops = [{"type": "e2a", "n": 10}]
	var moved: int = s.siege.gar_move(p, town, "e2a", 4, true, 50)
	assert(moved == 4 and p.troops[0].n == 6)
	assert(s.siege.gar_move(p, town, "e2a", 99, true, 50) == 5, "the last man stays with the hero")
	assert(s.siege.gar_move(p, town, "e2a", 3, false, 50) == 3)
	# plunder or spare
	var before: int = p.gold
	assert("разграбил" in s.siege.sack(p, town) and p.gold > before and town.dmg >= 0.6 and town.recruits.is_empty())
	assert("пощадил" in s.siege.spare(p, town) and town.dmg <= 0.1)
	print("World siege tests passed")
	quit(0)
