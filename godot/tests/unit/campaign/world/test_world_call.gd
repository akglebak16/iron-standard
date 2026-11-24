extends SceneTree
## Calls for help (#313, DESIGN.md §5.7): a lord or vassal that a stronger enemy chases, or that flees, calls; own lords and
## vassals that can turn it and get there in time answer (`rescue`), and the fleeing party runs to a strong own party in
## sight, so they meet half-way. The evaluator and the flight on synthetic data (made-up faction IDs, a hand-built threat
## map), then the live world: the calls of a step, a chase where the caller and the helper meet before the hunter catches
## up, a save with the new goal, and a ride that ends with the call.
const Goals = preload("res://core/campaign/world/party_goals.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Config = preload("res://core/campaign/config.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldCheckpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

var parties: Array = []
var settles: Array = []
var calls: Array = []
var wars := {"blue|red": true, "green|red": true}
var tm: ThreatMap = null
var next_id := 1

func _initialize() -> void:
	_check_evaluator()
	_check_choice()
	_check_flight()
	_check_world()
	print("World call tests passed")
	quit(0)

# ---------- synthetic ----------

func _goals() -> Goals:
	var g := Goals.new()
	g.parties = parties
	g.settles = settles
	g.strength = func(p): return float(p.troops.reduce(func(a, t): return a + int(t.n), 0))
	g.speed = func(p): return float(p.get("spd", 20.0))
	g.hostile = func(a, b):
		if a.fac == b.fac:
			return false
		if a.fac == "bandit" or b.fac == "bandit":
			return true
		return a.kind != "caravan" and b.kind != "caravan" and wars.has(_key(a.fac, b.fac))
	g.at_war = func(a, b): return wars.has(_key(a, b))
	g.threat_map = func(): return tm
	g.enemies = func(f): return tm.enemies_of(f, func(a, b): return a != b and (a == "bandit" or b == "bandit" or wars.has(_key(a, b)))) if tm != null else []
	g.calls = func(): return calls
	return g

static func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _reset() -> void:
	parties.clear()
	settles.clear()
	calls.clear()
	tm = null
	next_id = 1

func _party(kind: String, fac: String, x: float, y: float, n: int, extra := {}) -> Dictionary:
	var p := {"id": next_id, "kind": kind, "fac": fac, "name": kind, "x": x, "y": y, "troops": [{"type": "t", "n": n}],
		"hide": false, "path": [], "pi": 0, "state": "idle", "wait": 0.0, "goal": "", "gid": null, "ga": 0.0, "gs": 0.0}
	p.merge(extra, true)
	next_id += 1
	parties.append(p)
	return p

func _map() -> void:
	tm = ThreatMap.new()
	var list: Array = []
	for p in parties:
		list.append({"fac": p.fac, "x": p.x, "y": p.y, "strength": float(p.troops[0].n)})
	tm.rebuild(list)

## A call as PartyAI._beacons describes it.
func _call(c: Dictionary, foe: float, left := 20.0) -> Dictionary:
	var e := {"id": c.id, "fac": c.fac, "x": c.x, "y": c.y, "own": float(c.troops[0].n), "foe": foe, "left": left}
	calls.append(e)
	return e

static func _of(cands: Array, goal: String, gid: Variant = "any") -> Dictionary:
	for c in cands:
		if c.goal == goal and (gid is String or c.gid == gid):
			return c
	return {}

func _check_evaluator() -> void:
	_reset()
	var g := _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 80)
	var caller := _party("lord", "red", 1250.0, 1000.0, 50, {"state": "flee"})
	var e := _call(caller, 100.0)
	var c := _of(g.candidates(me), "rescue", caller.id)
	assert(not c.is_empty() and c.x == caller.x and c.y == caller.y, "a lord answers the call of its faction it hears: %s" % [g.candidates(me)])
	var answer := float(c.score)
	assert(_of(g.candidates(caller), "rescue").is_empty(), "the caller does not answer its own call")
	# hopeless: even together far weaker than the enemy
	e.foe = 400.0
	assert(_of(g.candidates(me), "rescue").is_empty(), "a hopeless call is not answered")
	e.foe = 100.0
	# too late: the caller is caught and beaten before the party gets there (250 at 20 an hour: 12.5 h)
	e.left = 3.0
	assert(_of(g.candidates(me), "rescue").is_empty(), "a call that is over before the party gets there is not answered")
	e.left = 20.0
	# out of hearing
	me.x = caller.x - Config.GOAL_ASSIST_RANGE - 20.0
	assert(_of(g.candidates(me), "rescue").is_empty(), "a call out of range is unknown")
	me.x = caller.x - Config.GOAL_ASSIST_RANGE + 20.0
	var far := float(_of(g.candidates(me), "rescue", caller.id).score)
	assert(far > 0.0 and far < answer, "a farther caller is worth less: %f < %f" % [far, answer])
	me.x = 1000.0
	# only its own faction (the enemy of my enemy is part 3); not campaign armies, caravans, bandits or retinues
	caller.fac = "green"
	e.fac = "green"
	assert(_of(g.candidates(me), "rescue").is_empty(), "the call of another faction is left to others")
	caller.fac = "red"
	e.fac = "red"
	assert(_of(g.candidates(me, {"army": true}), "rescue").is_empty(), "a party in a faction campaign follows its marshal")
	var vassal := _party("vassal", "red", 1000.0, 1020.0, 80)
	assert(not _of(g.candidates(vassal), "rescue", caller.id).is_empty(), "a faction vassal answers too")
	assert(_of(g.candidates(_party("caravan", "red", 1000.0, 1040.0, 80)), "rescue").is_empty(), "a caravan never answers")
	assert(_of(g.candidates(_party("bandit", "bandit", 1000.0, 1060.0, 80)), "rescue").is_empty(), "bands answer only from part 6 on")
	assert(_of(g.candidates(_party("cvass", "player", 1000.0, 1080.0, 80), {"mode": "patrol"}), "rescue").is_empty(), "the player's retinues follow his orders")
	# own parties already on the way
	parties.erase(vassal)
	var alone := float(_of(g.candidates(me), "rescue", caller.id).score)
	for i in 2:
		_party("lord", "red", 900.0, 900.0 + i * 10.0, 60, {"goal": "rescue", "gid": caller.id, "state": "roam"})
	g.rebuild_claims()
	assert(float(_of(g.candidates(me), "rescue", caller.id).score) < alone * 0.7, "a caller two own parties already ride to needs this one less")

