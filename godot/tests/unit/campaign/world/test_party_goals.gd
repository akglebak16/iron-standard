extends SceneTree
## Goals of map parties (party_goals.gd, DESIGN.md §5.2, ADR-023) on synthetic data: made-up faction IDs, an empty
## world, mixed kinds of parties, a hand-built threat map. No world, catalog or RNG of the game is involved.
## States are "red", "blue", "green", "violet", "black"; only the outlaws keep their ID (Config.BANDIT_FACTION): the map
## treats the factions that fight everyone by that ID (ThreatMap.factions_hostile).
const Goals = preload("res://core/campaign/world/party_goals.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Config = preload("res://core/campaign/config.gd")

var parties: Array = []
var settles: Array = []
var wars := {"blue|red": true}
var tm: ThreatMap = null
var next_id := 1

func _initialize() -> void:
	_check_curves()
	_check_empty()
	_check_hunt_and_flee()
	_check_crowd_and_speed()
	_check_hysteresis()
	_check_kinds()
	_check_modifiers()
	_check_risk_and_visibility()
	_check_plans()
	_check_flee_target()
	print("Party goals tests passed")
	quit(0)

func _goals() -> Variant:
	var g := Goals.new()
	g.parties = parties
	g.settles = settles
	g.strength = func(p): return float(p.troops.reduce(func(a, t): return a + int(t.n), 0)) * float(p.get("pw", 1.0))
	g.speed = func(p): return float(p.get("spd", 17.0))
	g.hostile = func(a, b):
		if a.fac == b.fac:
			return false
		if a.fac == "bandit" or b.fac == "bandit":
			return true
		return a.kind != "caravan" and b.kind != "caravan" and wars.has(_key(a.fac, b.fac))
	g.at_war = func(a, b): return wars.has(_key(a, b))
	g.threat_map = func(): return tm
	g.enemies = func(f): return tm.enemies_of(f, func(a, b): return a != b and (a == "bandit" or b == "bandit" or wars.has(_key(a, b)))) if tm != null else []
	return g

static func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func _reset() -> void:
	parties.clear()
	settles.clear()
	tm = null
	next_id = 1

func _party(kind: String, fac: String, x: float, y: float, n: int, extra := {}) -> Dictionary:
	var p := {"id": next_id, "kind": kind, "fac": fac, "name": kind, "x": x, "y": y, "troops": [{"type": "t", "n": n}],
		"hide": false, "path": [], "pi": 0, "state": "idle", "wait": 0.0, "goal": "", "gid": null, "ga": 0.0, "gs": 0.0}
	p.merge(extra, true)
	next_id += 1
	parties.append(p)
	return p

func _settle(kind: String, fac: String, x: float, y: float, extra := {}) -> Dictionary:
	var s := {"id": 5000 + settles.size(), "kind": kind, "fac": fac, "name": kind, "x": x, "y": y}
	s.merge(extra, true)
	settles.append(s)
	return s

func _map() -> void:
	tm = ThreatMap.new()
	var list: Array = []
	for p in parties:
		list.append({"fac": p.fac, "x": p.x, "y": p.y, "strength": float(p.troops[0].n) * float(p.get("pw", 1.0))})
	tm.rebuild(list)

func _best(cands: Array) -> Dictionary:
	return cands[0] if not cands.is_empty() else {}

func _of(cands: Array, goal: String, gid: Variant = "any") -> Dictionary:
	for c in cands:
		if c.goal == goal and (gid is String or c.gid == gid):
			return c
	return {}

func _check_curves() -> void:
	assert(Goals.ramp(0.0, 1.0, 2.0) == 0.0 and Goals.ramp(3.0, 1.0, 2.0) == 1.0 and is_equal_approx(Goals.ramp(1.5, 1.0, 2.0), 0.5))
	assert(is_equal_approx(Goals.ramp(0.5, 0.0, 1.0, 1.0, 0.0), 0.5), "a falling ramp")
	assert(Goals.combine([]) == 1.0 and Goals.combine([0.5]) == 0.5 and Goals.combine([0.0, 1.0]) == 0.0)
	var two := Goals.combine([0.8, 0.8])
	assert(two > 0.64 and two < 0.8, "compensation lifts a product of factors, but not above them: %f" % two)
	assert(Goals.combine([0.8, 0.8, 0.8]) > 0.8 * 0.8 * 0.8, "more factors, more compensation")
	assert(Goals.combine([0.8, 0.8, 0.5]) < two, "every factor well below 1 still lowers the score")
	assert(Goals.distance_factor(0.0, 100.0) == 1.0 and is_equal_approx(Goals.distance_factor(100.0, 100.0), 1.0 - Config.GOAL_DISTANCE_FALLOFF))

## No parties, no settlements, no threat map: nothing to do, and nothing breaks.
func _check_empty() -> void:
	_reset()
	var g = _goals()
	var lone := _party("lord", "red", 1000.0, 1000.0, 100)
	var cands = g.candidates(lone)
	assert(cands.is_empty(), "an empty world offers no goals: %s" % [cands])
	assert(g.choose(lone, cands, RandomNumberGenerator.new()).is_empty())
	assert(g.risk_at(lone, 1000.0, 1000.0, 100.0) == 0.0, "no threat map: no risk")
	var t = g.flee_target(lone, Vector2(900.0, 1000.0), [])
	assert(t.x > lone.x and t.sid == null, "with no haven and no map the party runs straight away")

func _check_hunt_and_flee() -> void:
	_reset()
	var g = _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 100)
	var weak := _party("lord", "blue", 1150.0, 1000.0, 40)
	_party("lord", "green", 1050.0, 1000.0, 10)  # at peace with red: not prey
	var cands = g.candidates(me)
	assert(_best(cands).goal == "hunt" and _best(cands).gid == weak.id, "a weaker enemy in sight is hunted: %s" % [cands])
	assert(_of(cands, "hunt", 3).is_empty(), "a faction at peace is left alone")
	weak.x = 1000.0 + Config.GOAL_SIGHT_RADIUS + 10.0
	assert(_of(g.candidates(me), "hunt").is_empty(), "out of sight is out of mind")
	weak.x = 1150.0
	weak.troops[0].n = 80  # ratio 0.8 > lord hunt_ratio 0.75
	assert(_of(g.candidates(me), "hunt").is_empty(), "a target near our strength is not hunted")
	var strong := _party("lord", "blue", 1100.0, 1000.0, 200)
	cands = g.candidates(me)
	assert(_best(cands).goal == "flee", "a much stronger enemy close by makes the party flee: %s" % [cands])
	strong.troops[0].n = 110
	assert(_of(g.candidates(me), "flee").is_empty(), "an enemy just a little stronger is no reason to run")
	strong.troops[0].n = 300
	var army = g.candidates(me, {"army": true})
	assert(_of(army, "flee").is_empty(), "a party in a faction campaign does not flee")
	weak.troops[0].n = 40
	weak.x = 1000.0 + Config.GOAL_ARMY_HUNT_RADIUS + 20.0
	assert(_of(army, "hunt").is_empty() and _of(g.candidates(me, {"army": true}), "hunt").is_empty(), "an army only attacks enemies close by")

