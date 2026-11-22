extends SceneTree
## Help in battle (#312, DESIGN.md §5.7.3): a lord or vassal goes to a running fight of its faction that it sees, can
## turn and can reach in time. The evaluator on synthetic data (made-up faction IDs, a hand-built list of fights), then
## the live world: the summary of fights, a helper that rides there and is taken in by hour_tick, a ride that ends with
## the fight, and a save with the new goal.
const Goals = preload("res://core/campaign/world/party_goals.gd")
const Config = preload("res://core/campaign/config.gd")
const WorldSkirmish = preload("res://core/campaign/world/world_skirmish.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldCheckpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

var parties: Array = []
var fights: Array = []
var wars := {"blue|red": true, "green|red": true}
var next_id := 1

func _initialize() -> void:
	_check_hours_left()
	_check_evaluator()
	_check_choice()
	_check_world()
	print("World assist tests passed")
	quit(0)

# ---------- synthetic ----------

func _goals() -> Goals:
	var g := Goals.new()
	g.parties = parties
	g.settles = []
	g.strength = func(p): return float(p.troops.reduce(func(a, t): return a + int(t.n), 0))
	g.speed = func(p): return float(p.get("spd", 20.0))
	g.hostile = func(a, b):
		if a.fac == b.fac:
			return false
		if a.fac == "bandit" or b.fac == "bandit":
			return true
		return a.kind != "caravan" and b.kind != "caravan" and wars.has(_key(a.fac, b.fac))
	g.at_war = func(a, b): return wars.has(_key(a, b))
	g.battles = func(): return fights
	return g

static func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _reset() -> void:
	parties.clear()
	fights.clear()
	next_id = 1

func _party(kind: String, fac: String, x: float, y: float, n: int, extra := {}) -> Dictionary:
	var p := {"id": next_id, "kind": kind, "fac": fac, "name": kind, "x": x, "y": y, "troops": [{"type": "t", "n": n}],
		"hide": false, "path": [], "pi": 0, "state": "idle", "wait": 0.0, "goal": "", "gid": null, "ga": 0.0, "gs": 0.0}
	p.merge(extra, true)
	next_id += 1
	parties.append(p)
	return p

## A fight of the given sides, as WorldSkirmish.battles describes it.
func _fight(id: int, x: float, y: float, a: Array, b: Array, left := 20.0) -> Dictionary:
	var sa := 0.0
	var sb := 0.0
	for p in a:
		sa += float(p.troops[0].n)
		p.fight = id
	for p in b:
		sb += float(p.troops[0].n)
		p.fight = id
	var f := {"id": id, "x": x, "y": y, "sides": [a, b], "strength": [sa, sb], "left": left}
	fights.append(f)
	return f

static func _of(cands: Array, goal: String, gid: Variant = "any") -> Dictionary:
	for c in cands:
		if c.goal == goal and (gid is String or c.gid == gid):
			return c
	return {}

func _check_hours_left() -> void:
	var even := WorldSkirmish.hours_left(100, 100.0, 1.0)
	assert(is_equal_approx(even, log(0.25) / log(1.0 - WorldSkirmish.LOSS)), "an even fight lasts until a side falls to a quarter: %f" % even)
	assert(WorldSkirmish.hours_left(100, 100.0, 3.0) < even, "a side facing a stronger enemy breaks sooner")
	assert(WorldSkirmish.hours_left(30, 100.0, 1.0) < even and WorldSkirmish.hours_left(25, 100.0, 1.0) == 0.0, "a side at its quarter is done")
	assert(WorldSkirmish.hours_left(0, 0.0, 1.0) == 0.0, "an empty side is done")

func _check_evaluator() -> void:
	_reset()
	var g := _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 60)
	var friend := _party("lord", "red", 1250.0, 1000.0, 80)
	var foe := _party("lord", "blue", 1255.0, 1000.0, 100)
	var f := _fight(7, 1252.0, 1000.0, [friend], [foe])
	var c := _of(g.candidates(me), "assist", 7)
	assert(not c.is_empty() and c.x == f.x and c.y == f.y, "a lord helps its faction's fight it sees: %s" % [g.candidates(me)])
	# the side needs the help more when its enemy is stronger
	var needy := float(c.score)
	foe.troops[0].n = 50
	f.strength = [80.0, 50.0]
	var winning := float(_of(g.candidates(me), "assist", 7).score)
	assert(winning > 0.0 and winning < needy, "a side that wins anyway needs help less: %f < %f" % [winning, needy])
	# not within its strength: the side with it is still far weaker
	foe.troops[0].n = 400
	f.strength = [80.0, 400.0]
	assert(_of(g.candidates(me), "assist").is_empty(), "a hopeless fight is not joined")
	foe.troops[0].n = 100
	f.strength = [80.0, 100.0]
	# distance and time
	var near := float(_of(g.candidates(me), "assist", 7).score)
	me.x = 1252.0 - Config.GOAL_ASSIST_RANGE + 20.0
	var far := float(_of(g.candidates(me), "assist", 7).score)
	assert(far > 0.0 and far < near, "a farther fight is worth less: %f < %f" % [far, near])
	me.x = 1252.0 - Config.GOAL_ASSIST_RANGE - 20.0
	assert(_of(g.candidates(me), "assist").is_empty(), "a fight out of sight is unknown")
	me.x = 1000.0
	f.left = 3.0  # 252 on the way at 20 an hour: 12.6 h, the fight ends in 3
	assert(_of(g.candidates(me), "assist").is_empty(), "a fight that ends before the party gets there is not worth the ride")
	f.left = 20.0
	# only its own faction's fights (the enemy of my enemy is part 3), only on the side it would join
	friend.fac = "green"
	assert(_of(g.candidates(me), "assist").is_empty(), "a fight without its faction is left to others")
	friend.fac = "red"
	var both := _party("lord", "red", 1240.0, 1000.0, 20)
	var bandit := _party("bandit", "bandit", 1260.0, 1000.0, 20)
	f.sides = [[friend, both], [foe, bandit]]
	assert(not _of(g.candidates(me), "assist", 7).is_empty(), "outlaws on the enemy side do not change the side")
	f.sides = [[friend, bandit], [foe]]
	assert(g.side_for(me, f.sides, "red") == -1, "a side with its enemy in it is not its side")
	assert(_of(g.candidates(me), "assist").is_empty())
	f.sides = [[friend], [foe]]
	parties.erase(both)
	parties.erase(bandit)
	# who helps: lords and faction vassals; not campaign armies, caravans, bandits or the player's retinues
	assert(_of(g.candidates(me, {"army": true}), "assist").is_empty(), "a party in a faction campaign follows its marshal")
	var vassal := _party("vassal", "red", 1000.0, 1020.0, 60)
	assert(not _of(g.candidates(vassal), "assist", 7).is_empty(), "a faction vassal helps too")
	var caravan := _party("caravan", "red", 1000.0, 1040.0, 60)
	assert(_of(g.candidates(caravan), "assist").is_empty(), "a caravan never rides to a fight")
	var band := _party("bandit", "bandit", 1000.0, 1060.0, 60)
	var bfriend := _party("bandit", "bandit", 1500.0, 1300.0, 40)
	var bfoe := _party("lord", "red", 1505.0, 1300.0, 50)
	_fight(8, 1502.0, 1300.0, [bfriend], [bfoe])
	assert(_of(g.candidates(band), "assist").is_empty(), "bands help each other only from part 6 on")
	var cvass := _party("cvass", "player", 1000.0, 1080.0, 60)
	assert(_of(g.candidates(cvass, {"mode": "patrol"}), "assist").is_empty(), "the player's retinues follow his orders")
	# own parties already on the way make it less attractive
	var alone := float(_of(g.candidates(me), "assist", 7).score)
	for i in 2:
		_party("lord", "red", 900.0, 900.0 + i * 10.0, 60, {"goal": "assist", "gid": 7, "state": "roam"})
	g.rebuild_claims()
	assert(float(_of(g.candidates(me), "assist", 7).score) < alone * 0.7, "a fight two own parties already ride to needs this one less")

