extends SceneTree
## Director of the undead invasion (undead_director.gd, DESIGN.md §5.5, stage 2c) and the goals of the dead
## (party_goals.gd) on synthetic data: made-up living factions "aa" and "bb", parties with a plain strength field, a
## defence and a field function instead of garrisons and the threat map. Only the dead keep their ID
## (Config.UNDEAD_FACTION): the director tells the living from the dead by it.
const Director = preload("res://core/campaign/world/undead_director.gd")
const Goals = preload("res://core/campaign/world/party_goals.gd")
const Ops = preload("res://core/campaign/world/campaign_ops.gd")
const Config = preload("res://core/campaign/config.gd")

const DEAD := Config.UNDEAD_FACTION

func _initialize() -> void:
	_check_targets()
	_check_score()
	_check_best()
	_check_switch()
	_check_rally()
	_check_mode()
	_check_storm()
	_check_goals_of_the_dead()
	_check_defence_of_the_living()
	print("Undead director tests passed")
	quit(0)

var defences := {}  # settlement id -> storm defence
var fields := {}    # faction -> living strength around any of its places

func _director() -> Director:
	var d := Director.new()
	d.strength = func(p: Dictionary) -> float: return float(p.s)
	d.defence = func(s: Dictionary) -> float: return float(defences.get(s.id, 100.0))
	d.field = func(_x: float, _y: float, f: String) -> float: return float(fields.get(f, 0.0))
	return d

static func _place(id: int, kind: String, fac: String, x: float, y: float, extra := {}) -> Dictionary:
	var s := {"id": id, "kind": kind, "fac": fac, "x": x, "y": y}
	s.merge(extra, true)
	return s

static func _army(id: int, s: float, x: float, y: float) -> Dictionary:
	return {"id": id, "kind": "dead", "fac": DEAD, "s": s, "x": x, "y": y}

func _check_targets() -> void:
	assert(Director.is_target(_place(1, "town", "aa", 0, 0)) and Director.is_target(_place(2, "castle", "bb", 0, 0)))
	assert(Director.is_target(_place(3, "town", Config.PLAYER_FACTION, 0, 0)), "the player's holdings are prey too")
	assert(not Director.is_target(_place(4, "village", "aa", 0, 0)), "villages are for the raids")
	assert(not Director.is_target(_place(5, "camp", "aa", 0, 0)))
	assert(not Director.is_target(_place(6, "town", DEAD, 0, 0)), "ruins of the dead are theirs already")
	assert(Director.centre([], {"x": 5.0, "y": 7.0}) == Vector2(5, 7), "a wave without armies stands at its barrow")
	assert(Director.centre([_army(1, 1, 0, 0), _army(2, 1, 100, 50)], {}) == Vector2(50, 25))

func _check_score() -> void:
	defences = {1: 100.0, 2: 100.0, 3: 900.0}
	fields = {}
	var d := _director()
	var near := _place(1, "town", "aa", 100, 0)
	var far := _place(2, "town", "aa", 1200, 0)
	var strong := _place(3, "town", "aa", 100, 10)
	var from := Vector2.ZERO
	var settles := [near, far, strong]
	assert(d.score(near, from, 1000.0, settles) > d.score(far, from, 1000.0, settles), "nearer is better")
	assert(d.score(near, from, 1000.0, settles) > d.score(strong, from, 1000.0, settles), "weaker is better")
	assert(d.score(strong, from, 1000.0, settles) > 0.0, "a strong place is still a target, only a poor one")
	var castle := _place(4, "castle", "aa", 100, 0)
	defences[4] = 100.0
	assert(d.score(near, from, 1000.0, settles) > d.score(castle, from, 1000.0, settles), "a town is worth more than a castle")
	var with_villages := settles + [_place(10, "village", "aa", 150, 0), _place(11, "village", "aa", 100, 80)]
	assert(d.score(near, from, 1000.0, with_villages) > d.score(near, from, 1000.0, settles), "villages around feed the raids")
	var burnt := settles + [_place(10, "village", "aa", 150, 0, {"burnt": 10})]
	assert(is_equal_approx(d.score(near, from, 1000.0, burnt), d.score(near, from, 1000.0, settles)), "burnt villages are no prey")
	var before := d.score(near, from, 1000.0, settles)
	fields = {"aa": 1500.0}
	assert(d.score(near, from, 1000.0, settles) < before, "living armies around a place make it stronger")
	assert(is_equal_approx(d.full_defence(near), 100.0 + Config.UNDEAD_FIELD_SHARE * 1500.0))
	fields = {}
	assert(d.score(_place(5, "town", DEAD, 0, 0), from, 1000.0, settles) == 0.0)