func _check_crowd_and_speed() -> void:
	_reset()
	var g = _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 100)
	var prey := _party("bandit", "blue", 1100.0, 1000.0, 20)
	var free = g.candidates(me)
	var alone := float(_of(free, "hunt", prey.id).score)
	for i in 2:
		_party("lord", "red", 900.0, 900.0 + i * 10.0, 100, {"goal": "hunt", "gid": prey.id, "state": "hunt"})
	g.rebuild_claims()
	var crowded := float(_of(g.candidates(me), "hunt", prey.id).score)
	assert(crowded < alone * 0.7, "a target two allies already chase is less attractive: %f < %f" % [crowded, alone])
	var mine = g.goal_key(me)
	me.goal = "hunt"
	me.gid = prey.id
	g.note(mine, me)
	assert(int(g.claims[Goals._claim_key("hunt", prey.id, "red")]) == 3, "the party's own claim is counted once")
	assert(is_equal_approx(float(_of(g.candidates(me), "hunt", prey.id).score), crowded), "a party is not crowded out by itself")
	_reset()
	g = _goals()
	me = _party("lord", "red", 1000.0, 1000.0, 100)
	var slow := _party("lord", "blue", 1100.0, 1000.0, 30)
	var fast := _party("lord", "blue", 1100.0, 1010.0, 30, {"spd": 22.0})
	var cands = g.candidates(me)
	assert(float(_of(cands, "hunt", fast.id).score) < float(_of(cands, "hunt", slow.id).score), "a faster target is worth less")
	me.goal = "hunt"
	me.gid = fast.id
	me.state = "hunt"
	me.ga = Config.GOAL_FASTER_CHASE_HOURS + 0.5
	assert(_of(g.candidates(me), "hunt", fast.id).is_empty(), "a faster target is not chased for long")
	me.gid = slow.id
	assert(not _of(g.candidates(me), "hunt", slow.id).is_empty(), "a slower one is chased as long as it is in sight")

