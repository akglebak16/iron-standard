extends SceneTree
## Caravan escort (#315, DESIGN.md §5.7): lords and faction vassals escort the caravans of their faction when the outlaws
## it fears are felt at the caravan or ahead on its route, if they can turn the danger; a caravan that an outlaw hunts or
## that flees calls for help like a lord (#313) and runs to a strong own party in sight. The evaluator on synthetic data
## (made-up faction IDs, a hand-built threat map), then the live world: the caravans and calls of a step, an escort that
## rides to a caravan and keeps with it, a save with a lord escorting, and an escort that ends with the caravan.
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
var wars := {"blue|red": true}
var tm: ThreatMap = null
var next_id := 1

func _initialize() -> void:
	_check_evaluator()
	_check_route()
	_check_flight()
	_check_world()
	print("World escort tests passed")
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
		if a.fac == "bandit" or b.fac == "bandit" or a.fac == "undead" or b.fac == "undead":
			return true
		return a.kind != "caravan" and b.kind != "caravan" and wars.has(_key(a.fac, b.fac))
	g.at_war = func(a, b): return wars.has(_key(a, b))
	g.threat_map = func(): return tm
	g.enemies = func(f): return tm.enemies_of(f, func(a, b): return a != b and (a == "bandit" or b == "bandit" or a == "undead" or b == "undead" or wars.has(_key(a, b)))) if tm != null else []
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

static func _of(cands: Array, goal: String, gid: Variant = "any") -> Dictionary:
	for c in cands:
		if c.goal == goal and (gid is String or c.gid == gid):
			return c
	return {}

## Who escorts: lords and faction vassals of the caravan's faction, when outlaws are near it and they can turn them.
func _check_evaluator() -> void:
	_reset()
	var g := _goals()
	var home := {"id": 5000, "kind": "town", "fac": "red", "name": "town", "x": 700.0, "y": 1000.0}
	settles.append(home)
	var caravan := _party("caravan", "red", 1000.0, 1000.0, 10)
	var band := _party("bandit", "bandit", 1100.0, 1000.0, 30)
	var lord := _party("lord", "red", 1000.0, 1200.0, 200)
	_map()
	var c := _of(g.candidates(lord), "escort", caravan.id)
	assert(not c.is_empty() and c.x == caravan.x and c.y == caravan.y, "a lord escorts an own caravan with a band near it: %s" % [g.candidates(lord)])
	var near := float(c.score)
	var vassal := _party("vassal", "red", 1000.0, 800.0, 100)
	assert(not _of(g.candidates(vassal), "escort", caravan.id).is_empty(), "a faction vassal escorts as before")
	parties.erase(vassal)
	# not other factions, not in a campaign, not bands, not other caravans, not the player's retinues
	var other := _party("lord", "blue", 1000.0, 1250.0, 200)
	assert(_of(g.candidates(other), "escort").is_empty(), "a lord does not escort the caravans of another faction")
	parties.erase(other)
	assert(_of(g.candidates(lord, {"army": true}), "escort").is_empty(), "a party in a faction campaign follows its marshal")
	assert(_of(g.candidates(_party("bandit", "bandit", 1500.0, 1500.0, 30)), "escort").is_empty(), "bands do not escort")
	assert(_of(g.candidates(_party("caravan", "red", 900.0, 1100.0, 10)), "escort").is_empty(), "caravans do not escort")
	assert(_of(g.candidates(_party("cvass", "player", 1000.0, 1300.0, 80), {"mode": "patrol"}), "escort").is_empty(), "the player's retinues follow his orders")
	_reset_to(caravan, band, lord)
	_map()
	# no danger: the band is gone
	band.troops[0].n = 0
	_map()
	g.reset()
	assert(_of(g.candidates(lord), "escort").is_empty(), "a caravan without outlaws around needs no escort")
	band.troops[0].n = 30
	_map()
	g.reset()
	# hopeless: even with the caravan the lord is far weaker than what is felt there
	var dead := _party("lord", "undead", 1050.0, 1000.0, 2000)
	_map()
	g.reset()
	assert(_of(g.candidates(lord), "escort").is_empty(), "a lord does not ride to a caravan the dead swarm around")
	parties.erase(dead)
	_map()
	g.reset()
	# out of range
	lord.y = 1000.0 + Config.GOAL_ESCORT_RANGE + 20.0
	assert(_of(g.candidates(lord), "escort").is_empty(), "a caravan out of range is not escorted")
	lord.y = 1000.0 + Config.GOAL_ESCORT_RANGE - 20.0
	var far := float(_of(g.candidates(lord), "escort", caravan.id).score)
	assert(far > 0.0 and far < near, "a farther caravan is worth less: %f < %f" % [far, near])
	lord.y = 1200.0
	# own parties already escorting it
	for i in 2:
		_party("vassal", "red", 1000.0, 1050.0 + i * 10.0, 60, {"goal": "escort", "gid": caravan.id, "state": "roam"})
	g.rebuild_claims()
	assert(float(_of(g.candidates(lord), "escort", caravan.id).score) < near * 0.7, "a caravan two own parties already escort needs this one less")
	# the caravans of the step come in a list when the world gives one
	g.rebuild_claims()
	g.caravans = func(): return []
	assert(_of(g.candidates(lord), "escort").is_empty(), "escorts read the caravans of the step")
	g.caravans = func(): return [caravan]
	assert(not _of(g.candidates(lord), "escort", caravan.id).is_empty(), "a caravan in the list is escorted")
	# through own lands only: far from every own settlement the escort would end with nothing to do
	home.x = caravan.x - Config.GOAL_ESCORT_HOME - 50.0
	g.reset()
	assert(_of(g.candidates(lord), "escort").is_empty(), "a caravan out of own lands is not escorted")