func _check_best() -> void:
	defences = {1: 100.0, 2: 100.0, 3: 100.0}
	fields = {}
	var d := _director()
	var a := _place(2, "town", "aa", 300, 0)
	var b := _place(1, "town", "bb", 0, 300)  # same distance and defence: the lower id wins
	var c := _place(3, "town", "aa", 900, 0)
	var settles := [a, b, c, _place(9, "town", DEAD, 10, 10)]
	var best := d.best_target(Vector2.ZERO, 1000.0, settles)
	assert(best.s.id == 1, "equal scores go to the lower id: %s" % [best])
	assert(d.best_target(Vector2.ZERO, 1000.0, settles, [1]).s.id == 2, "a banned target is skipped")
	assert(d.best_target(Vector2.ZERO, 1000.0, settles, [1, 2, 3]).is_empty(), "nothing left")
	assert(d.best_target(Vector2.ZERO, 1000.0, [_place(9, "town", DEAD, 0, 0)]).is_empty(), "the living hold nothing")
	var lone := d.best_target(Vector2.ZERO, 1000.0, [_place(4, "castle", "aa", 5000, 3000)])
	assert(not lone.is_empty() and lone.s.id == 4, "a far target beats no target: the dead never stand idle")

func _check_switch() -> void:
	var cur := _place(1, "town", "aa", 0, 0)
	assert(not Director.switch(cur, 0.5, {"s": cur, "score": 0.9}), "the same target is kept")
	assert(not Director.switch(cur, 0.5, {"s": _place(2, "town", "aa", 0, 0), "score": 0.5 * (1.0 + Config.UNDEAD_SWITCH_MARGIN) - 0.01}), "a slightly better one is not worth turning")
	assert(Director.switch(cur, 0.5, {"s": _place(2, "town", "aa", 0, 0), "score": 0.5 * (1.0 + Config.UNDEAD_SWITCH_MARGIN) + 0.01}))
	assert(Director.switch({}, 0.0, {"s": cur, "score": 0.1}), "a wave without a target takes any")
	assert(Director.switch(_place(1, "town", DEAD, 0, 0), 0.0, {"s": _place(2, "town", "aa", 0, 0), "score": 0.1}), "a fallen target is replaced")
	assert(not Director.switch(cur, 0.5, {}), "nothing to switch to")

func _check_rally() -> void:
	var d := _director()
	var t := _place(1, "town", "aa", 2000, 1500)
	var r := d.rally_point(Vector2(1000, 1500), t)
	assert(r.is_equal_approx(Vector2(2000 - Config.UNDEAD_RALLY_DISTANCE, 1500)), "short of the target on the side of the wave: %s" % r)
	d.passable = func(c: Vector2) -> bool: return c.x < 2000 - Config.UNDEAD_RALLY_DISTANCE - 1.0
	r = d.rally_point(Vector2(1000, 1500), t)
	assert(r.is_equal_approx(Vector2(2000 - Config.UNDEAD_RALLY_DISTANCE * 1.25, 1500)), "water at the first point: the next passable one: %s" % r)
	d.passable = func(_c: Vector2) -> bool: return false
	assert(d.rally_point(Vector2(1000, 1500), t).is_equal_approx(Vector2(2000 - Config.UNDEAD_RALLY_DISTANCE, 1500)), "nothing passable: the first point")
	d.passable = Callable()
	var edge := d.rally_point(Vector2(-500, 100), _place(2, "town", "aa", 100, 100))
	assert(edge.x >= Config.GOAL_MAP_MARGIN and edge.y >= Config.GOAL_MAP_MARGIN, "never by the map edge: %s" % edge)
	assert(d.rally_point(Vector2(700, 700), _place(3, "town", "aa", 700, 700)).distance_to(Vector2(700, 700)) > 1.0, "a wave already on the target still gets a rally point")