func _check_hysteresis() -> void:
	_reset()
	var g = _goals()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var me := _party("vassal", "red", 1000.0, 1000.0, 100, {"goal": "patrol", "gid": 7, "ga": 0.5, "state": "roam", "path": [Vector2(1100, 1000)]})
	var cur := {"goal": "patrol", "gid": 7, "x": 0.0, "y": 0.0, "score": 0.30}
	var better := {"goal": "rest", "gid": 8, "x": 0.0, "y": 0.0, "score": 0.36}
	var much := {"goal": "rest", "gid": 8, "x": 0.0, "y": 0.0, "score": 0.60}
	assert(g.current_score(me, [better, cur]) == 0.30)
	assert(g.choose(me, [much, cur], rng).is_empty(), "a new goal is held for its minimal time")
	me.ga = Config.GOAL_HOLD_HOURS + 0.1
	assert(g.choose(me, [better, cur], rng).is_empty(), "only a clearly better goal replaces the current one")
	assert(g.choose(me, [much, cur], rng).goal == "rest", "a much better goal wins after the hold")
	me.ga = 0.5
	var hunt := {"goal": "hunt", "gid": 9, "x": 0.0, "y": 0.0, "score": 0.5}
	assert(g.choose(me, [hunt, cur], rng).goal == "hunt", "a reactive goal interrupts a plan before the hold is over")
	var urgent := {"goal": "rest", "gid": 8, "x": 0.0, "y": 0.0, "score": Config.GOAL_URGENT_SCORE}
	assert(g.choose(me, [urgent, cur], rng).goal == "rest", "an urgent plan ignores the hold")
	assert(g.choose(me, [cur], rng).is_empty(), "the current goal is not re-taken")
	me.path = []
	me.wait = 0.0
	assert(g.current_score(me, [cur]) < 0.0, "a finished goal is no longer current")
	assert(g.choose(me, [cur], rng).goal == "patrol", "a finished goal may be taken again")
	me.state = "hunt"
	me.path = [Vector2(1100, 1000)]
	assert(not Goals.goal_active(me), "another system sent the party hunting: the plan is off")
	var a := {"goal": "patrol", "gid": 1, "x": 0.0, "y": 0.0, "score": 0.50}
	var b := {"goal": "patrol", "gid": 2, "x": 0.0, "y": 0.0, "score": 0.48}
	var c := {"goal": "patrol", "gid": 3, "x": 0.0, "y": 0.0, "score": 0.10}
	var picked := {}
	for i in 60:
		picked[g.choose({"goal": ""}, [a, b, c], rng).gid] = true
	assert(picked.has(1) and picked.has(2) and not picked.has(3), "a draw among near-best goals only: %s" % [picked])