## Help in battle reacts like hunting: it may break a plan before its hold time is over (with the margin).
func _check_choice() -> void:
	_reset()
	var g := _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 120, {"goal": "patrol", "gid": 5000, "ga": 0.5, "path": [Vector2(900, 900)], "pi": 0, "state": "roam"})
	var friend := _party("lord", "red", 1100.0, 1000.0, 60)
	var foe := _party("lord", "blue", 1105.0, 1000.0, 100)
	_fight(9, 1102.0, 1000.0, [friend], [foe])
	var cands: Array = g.candidates(me)
	cands.append({"goal": "patrol", "gid": 5000, "x": 900.0, "y": 900.0, "score": 0.2})
	cands.sort_custom(func(a, b): return a.score > b.score)
	assert(cands[0].goal == "assist", "a close fight of its own side outweighs a quiet patrol: %s" % [cands])
	var pick: Dictionary = g.choose(me, cands, RandomNumberGenerator.new())
	assert(pick.get("goal") == "assist", "a held patrol gives way to help in battle: %s" % [pick])

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
	var troop_a: String = s.roster.gen_troops(fa, 1, 0.5)[0].type
	var troop_b := troop_a  # one troop type on both sides: an even fight, whatever the factions field
	var spot := _lonely_spot(s)
	s.roster.parties.clear()  # nobody else around: the fight, the helper, nothing more
	var a: Dictionary = s.roster.make_party("lord", fa, "Тест А", spot.x, spot.y, [{"type": troop_a, "n": 80}])
	var b: Dictionary = s.roster.make_party("lord", fb, "Тест Б", spot.x + 5.0, spot.y, [{"type": troop_b, "n": 80}])
	s.skirmish.contact(a, b, s.ai.auto_fight)
	var sk: Dictionary = s.skirmish.fight_of(a)
	assert(not sk.is_empty(), "two lords fight for hours")
	var helper: Dictionary = s.roster.make_party("lord", fa, "Тест помощник", spot.x - 220.0, spot.y, [{"type": troop_a, "n": 60}])
	helper.ai = 0.0
	# the summary the evaluator reads
	var list: Array = s.skirmish.battles()
	assert(list.size() == 1 and list[0].id == sk.id and list[0].sides[0] == [a] and list[0].sides[1] == [b], "battles lists the fight with its sides: %s" % [list])
	assert(list[0].left > 10.0 and list[0].strength[0] > 0.0, "an even fight of 80 against 80 has hours left")
	assert(s.skirmish.has_fight(sk.id) and not s.skirmish.has_fight(sk.id + 100))
	# the helper rides there and hour_tick takes it in
	var rode := false
	for i in 24 * 5:
		s.step(0.2)
		if i % 5 == 4:
			s.hour_tick()
		if helper.get("goal") == "assist" and helper.state == "roam":
			rode = true
		if helper.get("fight") != null or not s.skirmish.has_fight(sk.id):
			break
	assert(rode, "the helper took the goal and rode to the fight")
	assert(helper.get("fight") == sk.id, "close to the fight, hour_tick took the helper in on its side: %s" % [helper])
	assert(helper.id in sk.A, "the helper joined its own side")
	# a save with the goal of a helper on the way loads
	var wait_spot := Vector2(spot.x + 300.0, spot.y + 200.0)
	var c: Dictionary = s.roster.make_party("lord", fb, "Тест В", wait_spot.x, wait_spot.y, [{"type": troop_b, "n": 80}])
	var d: Dictionary = s.roster.make_party("lord", fa, "Тест Г", wait_spot.x + 5.0, wait_spot.y, [{"type": troop_a, "n": 80}])
	s.skirmish.contact(c, d, s.ai.auto_fight)
	var sk2: Dictionary = s.skirmish.fight_of(c)
	var rider: Dictionary = s.roster.make_party("lord", fa, "Тест в пути", wait_spot.x - 200.0, wait_spot.y, [{"type": troop_a, "n": 60}])
	rider.goal = "assist"
	rider.gid = sk2.id
	rider.state = "roam"
	rider.ai = 10.0  # no evaluation in the next step: only the ride itself is checked
	s.roster.path_to(rider, wait_spot.x, wait_spot.y)
	var saved := WorldCheckpoint.capture(s)
	assert(WorldCheckpoint.valid(saved), "a world with a helper on the way saves")
	var back: RefCounted = WorldCheckpoint.restore(saved, data, ContentLoader.registry())
	assert(back != null, "and loads")
	var rider2: Dictionary = back.roster.party_by_id(rider.id)
	assert(rider2.goal == "assist" and int(rider2.gid) == sk2.id and back.skirmish.has_fight(sk2.id), "the goal and its fight come back")
	# the fight is over before the rider gets there: the ride ends
	s.skirmish.fights.erase(sk2)
	c.fight = null
	d.fight = null
	s.step(0.2)
	assert(rider.state == "idle" and rider.path.is_empty(), "a ride to a fight that is over stops: %s" % [rider.state])

func _warring_pair(s: RefCounted) -> Array:
	for a in Rules.REAL_FACTIONS:
		for b in Rules.REAL_FACTIONS:
			if a < b and Rules.at_war(a, b, s.wars.wars):
				return [a, b]
	return []

## A passable point far from settlements, so nobody rests or defends right there.
func _lonely_spot(s: RefCounted) -> Vector2:
	var best := Vector2(2600.0, 1700.0)
	var best_d := -1.0
	for gx in range(800, 4600, 100):
		for gy in range(600, 2900, 100):
			var c := Vector2(gx, gy)
			if not s.map.paths.passable_type(s.map.paths.terr_at(c.x, c.y)):
				continue
			if not s.map.paths.passable_type(s.map.paths.terr_at(c.x - 220.0, c.y)) or not s.map.paths.passable_type(s.map.paths.terr_at(c.x + 300.0, c.y + 200.0)):
				continue
			var d := INF
			for st in s.map.settles:
				d = minf(d, c.distance_to(Vector2(st.x, st.y)))
			if d > best_d:
				best_d = d
				best = c
	return best
