extends SceneTree
## Operations of factions in a live world (world_wars.gd, DESIGN.md §5.3, stage 2b): the marshal leads the host, lords
## stay home by threatened settlements, relief of an own besieged settlement, retreat, and sieges of the player's
## holdings instead of storms by lords passing by. Every check starts from a map cleared of parties; one world is
## built (4 s) and its settlements, wars, relations, campaigns and journal are reset between the checks.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Config = preload("res://core/campaign/config.gd")

var data := EuropeData.new()
var _shared: RefCounted = null
var _settles0: Array = []
var _wars0 := {}
var _rel0 := {}

func _initialize() -> void:
	assert(ContentLoader.populate(data))
	_check_marshal_and_defenders()
	_check_recall()
	_check_relief()
	_check_player_holding()
	_check_empty_lands()
	_shared.dispose()
	print("World operations tests passed")
	quit(0)

func _world() -> RefCounted:
	if _shared == null:
		_shared = WorldState.create(5, data, "emp", ContentLoader.registry())
		_settles0 = _shared.map.settles.duplicate(true)
		_wars0 = _shared.wars.wars.duplicate(true)
		_rel0 = _shared.player.rel.duplicate(true)
	else:
		for i in _settles0.size():
			var st: Dictionary = _shared.map.settles[i]
			st.clear()
			st.merge(_settles0[i].duplicate(true))
		_shared.wars.wars.clear()
		_shared.wars.wars.merge(_wars0.duplicate(true))
		_shared.wars.campaigns.clear()
		_shared.player.rel = _rel0.duplicate(true)
		_shared.journal.clear()
	var s = _shared
	s.roster.parties.clear()
	s.wars.hour = 0
	s._threat_step += 1  # the threat map is rebuilt from the parties this check places
	assert(s.roster.diplomatic_wars == s.wars.wars)
	return s

static func _place(s, kind: String, fac: String, skip: Array = []) -> Dictionary:
	for t in s.map.settles:
		if t.kind == kind and t.fac == fac and not t.id in skip:
			return t
	return {}

static func _lord(s, fac: String, name: String, at: Dictionary, dx: float, type: String, n: int, extra := {}) -> Dictionary:
	return s.roster.make_party("lord", fac, name, at.x + dx, at.y + 20.0, [{"type": type, "n": n}], extra)

static func _at(p: Dictionary, x: float, y: float) -> void:
	p.x = x
	p.y = y
	p.path = []
	p.pi = 0

static func _end(p: Dictionary) -> Vector2:
	return p.path.back() if not p.path.is_empty() else Vector2(p.x, p.y)

## The marshal leads, the nearest lord stays by a threatened castle and the weakest by the rest; the host musters and
## marches around the marshal, he waits for stragglers; a spent host gives up the siege.
func _check_marshal_and_defenders() -> void:
	var s = _world()
	var w = s.wars
	var events: Array = []
	w.operation.connect(func(e): events.append(e))
	var news: Array = []
	w.announced.connect(func(t): news.append(t))
	var home := _place(s, "town", "emp")
	var castle := _place(s, "castle", "emp")
	var a := _lord(s, "emp", "Маршал", home, 0, "e3", 300)
	var b := _lord(s, "emp", "Второй", home, 400, "e3", 200)
	var c := _lord(s, "emp", "У замка", castle, 30, "e2a", 200)
	var d := _lord(s, "emp", "Слабый", home, 60, "e1", 180)
	var e := _lord(s, "emp", "Потрёпанный", home, 90, "e3", 60)  # under half of a full army: rests, no campaign
	var foe: Dictionary = s.roster.make_party("lord", "nord", "Ярл у замка", castle.x + 60, castle.y, [{"type": "n3", "n": 400}])
	assert(w.ops.alerts("emp", s.map.settles, w._threat_at).any(func(x): return x.s == castle), "the threat map shows the enemy by the castle")
	w._campaign("emp")
	assert(w.campaigns.has("emp"), "a campaign starts")
	var camp: Dictionary = w.campaigns.emp
	assert(camp.marshal == a.id, "the strongest lord is the marshal")
	assert(c.id in camp.keep and d.id in camp.keep and camp.keep.size() == 2, "the lord by the threatened castle and the weakest stay home: %s" % [camp.keep])
	assert(camp.army.size() == 2 and a.id in camp.army and b.id in camp.army and a.army and b.army and not c.get("army", false) and not d.get("army", false))
	assert(not e.get("army", false) and not e.id in camp.keep, "a battered lord neither marches nor counts among those left home")
	assert(is_equal_approx(float(camp.s0), s.roster.strength_of(a) + s.roster.strength_of(b)), "the strength at the muster is kept")
	assert(events.size() == 1 and events[0].what == "start" and events[0].keep == 2)
	assert(news.any(func(t): return "ведёт Маршал" in t), "the chronicle names the marshal: %s" % [news])
	assert(a.sid == camp.gid, "the marshal rides to the rally point")
	assert(b.state == "travel" and _end(b).distance_to(Vector2(a.x, a.y)) < Config.OP_FOLLOW_KEEP, "the others ride to the marshal")
	# the host gathered at the rally: the march begins
	var rally: Dictionary = s.map.settlement_by_id(camp.gid)
	_at(a, rally.x, rally.y)
	_at(b, rally.x + 20, rally.y)
	w._campaign("emp")
	assert(camp.state == "march" and a.sid == camp.tid, "the march goes to the target")
	# a straggler: the marshal waits for him
	var t: Dictionary = s.map.settlement_by_id(camp.tid)
	var dir := Vector2(t.x - rally.x, t.y - rally.y).normalized()
	_at(a, rally.x + dir.x * 120.0, rally.y + dir.y * 120.0)
	_at(b, rally.x - dir.x * 500.0, rally.y - dir.y * 500.0)
	w._campaign("emp")
	assert(a.path.is_empty(), "the marshal waits for the host")
	assert(_end(b).distance_to(Vector2(a.x, a.y)) < Config.OP_FOLLOW_KEEP, "the straggler catches up with the marshal")
	_at(b, a.x + 10, a.y)
	w._campaign("emp")
	assert(a.pi < a.path.size(), "with the host together the marshal marches on")
	# at the walls: the siege begins
	_at(a, t.x, t.y + 30)
	_at(b, t.x + 20, t.y + 30)
	w._campaign("emp")
	assert(camp.state == "siege" and t.get("siege") != null and t.siege.f == "emp", "the siege begins at the walls")
	# the host bleeds below the retreat share: the siege is given up
	for p in [a, b]:
		p.troops = [{"type": "e3", "n": roundi(Rules.troop_count(p.troops) * Config.OP_RETREAT_SHARE * 0.6)}]
	w._campaign("emp")
	assert(not w.campaigns.has("emp") and t.get("siege") == null, "a spent host gives up the campaign and the siege")
	assert(events.back().what == "retreat" and events.back().why == "weak")
	assert(not a.army and not b.army, "the lords are free again")
	assert(foe in s.roster.parties)

