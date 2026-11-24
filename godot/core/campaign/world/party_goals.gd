extends RefCounted
## Goals of map parties (docs/modules/ai/DESIGN.md §5.2, stage 2a, ADR-023): one evaluator for lords, faction vassals,
## the player's retinues, bandits, caravans and the dead. Every goal scores 0..1 as a product of normalised factors
## (Dave Mark's Infinite Axis Utility System, with the compensation for the number of factors), times the weight of
## the goal for the kind of party (Config.GOAL_PROFILES, retinue orders in Config.GOAL_RETINUE_MODES).
## Distance is a factor of every goal. A goal is kept for a minimal time and replaced only by a clearly better one;
## a goal other parties of the faction already pursue is less attractive; a faster target is not chased for long.
## Risk and havens come from the threat map; foreign places out of scouting range carry an assumed risk (§5.1).
## The evaluator only reads: parties, settlements and services come in through the fields below, so it runs on
## synthetic data. It picks a goal; party_ai.gd carries it out. RNG is spent only in choose().
## Since stage 2c the dead follow the director of the invasion (undead_director.gd, DESIGN.md §5.5): an army gathers at
## the rally point of its wave (muster) and storms its target with the others (assault); raids burn villages ahead of the
## wave; with nothing else to do the dead roam around their front. The living defend the towns and castles the waves go
## for, from the inside (`doomed`).
## Since #312 (DESIGN.md §5.7, parties act together) a lord or vassal goes to help a running fight of its faction that it
## sees and can turn (`assist`); the fights come in through `battles`, a short list built once per world step.
## Since #313 a lord or vassal that a stronger enemy chases or that flees calls for help (`calls`, the same kind of list):
## own lords and vassals answer it (`rescue`), and the fleeing party runs to a strong own party nearby, not only to an
## own settlement (flee_target), so the two meet half-way.
## Since #315 lords escort the caravans of their faction too, not only faction vassals, and the danger to a caravan is read
## on the threat map at its place and ahead on its route (`caravan_danger`); the caravans come in through `caravans`, a list
## of the same pass. A caravan that an outlaw hunts or that flees calls like a lord (the calls), and it flees to a strong own
## party in sight too.
const Config = preload("res://core/campaign/config.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

## Goals that react to what a party sees; they may interrupt a plan before its hold time is over.
const REACTIVE := ["hunt", "flee", "assist", "rescue"]
## Goals carried out by riding to a settlement or a point and lingering there.
const PLANS := ["defend", "patrol", "raid", "rest", "escort", "follow", "roam", "guard", "muster", "assault"]
const PLAYER_ID := -1  # gid of a hunt after the player's party

var parties: Array = []                  # live list of map parties (roster.parties)
var settles: Array = []                  # live list of settlements (map.settles)
var strength: Callable                   # (party) -> float
var speed: Callable                      # (party) -> float, map units per hour
var hostile: Callable                    # (party, party) -> bool
var at_war: Callable                     # (faction, faction) -> bool, for raids on settlements
var allies: Callable = Callable()        # (party) -> float, friendly strength nearby (skirmish.ally_strength)
var threat_map: Callable = Callable()    # () -> ThreatMap or null
var enemies: Callable = Callable()       # (faction) -> Array of hostile factions on the threat map
var player_target: Callable = Callable() # (party) -> {x, y, strength} when the player may be attacked by it, else {}
var ruins: Callable = Callable()         # (faction) -> own former settlements held by the dead
var modifiers: Callable = Callable()     # (party) -> {goal: multiplier, "risk": exponent}; stage 3: traits, difficulty
var passable: Callable = Callable()      # (Vector2) -> bool, for threat-map havens
var doomed: Callable = Callable()        # () -> {settlement id: mode} targets of the undead waves (stage 2c), optional
var battles: Callable = Callable()       # () -> running fights (WorldSkirmish.battles, #312), optional
var calls: Callable = Callable()         # () -> calls for help [{id, fac, x, y, ...}] (party_ai.gd, #313), optional
var call_detail: Callable = Callable()   # (call) -> the call with own, foe, left, or {} when it is none; optional (the
										 # calls already carry them)
var caravans: Callable = Callable()      # () -> caravans on the map (party_ai.gd, #315), optional: else read from `parties`
var width := 5200.0
var height := 3400.0

## goal|gid|faction -> number of parties of the faction pursuing it; kept by note()/rebuild_claims().
var claims := {}
var _own := {}  # faction -> own settlements, until reset()
var _foes := {}  # faction -> Array hostile to it on the threat map, until reset(); "!" + faction: only the outlaws among them
var _danger := {}  # caravan id -> caravan_danger() of this step, until reset()
# The party candidates() works on, with what risk_at/crowd_factor would otherwise recompute for every settlement.
var _cp: Dictionary = {}
var _cp_map: ThreatMap = null
var _cp_foes: Array = []
var _cp_key := ""
var _cp_ready := false  # the map and the foes are asked for at the first risk_at, not before: the threat map of a step
						# is frozen when it is first requested, and that moment must not move

## Forgets per-step caches; call when parties or settlements may have changed (every world step).
func reset() -> void:
	_own = {}
	_foes = {}
	_danger = {}
	_cp = {}
	_cp_map = null
	_cp_foes = []
	_cp_key = ""
	_cp_ready = false

# ---------- curves ----------

static func clamp01(x: float) -> float:
	return clampf(x, 0.0, 1.0)

## Linear response: y0 at x <= x0, y1 at x >= x1.
static func ramp(x: float, x0: float, x1: float, y0 := 0.0, y1 := 1.0) -> float:
	if x1 == x0:
		return y1 if x >= x1 else y0
	return lerpf(y0, y1, clamp01((x - x0) / (x1 - x0)))

## Product of factors with Dave Mark's compensation, so a goal with more factors is not punished for their number.
static func combine(factors: Array) -> float:
	var score := 1.0
	for f in factors:
		score *= clamp01(float(f))
	if score <= 0.0 or factors.size() < 2:
		return score
	var mod := 1.0 - 1.0 / factors.size()
	return score + (1.0 - score) * mod * score

## combine() for 3, 4, 5 or 6 factors without building the array: the same products in the same order.
static func combine3(a: float, b: float, c: float) -> float:
	var score := clamp01(a)
	score *= clamp01(b)
	score *= clamp01(c)
	if score <= 0.0:
		return score
	return score + (1.0 - score) * (1.0 - 1.0 / 3) * score

static func combine4(a: float, b: float, c: float, d: float) -> float:
	var score := clamp01(a)
	score *= clamp01(b)
	score *= clamp01(c)
	score *= clamp01(d)
	if score <= 0.0:
		return score
	return score + (1.0 - score) * (1.0 - 1.0 / 4) * score

static func combine5(a: float, b: float, c: float, d: float, e: float) -> float:
	var score := clamp01(a)
	score *= clamp01(b)
	score *= clamp01(c)
	score *= clamp01(d)
	score *= clamp01(e)
	if score <= 0.0:
		return score
	return score + (1.0 - score) * (1.0 - 1.0 / 5) * score

static func combine6(a: float, b: float, c: float, d: float, e: float, f: float) -> float:
	var score := clamp01(a)
	score *= clamp01(b)
	score *= clamp01(c)
	score *= clamp01(d)
	score *= clamp01(e)
	score *= clamp01(f)
	if score <= 0.0:
		return score
	return score + (1.0 - score) * (1.0 - 1.0 / 6) * score

static func distance_factor(d: float, range_: float) -> float:
	return 1.0 - Config.GOAL_DISTANCE_FALLOFF * clamp01(d / maxf(1.0, range_))

func crowd_factor(goal: String, gid: Variant, p: Dictionary) -> float:
	var key := _claim_key(goal, gid, String(p.fac))
	var n := int(claims.get(key, 0))
	if (_cp_key if is_same(p, _cp) else goal_key(p)) == key:
		n -= 1
	return 1.0 / (1.0 + Config.GOAL_CROWD_PENALTY * maxi(0, n))

# ---------- profiles and hooks ----------

## Weights and radii of a party: by kind, a retinue by its order. Unknown kinds get GOAL_PROFILE_OTHER.
static func profile(p: Dictionary, mode := "") -> Dictionary:
	if p.get("kind") == "cvass":
		return Config.GOAL_RETINUE_MODES.get(mode, Config.GOAL_RETINUE_MODES.guard)
	return Config.GOAL_PROFILES.get(String(p.get("kind", "")), Config.GOAL_PROFILE_OTHER)

func _mods(p: Dictionary) -> Dictionary:
	return modifiers.call(p) if modifiers.is_valid() else {}

static func weight(prof: Dictionary, mods: Dictionary, goal: String) -> float:
	return float(prof.get(goal, 0.0)) * float(mods.get(goal, 1.0))

static func risk_factor(risk: float, mods: Dictionary) -> float:
	return pow(1.0 - clamp01(risk / Config.GOAL_RISK_SPAN), float(mods.get("risk", 1.0)))

# ---------- claims ----------

static func _claim_key(goal: String, gid: Variant, fac: String) -> String:
	return goal + "|" + str(gid) + "|" + fac

static func goal_key(p: Dictionary) -> String:
	var g := String(p.get("goal", ""))
	return "" if g == "" else _claim_key(g, p.get("gid"), String(p.fac))

func rebuild_claims() -> void:
	claims = {}
	for p in parties:
		var k := goal_key(p)
		if k != "":
			claims[k] = int(claims.get(k, 0)) + 1

## Records that p switched from the claim `old_key` to its current goal.
func note(old_key: String, p: Dictionary) -> void:
	if old_key != "" and claims.has(old_key):
		claims[old_key] = int(claims[old_key]) - 1
		if claims[old_key] <= 0:
			claims.erase(old_key)
	var k := goal_key(p)
	if k != "":
		claims[k] = int(claims.get(k, 0)) + 1

# ---------- threat ----------

func _map() -> ThreatMap:
	return threat_map.call() if threat_map.is_valid() else null

func _enemies(fac: String) -> Array:
	return enemies.call(fac) if enemies.is_valid() else []

## Threat-map layers hostile to the party. A profile with `outlaws_only` (caravans) fears only the factions that
## fight everyone: lords of states at war leave caravans alone (Rules.hostile).
func foes(p: Dictionary) -> Array:
	var fac := String(p.fac)
	var outlaws := bool(profile(p).get("outlaws_only", false))
	var key := "!" + fac if outlaws else fac
	var cached: Variant = _foes.get(key)
	if cached != null:
		return cached
	var all := _enemies(fac)
	var out: Array = all if not outlaws else all.filter(func(f): return f == Config.BANDIT_FACTION or f == Config.UNDEAD_FACTION)
	_foes[key] = out
	return out

## Enemy strength felt at (x, y) on the threat map, in strengths of a party of strength `me`.
func risk_at(p: Dictionary, x: float, y: float, me: float, minus := 0.0) -> float:
	if is_same(p, _cp):
		if not _cp_ready:
			_cp_ready = true
			_cp_map = _map()
			_cp_foes = foes(p) if _cp_map != null else []
		if _cp_map == null:
			return 0.0
		return maxf(0.0, _cp_map.threat(x, y, _cp_foes) - minus) / maxf(0.001, me)
	var m := _map()
	if m == null:
		return 0.0
	return maxf(0.0, m.threat(x, y, foes(p)) - minus) / maxf(0.001, me)

## Risk of a foreign place: known within scouting range of the party, assumed beyond it (§5.1 visibility).
func foreign_risk(p: Dictionary, x: float, y: float, me: float) -> float:
	if Vector2(x - p.x, y - p.y).length() > Config.GOAL_SCOUT_RADIUS:
		return Config.GOAL_UNKNOWN_RISK
	return risk_at(p, x, y, me)

# ---------- candidates ----------

## Own strength with allies nearby, never zero.
func own_strength(p: Dictionary) -> float:
	var me: float = strength.call(p)
	if allies.is_valid():
		me += float(allies.call(p))
	return maxf(0.001, me)

## Every goal the party could take now, best first: [{goal, gid, x, y, score}].
## ctx: army (bool, a faction campaign), fief (settlement of a retinue), lead ({x, y} of the followed party or player),
## lord (the vassal's lord party), mode (retinue order), haven_extra ([{id, x, y}] havens besides own settlements),
## wave (an undead army: {mode, tid, x, y, rx, ry} of its wave), front ({x, y} where the dead of its barrow strike).
func candidates(p: Dictionary, ctx := {}) -> Array:
	_cp = p
	_cp_ready = false
	_cp_key = goal_key(p)
	var mods := _mods(p)
	var prof := profile(p, String(ctx.get("mode", "")))
	var me := own_strength(p)
	var out: Array = []
	var seen := scan(p, me, prof, ctx)
	_hunt(p, me, prof, mods, ctx, seen, out)
	if bool(ctx.get("army", false)):
		_sort(out)
		return out
	_flee(p, me, prof, mods, seen, out)
	_assist(p, prof, mods, out)
	_rescue(p, prof, mods, out)
	_defend(p, me, prof, mods, out)
	_patrol(p, prof, mods, ctx, out)
	_raid(p, me, prof, mods, out)
	_rest(p, me, prof, mods, out)
	_escort(p, prof, mods, out)
	_follow(p, prof, mods, ctx, out)
	_guard(p, prof, mods, ctx, out)
	_muster(p, prof, mods, ctx, out)
	_assault(p, prof, mods, ctx, out)
	_ravage(p, me, prof, mods, ctx, out)
	_roam(p, prof, mods, ctx, out)
	_sort(out)
	return out

static func _sort(out: Array) -> void:
	out.sort_custom(func(a, b): return a.score > b.score)

## Parties in sight: weaker ones as prey, the pressure of stronger ones (1 = an enemy `flee_ratio` times stronger) and the
## strength of the strongest of them (`foe`). A lord or vassal also notes the free lords and vassals of its faction in sight
## that are not already at hand (`friends`, #313): a flight may run to them; since #315 so does a caravan.
func scan(p: Dictionary, me: float, prof: Dictionary, ctx: Dictionary) -> Dictionary:
	var army := bool(ctx.get("army", false))
	var sight := Config.GOAL_ARMY_HUNT_RADIUS if army else float(prof.sight)
	var flee_sight := float(prof.flee_sight)
	var hunt_ratio := float(prof.hunt_ratio)
	var flee_ratio := float(prof.flee_ratio)
	var skip_busy := bool(prof.get("skip_busy", false))
	var leash := float(prof.get("leash", 0.0))
	var fief: Dictionary = ctx.get("fief", {})
	var prey: Array = []
	var pressure := 0.0
	var foe := 0.0
	var friends: Array = []
	var friendly: bool = not army and (Rules.is_noble(p) or p.kind == "caravan")
	var from := Vector2(p.x, p.y)
	var look := maxf(sight, flee_sight)
	var px: float = p.x
	var py: float = p.y
	for o in parties:
		# Distant parties are rejected before their flags are read (the checks are pure, so their order does not matter).
		if absf(o.x - px) > look or absf(o.y - py) > look:
			continue
		if is_same(o, p) or o.hide or o.kind == "camp" or o.get("lock", false) or (skip_busy and o.get("fight", false)):
			continue
		var d := Vector2(o.x - px, o.y - py).length()
		if d > look:
			continue
		if not hostile.call(p, o):
			if friendly and o.fac == p.fac and d >= Config.GOAL_FLEE_FRIEND_MIN and (o.kind == "lord" or o.kind == "vassal") and not o.get("fight"):
				friends.append(o)
			continue
		var so: float = strength.call(o)
		if so < me * hunt_ratio:
			if d <= sight and (leash <= 0.0 or fief.is_empty() or Vector2(o.x - fief.x, o.y - fief.y).length() <= leash):
				prey.append({"party": o, "d": d, "strength": so})
		elif so > me * flee_ratio and d < flee_sight and not army:
			var k := so / (me * flee_ratio)
			if k > pressure:
				pressure = k
				foe = so
				from = Vector2(o.x, o.y)
	if player_target.is_valid():
		var pl: Dictionary = player_target.call(p)
		if pl.has("x"):
			var d := Vector2(pl.x - p.x, pl.y - p.y).length()
			var sp := float(pl.strength)
			if d < minf(Config.GOAL_PLAYER_SIGHT, sight) and sp < me * Config.GOAL_PLAYER_HUNT_RATIO:
				prey.append({"party": {"id": PLAYER_ID, "kind": "player", "x": pl.x, "y": pl.y}, "d": d, "strength": sp, "ratio": Config.GOAL_PLAYER_HUNT_RATIO})
			elif not army and sp > me * Config.GOAL_PLAYER_FLEE_RATIO and d < Config.GOAL_PLAYER_FLEE_SIGHT:
				var k := sp / (me * Config.GOAL_PLAYER_FLEE_RATIO)
				if k > pressure:
					pressure = k
					foe = sp
					from = Vector2(pl.x, pl.y)
	return {"prey": prey, "pressure": pressure, "foe": foe, "friends": friends, "from": from, "sight": sight}

func _hunt(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, ctx: Dictionary, seen: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "hunt")
	if w <= 0.0:
		return
	var vm: float = maxf(0.001, speed.call(p))
	var chasing := String(p.get("goal", "")) == "hunt"
	for e in seen.prey:
		var o: Dictionary = e.party
		var ratio_limit := float(e.get("ratio", prof.hunt_ratio))
		var adv := ramp(float(e.strength) / me, 0.0, ratio_limit, 1.0, Config.GOAL_HUNT_EDGE_FLOOR)
		var worth := float(Config.GOAL_PREY_WORTH.get(String(o.kind), Config.GOAL_PREY_WORTH_OTHER))
		var catch := 1.0
		if o.has("troops"):
			var vo: float = speed.call(o)
			if vo > vm:
				catch = clamp01(1.0 - Config.GOAL_FASTER_PENALTY * (vo - vm) / vm)
				if chasing and p.get("gid") == o.id and float(p.get("ga", 0.0)) > Config.GOAL_FASTER_CHASE_HOURS:
					catch = 0.0
		var risk := risk_factor(risk_at(p, o.x, o.y, me, float(e.strength)), mods)
		var s := w * combine6(adv, worth, distance_factor(float(e.d), float(seen.sight)), catch, crowd_factor("hunt", o.id, p), risk)
		if s > 0.0:
			out.append({"goal": "hunt", "gid": o.id, "x": o.x, "y": o.y, "score": s})

## Fleeing scores by the pressure of stronger enemies in sight and on the threat map. A flight already under way
## keeps a residual score until its hold time is over, so a party does not turn back at the edge of sight.
## The candidate carries what flee_target needs: the enemy strength (the strongest in sight, or the enemies felt on the
## threat map) and the own parties in sight (#313).
func _flee(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, seen: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "flee")
	if w <= 0.0:
		return
	var pressure := float(seen.pressure)
	var foe := float(seen.get("foe", 0.0))
	if bool(prof.get("map_pressure", true)):
		var felt := risk_at(p, p.x, p.y, me)
		pressure = maxf(pressure, felt * Config.GOAL_FLEE_MAP_SHARE / float(prof.flee_ratio))
		foe = maxf(foe, felt * me * Config.GOAL_FLEE_MAP_SHARE)
	var s := 0.0
	if pressure > 1.0:
		s = w * ramp(pressure, 1.0, Config.GOAL_FLEE_FULL_PRESSURE, 0.5, 1.0)
	elif p.get("goal", "") == "flee" and goal_active(p) and float(p.get("ga", 0.0)) < Config.GOAL_HOLD_HOURS:
		s = w * Config.GOAL_FLEE_RESIDUAL
	if s > 0.0:
		out.append({"goal": "flee", "gid": null, "x": float(seen.from.x), "y": float(seen.from.y), "score": s, "foe": foe,
			"friends": seen.get("friends", [])})

## Help in battle (#312, DESIGN.md §5.7.3): a running fight with the party's faction on a side that the party would join
## by the rule of world_skirmish.hour_tick (hostile to someone on the other side, to no one on this one). Factors: how much
## the side needs help, whether the party turns it (no goal when even with it the side is hopeless), whether it gets there
## before the fight is over, and own parties already on the way. Distance is weighed by the time it takes against the
## hours the fight has left, not again as the distance factor; the enemy at the fight by the odds, not as threat-map risk.
func _assist(p: Dictionary, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "assist")
	if w <= 0.0 or not battles.is_valid():
		return
	var list: Array = battles.call()
	if list.is_empty():
		return
	var reach := Config.GOAL_ASSIST_RANGE
	var me := -1.0  # own strength and speed only once a fight is in reach: most evaluations see none
	var vm := 0.0
	var fac := String(p.fac)
	for b in list:
		if absf(b.x - p.x) > reach or absf(b.y - p.y) > reach:
			continue
		var d := Vector2(b.x - p.x, b.y - p.y).length()
		if d > reach:
			continue
		var side := side_for(p, b.sides, fac)
		if side < 0:
			continue
		if me < 0.0:
			me = strength.call(p)
			vm = maxf(0.001, speed.call(p))
		var own: float = b.strength[side]
		var foe: float = b.strength[1 - side]
		var need := ramp(foe / maxf(0.001, own), Config.GOAL_ASSIST_NEED.x, Config.GOAL_ASSIST_NEED.y, Config.GOAL_ASSIST_NEED_FLOOR, 1.0)
		var odds := ramp((own + me) / maxf(0.001, foe), Config.GOAL_ASSIST_ODDS.x, Config.GOAL_ASSIST_ODDS.y)
		if odds <= 0.0:
			continue
		var in_time := ramp(d / vm / maxf(0.5, float(b.left)), Config.GOAL_ASSIST_IN_TIME.x, Config.GOAL_ASSIST_IN_TIME.y, 1.0, 0.0)
		if in_time <= 0.0:
			continue
		var s := w * combine4(need, odds, in_time, crowd_factor("assist", b.id, p))
		if s > 0.0:
			out.append({"goal": "assist", "gid": b.id, "x": b.x, "y": b.y, "score": s})

## The side of a fight (0, 1) that p would join by the rule of world_skirmish.hour_tick and where its faction `fac` fights
## (part 1 helps only its own), or -1.
func side_for(p: Dictionary, sides: Array, fac: String) -> int:
	for side in 2:
		var mine := false
		var clean := true
		for q in sides[side]:
			if q.fac == fac:
				mine = true
			if hostile.call(p, q):
				clean = false
				break
		if not mine or not clean:
			continue
		for q in sides[1 - side]:
			if hostile.call(p, q):
				return side
	return -1

## Where a fleeing party meets the own parties that answer its call (#313): the best of them as a haven (flee_target), or
## {} when none is safe to run to. The caller re-plans its flight to it, so the two ride towards each other.
func meet_target(p: Dictionary, from: Vector2, friends: Array, foe: float) -> Dictionary:
	var t := _friend_haven(p, from, risk_at(p, p.x, p.y, own_strength(p)), friends, foe)
	t.erase("cost")
	return t

## The best own party to flee to, with its cost on the scale of flee_target: together with p at least as strong as the
## enemy, within the haven range, not past the enemy, and clearly safer than here in their joint strength.
func _friend_haven(p: Dictionary, from: Vector2, here_risk: float, friends: Array, foe: float) -> Dictionary:
	var best := {}
	if friends.is_empty():
		return best
	var here := Vector2(p.x, p.y)
	var away := here - from
	var best_cost := INF
	var alone := maxf(0.001, float(strength.call(p)))
	for o in friends:
		var both: float = alone + float(strength.call(o))
		if both < foe * Config.GOAL_FLEE_FRIEND_ODDS:
			continue
		var at := Vector2(o.x, o.y)
		var d := here.distance_to(at)
		if d > Config.GOAL_FLEE_HAVEN_RANGE or d < 1.0:
			continue
		if away.length() > 0.0 and (at - here).dot(away) < 0.0 and at.distance_to(from) < here.distance_to(from):
			continue
		var risk := risk_at(p, at.x, at.y, both)
		if here_risk > 0.0 and risk >= here_risk * Config.GOAL_FLEE_SAFER:
			continue
		var mid := (here + at) * 0.5
		var cost := (risk + risk_at(p, mid.x, mid.y, both)) * Config.GOAL_FLEE_THREAT_COST + d / Config.GOAL_FLEE_HAVEN_RANGE
		if cost < best_cost:
			best_cost = cost
			best = {"x": at.x, "y": at.y, "sid": null, "pid": o.id, "cost": cost}
	return best

## Calls for help (#313, DESIGN.md §5.7.2): an own lord or vassal in danger — a stronger enemy chases it, or it flees. The
## same factors as help in battle: how much it needs help (enemy / its strength), whether the party turns it (no goal when
## even together they are hopeless), whether the party gets there before the caller is caught and beaten (`left`), and own
## parties already on the way. The calls of other factions are left to part 3 (the enemy of my enemy).
func _rescue(p: Dictionary, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "assist")
	if w <= 0.0 or not calls.is_valid():
		return
	var list: Array = calls.call()
	if list.is_empty():
		return
	var reach := Config.GOAL_ASSIST_RANGE
	var me := -1.0  # own strength and speed only once a call is in reach
	var vm := 0.0
	for c in list:
		if c.fac != p.fac or c.id == p.id or absf(c.x - p.x) > reach or absf(c.y - p.y) > reach:
			continue
		var d := Vector2(c.x - p.x, c.y - p.y).length()
		if d > reach:
			continue
		var info: Dictionary = call_detail.call(c) if call_detail.is_valid() else c
		if info.is_empty():
			continue
		if me < 0.0:
			me = strength.call(p)
			vm = maxf(0.001, speed.call(p))
		var own: float = info.own
		var foe: float = info.foe
		var need := ramp(foe / maxf(0.001, own), Config.GOAL_ASSIST_NEED.x, Config.GOAL_ASSIST_NEED.y, Config.GOAL_ASSIST_NEED_FLOOR, 1.0)
		var odds := ramp((own + me) / maxf(0.001, foe), Config.GOAL_ASSIST_ODDS.x, Config.GOAL_ASSIST_ODDS.y)
		if odds <= 0.0:
			continue
		var in_time := ramp(d / vm / maxf(0.5, float(info.left)), Config.GOAL_ASSIST_IN_TIME.x, Config.GOAL_ASSIST_IN_TIME.y, 1.0, 0.0)
		if in_time <= 0.0:
			continue
		var s := w * combine4(need, odds, in_time, crowd_factor("rescue", c.id, p))
		if s > 0.0:
			out.append({"goal": "rescue", "gid": c.id, "x": c.x, "y": c.y, "score": s})

## Own settlements a party belongs to (not camps): the settlements of its faction.
func own_settlements(fac: String) -> Array:
	if not _own.has(fac):
		_own[fac] = settles.filter(func(s): return s.fac == fac and s.kind != "camp")
	return _own[fac]

## Defence of own settlements in danger: besieged, with enemies around, or the target of an undead wave (stage 2c). A
## town or castle the dead go for is defended from the inside: the lords inside hold the walls with the garrison.
func _defend(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "defend")
	if w <= 0.0:
		return
	var doom: Dictionary = doomed.call() if doomed.is_valid() else {}
	var defend_range := Config.GOAL_DEFEND_RANGE
	for s in own_settlements(String(p.fac)):
		if absf(s.x - p.x) > defend_range or absf(s.y - p.y) > defend_range:
			continue
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		if d > defend_range:
			continue
		var enemy := risk_at(p, s.x, s.y, me)
		var dead: bool = doom.has(s.id) and s.kind != Config.SETTLEMENT_VILLAGE
		var urgency := 1.0 if s.get("siege") != null or dead else clamp01(enemy / Config.GOAL_DEFEND_THREAT_SHARE)
		if urgency <= 0.0:
			continue
		var score := w * combine4(urgency, distance_factor(d, Config.GOAL_DEFEND_RANGE), risk_factor(enemy, mods), crowd_factor("defend", s.id, p))
		if score > 0.0:
			out.append({"goal": "defend", "gid": s.id, "x": s.x, "y": s.y, "score": score, "inside": dead})

## Patrol of own lands, more often where enemies were seen lately (s.alarm hours, kept by party_ai.gd hour_tick).
func _patrol(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "patrol")
	if w <= 0.0:
		return
	var fief: Dictionary = ctx.get("fief", {})
	var centre := Vector2(p.x, p.y) if fief.is_empty() else Vector2(fief.x, fief.y)
	var reach := Config.GOAL_PATROL_RANGE if fief.is_empty() else Config.GOAL_RETINUE_PATROL_RANGE.y
	for s in own_settlements(String(p.fac)):
		if absf(s.x - centre.x) > reach or absf(s.y - centre.y) > reach:
			continue
		var d := Vector2(s.x - centre.x, s.y - centre.y).length()
		if d > reach:
			continue
		var alarm := ramp(float(s.get("alarm", 0)), 0.0, float(Config.GOAL_ALARM_HOURS), Config.GOAL_PATROL_BASE, 1.0)
		var score := w * combine3(alarm, distance_factor(d, reach), crowd_factor("patrol", s.id, p))
		if score > 0.0:
			out.append({"goal": "patrol", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Raids: enemy villages of a faction at war, the player's villages when he is an enemy, own ruins held by the dead.
## The player's towns and castles are besieged by campaigns (world_wars.gd, stage 2b), not raided.
func _raid(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "raid")
	if w <= 0.0:
		return
	var full := ramp(float(strength.call(p)) / maxf(0.001, full_strength(p)), Config.GOAL_RAID_FULL_SHARE.x, Config.GOAL_RAID_FULL_SHARE.y)
	if full <= 0.0:
		return
	var fac := String(p.fac)
	if fac == Config.UNDEAD_FACTION:
		return  # the dead burn villages ahead of their wave (_ravage)
	var targets: Array = []
	var reach := Config.GOAL_RAID_RANGE
	for s in settles:
		if absf(s.x - p.x) > reach or absf(s.y - p.y) > reach:
			continue  # beyond the raid range (settlements, the player's villages): not a target, no need to ask about wars
		if s.fac == fac or s.kind == "camp" or s.get("siege") != null:
			continue
		if s.fac == Config.PLAYER_FACTION:
			if s.kind == Config.SETTLEMENT_VILLAGE and int(s.get("burnt", 0)) <= 0 and player_target.is_valid() and _player_enemy(p):
				targets.append({"s": s, "value": float(Config.GOAL_RAID_VALUE.player), "range": Config.GOAL_RAID_RANGE})
		elif s.kind == Config.SETTLEMENT_VILLAGE and s.fac != Config.UNDEAD_FACTION and int(s.get("burnt", 0)) <= 0 and at_war.call(fac, String(s.fac)):
			targets.append({"s": s, "value": float(Config.GOAL_RAID_VALUE.village), "range": Config.GOAL_RAID_RANGE})
	if ruins.is_valid():
		for s in ruins.call(fac):
			targets.append({"s": s, "value": float(Config.GOAL_RAID_VALUE.ruin), "range": Config.GOAL_RUIN_RANGE})
	for t in targets:
		var s: Dictionary = t.s
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		if d > float(t.range):
			continue
		var score := w * combine5(float(t.value), full, distance_factor(d, float(t.range)), risk_factor(foreign_risk(p, s.x, s.y, me), mods), crowd_factor("raid", s.id, p))
		if score > 0.0:
			out.append({"goal": "raid", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Whether the player's holdings are prey for p: player_target tells hostility even when the hero is away.
func _player_enemy(p: Dictionary) -> bool:
	var pl: Dictionary = player_target.call(p)
	return bool(pl.get("hostile", not pl.is_empty()))

## Full army of a party, for rest and raids.
static func full_strength_count(p: Dictionary) -> float:
	match String(p.get("kind", "")):
		"lord":
			return Config.GOAL_LORD_FULL * Rules.MK
		"vassal":
			return Config.GOAL_VASSAL_FULL * Rules.MK
	return Config.GOAL_PARTY_FULL * Rules.MK

## Strength of a full army: the same troops scaled to the full head count.
func full_strength(p: Dictionary) -> float:
	var n := 0
	for t in p.get("troops", []):
		n += int(t.n)
	if n <= 0:
		return 1.0
	return float(strength.call(p)) * full_strength_count(p) / n

## Rest and refill in an own settlement; vassals stand by villages and castles (towns are for lords).
func _rest(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "rest")
	if w <= 0.0:
		return
	var n := 0
	for t in p.troops:
		n += int(t.n)
	var need := ramp(1.0 - n / full_strength_count(p), Config.GOAL_REST_NEED.x, Config.GOAL_REST_NEED.y, Config.GOAL_REST_BASE, 1.0)
	var vassal: bool = p.kind == "vassal"
	var rest_range := Config.GOAL_REST_RANGE
	for s in own_settlements(String(p.fac)):
		if absf(s.x - p.x) > rest_range or absf(s.y - p.y) > rest_range:
			continue
		if vassal and s.kind == Config.SETTLEMENT_TOWN:
			continue
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		if d > rest_range:
			continue
		var place := Config.GOAL_REST_VILLAGE if s.kind == Config.SETTLEMENT_VILLAGE and not vassal else 1.0
		var score := w * combine4(need, place, distance_factor(d, Config.GOAL_REST_RANGE), risk_factor(risk_at(p, s.x, s.y, me), mods))
		if score > 0.0:
			out.append({"goal": "rest", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Escort of an own caravan in danger (#315, DESIGN.md §5.7): the outlaws it fears are felt at its place or ahead on its
## route (caravan_danger). Factors: the danger, whether the party turns it (no goal when even together with the caravan it is
## hopeless against what is felt, GOAL_ASSIST_ODDS), the distance and own parties already escorting it. A caravan is
## escorted through own lands only (an own settlement within GOAL_ESCORT_HOME): beyond them an escort would end far from
## home with nothing to do. Lords and faction vassals escort; the caravans come from `caravans` (a list of the step), else
## from the parties.
func _escort(p: Dictionary, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "escort")
	if w <= 0.0 or _map() == null:
		return
	var reach := Config.GOAL_ESCORT_RANGE
	var me := -1.0  # own strength only once a caravan in danger is in reach
	for c in (caravans.call() if caravans.is_valid() else parties):
		if c.kind != "caravan" or c.fac != p.fac or c.hide or absf(c.x - p.x) > reach or absf(c.y - p.y) > reach:
			continue
		var d := Vector2(c.x - p.x, c.y - p.y).length()
		if d > reach:
			continue
		var cd := caravan_danger(c)
		if float(cd.home) > Config.GOAL_ESCORT_HOME:
			continue
		var danger := ramp(float(cd.danger), Config.GOAL_ESCORT_DANGER.x, Config.GOAL_ESCORT_DANGER.y)
		if danger <= 0.0:
			continue
		if me < 0.0:
			me = strength.call(p)
		var odds := ramp((float(cd.own) + me) / maxf(0.001, float(cd.foe)), Config.GOAL_ASSIST_ODDS.x, Config.GOAL_ASSIST_ODDS.y)
		if odds <= 0.0:
			continue
		var score := w * combine4(danger, odds, distance_factor(d, reach), crowd_factor("escort", c.id, p))
		if score > 0.0:
			out.append({"goal": "escort", "gid": c.id, "x": c.x, "y": c.y, "score": score})

## Danger to a caravan (#315): the outlaws it fears (foes: bandits and the dead) felt on the threat map at its place and at
## points every GOAL_ESCORT_AHEAD_STEP ahead on its route, up to GOAL_ESCORT_AHEAD; the worst of them. Returns {danger: in
## caravan strengths, foe: that strength, own: the caravan's strength, home: distance to the nearest own settlement};
## worked out once per step and caravan.
func caravan_danger(c: Dictionary) -> Dictionary:
	var cached: Variant = _danger.get(c.id)
	if cached != null:
		return cached
	var own := maxf(0.001, float(strength.call(c)))
	var home := INF
	for s in own_settlements(String(c.fac)):
		home = minf(home, Vector2(s.x - c.x, s.y - c.y).length())
	var out := {"danger": 0.0, "foe": 0.0, "own": own, "home": home}
	var m := _map()
	if m != null:
		var fs := foes(c)
		var worst := m.threat(c.x, c.y, fs)
		var path: Array = c.get("path", [])
		var i := int(c.get("pi", 0))
		var at := Vector2(c.x, c.y)
		var walked := 0.0
		var mark := Config.GOAL_ESCORT_AHEAD_STEP
		while i < path.size() and mark <= Config.GOAL_ESCORT_AHEAD:
			var to: Vector2 = path[i]
			var seg := at.distance_to(to)
			while seg > 0.0 and walked + seg >= mark and mark <= Config.GOAL_ESCORT_AHEAD:
				var q := at.lerp(to, (mark - walked) / seg)
				worst = maxf(worst, m.threat(q.x, q.y, fs))
				mark += Config.GOAL_ESCORT_AHEAD_STEP
			walked += seg
			at = to
			i += 1
		out.danger = worst / own
		out.foe = worst
	_danger[c.id] = out
	return out

## Following a leader: a faction vassal its lord, a retinue the player (ctx.lead).
func _follow(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "follow")
	var lead: Dictionary = ctx.get("lead", {})
	if w <= 0.0 or lead.is_empty():
		return
	var d := Vector2(lead.x - p.x, lead.y - p.y).length()
	var keep := float(ctx.get("keep", Config.GOAL_FOLLOW_KEEP))
	var far := ramp(d, keep * 0.5, keep * 2.0, 0.5, 1.0)
	out.append({"goal": "follow", "gid": lead.get("id"), "x": lead.x, "y": lead.y, "score": w * far})

## A guarding retinue stays by its fief.
func _guard(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "guard")
	var fief: Dictionary = ctx.get("fief", {})
	if w <= 0.0 or fief.is_empty():
		return
	out.append({"goal": "guard", "gid": fief.id, "x": fief.x, "y": fief.y, "score": w})

## An undead army gathers at the rally point of its wave; less eagerly once it is there, so it still crushes weak
## enemies that come close (hunt).
func _muster(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "muster")
	var wave: Dictionary = ctx.get("wave", {})
	if w <= 0.0 or wave.is_empty() or String(wave.mode) != "gather":
		return
	var d := Vector2(float(wave.rx) - p.x, float(wave.ry) - p.y).length()
	var far := ramp(d, Config.UNDEAD_RALLY_RADIUS * 0.5, Config.UNDEAD_RALLY_RADIUS * 2.0, 0.4, 1.0)
	out.append({"goal": "muster", "gid": wave.tid, "x": float(wave.rx), "y": float(wave.ry), "score": w * far})

## An undead army marches on the target of its wave and waits at the walls for the storm.
func _assault(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "assault")
	var wave: Dictionary = ctx.get("wave", {})
	if w <= 0.0 or wave.is_empty() or String(wave.mode) != "attack":
		return
	out.append({"goal": "assault", "gid": wave.tid, "x": float(wave.x), "y": float(wave.y), "score": w})

## Undead raids burn living villages ahead of their wave: near its front (the target) and within reach of the raid. The
## dead weigh no risk (they never flee either): the front of a wave is where the living gather, and a raid that feared
## them would only roam.
func _ravage(p: Dictionary, _me: float, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "raid")
	var front: Dictionary = ctx.get("front", {})
	if w <= 0.0 or String(p.fac) != Config.UNDEAD_FACTION or front.is_empty():
		return
	for s in settles:
		if s.kind != Config.SETTLEMENT_VILLAGE or s.fac == Config.UNDEAD_FACTION or int(s.get("burnt", 0)) > 0:
			continue
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		var df := Vector2(s.x - float(front.x), s.y - float(front.y)).length()
		if d > Config.UNDEAD_RAVAGE_REACH or df > Config.UNDEAD_RAVAGE_RANGE:
			continue
		var score := w * combine([distance_factor(d, Config.UNDEAD_RAVAGE_REACH), distance_factor(df, Config.UNDEAD_RAVAGE_RANGE),
			crowd_factor("raid", s.id, p)])
		if score > 0.0:
			out.append({"goal": "raid", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Bandits roam around their camp; the dead with nothing else to do around their front (stage 2c).
func _roam(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "roam")
	if w <= 0.0:
		return
	var front: Dictionary = ctx.get("front", {})
	if not front.is_empty():
		out.append({"goal": "roam", "gid": p.get("home"), "x": float(front.x), "y": float(front.y), "score": w})
		return
	out.append({"goal": "roam", "gid": p.get("home"), "x": p.x, "y": p.y, "score": w})

# ---------- choice ----------

## Score of the party's current goal among `cands`, or -1 when the goal is gone or finished.
func current_score(p: Dictionary, cands: Array) -> float:
	var g := String(p.get("goal", ""))
	if g == "" or not goal_active(p):
		return -1.0
	for c in cands:
		if c.goal == g and c.gid == p.get("gid"):
			return float(c.score)
	return -1.0

## Whether the current goal is still being carried out: the state fits it and the work is not done.
static func goal_active(p: Dictionary) -> bool:
	var g := String(p.get("goal", ""))
	var moving: bool = p.pi < p.path.size()
	match g:
		"":
			return false
		"hunt":
			return p.state == "hunt"
		"flee":
			return p.state == "flee" and moving
	if p.state == "hunt" or p.state == "flee":
		return false
	return moving or float(p.get("wait", 0.0)) > 0.0

## Picks the goal to carry out: the current one while it holds (minimal time, margin), else a draw among the best.
## Returns {} to keep the current goal (or to stay idle when there is nothing to do).
func choose(p: Dictionary, cands: Array, rng: RandomNumberGenerator) -> Dictionary:
	if cands.is_empty():
		return {}
	var best: Dictionary = cands[0]
	var cur := current_score(p, cands)
	if cur >= 0.0:
		var held := float(p.get("ga", 0.0)) < Config.GOAL_HOLD_HOURS
		var urgent := float(best.score) >= Config.GOAL_URGENT_SCORE or String(best.goal) in REACTIVE
		if held and not urgent:
			return {}
		if float(best.score) <= cur * (1.0 + Config.GOAL_SWITCH_MARGIN):
			return {}
		if best.goal == p.get("goal") and best.gid == p.get("gid"):
			return {}
	var band: Array = cands.filter(func(c): return float(c.score) >= float(best.score) * Config.GOAL_PICK_BAND)
	if band.size() == 1:
		return best
	var total := 0.0
	for c in band:
		total += float(c.score)
	var r := rng.randf() * total
	for c in band:
		r -= float(c.score)
		if r <= 0.0:
			return c
	return band[band.size() - 1]

# ---------- flight ----------

## Where to flee from `from`: the own settlement that is clearly safer than here, with the least enemies around it and
## on the way, and not towards the enemy; else the safest threat-map cell nearby if it is safer than here; else straight
## away from the enemy. Returns {x, y, sid}.
## Since #313 an own lord or vassal in sight (`friends`, from scan) is a haven too, when together they stand up to the
## enemy (`foe`): its place and the way there are weighed in their joint strength, since it answers the call and comes to
## meet the fleeing party. Such a haven returns {x, y, sid: null, pid}.
func flee_target(p: Dictionary, from: Vector2, havens: Array, friends: Array = [], foe := 0.0) -> Dictionary:
	var me := own_strength(p)
	var here := Vector2(p.x, p.y)
	var here_risk := risk_at(p, here.x, here.y, me)
	var away := here - from
	var best: Dictionary = {}
	var best_cost := INF
	for h in havens:
		var at := Vector2(h.x, h.y)
		var d := here.distance_to(at)
		if d > Config.GOAL_FLEE_HAVEN_RANGE or d < 1.0:
			continue
		if away.length() > 0.0 and (at - here).dot(away) < 0.0 and at.distance_to(from) < here.distance_to(from):
			continue
		var risk := risk_at(p, at.x, at.y, me)
		if here_risk > 0.0 and risk >= here_risk * Config.GOAL_FLEE_SAFER:
			continue
		var mid := (here + at) * 0.5
		var cost := (risk + risk_at(p, mid.x, mid.y, me)) * Config.GOAL_FLEE_THREAT_COST + d / Config.GOAL_FLEE_HAVEN_RANGE
		if cost < best_cost:
			best_cost = cost
			best = {"x": at.x, "y": at.y, "sid": h.get("id")}
	var friend := _friend_haven(p, from, here_risk, friends, foe)
	if not friend.is_empty() and float(friend.cost) < best_cost:
		best = friend
	if not best.is_empty():
		best.erase("cost")
		return best
	var m := _map()
	if m != null:
		var points: Array = havens.map(func(h): return Vector2(h.x, h.y))
		var safe := m.safe_cell(p.x, p.y, Config.GOAL_FLEE_SAFE_RADIUS, String(p.fac), foes(p), points, passable)
		if safe.distance_to(here) > 1.0 and (risk_at(p, safe.x, safe.y, me) < here_risk or away.length() <= 0.0):
			return {"x": safe.x, "y": safe.y, "sid": null}
	var a := atan2(away.y, away.x) if away.length() > 0.0 else 0.0
	return {"x": clampf(p.x + cos(a) * Config.GOAL_FLEE_FALLBACK, Config.GOAL_MAP_MARGIN, width - Config.GOAL_MAP_MARGIN),
		"y": clampf(p.y + sin(a) * Config.GOAL_FLEE_FALLBACK, Config.GOAL_MAP_MARGIN, height - Config.GOAL_MAP_MARGIN), "sid": null}
