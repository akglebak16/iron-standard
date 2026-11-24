extends RefCounted
## Map-party AI: goals of parties, resting in settlements and auto-resolved fights between parties (aiParty, vassalIdle,
## vassalRest, cvAI, autoFight, stepWorld in src/05_world.js and src/05h_vassals.js).
## Since stage 2a (docs/modules/ai/DESIGN.md §5.2, ADR-023) every party picks a goal through party_goals.gd — lords,
## faction vassals, the player's retinues (orders of world_vassals.gd are weight sets), bandits, caravans and the dead —
## and this file carries the goal out: routes, chases, arrivals. Faction campaigns are operations of world_wars.gd (stage 2b).
## The dead follow the director of the invasion (stage 2c, world_undead.gd): their wave and front come in the context.
## Help in battle (#312, DESIGN.md §5.7): the running fights of world_skirmish reach the evaluator as a list built once per
## step on first request; a helper rides to the fight and hour_tick takes it in once it is close.
## Calls for help (#313): lords and vassals that a stronger enemy chases or that flee call; the calls are gathered in the
## same pass over the parties as the fights (`_beacons`), and an own party that answers rides to the caller (`rescue`).
## Caravan escort (#315): the same pass lists the caravans for the escort goal of lords and vassals, and a caravan that an
## outlaw hunts or that flees calls like a lord.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const Config = preload("res://core/campaign/config.gd")
const Goals = preload("res://core/campaign/world/party_goals.gd")
const Skirmish = preload("res://core/campaign/world/world_skirmish.gd")

const WW := 5200.0
const WH := 3400.0

const CONTACT_REACH := 15.0 # parties closer than this meet on the map (fight if hostile)
var roster: Roster
var player: RefCounted  # PlayerParty: x, y, troops, rel, busy, inside, away

var undead: RefCounted = null  # WorldUndead, optional
var clans: RefCounted = null   # WorldClans, optional: rulers survive lost fights
var vassals: RefCounted = null  # WorldVassals, optional: the player's retinues
var skirmish: RefCounted = null # WorldSkirmish, optional: fights lasting hours, rallying neighbours
var goals := Goals.new()
var threat_map: Callable = Callable()  # () -> ThreatMap (WorldState.threat_map), optional
var native: RefCounted = null          # optional port of the native world kernel (ADR-025): contact pairs
var enemies: Callable = Callable()     # (faction) -> hostile factions on the threat map, optional

var _map_cache: RefCounted = null
var _enemy_cache := {}
var _doom_cache: Variant = null
var _battle_cache: Variant = null
var _call_cache: Variant = null  # calls for help of the step, with _battle_cache (_beacons)
var _caravan_cache: Array = []   # caravans on the map, with _call_cache (_beacons)
var _caught := {}                # lord or vassal id -> the party, while it is in a fight (an answer rides on to it)
var _call_of := {}               # caller id -> its call
var _answers := {}               # caller id -> own parties riding to it (goal "rescue")

func _init(r: Roster, p: RefCounted) -> void:
	roster = r
	player = p
	goals.width = WW
	goals.height = WH
	goals.strength = roster.strength_of
	goals.speed = roster.speed_of
	goals.hostile = roster.hostile
	goals.at_war = _at_war
	goals.allies = _allies
	goals.player_target = _player_target
	goals.ruins = _ruins
	goals.passable = _passable
	goals.threat_map = _threat
	goals.enemies = _enemies_of
	goals.doomed = _doomed
	goals.battles = _battles
	goals.calls = _calls
	goals.call_detail = _call_detail
	goals.caravans = _caravans

## Breaks the links to the world so a disposed campaign is freed.
func dispose() -> void:
	goals = Goals.new()
	threat_map = Callable()
	enemies = Callable()
	_map_cache = null
	_enemy_cache = {}
	_doom_cache = null
	_battle_cache = null
	_call_cache = null
	_caravan_cache = []
	_caught = {}
	_call_of = {}
	_answers = {}

func _at_war(a: String, b: String) -> bool:
	return Rules.at_war(a, b, roster.diplomatic_wars)

func _allies(p: Dictionary) -> float:
	return skirmish.ally_strength(p) if skirmish != null else 0.0

func _ruins(f: String) -> Array:
	return undead.ruins_for(f) if undead != null else []

## Running fights for help in battle (#312); cached per world step like the threat map. Fights change only in the
## contact phase and in hour_tick, both after the evaluations of the step.
func _battles() -> Array:
	_beacons()
	return _battle_cache

## Calls for help of the step (#313): [{id, fac, x, y}]; what the call needs (own, foe, left) comes from _call_detail.
func _calls() -> Array:
	_beacons()
	return _call_cache

