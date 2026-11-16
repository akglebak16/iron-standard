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
const Config = preload("res://core/campaign/config.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

## Goals that react to what a party sees; they may interrupt a plan before its hold time is over.
const REACTIVE := ["hunt", "flee"]
## Goals carried out by riding to a settlement or a point and lingering there.
const PLANS := ["defend", "patrol", "raid", "rest", "escort", "follow", "roam", "guard"]
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
var width := 5200.0
var height := 3400.0

## goal|gid|faction -> number of parties of the faction pursuing it; kept by note()/rebuild_claims().
var claims := {}
var _own := {}  # faction -> own settlements, until reset()

## Forgets per-step caches; call when parties or settlements may have changed (every world step).
func reset() -> void:
	_own = {}

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

static func distance_factor(d: float, range_: float) -> float:
	return 1.0 - Config.GOAL_DISTANCE_FALLOFF * clamp01(d / maxf(1.0, range_))

func crowd_factor(goal: String, gid: Variant, p: Dictionary) -> float:
	var n := int(claims.get(_claim_key(goal, gid, String(p.fac)), 0))
	if goal_key(p) == _claim_key(goal, gid, String(p.fac)):
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
	return "%s|%s|%s" % [goal, gid, fac]

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
	var all := _enemies(String(p.fac))
	if not bool(profile(p).get("outlaws_only", false)):
		return all
	return all.filter(func(f): return f == Config.BANDIT_FACTION or f == Config.UNDEAD_FACTION)

## Enemy strength felt at (x, y) on the threat map, in strengths of a party of strength `me`.
func risk_at(p: Dictionary, x: float, y: float, me: float, minus := 0.0) -> float:
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
## lord (the vassal's lord party), mode (retinue order), haven_extra ([{id, x, y}] havens besides own settlements).
func candidates(p: Dictionary, ctx := {}) -> Array:
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
	_defend(p, me, prof, mods, out)
	_patrol(p, prof, mods, ctx, out)
	_raid(p, me, prof, mods, out)
	_rest(p, me, prof, mods, out)
	_escort(p, prof, mods, out)
	_follow(p, prof, mods, ctx, out)
	_guard(p, prof, mods, ctx, out)
	_roam(p, prof, mods, out)
	_sort(out)
	return out

static func _sort(out: Array) -> void:
	out.sort_custom(func(a, b): return a.score > b.score)

## Parties in sight: weaker ones as prey, the pressure of stronger ones (1 = an enemy `flee_ratio` times stronger).
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
	var from := Vector2(p.x, p.y)
	var look := maxf(sight, flee_sight)
	for o in parties:
		if o == p or o.hide or o.kind == "camp" or o.get("lock", false) or (skip_busy and o.get("fight", false)):
			continue
		var d := Vector2(o.x - p.x, o.y - p.y).length()
		if d > look or not hostile.call(p, o):
			continue
		var so: float = strength.call(o)
		if so < me * hunt_ratio:
			if d <= sight and (leash <= 0.0 or fief.is_empty() or Vector2(o.x - fief.x, o.y - fief.y).length() <= leash):
				prey.append({"party": o, "d": d, "strength": so})
		elif so > me * flee_ratio and d < flee_sight and not army:
			var k := so / (me * flee_ratio)
			if k > pressure:
				pressure = k
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
					from = Vector2(pl.x, pl.y)
	return {"prey": prey, "pressure": pressure, "from": from, "sight": sight}

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
		var s := w * combine([adv, worth, distance_factor(float(e.d), float(seen.sight)), catch, crowd_factor("hunt", o.id, p), risk])
		if s > 0.0:
			out.append({"goal": "hunt", "gid": o.id, "x": o.x, "y": o.y, "score": s})

## Fleeing scores by the pressure of stronger enemies in sight and on the threat map. A flight already under way
## keeps a residual score until its hold time is over, so a party does not turn back at the edge of sight.
func _flee(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, seen: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "flee")
	if w <= 0.0:
		return
	var pressure := float(seen.pressure)
	if bool(prof.get("map_pressure", true)):
		pressure = maxf(pressure, risk_at(p, p.x, p.y, me) * Config.GOAL_FLEE_MAP_SHARE / float(prof.flee_ratio))
	var s := 0.0
	if pressure > 1.0:
		s = w * ramp(pressure, 1.0, Config.GOAL_FLEE_FULL_PRESSURE, 0.5, 1.0)
	elif p.get("goal", "") == "flee" and goal_active(p) and float(p.get("ga", 0.0)) < Config.GOAL_HOLD_HOURS:
		s = w * Config.GOAL_FLEE_RESIDUAL
	if s > 0.0:
		out.append({"goal": "flee", "gid": null, "x": float(seen.from.x), "y": float(seen.from.y), "score": s})

## Own settlements a party belongs to (not camps): the settlements of its faction.
func own_settlements(fac: String) -> Array:
	if not _own.has(fac):
		_own[fac] = settles.filter(func(s): return s.fac == fac and s.kind != "camp")
	return _own[fac]

func _defend(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "defend")
	if w <= 0.0:
		return
	for s in own_settlements(String(p.fac)):
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		if d > Config.GOAL_DEFEND_RANGE:
			continue
		var enemy := risk_at(p, s.x, s.y, me)
		var urgency := 1.0 if s.get("siege") != null else clamp01(enemy / Config.GOAL_DEFEND_THREAT_SHARE)
		if urgency <= 0.0:
			continue
		var score := w * combine([urgency, distance_factor(d, Config.GOAL_DEFEND_RANGE), risk_factor(enemy, mods), crowd_factor("defend", s.id, p)])
		if score > 0.0:
			out.append({"goal": "defend", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Patrol of own lands, more often where enemies were seen lately (s.alarm hours, kept by party_ai.gd hour_tick).
func _patrol(p: Dictionary, prof: Dictionary, mods: Dictionary, ctx: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "patrol")
	if w <= 0.0:
		return
	var fief: Dictionary = ctx.get("fief", {})
	var centre := Vector2(p.x, p.y) if fief.is_empty() else Vector2(fief.x, fief.y)
	var reach := Config.GOAL_PATROL_RANGE if fief.is_empty() else Config.GOAL_RETINUE_PATROL_RANGE.y
	for s in own_settlements(String(p.fac)):
		var d := Vector2(s.x - centre.x, s.y - centre.y).length()
		if d > reach:
			continue
		var alarm := ramp(float(s.get("alarm", 0)), 0.0, float(Config.GOAL_ALARM_HOURS), Config.GOAL_PATROL_BASE, 1.0)
		var score := w * combine([alarm, distance_factor(d, reach), crowd_factor("patrol", s.id, p)])
		if score > 0.0:
			out.append({"goal": "patrol", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Raids: enemy villages of a faction at war, the player's holdings when he is an enemy, own ruins held by the dead.
func _raid(p: Dictionary, me: float, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "raid")
	if w <= 0.0:
		return
	var full := ramp(float(strength.call(p)) / maxf(0.001, full_strength(p)), Config.GOAL_RAID_FULL_SHARE.x, Config.GOAL_RAID_FULL_SHARE.y)
	if full <= 0.0:
		return
	var fac := String(p.fac)
	var targets: Array = []
	for s in settles:
		if s.fac == fac or s.kind == "camp" or s.get("siege") != null:
			continue
		if s.fac == Config.PLAYER_FACTION:
			if player_target.is_valid() and _player_enemy(p):
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
		var score := w * combine([float(t.value), full, distance_factor(d, float(t.range)), risk_factor(foreign_risk(p, s.x, s.y, me), mods), crowd_factor("raid", s.id, p)])
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
	for s in own_settlements(String(p.fac)):
		if vassal and s.kind == Config.SETTLEMENT_TOWN:
			continue
		var d := Vector2(s.x - p.x, s.y - p.y).length()
		if d > Config.GOAL_REST_RANGE:
			continue
		var place := Config.GOAL_REST_VILLAGE if s.kind == Config.SETTLEMENT_VILLAGE and not vassal else 1.0
		var score := w * combine([need, place, distance_factor(d, Config.GOAL_REST_RANGE), risk_factor(risk_at(p, s.x, s.y, me), mods)])
		if score > 0.0:
			out.append({"goal": "rest", "gid": s.id, "x": s.x, "y": s.y, "score": score})

## Guarding an own caravan that has enemies around it.
func _escort(p: Dictionary, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "escort")
	if w <= 0.0 or _map() == null:
		return
	for c in parties:
		if c.kind != "caravan" or c.fac != p.fac or c.hide:
			continue
		var d := Vector2(c.x - p.x, c.y - p.y).length()
		if d > Config.GOAL_ESCORT_RANGE:
			continue
		var danger := ramp(risk_at(c, c.x, c.y, maxf(0.001, strength.call(c))), Config.GOAL_ESCORT_DANGER.x, Config.GOAL_ESCORT_DANGER.y)
		if danger <= 0.0:
			continue
		var score := w * combine([danger, distance_factor(d, Config.GOAL_ESCORT_RANGE), crowd_factor("escort", c.id, p)])
		if score > 0.0:
			out.append({"goal": "escort", "gid": c.id, "x": c.x, "y": c.y, "score": score})

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

## Bandits roam around their camp.
func _roam(p: Dictionary, prof: Dictionary, mods: Dictionary, out: Array) -> void:
	var w := weight(prof, mods, "roam")
	if w <= 0.0:
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
func flee_target(p: Dictionary, from: Vector2, havens: Array) -> Dictionary:
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
	if not best.is_empty():
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
