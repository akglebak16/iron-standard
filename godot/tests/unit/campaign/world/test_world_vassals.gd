extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
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
	# a retinue by its fief helps the garrison hold a siege (stage 2b: sieges instead of storms) and shares its losses
	retinue.x = castle.x + 2000.0
	var bare: float = s.wars.siege_def(castle)
	retinue.x = castle.x + 10.0
	retinue.y = castle.y + 20.0
	assert(s.wars.siege_def(castle) > bare, "the retinue by the walls counts for the defence")
	var men: int = Rules.troop_count(retinue.troops)
	var khan_army: Dictionary = s.roster.make_party("lord", "khan", "Тумен", castle.x + 20, castle.y, [{"type": "k2a", "n": 400}], {"army": true})
	castle.siege = {"f": "khan", "t0": s.wars.now_h(), "a0": s.roster.strength_of(khan_army), "g0": 100}
	for i in 10:
		if castle.get("siege") == null or not retinue in s.roster.parties or Rules.troop_count(retinue.troops) < men:
			break
		retinue.x = castle.x + 10.0
		retinue.y = castle.y + 20.0
		s.wars._siege_tick(castle)
	assert(Rules.troop_count(retinue.troops) < men or not retinue in s.roster.parties, "the retinue bleeds with the garrison")
	castle.siege = null
	s.roster.remove(khan_army)
	if not retinue in s.roster.parties:
		retinue = vs.spawn(p.vass[0])
	# retinue AI and hostility
	assert(not s.roster.hostile(retinue, {"kind": "caravan", "fac": "emp"}))
	assert(s.roster.hostile(retinue, {"kind": "bandit", "fac": "bandit"}))
	p.rel["khan"] = -50
	assert(s.roster.hostile(retinue, {"kind": "lord", "fac": "khan"}))
	for m in ["patrol", "follow", "guard"]:
		vs.set_mode(cid, m)
		s.ai.ai_party(retinue, 1.0)
	# helpers join a battle and share the losses
	var enemy: Dictionary = s.roster.make_party("bandit", "bandit", "Тест", retinue.x + 20, retinue.y, [{"type": "b1", "n": 10}])
	var help: Array = vs.helpers(enemy)
	assert(help == [retinue])
	var allies: Array = Bridge.snapshot(help)
	var b := Bridge.new(ContentLoader.registry(), RandomNumberGenerator.new())
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
	# a hostile faction takes an empty fief of the player by a siege (stage 2b: no more storms by a lord passing by)
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "khan":
			town = t
			break
	s.siege.capture(p, town)
	town.gar = []
	var lord: Dictionary = s.roster.parties.filter(func(q): return q.kind == "lord" and q.fac == "khan")[0]
	lord.hide = false
	lord.army = true
	lord.x = town.x
	lord.y = town.y
	town.siege = {"f": "khan", "t0": s.wars.now_h() - 20, "a0": s.roster.strength_of(lord), "g0": 10}
	s.wars._siege_tick(town)
	assert(town.fac == "khan", "the empty town falls")
	# revoke: the companion comes back with the vassal's purse
	assert(vs.revoke(cid))
	assert(p.vass.is_empty() and p.comps.size() == 1 and not castle.has("vass"))
	vs.grant(cid, castle.id)
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(s))), data, ContentLoader.registry())
	assert(back.player.vass.size() == 1 and back.player.vass[0].sid is int and back.map.settlement_by_id(castle.id).vass == cid)
	_check_orders(s, cid, castle, where)
	var pw := PartyWindow.new()
	root.add_child(pw)
	await process_frame
	pw.open_for(s, "comps")
	assert(pw.body.get_child_count() >= 3)
	print("Vassals tests passed")
	quit(0)

## Orders of a retinue are weight sets of the shared goals (party_goals.gd); for the player they mean what they meant.
func _check_orders(s, cid: String, castle: Dictionary, town: Dictionary) -> void:
	var vs = s.vassals
	var retinue: Dictionary = vs.party_of(vs.of_id(cid))
	assert(not retinue.is_empty())
	var all: Array = s.roster.parties
	s.roster.parties = [retinue]  # nobody else on the map: only the order decides
	var p = s.player
	p.away = false
	p.x = town.x + 10.0
	p.y = town.y + 34.0
	vs.set_mode(cid, "guard")
	retinue.x = castle.x + 300.0
	retinue.y = castle.y + 22.0
	s.ai.ai_party(retinue, 0.2)
	assert(retinue.goal == "guard" and not retinue.path.is_empty(), "guarding: back to the fief")
	var end: Vector2 = retinue.path[retinue.path.size() - 1]
	assert(end.distance_to(Vector2(castle.x, castle.y + 22.0)) < 40.0, "the guard stands by its fief: %s" % [end])
	vs.set_mode(cid, "follow")
	s.ai.ai_party(retinue, 0.2)
	assert(retinue.goal == "follow" and retinue.gid == -1 and not retinue.path.is_empty(), "following the player")
	end = retinue.path[retinue.path.size() - 1]
	assert(end.distance_to(Vector2(p.x, p.y)) < 80.0, "the retinue rides up to the player: %s" % [end])
	vs.set_mode(cid, "patrol")
	s.ai.ai_party(retinue, 0.2)
	assert(retinue.goal == "patrol" and not retinue.path.is_empty(), "patrolling around the fief")
	end = retinue.path[retinue.path.size() - 1]
	assert(end.distance_to(Vector2(castle.x, castle.y)) < 700.0)
	s.roster.parties = all