## Caravans on the map for the escort goal (#315), cached per world step with the calls.
func _caravans() -> Array:
	_beacons()
	return _caravan_cache

## The beacons of a world step (DESIGN.md §5.7.2), built on first request in one pass over the parties: the fighters for
## WorldSkirmish.battles, the hunters and the fleeing lords and vassals for the calls, the caravans for the escort (#315).
## A caller is a free lord, vassal or caravan (not hidden, locked or in a fight) that hostile parties hunt or that flees.
## The same pass notes who already rides to which caller (`_answers`). Only reads; strengths and the threat map are asked
## for in _call_detail, when somebody who could answer is near.
func _beacons() -> void:
	if _call_cache != null:
		return
	var fighters: Array = []
	var hunters := {}  # hunted party id -> its hunters
	var free := {}     # party id -> a free lord or vassal
	var fleeing: Array = []
	_caravan_cache = []
	for p in roster.parties:
		if p.get("fight"):
			fighters.append(p)
			if Rules.is_noble(p):
				_caught[p.id] = p  # caught already: an answer rides on to its fight
			continue
		var st = p.get("state")
		if st == "roam" and p.get("goal") == "rescue":
			var g = p.get("gid")
			if _answers.has(g):
				_answers[g].append(p)
			else:
				_answers[g] = [p]
		if st == "hunt":
			var t = p.get("tid")
			if t != null:
				if hunters.has(t):
					hunters[t].append(p)
				else:
					hunters[t] = [p]
		var caravan: bool = p.kind == "caravan"
		if (caravan or Rules.is_noble(p)) and not p.hide and not p.get("lock", false):
			free[p.id] = p
			if caravan:
				_caravan_cache.append(p)
			if st == "flee":
				fleeing.append(p)
	_battle_cache = skirmish.battles(fighters) if skirmish != null else []
	_call_cache = []
	for id in hunters:
		var c: Dictionary = free.get(id, {})
		if not c.is_empty():
			_call(c, hunters[id])
	for c in fleeing:
		if not hunters.has(c.id):
			_call(c, [])

func _call(c: Dictionary, hunters: Array) -> void:
	var e := {"id": c.id, "fac": c.fac, "x": c.x, "y": c.y, "party": c, "hunters": hunters}
	_call_cache.append(e)
	_call_of[c.id] = e

## What a call needs, worked out once per step and only for calls somebody could answer: the caller's strength (`own`),
## its enemy (`foe`: the hunters, or for a flight without hunters the enemies felt around it on the threat map — for a
## caravan only the outlaws it fears), `left` (hours until the nearest hunter reaches it standing and its side breaks,
## WorldSkirmish.hours_left; a small party against small hunters and a caravan are settled at once) and the nearest hunter
## (`fx`, `fy`). {} when the caller is not the weaker one: then it is no call.
func _call_detail(e: Dictionary) -> Dictionary:
	if e.has("own"):
		return e
	if e.has("none"):
		return {}
	var c: Dictionary = e.party
	var hunters: Array = e.hunters
	var own := maxf(0.001, roster.strength_of(c))
	var foe := 0.0
	var reach := INF
	var caravan: bool = c.kind == "caravan"
	var small := caravan or Rules.troop_count(c.troops) < 12 * Rules.MK
	var near: Dictionary = {}
	for h in hunters:
		foe += roster.strength_of(h)
		var t := _dist(h, c) / maxf(0.001, roster.speed_of(h))
		if t < reach:
			reach = t
			near = h
		small = caravan or (small and Rules.troop_count(h.troops) < 12 * Rules.MK)
	if hunters.is_empty():
		var m: RefCounted = _threat()
		if m != null:
			foe = m.threat(c.x, c.y, goals.foes(c) if caravan else _enemies_of(String(c.fac)))
		reach = 0.0
	if foe <= own:
		e.none = true
		return {}
	var men := Rules.troop_count(c.troops)
	e.own = own
	e.foe = foe
	e.left = reach + (0.0 if small else Skirmish.hours_left(men, float(men), foe / own))
	if not near.is_empty():
		e.fx = near.x  # the nearest hunter: a flight does not run past it
		e.fy = near.y
	return e

## Towns and castles the undead waves go for (stage 2c); cached per world step like the threat map.
func _doomed() -> Dictionary:
	if _doom_cache == null:
		_doom_cache = undead.doomed() if undead != null else {}
	return _doom_cache

func _passable(c: Vector2) -> bool:
	return roster.map.paths.passable_type(roster.map.paths.terr_at(c.x, c.y))

