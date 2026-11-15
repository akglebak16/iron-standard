extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const WorldSave = preload("res://campaign/world/world_save.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Bridge = preload("res://apps/godot/composition/world_battle_bridge.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var s := WorldState.create(5, data, "emp")
	var p = s.player
	var vs = s.vassals
	var castle: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "castle" and t.fac == "nord":
			castle = t
			break
	s.siege.capture(p, castle)
	var where: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and not s.companions.at(p, t).is_empty():
			where = t
			break
	p.gold = 10000
	var cid: String = s.companions.at(p, where)[0].id
	assert(s.companions.hire(p, where, cid) == "")
	assert(vs.why_not(cid, where.id) != "", "only own fiefs")
	assert(vs.grant(cid, castle.id) == "")
	assert(p.comps.is_empty() and p.vass.size() == 1 and castle.vass == cid)
	assert(s.companions.at(p, where).all(func(c): return c.id != cid), "a vassal is not in a tavern")
	var retinue: Dictionary = vs.party_of(p.vass[0])
	assert(not retinue.is_empty() and retinue.kind == "cvass")
	assert(not castle in s.siege.holdings(), "the vassal pays the garrison himself")
	# a day: tribute and hiring
	var gold: int = p.gold
	p.vass[0].gold = 2000.0
	vs.day_tick()
	assert(p.gold >= gold and Rules.troop_count(retinue.troops) > 4, "the retinue grows")
	# retinue AI and hostility
	assert(not Rules.hostile(retinue, {"kind": "caravan", "fac": "emp"}))
	assert(Rules.hostile(retinue, {"kind": "bandit", "fac": "bandit"}))
	p.rel["khan"] = -50
	Rules.player_rel = p.rel
	assert(Rules.hostile(retinue, {"kind": "lord", "fac": "khan"}))
	for m in ["patrol", "follow", "guard"]:
		vs.set_mode(cid, m)
		vs.ai(retinue, 1.0)
	# helpers join a battle and share the losses
	var enemy: Dictionary = s.roster.make_party("bandit", "bandit", "Тест", retinue.x + 20, retinue.y, [{"type": "b1", "n": 10}])
	var help: Array = vs.helpers(enemy)
	assert(help == [retinue])
	var allies: Array = Bridge.snapshot(help)
	var b := Bridge.new()
	p.troops = [{"type": "e1", "n": 10}]
	var before: int = Rules.troop_count(retinue.troops)
	var party: Dictionary = b.party_dict(s, allies)
	assert(Rules.troop_count(party.troops) == 10 + before)
	var after: Array = Bridge.merged([], [])
	after = party.troops.duplicate(true)
	for t in after:
		t.n = int(t.n / 2)
	var mine: Array = b._split(s, p.troops, after, allies)
	assert(Rules.troop_count(mine) <= 10 and Rules.troop_count(retinue.troops) <= before)
	# a hostile lord storms an empty fief of the player
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "khan":
			town = t
			break
	s.siege.capture(p, town)
	town.gar = []
	var lord: Dictionary = s.roster.parties.filter(func(q): return q.kind == "lord" and q.fac == "khan")[0]
	lord.hide = false
	lord.x = town.x
	lord.y = town.y
	s.siege.assaults_tick(p)
	assert(town.fac == "khan", "the empty town falls")
	# revoke: the companion comes back with the vassal's purse
	assert(vs.revoke(cid))
	assert(p.vass.is_empty() and p.comps.size() == 1 and not castle.has("vass"))
	vs.grant(cid, castle.id)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data)
	assert(back.player.vass.size() == 1 and back.player.vass[0].sid is int and back.map.settlement_by_id(castle.id).vass == cid)
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	pw.open_for(s, "comps")
	assert(pw.body.get_child_count() >= 3)
	print("Vassals tests passed")
	quit(0)