## An own town besieged near the marshal recalls a campaign against a castle; the host becomes its relief at once.
func _check_recall() -> void:
	var s = _world()
	var w = s.wars
	var events: Array = []
	w.operation.connect(func(e): events.append(e))
	var home := _place(s, "town", "emp")
	var a := _lord(s, "emp", "Маршал", home, 0, "e3", 300)
	var b := _lord(s, "emp", "Второй", home, 30, "e3", 250)
	w._campaign("emp")
	var camp: Dictionary = w.campaigns.emp
	var target := _place(s, "castle", "nord")
	camp.tid = target.id
	var besieged := _place(s, "town", "emp", [home.id])
	_at(a, besieged.x + 500, besieged.y)
	_at(b, besieged.x + 520, besieged.y)
	var foe: Dictionary = s.roster.make_party("lord", "nord", "Ярл", besieged.x + 20, besieged.y, [{"type": "n2a", "n": 300}], {"army": true})
	besieged.siege = {"f": "nord", "t0": w.now_h() - 4, "a0": s.roster.strength_of(foe), "g0": 100}
	w._campaign("emp")
	assert(not w.campaigns.has("emp"), "the campaign is called off")
	assert(events.back().what == "relief" and events[events.size() - 2].why == "home", "retreat for home, then relief: %s" % [events])
	assert(a.get("relief") == besieged.id and a.army, "the former host rides to the besieged town")
	assert(int(besieged.siege.relN) == 1)

## Relief reaches farther than before, one at a time per faction, and is not thrown at a hopeless siege.
func _check_relief() -> void:
	var s = _world()
	var w = s.wars
	var c1 := _place(s, "castle", "emp")
	var t2 := _place(s, "town", "emp")
	var t3 := _place(s, "town", "emp", [t2.id])
	var siege := func(place: Dictionary, n: int) -> Dictionary:
		var foe: Dictionary = s.roster.make_party("lord", "nord", "Осаждающий", place.x + 20, place.y, [{"type": "n2a", "n": n}], {"army": true})
		place.siege = {"f": "nord", "t0": w.now_h() - 20, "a0": s.roster.strength_of(foe), "g0": 100}
		return foe
	siege.call(c1, 250)
	var l1 := _lord(s, "emp", "Дальний", c1, 700, "e3", 200)
	w._siege_tick(c1)
	assert(l1.get("relief") == c1.id and l1.army, "a lord 700 away relieves the castle (480 before stage 2b)")
	siege.call(t2, 250)
	var l2 := _lord(s, "emp", "Ближний", t2, 300, "e3", 200)
	w._siege_tick(t2)
	assert(l2.get("relief") == null, "one defensive operation at a time")
	c1.siege = null
	w._sg_hour()
	assert(l1.get("relief") == null and not l1.army, "relief goes home when its siege is over")
	w._siege_tick(t2)
	assert(l2.get("relief") == t2.id, "the next besieged town gets its relief")
	t2.siege = null
	w._sg_hour()
	siege.call(t3, 3000)
	var l3 := _lord(s, "emp", "Одинокий", t3, 200, "e3", 120)
	w._siege_tick(t3)
	assert(l3.get("relief") == null and int(t3.siege.get("relN", 0)) == 0, "hopeless relief is not sent")