func _threat() -> RefCounted:
	if _map_cache == null and threat_map.is_valid():
		_map_cache = threat_map.call()
	return _map_cache

func _enemies_of(f: String) -> Array:
	if not _enemy_cache.has(f):
		_enemy_cache[f] = enemies.call(f) if enemies.is_valid() else []
	return _enemy_cache[f]

## The player's party as seen by p: {} when p is not hostile to him, {hostile} when he cannot be attacked now,
## {hostile, x, y, strength} when he can.
func _player_target(p: Dictionary) -> Dictionary:
	if player == null or p.kind == "cvass" or not Rules.hostile_to_player(p, player.rel):
		return {}
	if not _player_prey():
		return {"hostile": true}
	return {"hostile": true, "x": player.x, "y": player.y, "strength": Rules.strength(player.troops, roster.info) + Config.GOAL_PLAYER_STRENGTH_BONUS}

func _fresh() -> void:
	goals.parties = roster.parties
	goals.settles = roster.map.settles
	goals.reset()
	_map_cache = null
	_enemy_cache = {}
	_doom_cache = null
	_battle_cache = null
	_call_cache = null
	_caravan_cache = []
	_caught = {}
	_call_of = {}
	_answers = {}

func step(dh: float) -> void:
	_fresh()
	goals.rebuild_claims()
	for p in roster.parties.duplicate():
		if p in roster.parties:
			ai_party(p, dh)
	var list := roster.parties.duplicate()
	if native != null:
		_contacts_native(list)
	else:
		_contacts(list)

## The contact phase: parties closer than CONTACT_REACH fight if hostile, each at most once per step (the reference).
func _contacts(list: Array) -> void:
	for i in list.size():
		var a: Dictionary = list[i]
		if _skip_fight(a) or not (a in roster.parties):
			continue
		var ax: float = a.x
		var ay: float = a.y
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			# Reject distant pairs before reading flags and searching the roster.
			# Potential contacts keep the original distance and iteration order.
			var dx: float = ax - b.x
			if absf(dx) >= CONTACT_REACH or not (Vector2(dx, ay - b.y).length() < CONTACT_REACH):
				continue
			if _skip_fight(b) or not (b in roster.parties):
				continue
			if roster.hostile(a, b):
				if skirmish != null:
					skirmish.contact(a, b, auto_fight)
				else:
					auto_fight(a, b)
				break

## The contact phase with the pairs found by the native kernel: the same pairs, checks and order as the loop in step.
func _contacts_native(list: Array) -> void:
	var n := list.size()
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	xs.resize(n)
	ys.resize(n)
	for i in n:
		xs[i] = list[i].x
		ys[i] = list[i].y
	var pairs: PackedInt32Array = native.contact_pairs(xs, ys, CONTACT_REACH)
	var k := 0
	var count := pairs.size()
	while k < count:
		var i := pairs[k]
		var a: Dictionary = list[i]
		var open := not _skip_fight(a) and a in roster.parties
		while k < count and pairs[k] == i:
			var b: Dictionary = list[pairs[k + 1]]
			k += 2
			if not open or _skip_fight(b) or not (b in roster.parties):
				continue
			if roster.hostile(a, b):
				if skirmish != null:
					skirmish.contact(a, b, auto_fight)
				else:
					auto_fight(a, b)
				open = false
				# A fight settled on the spot may send a beaten ruler home (clans.ruler_home): the reference loop sees
				# him there in the next rows, so the pairs of those rows are searched again from the new positions.
				if _moved(list, xs, ys):
					pairs = native.contact_pairs(xs, ys, CONTACT_REACH)
					count = pairs.size()
					k = 0
					while k < count and pairs[k] <= i:
						k += 2

## Whether a party of `list` stands elsewhere than in the columns; the columns are brought up to date.
static func _moved(list: Array, xs: PackedFloat64Array, ys: PackedFloat64Array) -> bool:
	var moved := false
	for j in list.size():
		var q: Dictionary = list[j]
		if xs[j] != q.x or ys[j] != q.y:
			xs[j] = q.x
			ys[j] = q.y
			moved = true
	return moved

## Hourly: settlements remember enemies seen around them (s.alarm, saved with the settlement); patrols go there.
func hour_tick() -> void:
	_fresh()
	var m: RefCounted = _threat()
	if m == null:
		return
	var doom := _doomed()
	for s in roster.map.settles:
		if s.kind == "camp":
			continue
		if doom.has(s.id) or m.threat(s.x, s.y, _enemies_of(String(s.fac))) >= Config.GOAL_ALARM_MIN_THREAT:
			s.alarm = Config.GOAL_ALARM_HOURS
		elif int(s.get("alarm", 0)) > 0:
			s.alarm = int(s.alarm) - 1