func _reset_to(a: Dictionary, b: Dictionary, c: Dictionary) -> void:
	parties.clear()
	parties.append_array([a, b, c])

## The danger ahead on the route: a band on the way is felt before the caravan gets there, behind it or off the route not.
func _check_route() -> void:
	_reset()
	var g := _goals()
	settles.append({"id": 5000, "kind": "town", "fac": "red", "name": "town", "x": 700.0, "y": 1050.0})
	var caravan := _party("caravan", "red", 1050.0, 1050.0, 10)
	var band := _party("bandit", "bandit", 1450.0, 1050.0, 30)  # 400 ahead: nothing felt at the caravan itself
	var lord := _party("lord", "red", 1050.0, 1250.0, 200)
	_map()
	assert(tm.threat(caravan.x, caravan.y, ["bandit"]) == 0.0, "the band is out of the caravan's own threat radius")
	assert(_of(g.candidates(lord), "escort").is_empty(), "without a route the caravan is out of danger")
	caravan.path = [Vector2(1150.0, 1050.0), Vector2(1350.0, 1050.0), Vector2(1950.0, 1050.0)]
	caravan.pi = 0
	g.reset()
	var cd := g.caravan_danger(caravan)
	assert(float(cd.danger) > Config.GOAL_ESCORT_DANGER.x and is_equal_approx(float(cd.own), 10.0), "the band ahead is felt on the route: %s" % [cd])
	assert(not _of(g.candidates(lord), "escort", caravan.id).is_empty(), "a lord escorts a caravan whose route runs past a band")
	# the route is read from the caravan's next point on: a band behind it does not count
	band.x = 650.0
	_map()
	g.reset()
	assert(_of(g.candidates(lord), "escort").is_empty(), "a band behind the caravan, away from its route, is no danger ahead")
	# no farther than GOAL_ESCORT_AHEAD
	band.x = caravan.x + Config.GOAL_ESCORT_AHEAD + Config.THREAT_RADIUS + 100.0
	_map()
	g.reset()
	assert(float(g.caravan_danger(caravan).danger) == 0.0, "a band beyond the look ahead is not felt")
	# once per step: the danger is kept until reset
	band.x = 1450.0
	_map()
	assert(float(g.caravan_danger(caravan).danger) == 0.0, "the danger of a caravan is worked out once per step")
	g.reset()
	assert(float(g.caravan_danger(caravan).danger) > 0.0, "and again after the step")

