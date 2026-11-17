extends RefCounted
## Map-party AI: goals of parties, resting in settlements and auto-resolved fights between parties (aiParty, vassalIdle,
## vassalRest, cvAI, autoFight, stepWorld in src/05_world.js and src/05h_vassals.js).
## Since stage 2a (docs/modules/ai/DESIGN.md §5.2, ADR-023) every party picks a goal through party_goals.gd — lords,
## faction vassals, the player's retinues (orders of world_vassals.gd are weight sets), bandits, caravans and the dead —
## and this file carries the goal out: routes, chases, arrivals. Faction campaigns are operations of world_wars.gd (stage 2b).
## The dead follow the director of the invasion (stage 2c, world_undead.gd): their wave and front come in the context.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const Config = preload("res://core/campaign/config.gd")
const Goals = preload("res://core/campaign/world/party_goals.gd")

const WW := 5200.0
const WH := 3400.0

var roster: Roster
var player: RefCounted  # PlayerParty: x, y, troops, rel, busy, inside, away

var undead: RefCounted = null  # WorldUndead, optional
var clans: RefCounted = null   # WorldClans, optional: rulers survive lost fights
var vassals: RefCounted = null  # WorldVassals, optional: the player's retinues
var skirmish: RefCounted = null # WorldSkirmish, optional: fights lasting hours, rallying neighbours
var goals := Goals.new()
var threat_map: Callable = Callable()  # () -> ThreatMap (WorldState.threat_map), optional
var enemies: Callable = Callable()     # (faction) -> hostile factions on the threat map, optional

var _map_cache: RefCounted = null
var _enemy_cache := {}
var _doom_cache: Variant = null

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

## Breaks the links to the world so a disposed campaign is freed.
func dispose() -> void:
	goals = Goals.new()
	threat_map = Callable()
	enemies = Callable()
	_map_cache = null
	_enemy_cache = {}
	_doom_cache = null

func _at_war(a: String, b: String) -> bool:
	return Rules.at_war(a, b, roster.diplomatic_wars)

func _allies(p: Dictionary) -> float:
	return skirmish.ally_strength(p) if skirmish != null else 0.0

func _ruins(f: String) -> Array:
	return undead.ruins_for(f) if undead != null else []

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

func step(dh: float) -> void:
	_fresh()
	goals.rebuild_claims()
	for p in roster.parties.duplicate():
		if p in roster.parties:
			ai_party(p, dh)
	var list := roster.parties.duplicate()
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
			if absf(dx) >= 15.0 or not (Vector2(dx, ay - b.y).length() < 15.0):
				continue
			if _skip_fight(b) or not (b in roster.parties):
				continue
			if roster.hostile(a, b):
				if skirmish != null:
					skirmish.contact(a, b, auto_fight)
				else:
					auto_fight(a, b)
				break

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
	elif p.get("goal", "") == "escort":
		_escort(p, dh)
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
			_flee(p, Vector2(c.x, c.y), ctx)
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

## Flight to a safe own place (DESIGN.md §5.1): an own settlement away from the enemy, else the safest cell nearby.
func _flee(p: Dictionary, from: Vector2, ctx: Dictionary) -> void:
	var havens: Array = []
	for s in goals.own_settlements(String(p.fac)):
		havens.append({"id": s.id, "x": s.x, "y": s.y})
	havens.append_array(ctx.get("havens", []))
	var t := goals.flee_target(p, from, havens)
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

## Escort: keeps close to the caravan; the goal ends when the caravan is gone.
func _escort(p: Dictionary, dh: float) -> void:
	var c := roster.party_by_id(p.get("gid"))
	if c.is_empty() or c.hide:
		p.path = []
		p.pi = 0
		p.wait = 0.0
		p.state = "idle"
		return
	p.rp = float(p.get("rp", 0.0)) - dh
	if p.rp <= 0.0:
		p.rp = Config.GOAL_CHASE_REPATH_HOURS
		if _dist(c, p) > Config.GOAL_ESCORT_KEEP:
			p.state = "roam"
			roster.path_to(p, c.x, c.y)

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
			"escort":
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