func _skip_fight(p: Dictionary) -> bool:
	return p.hide or p.kind == "camp" or p.get("lock", false) or p.get("fight", false)

func _dist(a, b) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

func _player_prey() -> bool:
	return not (player.inside or player.away or player.busy != "")

func ai_party(p: Dictionary, dh: float) -> void:
	if p.kind == "camp":
		return
	p.cd -= dh
	var ctx := {}
	if p.kind == "cvass":
		if vassals == null or p.get("fight", false):
			return
		ctx = vassals.retinue_context(p)
		if ctx.is_empty():
			roster.remove(p)
			return
	else:
		if p.get("lock", false) or p.get("fight", false):
			return
		if p.hide:
			_rest_inside(p, dh)
			return
	p.ga = float(p.get("ga", 0.0)) + dh
	p.ai = float(p.get("ai", 0.0)) - dh
	if p.ai <= 0.0:
		p.ai = roster.rnd(Config.GOAL_THINK_HOURS.x, Config.GOAL_THINK_HOURS.y)
		if _think(p, ctx):
			return
	if p.state == "hunt":
		_chase(p, dh)
	elif p.state == "flee" and p.get("goal", "") == "flee" and (Rules.is_noble(p) or p.kind == "caravan"):
		_meet(p, dh)
	elif p.get("goal", "") == "escort":
		_escort(p, dh)
	elif p.get("goal", "") == "assist":
		_assist(p)
	elif p.get("goal", "") == "rescue":
		_rescue(p, dh)
	if p.pi < p.path.size():
		if roster.move_along(p, dh):
			_arrived(p)
	elif p.state == "travel" and p.kind == "caravan":
		var s := roster.map.settlement_by_id(p.sid) if p.sid != null else {}
		if s.is_empty():
			roster.remove(p)
		else:
			roster.path_to(p, s.x, s.y)

## Resting inside a settlement; on leaving, the party tops up its troops there.
func _rest_inside(p: Dictionary, dh: float) -> void:
	p.wait -= dh
	if p.wait > 0.0:
		return
	p.hide = false
	var h := roster.map.settlement_by_id(p.home) if p.home != null else {}
	if not h.is_empty():
		var lord: bool = p.kind == "lord"
		var need := (Config.GOAL_LORD_FULL if lord else Config.GOAL_PARTY_FULL) * Rules.MK - Rules.troop_count(p.troops)
		if need > 0.0 and h.fac == p.fac:
			var n := mini(ceili(need / Rules.MK), roster.rint(10, 25) if lord else roster.rint(4, 10))
			for a in roster.gen_troops(p.fac, n, 0.6):
				Rules.add_troops(p.troops, a.type, a.n)
	if p.kind == "lord":
		p.state = "idle"

## Context of the evaluator for this party: campaign membership, the vassal's lord, havens.
func _context(p: Dictionary, ctx: Dictionary) -> Dictionary:
	ctx.army = p.get("army", false)
	if p.kind == "vassal":
		var lord := roster.party_by_id(p.lid) if p.get("lid") != null else {}
		if lord.is_empty() or lord.fac != p.fac:
			var ls := roster.parties.filter(func(q): return q.kind == "lord" and q.fac == p.fac)
			lord = roster.pick(ls) if not ls.is_empty() else {}
			p.lid = lord.id if not lord.is_empty() else null
		if not lord.is_empty():
			ctx.lead = {"id": lord.id, "x": lord.x, "y": lord.y}
	elif p.kind == "bandit":
		var c := roster.map.settlement_by_id(p.home) if p.home != null else {}
		if not c.is_empty():
			ctx.havens = [{"id": c.id, "x": c.x, "y": c.y}]
	elif p.fac == Config.UNDEAD_FACTION and undead != null:
		ctx.wave = undead.wave_of(p)
		ctx.front = undead.front_of(p)
	return ctx

## Re-evaluates the goal. Returns true when the party took a new goal this tick.
func _think(p: Dictionary, ctx: Dictionary) -> bool:
	goals.parties = roster.parties
	goals.settles = roster.map.settles
	ctx = _context(p, ctx)
	if p.get("goal", "") != "" and p.state == "idle" and p.pi >= p.path.size() and float(p.get("wait", 0.0)) > 0.0:
		p.wait = float(p.wait) - Config.GOAL_WAIT_PER_THINK
	var old_key := Goals.goal_key(p)
	var cands := goals.candidates(p, ctx)
	var pick := goals.choose(p, cands, roster.rng)
	if pick.is_empty():
		if goals.current_score(p, cands) >= 0.0:
			return false
		_clear_goal(p)
		goals.note(old_key, p)
		if p.state == "hunt" or p.state == "flee":
			p.state = "idle"
			p.tid = null
			p.tpl = false
			p.path = []
		if p.state == "idle" and p.pi >= p.path.size() and not ctx.army:
			_idle(p)
		return false
	_apply(p, pick, ctx)
	goals.note(old_key, p)
	return true