## An answer reacts like help in battle: it may break a plan before its hold time is over (with the margin).
func _check_choice() -> void:
	_reset()
	var g := _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 120, {"goal": "patrol", "gid": 5000, "ga": 0.5, "path": [Vector2(900, 900)], "pi": 0, "state": "roam"})
	var caller := _party("lord", "red", 1100.0, 1000.0, 60, {"state": "flee"})
	_call(caller, 100.0)
	var cands: Array = g.candidates(me)
	cands.append({"goal": "patrol", "gid": 5000, "x": 900.0, "y": 900.0, "score": 0.2})
	cands.sort_custom(func(a, b): return a.score > b.score)
	assert(cands[0].goal == "rescue", "a close call of its own side outweighs a quiet patrol: %s" % [cands])
	var pick: Dictionary = g.choose(me, cands, RandomNumberGenerator.new())
	assert(pick.get("goal") == "rescue", "a held patrol gives way to the call: %s" % [pick])

## The fleeing party runs to a strong own party in sight, away from the enemy, rather than to a far own town.
func _check_flight() -> void:
	_reset()
	var g := _goals()
	var town := {"id": 5000, "kind": "town", "fac": "red", "name": "town", "x": 1600.0, "y": 1000.0}
	settles.append(town)
	var me := _party("lord", "red", 1000.0, 1000.0, 50)
	var foe := _party("lord", "blue", 850.0, 1000.0, 200)
	var friend := _party("lord", "red", 1200.0, 1000.0, 150)
	var behind := _party("lord", "red", 780.0, 1000.0, 300)  # past the enemy: no haven
	var near := _party("vassal", "red", 1040.0, 1000.0, 300)  # at hand already
	_map()
	var flee := _of(g.candidates(me), "flee")
	assert(not flee.is_empty(), "a lord flees an enemy four times its strength")
	assert(is_equal_approx(float(flee.foe), 200.0), "the flight knows the enemy it runs from: %s" % [flee.foe])
	assert(friend in flee.friends and behind in flee.friends and not near in flee.friends, "own lords and vassals in sight, not those at hand: %s" % [flee.friends.map(func(o): return o.id)])
	var havens := [{"id": town.id, "x": town.x, "y": town.y}]
	var t := g.flee_target(me, Vector2(foe.x, foe.y), havens, flee.friends, float(flee.foe))
	assert(t.get("pid") == friend.id and t.x == friend.x, "flight to the strong own lord nearby, not past the enemy and not to the far town: %s" % [t])
	assert(g.flee_target(me, Vector2(foe.x, foe.y), havens).sid == town.id, "without own parties in sight: the own town, as before")
	friend.troops[0].n = 20
	_map()
	t = g.flee_target(me, Vector2(foe.x, foe.y), havens, [friend], 200.0)
	assert(t.sid == town.id and not t.has("pid"), "a weak own party is no haven: together they do not stand up to the enemy: %s" % [t])
	friend.troops[0].n = 150
	# an answer under way: the flight turns to meet it, unless it comes from past the enemy
	var m := g.meet_target(me, Vector2(foe.x, foe.y), [friend], 200.0)
	assert(m.get("pid") == friend.id, "the caller turns to the own lord riding to it: %s" % [m])
	assert(g.meet_target(me, Vector2(foe.x, foe.y), [behind], 200.0).is_empty(), "not to one that comes from past the enemy")
	assert(g.meet_target(me, Vector2(foe.x, foe.y), [], 200.0).is_empty(), "nobody rides to it: the flight stays as it is")
	# a caravan looks for own lords and vassals in sight too (#315); bands do not (part 6)
	var caravan := _party("caravan", "red", 1000.0, 1100.0, 10)
	var band := _party("bandit", "bandit", 950.0, 1100.0, 200)
	_map()
	var cf := _of(g.candidates(caravan), "flee")
	assert(not cf.is_empty() and me in cf.friends and friend in cf.friends, "a caravan flees and sees own lords in sight: %s" % [cf])
	var bf := _of(g.candidates(band), "flee")
	assert(bf.is_empty() or bf.friends.is_empty(), "a band does not look for own parties")