## A fleeing caravan runs to a strong own lord in sight, not only to an own town.
func _check_flight() -> void:
	_reset()
	var g := _goals()
	var town := {"id": 5000, "kind": "town", "fac": "red", "name": "town", "x": 1600.0, "y": 1000.0}
	settles.append(town)
	var caravan := _party("caravan", "red", 1000.0, 1000.0, 10)
	var band := _party("bandit", "bandit", 880.0, 1000.0, 30)
	var lord := _party("lord", "red", 1200.0, 1000.0, 200)
	_map()
	var flee := _of(g.candidates(caravan), "flee")
	assert(not flee.is_empty() and lord in flee.friends, "a caravan flees the band and sees the own lord: %s" % [flee])
	var t := g.flee_target(caravan, Vector2(band.x, band.y), [{"id": town.id, "x": town.x, "y": town.y}], flee.friends, float(flee.foe))
	assert(t.get("pid") == lord.id, "the caravan runs to the own lord nearby, not to the far town: %s" % [t])

# ---------- live world ----------

func _check_world() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s: RefCounted = WorldState.create(5, data, "emp", ContentLoader.registry())
	s.player.away = true
	var spot := _lonely_spot(s)
	var fa := ""  # the faction of the nearest settlement: the spot lies in its lands, where its caravans are escorted
	var near_d := INF
	for st in s.map.settles:
		var dd := spot.distance_to(Vector2(st.x, st.y))
		if st.fac in Rules.REAL_FACTIONS and st.kind != "camp" and dd < near_d:
			near_d = dd
			fa = st.fac
	assert(near_d < Config.GOAL_ESCORT_HOME - 300.0, "the spot lies in own lands: %f" % near_d)
	var troop: String = s.roster.gen_troops(fa, 1, 0.5)[0].type  # one troop type everywhere: same speed, plain strengths
	s.roster.parties.clear()  # nobody else around: the caravan, the band, the lord
	var town: Dictionary = {}
	for st in s.map.settles:
		if st.kind == "town" and st.fac == fa:
			town = st
			break
	assert(not town.is_empty(), "the faction has a town")
	var caravan: Dictionary = s.roster.make_party("caravan", fa, "Тест караван", spot.x, spot.y, [{"type": troop, "n": 6}],
		{"home": town.id, "sid": town.id, "state": "travel"})
	caravan.path = [Vector2(spot.x + 100.0, spot.y), Vector2(spot.x + 250.0, spot.y)]
	caravan.pi = 0
	caravan.ai = 1000.0  # keeps its way: only the band and the lord decide here
	var band: Dictionary = s.roster.make_party("bandit", "bandit", "Тест шайка", spot.x + 150.0, spot.y + 120.0, [{"type": troop, "n": 30}])
	band.ai = 1000.0
	var lord: Dictionary = s.roster.make_party("lord", fa, "Тест лорд", spot.x - 250.0, spot.y, [{"type": troop, "n": 200}])
	# the caravans and the danger of a step
	s.ai._fresh()
	assert(s.ai._caravans() == [caravan], "the step lists the caravans: %s" % [s.ai._caravans()])
	assert(float(s.ai.goals.caravan_danger(caravan).danger) > Config.GOAL_ESCORT_DANGER.x, "the band on the way is a danger to the caravan")
	# a hunted caravan calls; its enemy is the hunter and it holds out only until the hunter is there
	band.state = "hunt"
	band.tid = caravan.id
	s.ai._fresh()
	var list: Array = s.ai._calls()
	assert(list.size() == 1 and list[0].id == caravan.id, "the hunted caravan calls: %s" % [list])
	var detail: Dictionary = s.ai._call_detail(list[0])
	assert(is_equal_approx(float(detail.foe), s.roster.strength_of(band)), "its enemy is the hunter")
	var reach: float = Vector2(band.x - caravan.x, band.y - caravan.y).length() / s.roster.speed_of(band)
	assert(is_equal_approx(float(detail.left), reach), "a caravan is settled at once: it holds out until the hunter is there (%f, %f)" % [detail.left, reach])
	# a fleeing caravan without hunters fears only the outlaws: a lord of a state at war nearby is no enemy of it
	band.state = "idle"
	band.tid = null
	caravan.state = "flee"
	s.ai._fresh()
	var flight: Dictionary = s.ai._call_detail(s.ai._calls()[0])
	assert(not flight.is_empty() and float(flight.foe) > 0.0, "the fleeing caravan calls against the band felt around it")
	var enemy_lord: Dictionary = s.roster.make_party("lord", _enemy_of(s, fa), "Тест враг", spot.x + 60.0, spot.y - 60.0, [{"type": troop, "n": 500}])
	s._threat_step += 1  # a new step for the threat map: it is built again with the enemy lord on it
	s.ai._fresh()
	assert(s.threat_map().influence(String(enemy_lord.fac), enemy_lord.x, enemy_lord.y) > 0.0, "the enemy lord is on the map")
	assert(is_equal_approx(float(s.ai._call_detail(s.ai._calls()[0]).foe), float(flight.foe)), "lords of states at war leave caravans alone: not counted")
	s.roster.remove(enemy_lord)
	# the lord escorts the caravan, which stands with the band near it: rides to it and keeps with it. The lord decides once
	# (it would hunt the band once it sees it); after that only the escort itself is checked.
	caravan.state = "idle"
	caravan.path = []
	lord.ai = 0.0
	var escorted := false
	var close := false
	for i in 5 * 48:  # up to two days
		s.step(0.2)
		if i % 5 == 4:
			s.hour_tick()
		if lord.get("goal") == "escort" and lord.gid == caravan.id and not escorted:
			escorted = true
			lord.ai = 1000.0
		if escorted and Vector2(lord.x - caravan.x, lord.y - caravan.y).length() <= 60.0:
			close = true
			break
		if not caravan in s.roster.parties:
			break
	assert(escorted, "the lord took the escort of the caravan: goal %s" % [lord.get("goal")])
	assert(close, "the lord reached the caravan: lord %s, caravan %s" % [Vector2(lord.x, lord.y), Vector2(caravan.x, caravan.y)])
	# the band goes for the caravan: the escort rides at the band, so the band meets it before the caravan (a caravan's own
	# fight is settled at once and without its escort)
	band.state = "hunt"
	band.tid = caravan.id
	band.goal = "hunt"
	band.gid = caravan.id
	lord.rp = 0.0
	s.step(0.2)
	assert(not lord.path.is_empty(), "the escort rides out")
	var end: Vector2 = lord.path[lord.path.size() - 1]
	assert(end.distance_to(Vector2(band.x, band.y)) < end.distance_to(Vector2(caravan.x, caravan.y)), "the escort rides at the hunting band: %s, band %s" % [end, Vector2(band.x, band.y)])
	band.state = "idle"
	band.tid = null
	band.goal = ""
	band.gid = null
	# a save with a lord escorting loads
	var saved := WorldCheckpoint.capture(s)
	assert(WorldCheckpoint.valid(saved), "a world with a lord escorting saves")
	var back: RefCounted = WorldCheckpoint.restore(saved, data, ContentLoader.registry())
	assert(back != null, "and loads")
	var lord2: Dictionary = back.roster.party_by_id(lord.id)
	assert(lord2.goal == "escort" and int(lord2.gid) == caravan.id, "the goal and its caravan come back")
	# the caravan is gone: the escort ends
	s.roster.remove(caravan)
	lord.ai = 10.0  # no evaluation in the next step: only the escort itself is checked
	lord.state = "roam"
	lord.path = [Vector2(lord.x + 50.0, lord.y)]
	lord.pi = 0
	s.step(0.2)
	assert(lord.state == "idle" and lord.path.is_empty(), "an escort of a caravan that is gone stops: %s %s %s %s %s" % [lord.state, lord.get("goal"), lord.get("fight"), lord.hide, lord.ai])

func _enemy_of(s: RefCounted, fa: String) -> String:
	for b in Rules.REAL_FACTIONS:
		if b != fa and Rules.at_war(fa, b, s.wars.wars):
			return b
	for b in Rules.REAL_FACTIONS:
		if b != fa:
			return b
	return fa

## A point far from settlements with passable land around it, so nobody rests or defends right there and every route is short.
func _lonely_spot(s: RefCounted) -> Vector2:
	var best := Vector2(2600.0, 1700.0)
	var best_d := -1.0
	for gx in range(800, 4600, 100):
		for gy in range(600, 2800, 100):
			var c := Vector2(gx, gy)
			var ok := true
			for dx in range(-300, 301, 50):
				for dy in [-60.0, 0.0, 120.0]:
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