## The player's holdings: no storm by a lord passing by; a faction hostile to the player besieges them in a campaign,
## the journal tells the player, and the siege is lifted or the holding taken by the rules of every siege.
func _check_player_holding() -> void:
	var s = _world()
	var w = s.wars
	var p = s.player
	var kt := _place(s, "town", "khan")
	s.siege.capture(p, kt)
	assert(kt.fac == "player")
	kt.gar = [{"type": "e1", "n": 10}]
	for k in w.wars.keys():
		if "khan" in k.split("|"):
			w.wars.erase(k)
	p.rel["khan"] = 50
	assert(not "player" in w._foes_of("khan"), "a friendly faction does not besiege the player")
	p.rel["khan"] = -60
	assert(w._foes_of("khan") == ["player"], "a hostile one does: %s" % [w._foes_of("khan")])
	# a lord standing by the walls does not storm them any more
	var passer := _lord(s, "khan", "Проезжий", kt, 10, "k2a", 30)
	assert(not s.siege.has_method("assaults_tick"))
	for h in [3, 6, 9]:
		s.clock.hour = h
		s.hour_tick()
	assert(kt.fac == "player", "a lord passing by does not take the town")
	s.roster.remove(passer)
	# a campaign: the town is besieged and the player is told
	var home := _place(s, "town", "khan", [kt.id])
	var k1 := _lord(s, "khan", "Хан", home, 0, "k2a", 400)
	var k2 := _lord(s, "khan", "Нойон", home, 30, "k2a", 300)
	w.hour = 0
	w._campaign("khan")
	assert(w.campaigns.has("khan") and w.campaigns.khan.tid == kt.id, "the player's town is the target")
	assert(s.journal.any(func(j): return "твой" in j.text and j.kind == WorldState.JOURNAL_BAD), "the player hears of the campaign")
	var camp: Dictionary = w.campaigns.khan
	camp.state = "march"
	camp.t1 = w.now_h()
	_at(k1, kt.x, kt.y + 30)
	_at(k2, kt.x + 20, kt.y + 30)
	w._campaign("khan")
	assert(kt.get("siege") != null and kt.siege.f == "khan", "the town is besieged")
	assert(s.journal.any(func(j): return "осаждает твой" in j.text and j.kind == WorldState.JOURNAL_BAD), "the journal tells of the siege")
	# the player beats the besiegers on the map: the siege is lifted
	s.roster.remove(k1)
	s.roster.remove(k2)
	w._siege_tick(kt)
	assert(kt.get("siege") == null and kt.fac == "player")
	assert(s.journal.front().kind == WorldState.JOURNAL_GOOD and "снята" in s.journal.front().text, "the player hears that the siege is over")
	# a siege that wears the garrison down takes the town; the player is not a state that falls
	var news: Array = []
	w.announced.connect(func(t): news.append(t))
	var k3 := _lord(s, "khan", "Тумен", kt, 10, "k2a", 400, {"army": true})
	kt.siege = {"f": "khan", "t0": w.now_h() - 20, "a0": s.roster.strength_of(k3), "g0": 10}
	kt.gar = []
	w._siege_tick(kt)
	assert(kt.fac == "khan" and kt.get("owner") == null, "the town is lost")
	assert(s.journal.any(func(j): return "Владение потеряно" in j.text and j.kind == WorldState.JOURNAL_BAD))
	assert(not news.any(func(t): return "пало" in t), "losing the last holding is not the fall of a state: %s" % [news])

## A faction without settlements or without enemies starts no campaign.
func _check_empty_lands() -> void:
	var s = _world()
	var w = s.wars
	var home := _place(s, "town", "emp")
	_lord(s, "emp", "А", home, 0, "e3", 300)
	_lord(s, "emp", "Б", home, 30, "e3", 300)
	for k in w.wars.keys():
		if "emp" in k.split("|"):
			w.wars.erase(k)
	w._campaign("emp")
	assert(not w.campaigns.has("emp"), "no war, no campaign")
	w.wars[Rules.war_key("emp", "nord")] = {"since": 1}
	for t in s.map.settles:
		if t.fac == "emp":
			t.fac = "nord"
	w._campaign("emp")
	assert(not w.campaigns.has("emp"), "no lands, no campaign")
	assert(w.ops.alerts("emp", s.map.settles, w._threat_at).is_empty())