# ---------- live world ----------

func _check_world() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s: RefCounted = WorldState.create(5, data, "emp", ContentLoader.registry())
	s.player.away = true
	var pair := _warring_pair(s)
	assert(not pair.is_empty(), "the world starts with a war between two states")
	var fa: String = pair[0]
	var fb: String = pair[1]
	var troop: String = s.roster.gen_troops(fa, 1, 0.5)[0].type  # one troop type everywhere: same speed, plain strengths
	var spot := _lonely_spot(s)
	s.roster.parties.clear()  # nobody else around: the caller, its hunter, the helper
	var caller: Dictionary = s.roster.make_party("lord", fa, "Тест зовущий", spot.x, spot.y, [{"type": troop, "n": 50}])
	var hunter: Dictionary = s.roster.make_party("lord", fb, "Тест охотник", spot.x + 150.0, spot.y, [{"type": troop, "n": 160}])
	var helper: Dictionary = s.roster.make_party("lord", fa, "Тест помощник", spot.x - 240.0, spot.y, [{"type": troop, "n": 200}])
	hunter.state = "hunt"
	hunter.tid = caller.id
	hunter.goal = "hunt"
	hunter.gid = caller.id
	hunter.rp = 0.0
	hunter.ai = 1000.0  # keeps hunting: only the caller and the helper decide here
	s.roster.path_to(hunter, caller.x, caller.y)
	# the calls of a step
	s.ai._fresh()
	var list: Array = s.ai._calls()
	assert(list.size() == 1 and list[0].id == caller.id, "the hunted lord calls: %s" % [list])
	var detail: Dictionary = s.ai._call_detail(list[0])
	assert(is_equal_approx(float(detail.foe), s.roster.strength_of(hunter)), "its enemy is the hunter")
	assert(float(detail.left) > 150.0 / s.roster.speed_of(hunter), "it holds out until the hunter reaches it and beyond")
	assert(detail.fx == hunter.x and detail.fy == hunter.y, "a flight knows where the nearest hunter is")
	hunter.troops[0].n = 20
	s.ai._fresh()
	assert(s.ai._call_detail(s.ai._calls()[0]).is_empty(), "chased by a weaker party, nobody calls")
	hunter.troops[0].n = 160
	s.ai._fresh()
	assert(s.ai._battles().is_empty(), "no fight goes on yet")
	# both decide: the caller runs to the helper, the helper rides to the caller, they meet before the hunter catches up
	caller.ai = 0.0
	helper.ai = 0.0
	var answered := false
	var met := false
	var ran_to_friend := false
	for i in 24 * 5:
		s.step(0.2)
		if i % 5 == 4:
			s.hour_tick()
		if helper.get("goal") == "rescue" and int(helper.gid) == caller.id:
			answered = true
		if caller.state == "flee" and not caller.path.is_empty():
			var end: Vector2 = caller.path[caller.path.size() - 1]
			ran_to_friend = ran_to_friend or end.x < spot.x
		if Vector2(caller.x - helper.x, caller.y - helper.y).length() <= 90.0 or (caller.get("fight") != null and caller.get("fight") == helper.get("fight")):
			met = true
			break
		if caller.get("fight") != null and Vector2(helper.x - caller.x, helper.y - caller.y).length() > 300.0:
			break
	assert(answered, "the helper answered the call")
	assert(ran_to_friend, "the caller ran towards the helper, not away from it")
	assert(met, "the caller and the helper met: caller %s, helper %s" % [Vector2(caller.x, caller.y), Vector2(helper.x, helper.y)])
	# a save with the goal of a helper on the way loads
	var caller2: Dictionary = s.roster.make_party("vassal", fa, "Тест в беде", spot.x, spot.y + 250.0, [{"type": troop, "n": 30}])
	var rider: Dictionary = s.roster.make_party("lord", fa, "Тест в пути", spot.x - 200.0, spot.y + 250.0, [{"type": troop, "n": 60}])
	caller2.state = "flee"
	s.roster.path_to(caller2, spot.x + 200.0, spot.y + 250.0)
	rider.goal = "rescue"
	rider.gid = caller2.id
	rider.state = "roam"
	rider.ai = 10.0  # no evaluation in the next steps: only the ride itself is checked
	s.roster.path_to(rider, caller2.x, caller2.y)
	var saved := WorldCheckpoint.capture(s)
	assert(WorldCheckpoint.valid(saved), "a world with a helper on the way saves")
	var back: RefCounted = WorldCheckpoint.restore(saved, data, ContentLoader.registry())
	assert(back != null, "and loads")
	var rider2: Dictionary = back.roster.party_by_id(rider.id)
	assert(rider2.goal == "rescue" and int(rider2.gid) == caller2.id, "the goal and its caller come back")
	# the call is over (the caller is safe inside a settlement): the ride ends
	caller2.hide = true
	caller2.ai = 10.0
	caller2.wait = 10.0  # stays inside through the step
	s.step(0.2)
	assert(rider.state == "idle" and rider.path.is_empty(), "a ride to a call that is over stops: %s" % [rider.state])

func _warring_pair(s: RefCounted) -> Array:
	for a in Rules.REAL_FACTIONS:
		for b in Rules.REAL_FACTIONS:
			if a < b and Rules.at_war(a, b, s.wars.wars):
				return [a, b]
	return []

## A point far from settlements with passable land along the line of the chase and below it, so nobody rests or defends
## right there and every route is short.
func _lonely_spot(s: RefCounted) -> Vector2:
	var best := Vector2(2600.0, 1700.0)
	var best_d := -1.0
	for gx in range(800, 4600, 100):
		for gy in range(600, 2800, 100):
			var c := Vector2(gx, gy)
			var ok := true
			for dx in range(-300, 251, 50):
				for dy in [0.0, 250.0]:
					if not s.map.paths.passable_type(s.map.paths.terr_at(c.x + dx, c.y + dy)):
						ok = false
			if not ok:
				continue
			var d := INF
			for st in s.map.settles:
				d = minf(d, c.distance_to(Vector2(st.x, st.y)))
			if d > best_d:
				best_d = d
				best = c
	return best