func _clear_goal(p: Dictionary) -> void:
	p.goal = ""
	p.gid = null
	p.gs = 0.0

## Parties without plans of their own when nothing is to be done: the dead go where world_undead.gd sends them,
## caravans resume their trade route, lords of a faction without settlements wait.
func _idle(p: Dictionary) -> void:
	if p.fac == "undead":
		p.wait -= Config.GOAL_WAIT_PER_THINK
		if p.wait <= 0.0 and undead != null:
			undead.idle(p)
		return
	match p.kind:
		"caravan":
			p.state = "travel"
		"lord", "vassal":
			p.wait = 5.0

func _apply(p: Dictionary, c: Dictionary, ctx: Dictionary) -> void:
	p.goal = c.goal
	p.gid = c.gid
	p.ga = 0.0
	p.gs = c.score
	p.wait = 0.0
	if c.goal == "defend" and c.get("inside", false):
		var t: Dictionary = roster.map.settlement_by_id(c.gid)  # the dead go for it: hold its walls from the inside
		p.tid = null
		p.tpl = false
		p.sid = t.id
		p.state = "travel"
		roster.path_to(p, t.x, t.y)
		return
	match String(c.goal):
		"hunt":
			var pl: bool = c.gid == Goals.PLAYER_ID
			p.tid = null if pl else c.gid
			p.tpl = pl
			p.state = "hunt"
			roster.path_to(p, c.x, c.y)
			if skirmish != null and not pl and not ctx.army:
				var t := roster.party_by_id(c.gid)
				if not t.is_empty():
					skirmish.rally(p, t)
		"flee":
			_flee(p, Vector2(c.x, c.y), ctx, c.get("friends", []), float(c.get("foe", 0.0)))
		"rest", "raid", "assault":
			var s: Dictionary = roster.map.settlement_by_id(c.gid)
			p.tid = null
			p.tpl = false
			p.sid = s.id
			p.state = "travel"
			if p.kind == "vassal":
				roster.path_to(p, s.x + roster.rnd(-15, 15), s.y + 24.0)
			else:
				roster.path_to(p, s.x, s.y)
		"muster":
			_roam_to(p, c.x, c.y, Config.UNDEAD_MUSTER_SPREAD)
		"patrol", "defend":
			var s: Dictionary = roster.map.settlement_by_id(c.gid)
			var r := Config.GOAL_PATROL_OFFSET
			if c.goal == "defend":
				r = Vector2(Config.GOAL_DEFEND_OFFSET * 0.5, Config.GOAL_DEFEND_OFFSET)
			elif p.kind == "cvass":
				r = Config.GOAL_RETINUE_PATROL_RANGE
			_roam_to(p, s.x, s.y, r)
		"escort":
			p.tid = null
			p.state = "roam"
			roster.path_to(p, c.x, c.y)
		"assist":
			p.tid = null
			p.tpl = false
			p.state = "roam"
			roster.path_to(p, c.x, c.y)
		"rescue":
			p.tid = null
			p.tpl = false
			p.state = "roam"
			p.rp = Config.GOAL_CHASE_REPATH_HOURS
			roster.path_to(p, c.x, c.y)
		"follow":
			if p.kind == "cvass":
				if _dist(player, p) > Config.GOAL_RETINUE_FOLLOW_KEEP:
					p.state = "roam"
					roster.path_to(p, player.x + roster.rnd(-40, 40), player.y + roster.rnd(20, 50))
			elif _dist(c, p) > Config.GOAL_FOLLOW_KEEP:
				var a := roster.rnd(0.0, TAU)
				var tx := clampf(c.x + cos(a) * Config.GOAL_FOLLOW_OFFSET, Config.GOAL_MAP_MARGIN, WW - Config.GOAL_MAP_MARGIN)
				var ty := clampf(c.y + sin(a) * Config.GOAL_FOLLOW_OFFSET + 20.0, Config.GOAL_MAP_MARGIN, WH - Config.GOAL_MAP_MARGIN)
				if roster.path_to(p, tx, ty):
					p.state = "roam"
		"guard":
			var far := Vector2(c.x - p.x, c.y - p.y).length() > Config.GOAL_RETINUE_GUARD_FAR
			if far or roster.rng.randf() < Config.GOAL_RETINUE_GUARD_WANDER:
				var a := roster.rnd(0.0, TAU)
				var r := 20.0 if far else roster.rnd(Config.GOAL_RETINUE_GUARD_RANGE.x, Config.GOAL_RETINUE_GUARD_RANGE.y)
				if roster.path_to(p, clampf(c.x + cos(a) * r, Config.GOAL_MAP_MARGIN, WW - Config.GOAL_MAP_MARGIN), clampf(c.y + 22 + sin(a) * r, Config.GOAL_MAP_MARGIN, WH - Config.GOAL_MAP_MARGIN)):
					p.state = "roam"
		"roam":
			if p.fac == Config.UNDEAD_FACTION:
				_roam_to(p, c.x, c.y, Config.UNDEAD_ROAM_RANGE)  # around the front of its barrow
				return
			var h := roster.map.settlement_by_id(p.home) if p.home != null else {}
			_roam_to(p, h.x if not h.is_empty() else p.x, h.y if not h.is_empty() else p.y, Config.GOAL_ROAM_RANGE)