func _check_mode() -> void:
	defences = {1: 1000.0}
	var d := _director()
	var t := _place(1, "town", "aa", 1000, 0)
	var rally := Vector2(740, 0)
	var at_rally := [_army(1, 800.0, 740, 0), _army(2, 600.0, 760, 20)]
	assert(d.mode("gather", at_rally, rally, t, Config.UNDEAD_MIN_GATHER_HOURS - 1.0) == "gather", "the living get time to hear of it")
	assert(d.mode("gather", at_rally, rally, t, Config.UNDEAD_MIN_GATHER_HOURS) == "attack", "gathered and clearly stronger: attack")
	var weak := [_army(1, 500.0, 740, 0), _army(2, 400.0, 760, 20)]
	assert(d.mode("gather", weak, rally, t, Config.UNDEAD_MIN_GATHER_HOURS) == "gather", "too weak: keep gathering")
	assert(d.mode("gather", weak, rally, t, Config.UNDEAD_GATHER_HOURS) == "attack", "all gathered, waited, not hopeless: attack")
	var hopeless := [_army(1, 300.0, 740, 0)]
	assert(d.mode("gather", hopeless, rally, t, Config.UNDEAD_GATHER_HOURS) == "gather")
	assert(d.mode("gather", hopeless, rally, t, Config.UNDEAD_GATHER_HOURS * 2) == "attack", "the dead never wait for ever")
	var straggler := [_army(1, 800.0, 740, 0), _army(2, 600.0, 760, 20), _army(3, 50.0, 0, 0)]
	assert(d.mode("gather", straggler, rally, t, Config.UNDEAD_MIN_GATHER_HOURS) == "attack", "the gathered strength decides, not the stragglers")
	var away := [_army(1, 900.0, 740, 0), _army(2, 900.0, 0, 0)]
	assert(d.mode("gather", away, rally, t, Config.UNDEAD_MIN_GATHER_HOURS) == "gather", "half of the wave is still on its way")
	assert(d.mode("gather", away, rally, t, Config.UNDEAD_GATHER_HOURS * 3) == "gather", "waiting for a straggler is not all gathered")
	assert(d.mode("attack", [_army(1, Config.UNDEAD_FALLBACK_SHARE * 1000.0 + 1.0, 0, 0)], rally, t, 0.0) == "attack", "an attack goes on")
	assert(d.mode("attack", [_army(1, Config.UNDEAD_FALLBACK_SHARE * 1000.0 - 1.0, 0, 0)], rally, t, 0.0) == "gather", "worn down: gather again")
	assert(d.mode("attack", [], rally, t, 0.0) == "gather" and d.mode("gather", at_rally, rally, {}, 0.0) == "gather")
	var at_walls := [_army(1, 800.0, 1000, 60), _army(2, 600.0, 990, -40)]
	assert(Director.gathered(at_walls, rally, t).size() == 2, "by the walls counts as gathered")

func _check_storm() -> void:
	var d := _director()
	var t := _place(1, "castle", "bb", 0, 0)
	var two_of_three := [_army(1, 400.0, 50, 0), _army(2, 400.0, 0, 60), _army(3, 400.0, 600, 0)]
	assert(Director.at_walls(two_of_three, t).size() == 2)
	assert(not d.storm_ready(two_of_three, t, 0.0), "two thirds of the strength wait for the rest")
	assert(d.storm_ready(two_of_three, t, Config.UNDEAD_STORM_WAIT), "but not for ever")
	var most := [_army(1, 800.0, 50, 0), _army(2, 100.0, 600, 0)]
	assert(d.storm_ready(most, t, 0.0), "most of the strength is there")
	assert(not d.storm_ready([_army(1, 800.0, 600, 0)], t, 99.0), "nobody at the walls: no storm")