func _check_kinds() -> void:
	_reset()
	var g = _goals()
	_settle("town", "red", 1300.0, 1000.0)
	_settle("village", "blue", 1100.0, 1300.0)
	var bandit := _party("bandit", "bandit", 1000.0, 1000.0, 30, {"home": 77})
	var caravan := _party("caravan", "red", 1010.0, 1000.0, 10)
	var dead := _party("dead", "black", 990.0, 1000.0, 10)
	var odd := _party("wanderer", "violet", 980.0, 1000.0, 10)
	var lord := _party("lord", "blue", 1000.0, 1400.0, 400)
	_map()
	var cb = g.candidates(bandit)
	assert(not _of(cb, "roam").is_empty() and _of(cb, "rest").is_empty() and _of(cb, "raid").is_empty(), "bandits roam, they do not rest or raid: %s" % [cb])
	assert(not _of(cb, "hunt", caravan.id).is_empty(), "bandits hunt a weak caravan")
	var cc = g.candidates(caravan)
	assert(_of(cc, "hunt").is_empty(), "caravans do not hunt")
	assert(not _of(cc, "flee").is_empty(), "a caravan flees from bandits")
	bandit.x = 3000.0
	lord.y = 1060.0
	_map()
	assert(_of(g.candidates(caravan), "flee").is_empty(), "lords of a state at war leave caravans alone: no flight from the lord nearby")
	lord.fac = "bandit"
	lord.y = 1060.0
	_map()
	assert(_of(g.candidates(dead), "flee").is_empty(), "the dead never flee")
	assert(not _of(g.candidates(odd), "flee").is_empty(), "an unknown kind of party gets the default profile")
	lord.fac = "blue"
	# the player's retinue: orders are weight sets over the same goals
	_reset()
	g = _goals()
	var fief := _settle("castle", "player", 1000.0, 1000.0)
	var ret := _party("cvass", "player", 1000.0, 1100.0, 50)
	var far := _party("bandit", "bandit", 1000.0, 1240.0, 10)  # 140 from the retinue, 240 from the fief
	var near := _party("bandit", "bandit", 1000.0, 1150.0, 10, {"fight": 3})
	var guard = g.candidates(ret, {"mode": "guard", "fief": fief})
	assert(_of(guard, "hunt", far.id).is_empty(), "guarding: a target beyond the leash of the fief is ignored")
	assert(_of(guard, "hunt", near.id).is_empty(), "retinues leave parties already in a fight alone")
	assert(not _of(guard, "guard", fief.id).is_empty() and _of(guard, "patrol").is_empty() and _of(guard, "follow").is_empty())
	var patrol = g.candidates(ret, {"mode": "patrol", "fief": fief})
	assert(not _of(patrol, "hunt", far.id).is_empty() and not _of(patrol, "patrol", fief.id).is_empty(), "patrol hunts farther and rides around")
	var follow = g.candidates(ret, {"mode": "follow", "fief": fief, "lead": {"id": -1, "x": 1400.0, "y": 1000.0}, "keep": 70.0})
	assert(not _of(follow, "follow", -1).is_empty() and _of(follow, "guard").is_empty(), "follow mode follows the player")
	assert(Goals.profile({"kind": "cvass"}, "nonsense") == Config.GOAL_RETINUE_MODES.guard, "an unknown order guards")

func _check_modifiers() -> void:
	_reset()
	var g = _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 100)
	var prey := _party("lord", "blue", 1100.0, 1000.0, 30)
	_party("lord", "blue", 1110.0, 1100.0, 60)  # guards of the prey: risk at the target
	_map()
	var plain := float(_of(g.candidates(me), "hunt", prey.id).score)
	g.modifiers = func(_p): return {"hunt": 0.0}
	assert(_of(g.candidates(me), "hunt").is_empty(), "stage 3 hook: a weight multiplier of 0 removes the goal")
	g.modifiers = func(_p): return {"risk": 3.0}
	var careful := float(_of(g.candidates(me), "hunt", prey.id).score)
	g.modifiers = func(_p): return {"risk": 0.0}
	var bold := float(_of(g.candidates(me), "hunt", prey.id).score)
	assert(careful < plain and plain < bold, "the risk exponent makes a lord careful or bold: %f %f %f" % [careful, plain, bold])