## Rides to a random passable point at distance r.x..r.y from (x, y); a few tries, then stays.
func _roam_to(p: Dictionary, x: float, y: float, r: Vector2) -> void:
	p.tid = null
	p.tpl = false
	p.state = "roam"
	for i in Config.GOAL_ROAM_TRIES:
		var a := roster.rnd(0.0, TAU)
		var d := roster.rnd(r.x, r.y)
		var tx := clampf(x + cos(a) * d, Config.GOAL_MAP_MARGIN, WW - Config.GOAL_MAP_MARGIN)
		var ty := clampf(y + sin(a) * d, Config.GOAL_MAP_MARGIN, WH - Config.GOAL_MAP_MARGIN)
		if _passable(Vector2(tx, ty)) and roster.path_to(p, tx, ty):
			return
	p.path = []
	p.pi = 0

## Flight to a safe own place (DESIGN.md §5.1): an own settlement away from the enemy, a strong own party in sight (#313),
## else the safest cell nearby.
func _flee(p: Dictionary, from: Vector2, ctx: Dictionary, friends: Array = [], foe := 0.0) -> void:
	var havens: Array = []
	for s in goals.own_settlements(String(p.fac)):
		havens.append({"id": s.id, "x": s.x, "y": s.y})
	havens.append_array(ctx.get("havens", []))
	var t := goals.flee_target(p, from, havens, friends, foe)
	p.tid = null
	p.tpl = false
	p.state = "flee"
	if roster.path_to(p, t.x, t.y):
		return
	var a := atan2(p.y - from.y, p.x - from.x)
	roster.path_to(p, clampf(p.x + cos(a) * Config.GOAL_FLEE_FALLBACK, Config.GOAL_MAP_MARGIN, WW - Config.GOAL_MAP_MARGIN), clampf(p.y + sin(a) * Config.GOAL_FLEE_FALLBACK, Config.GOAL_MAP_MARGIN, WH - Config.GOAL_MAP_MARGIN))

func _chase(p: Dictionary, dh: float) -> void:
	if p.get("tpl", false):
		if not _player_prey() or _dist(player, p) > Config.GOAL_PLAYER_DROP:
			p.state = "idle"
			p.path = []
			p.tpl = false
		else:
			p.rp -= dh
			if p.rp <= 0.0:
				p.rp = Config.GOAL_CHASE_REPATH_HOURS
				roster.path_to(p, player.x, player.y)
	else:
		var t := roster.party_by_id(p.tid)
		if t.is_empty() or t.hide:
			p.state = "idle"
			p.path = []
		else:
			p.rp -= dh
			if p.rp <= 0.0:
				p.rp = Config.GOAL_CHASE_REPATH_HOURS
				roster.path_to(p, t.x, t.y)

## Help in battle: the ride ends when the fight is over before the party got there. Only the ride: after its own fight
## a helper keeps what world_skirmish gave it (a loser flees).
func _assist(p: Dictionary) -> void:
	if p.state != "roam" or (skirmish != null and skirmish.has_fight(p.get("gid"))):
		return
	p.path = []
	p.pi = 0
	p.wait = 0.0
	p.state = "idle"