## Goals of undead parties come from their wave and front (party_goals.gd).
func _check_goals_of_the_dead() -> void:
	var g: Variant = Goals.new()
	var settles := [_place(1, "town", "aa", 1000, 0), _place(2, "village", "aa", 900, 100), _place(3, "village", "aa", 3000, 0),
		_place(4, "village", "aa", 950, 0, {"burnt": 5}), _place(5, "village", DEAD, 1000, 50)]
	var parties: Array = []
	g.parties = parties
	g.settles = settles
	g.strength = func(p): return float(p.s)
	g.speed = func(_p): return 17.0
	g.hostile = func(a, b): return (a.fac == DEAD) != (b.fac == DEAD)
	g.at_war = func(_a, _b): return false
	var army := {"id": 10, "kind": "dead", "fac": DEAD, "s": 1000.0, "x": 0.0, "y": 0.0, "troops": [], "path": [], "pi": 0, "state": "idle", "hide": false}
	parties.append(army)
	var wave := {"mode": "gather", "tid": 1, "x": 1000.0, "y": 0.0, "rx": 740.0, "ry": 0.0}
	var c = g.candidates(army, {"wave": wave, "front": {"x": 1000.0, "y": 0.0}})
	assert(c[0].goal == "muster" and c[0].gid == 1 and is_equal_approx(c[0].x, 740.0), "a gathering army goes to the rally point: %s" % [c])
	var far_score: float = c[0].score
	army.x = 740.0
	c = g.candidates(army, {"wave": wave, "front": {"x": 1000.0, "y": 0.0}})
	var near_score: float = c.filter(func(x): return x.goal == "muster")[0].score
	assert(near_score < far_score, "at the rally point it musters less eagerly, so it can crush weak enemies nearby")
	assert(not c.any(func(x): return x.goal == "raid"), "armies do not burn villages: raids do")
	wave.mode = "attack"
	c = g.candidates(army, {"wave": wave, "front": {"x": 1000.0, "y": 0.0}})
	assert(c[0].goal == "assault" and c[0].gid == 1 and not c.any(func(x): return x.goal == "muster"), "an attacking army marches on the target")
	var prey := {"id": 11, "kind": "lord", "fac": "aa", "s": 100.0, "x": 760.0, "y": 0.0, "troops": [{"type": "t", "n": 1}], "path": [], "pi": 0, "state": "idle", "hide": false}
	parties.append(prey)
	army.goal = "assault"
	army.gid = 1
	army.path = [Vector2(1000, 0)]
	c = g.candidates(army, {"wave": wave, "front": {"x": 1000.0, "y": 0.0}})
	assert(g.choose(army, c, RandomNumberGenerator.new()).is_empty(), "an assault is not dropped for a passing lord")
	assert(not c.any(func(x): return x.goal == "flee"), "the dead never flee")
	parties.erase(prey)
	var raid := {"id": 12, "kind": "raid", "fac": DEAD, "s": 100.0, "x": 800.0, "y": 0.0, "troops": [], "path": [], "pi": 0, "state": "idle", "hide": false}
	parties.append(raid)
	c = g.candidates(raid, {"front": {"x": 1000.0, "y": 0.0}})
	var burns = c.filter(func(x): return x.goal == "raid")
	assert(burns.size() == 1 and burns[0].gid == 2, "raids burn living villages ahead of the wave, not burnt ones, not far ones: %s" % [burns])
	assert(c.any(func(x): return x.goal == "roam" and is_equal_approx(x.x, 1000.0)), "with nothing better they roam around the front")
	settles[1].burnt = 3
	c = g.candidates(raid, {"front": {"x": 1000.0, "y": 0.0}})
	assert(c[0].goal == "roam", "nothing left to burn: roam around the front, not off to the map edge")
	c = g.candidates(raid, {})
	assert(c[0].goal == "roam" and is_equal_approx(c[0].x, 800.0), "without a front a raid roams where it is")

## The living defend from the inside the towns and castles the dead go for (party_goals.gd _defend, campaign_ops alerts).
func _check_defence_of_the_living() -> void:
	var g: Variant = Goals.new()
	var town := _place(1, "town", "aa", 300, 0)
	var quiet := _place(2, "town", "aa", 0, 300)
	var village := _place(3, "village", "aa", 100, 0)
	g.parties = []
	g.settles = [town, quiet, village]
	g.strength = func(p): return float(p.s)
	g.speed = func(_p): return 17.0
	g.hostile = func(_a, _b): return false
	g.at_war = func(_a, _b): return false
	var lord := {"id": 20, "kind": "lord", "fac": "aa", "s": 500.0, "x": 0.0, "y": 0.0, "troops": [{"type": "t", "n": 330}], "path": [], "pi": 0, "state": "idle", "hide": false}
	assert(not g.candidates(lord).any(func(x): return x.goal == "defend"), "nothing to defend in quiet lands")
	g.doomed = func(): return {1: "gather", 3: "gather"}
	var c = g.candidates(lord)
	var defend = c.filter(func(x): return x.goal == "defend")
	assert(defend.size() == 1 and defend[0].gid == 1 and defend[0].inside, "the doomed town is defended from the inside: %s" % [defend])
	assert(c[0].goal == "defend", "it outweighs patrols and rest")
	var ops := Ops.new()
	ops.strength = func(p): return float(p.s)
	var a: Array = ops.alerts("aa", [town, quiet, village], Callable(), {1: "attack"})
	assert(a.size() == 1 and a[0].s.id == 1 and a[0].doomed and not a[0].besieged, "a doomed town keeps a defender home: %s" % [a])
	var besieged := _place(4, "castle", "aa", 0, 900, {"siege": {"f": "bb"}})
	a = ops.alerts("aa", [town, besieged], Callable(), {1: "attack"})
	assert(a[0].s.id == 4 and a[1].s.id == 1, "a siege comes first")
	var ruin := _place(5, "castle", DEAD, 0, 0, {"ruinOf": "aa"})
	var other := _place(6, "town", DEAD, 0, 0, {"ruinOf": "bb"})
	assert(Ops.own_ruins("aa", [town, ruin, other, _place(7, "village", DEAD, 0, 0, {"ruinOf": "aa"})]) == [ruin], "only own towns and castles are retaken")