func _check_risk_and_visibility() -> void:
	_reset()
	var g = _goals()
	var me := _party("lord", "red", 1000.0, 1000.0, 100)
	var lone := _party("lord", "blue", 1150.0, 1000.0, 30)
	var guarded := _party("lord", "blue", 850.0, 1000.0, 30)
	_party("lord", "blue", 800.0, 1060.0, 70)
	_map()
	var cands = g.candidates(me)
	assert(float(_of(cands, "hunt", lone.id).score) > float(_of(cands, "hunt", guarded.id).score), "prey near its friends is riskier")
	assert(g.risk_at(me, 800.0, 1000.0, 100.0) > 0.5 and g.risk_at(me, 3000.0, 3000.0, 100.0) == 0.0)
	assert(g.foreign_risk(me, 1000.0 + Config.GOAL_SCOUT_RADIUS + 50.0, 1000.0, 100.0) == Config.GOAL_UNKNOWN_RISK, "beyond scouting range the risk is assumed, not seen")

func _check_plans() -> void:
	_reset()
	var g = _goals()
	var quiet := _settle("village", "red", 1200.0, 1000.0)
	var alarmed := _settle("village", "red", 800.0, 1000.0, {"alarm": Config.GOAL_ALARM_HOURS})
	var town := _settle("town", "red", 1000.0, 1300.0)
	var besieged := _settle("castle", "red", 1000.0, 700.0, {"siege": {"f": "blue"}})
	var enemy := _settle("village", "blue", 1400.0, 1000.0)
	var peace := _settle("village", "green", 1000.0, 1450.0)
	var me := _party("lord", "red", 1000.0, 1000.0, 330)
	_map()
	var cands = g.candidates(me)
	assert(float(_of(cands, "patrol", alarmed.id).score) > float(_of(cands, "patrol", quiet.id).score), "patrols go where enemies were seen lately")
	assert(not _of(cands, "defend", besieged.id).is_empty() and _of(cands, "defend", quiet.id).is_empty(), "a besieged own settlement is defended")
	assert(not _of(cands, "raid", enemy.id).is_empty() and _of(cands, "raid", peace.id).is_empty(), "raids only on factions at war")
	enemy.burnt = 10
	assert(_of(g.candidates(me), "raid", enemy.id).is_empty(), "a burnt village is not raided again")
	assert(not _of(cands, "rest", town.id).is_empty())
	var full := float(_of(cands, "rest", town.id).score)
	me.troops[0].n = 120
	var hurt := float(_of(g.candidates(me), "rest", town.id).score)
	assert(hurt > full, "a beaten army wants rest more: %f > %f" % [hurt, full])
	assert(_of(g.candidates(me), "raid").is_empty(), "a beaten army does not raid")
	var caravan := _party("caravan", "red", 1100.0, 1100.0, 10)
	_party("bandit", "bandit", 1130.0, 1100.0, 20)
	_map()
	var vassal := _party("vassal", "red", 1000.0, 1050.0, 100)
	var cv = g.candidates(vassal, {"lead": {"id": me.id, "x": me.x, "y": me.y}})
	assert(not _of(cv, "escort", caravan.id).is_empty(), "a vassal escorts an own caravan in danger")
	assert(_of(cv, "rest", town.id).is_empty(), "vassals stand by villages and castles, not towns")
	assert(not _of(cv, "follow", me.id).is_empty())
	assert(_of(g.candidates(me), "escort").is_empty(), "lords do not escort")

func _check_flee_target() -> void:
	_reset()
	var g = _goals()
	var behind := _settle("town", "red", 750.0, 1000.0)
	var ahead := _settle("town", "red", 1400.0, 1000.0)
	var me := _party("lord", "red", 1000.0, 1000.0, 50)
	var foe := _party("lord", "blue", 850.0, 1000.0, 200)
	_map()
	var havens := [behind, ahead].map(func(s): return {"id": s.id, "x": s.x, "y": s.y})
	var t = g.flee_target(me, Vector2(foe.x, foe.y), havens)
	assert(t.sid == ahead.id, "flight to the own town away from the enemy, not past it: %s" % [t])
	_party("lord", "blue", 1400.0, 1050.0, 300)
	_map()
	t = g.flee_target(me, Vector2(foe.x, foe.y), havens)
	assert(t.sid != ahead.id, "a haven held by stronger enemies is no haven: %s" % [t])
	assert(g.risk_at(me, t.x, t.y, 50.0) < g.risk_at(me, me.x, me.y, 50.0), "the flight ends somewhere safer")