## Answer to a call for help (#313): rides to the caller, re-planned as it moves (the caller runs to meet it), and on to its
## fight when it is caught. The ride ends when the call is over: the caller is safe, inside, or gone. Only the ride: after
## its own fight a helper keeps what world_skirmish gave it (a loser flees).
func _rescue(p: Dictionary, dh: float) -> void:
	if p.state == "hunt" or p.state == "flee":
		return
	_beacons()
	var c: Dictionary = _caught.get(p.get("gid"), {})
	var e: Variant = _call_of.get(p.get("gid"))
	if e != null and not _call_detail(e).is_empty():
		c = e.party
	if c.is_empty():
		if p.state == "roam":
			p.path = []
			p.pi = 0
			p.state = "idle"
		p.wait = 0.0
		return
	_guard(p, c, dh)

## A fleeing lord, vassal or caravan (#315) whose call is answered turns its flight towards the nearest own party riding to
## it, when that one is closer than the end of its flight and safe to run to (#313): the two meet half-way.
func _meet(p: Dictionary, dh: float) -> void:
	p.rp = float(p.get("rp", 0.0)) - dh
	if p.rp > 0.0:
		return
	p.rp = Config.GOAL_CHASE_REPATH_HOURS
	_beacons()
	var riders: Array = _answers.get(p.id, [])
	if riders.is_empty() or p.path.is_empty():
		return
	var call := _call_detail(_call_of.get(p.id, {"none": true}))
	if call.is_empty():
		return
	var from := Vector2(float(call.fx), float(call.fy)) if call.has("fx") else Vector2(p.x, p.y)
	var t := goals.meet_target(p, from, riders, float(call.foe))
	if t.is_empty():
		return
	var here := Vector2(p.x, p.y)
	var end: Vector2 = p.path[p.path.size() - 1]
	if here.distance_to(Vector2(t.x, t.y)) < here.distance_to(end):
		roster.path_to(p, t.x, t.y)

## Escort: keeps close to the caravan; the goal ends when the caravan is gone. The caravan is looked up in the caravans of
## the step (#315), not in the whole roster: escorts are many more since lords escort too.
func _escort(p: Dictionary, dh: float) -> void:
	var c: Dictionary = {}
	var gid = p.get("gid")
	for q in _caravans():
		if q.id == gid:
			c = q
			break
	if c.is_empty() or c.hide:
		p.path = []
		p.pi = 0
		p.wait = 0.0
		p.state = "idle"
		return
	_guard(p, c, dh)

## Keeps with the party `c` it rides to, re-planned as it moves. A caravan's own fight is settled at once and without its
## escort (world_skirmish.contact), so an escort or an answer to a caravan's call rides at the nearest outlaw hunting the
## caravan that it can beat, and the hunter meets it first (#315).
func _guard(p: Dictionary, c: Dictionary, dh: float) -> void:
	p.rp = float(p.get("rp", 0.0)) - dh
	if p.rp > 0.0:
		return
	p.rp = Config.GOAL_CHASE_REPATH_HOURS
	var t := _hunter_of(p, c) if c.kind == "caravan" else {}
	if not t.is_empty():
		p.state = "roam"
		roster.path_to(p, t.x, t.y)
	elif _dist(c, p) > Config.GOAL_ESCORT_KEEP:
		p.state = "roam"
		roster.path_to(p, c.x, c.y)

## The nearest party hunting the caravan `c` in this step (its call, _beacons) that p is hostile to and stronger than, or {}.
func _hunter_of(p: Dictionary, c: Dictionary) -> Dictionary:
	_beacons()
	var e: Variant = _call_of.get(c.id)
	if e == null or e.hunters.is_empty():
		return {}
	var me := -1.0
	var best: Dictionary = {}
	var best_d := INF
	for h in e.hunters:
		if h.hide or h.get("fight") or not roster.hostile(p, h):
			continue
		if me < 0.0:
			me = roster.strength_of(p)
		if roster.strength_of(h) >= me:
			continue
		var d := _dist(h, p)
		if d < best_d:
			best_d = d
			best = h
	return best

func _arrived(p: Dictionary) -> void:
	if p.state == "flee":
		p.state = "idle"
		p.path = []
		p.pi = 0
		if p.kind == "caravan" or p.kind == "cvass":
			return
		for s in goals.own_settlements(String(p.fac)):
			if Vector2(s.x - p.x, s.y - p.y).length() < 40.0:
				p.sid = s.id
				p.state = "travel"
				_arrived(p)
				return
		return
	if p.state == "travel":
		var s := roster.map.settlement_by_id(p.sid) if p.sid != null else {}
		if s.is_empty() or Vector2(s.x - p.x, s.y - p.y).length() >= 40.0:
			return
		if p.get("army", false):
			p.state = "idle"
			p.path = []
			p.pi = 0
			p.arrived = true
			return
		if p.fac == "undead" and undead != null:
			undead.arrive(p, s)
			return
		if s.fac == "undead" and Rules.is_noble(p) and undead != null and not undead.noble_retake(p, s):
			p.state = "idle"
			p.path = []
			p.wait = float(roster.rint(3, 8))
			if Rules.troop_count(p.troops) < 10:
				roster.remove(p)
			return
		if p.kind == "caravan":
			if s.fac != "bandit":
				roster.remove(p)
			return
		if s.fac == "player" and p.fac != "player":
			if s.kind == Config.SETTLEMENT_VILLAGE and p.get("goal", "") == "raid" and player != null and Rules.hostile_to_player(p, player.rel):
				_raid_arrive(p, s)
				return
			p.state = "idle"
			p.path = []
			p.wait = float(roster.rint(4, 10))
			return
		if p.kind == "vassal":
			_vassal_rest(p, s)
			return
		if s.fac != p.fac:
			_raid_arrive(p, s)
			return
		p.hide = true
		p.wait = float(roster.rint(5, 20))
		p.home = s.id
		p.x = s.x
		p.y = s.y
		p.state = "idle"
		p.path = []
	elif p.state == "roam":
		p.state = "idle"
		p.path = []
		p.pi = 0
		match String(p.get("goal", "")):
			"patrol":
				p.wait = float(roster.rint(Config.GOAL_PATROL_WAIT.x, Config.GOAL_PATROL_WAIT.y)) if p.kind != "cvass" else 0.0
			"defend":
				p.wait = float(Config.GOAL_DEFEND_WAIT)
			"escort", "assist", "rescue":
				p.wait = Config.GOAL_WAIT_PER_THINK
			"muster":
				p.wait = float(Config.UNDEAD_MUSTER_WAIT)
			_:
				p.wait = float(roster.rint(2, 6)) if p.kind == "vassal" else 0.0

## A raid reaches an enemy village: it burns and gives no recruits for a while, the raiders take some gold.
func _raid_arrive(p: Dictionary, s: Dictionary) -> void:
	p.state = "idle"
	p.path = []
	p.pi = 0
	var foe: bool = Rules.at_war(p.fac, s.fac, roster.diplomatic_wars) or (s.fac == Config.PLAYER_FACTION and player != null and Rules.hostile_to_player(p, player.rel))
	if s.kind == Config.SETTLEMENT_VILLAGE and foe and int(s.get("burnt", 0)) <= 0:
		s.burnt = Config.GOAL_RAID_BURN_HOURS
		p.gold += Config.GOAL_RAID_GOLD
	p.wait = float(roster.rint(Config.GOAL_PATROL_WAIT.x, Config.GOAL_PATROL_WAIT.y))

## At its own settlement a vassal stands by the walls for a few hours and tops up its men.
func _vassal_rest(p: Dictionary, s: Dictionary) -> void:
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.wait = float(roster.rint(3, 8))
	p.home = s.id
	var need := Config.GOAL_VASSAL_FULL * Rules.MK - Rules.troop_count(p.troops)
	if need > 0.0 and s.fac == p.fac:
		for a in roster.gen_troops(p.fac, mini(ceili(need / Rules.MK), roster.rint(4, 10)), 0.55):
			Rules.add_troops(p.troops, a.type, a.n)

## Auto-resolves a meeting of two AI parties: the stronger one wins and loses part of its men, the loser disappears.
func auto_fight(a: Dictionary, b: Dictionary) -> void:
	var sa := roster.strength_of(a) * roster.rnd(0.8, 1.25)
	var sb := roster.strength_of(b) * roster.rnd(0.8, 1.25)
	var w: Dictionary = a if sa >= sb else b
	var l: Dictionary = b if w == a else a
	var ratio := minf(sa, sb) / maxf(sa, sb)
	var wl := minf(0.85, ratio * 0.85)
	if w.fac == "undead" and undead != null:
		undead.raise(w, Rules.troop_count(l.troops) * undead.RAISE)
	for s in w.troops.duplicate():
		var dead := 0
		for i in int(s.n):
			if roster.rng.randf() < wl:
				dead += 1
		Rules.remove_troops(w.troops, s.type, dead)
	if l.get("ruler", false) and clans != null and roster.rng.randf() < 0.75:
		for t in l.troops.duplicate():
			Rules.remove_troops(l.troops, t.type, floori(int(t.n) * 0.55))
		clans.ruler_home(l)
	else:
		roster.remove(l)
	if w.troops.is_empty() or Rules.troop_count(w.troops) < 2:
		roster.remove(w)
	w.state = "idle"
	w.path = []
	w.pi = 0
	w.cd = 3.0
	w.gold += 20
