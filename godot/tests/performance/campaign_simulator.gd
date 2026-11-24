extends RefCounted
## Campaign simulator (docs/modules/ai/DESIGN.md §7.2): the world runs without the player for N days on a fixed seed
## while an observer only reads it. The world goes through the same clock as the game (clock.advance -> step/hour_tick);
## the observer spends no RNG and changes nothing, so the same seed gives the same world with or without it.
## Invariants of §7.2 are measured, not enforced. Since stage 2a the goal of a party (party_goals.gd) is part of the
## "goal" that the jitter metric watches, next to tid/sid/chase of the player; before 2a parties had no goal field.
## Since stage 2b the observer also listens to world_wars.operation (campaigns, lords left home, retreats, relief) and
## measures how close the host keeps to its marshal on the march; a signal connection changes nothing in the world.
## Since stage 2c it follows the undead crisis (DESIGN.md §5.5): where and how fast the dead go, what the living lose
## and retake, whether the invasion burns out or overruns the world, and how long undead parties stand idle. It listens
## to world_undead.announced (storms) and, when present, world_undead.wave (the director of the invasion).
## Since stage 2d (the faction strategist, DESIGN.md §5.4) it measures diplomacy once a day: wars at once, the share of
## neighbouring pairs at war (neighbours by world_wars.borders, which only reads the map), states at war with every
## neighbour, the most fronts of one state and the war weariness when the world keeps it (world_wars.weary). It also
## times every world hour and every day tick (hour 0: world_wars.war_day among others) as the game runs them.
## Since #307 (parties act together, DESIGN.md §5.7) it follows every fight of world_skirmish: who could have helped a side
## (a free party within HELP_RADIUS that would join it by the rule of world_skirmish.hour_tick: hostile to the other side,
## not to this one), whether helping was within its strength, and who joined later; and the fate of every caravan.
## Since #313 (calls for help, DESIGN.md §5.7) it follows every lord or vassal in danger — chased by a hostile party or
## fleeing: whether an own lord or vassal was near enough to help, whether one reached it (closer than JOIN_RADIUS), whether
## it was caught (a fight) and got help there, and whether it was lost. It also tells which side of a fight won, so the
## share of fights won by the side that was weaker at the start shows whether help turns fights.
## Since #315 (caravan escort, DESIGN.md §5.7) it follows the caravans more closely: how much of their time an own free lord
## or vassal rides within JOIN_RADIUS of them (guarded), how much of it they spend where the outlaws on the threat map are at
## least as strong as the caravan, and every caravan in danger (an outlaw hunts it or it flees) the way #313 follows lords:
## an own lord or vassal near enough to turn it, one that reached it, and whether the caravan was lost.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const PartyAI = preload("res://core/campaign/world/party_ai.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")

const CULTURE := "emp"
const REAL_SECONDS_PER_CALL := 1.0  # clock.advance slice: 1.2 world hours at speed 1
const HEAT_CELL := 50.0             # heat map cell: 104 × 68 over Europe
const EDGE_MARGIN := 150.0          # "at the map edge"
const EDGE_STREAK_HOURS := 6        # an edge stand this long counts as stuck
const JITTER_LIMIT_PER_DAY := 12.0  # goal or state changes per party-day above this look like dithering
const FLIPFLOP_STEPS := 15          # A -> B -> A within 3 world hours
const RELIEF_SCAN_RADIUS := 900.0   # an own lord this close could have tried to relieve a siege (borders() reach)
const RELIEF_MIN_TROOPS := 36       # 18 × MK, the relief threshold of world_wars
const RELIEF_GRACE_HOURS := 12      # world_wars sends relief after 10 h of siege; a helper nearby this long is a miss
const FLEE_SAFE_RADIUS := 300.0     # search radius of the threat-map alternative for a flight
const HOST_RADIUS := 150.0          # a follower this close to the marshal keeps up with the host (OP_MUSTER_RADIUS)
const UNDEAD_STAND_STREAK_HOURS := 12 # an undead party standing idle this long in a row counts as stuck
const UNDEAD_BURN_RADIUS := 60.0      # a village that caught fire with an undead party this close was burnt by the dead
const HELP_RADIUS := 400.0          # a free party this close to a fight could have come to help (#307, GOAL_ASSIST_RANGE)
const JOIN_RADIUS := 90.0           # world_skirmish.hour_tick takes in parties this close
const SKIRMISH_LOSS := 0.06          # world_skirmish.LOSS: share a side loses per hour against equal strength
const CARAVAN_ARRIVE := 60.0        # a caravan gone this close to its destination arrived; elsewhere it was taken

var world: RefCounted
var steps := 0
var hours := 0
var wall_usec := 0

var _party_last := {}   # id -> {state, goal, prev_state, prev_step}
var _party_stats := {}  # id -> {kind, fac, name, steps, state, goal, flip}
var _wars := {}         # key -> since
var _war_log: Array = []
var _owners := {}       # settlement id -> faction
var _owner_log: Array = []
var _alive: Array = []
var _fallen: Array = []
var _lords := {}        # id -> fac
var _lord_log := {"died": [], "new": []}
var _vassals := {}
var _vassal_log := {"died": 0, "new": 0}
var _crisis := {"start_day": -1, "end_day": -1}
var _daily: Array = []
var _sieges := {}       # settlement id -> record
var _siege_log: Array = []
var _edge_streak := {}  # party id -> hours
var _edge := {"party_hours": 0, "streaks": 0, "max_streak": 0, "by_kind": {}}
var _flees := {"count": 0, "into_more_threat": 0, "dest_ratio_sum": 0.0, "safe_better": 0, "safe_ratio_sum": 0.0, "measured": 0}
var _threat_cost := {"samples": 0, "usec": 0, "sources": 0, "cells": 0}
var _goal_steps := {}   # kind -> goal ("" = none) -> party-steps
var _burnt := {}        # settlement id -> was burning at the last hour
var _burns := 0         # villages set on fire (by the dead or by raids)
var _ops_log: Array = [] # every operation event with its day
var _skip := {}         # settlement id -> {why: true}: relief was due but not sent (busy elsewhere, too weak)
var _undead := {"armies": 0, "raids": 0, "party_hours": 0, "idle_hours": 0, "gather_hours": 0, "roam_hours": 0, "stuck": 0,
	"max_stand": 0, "storms": 0, "storms_won": 0, "burns": 0, "captures": [], "retaken": [], "armies_gone_day": -1, "waves": [],
	"reach_sum": 0.0, "reach_days": 0, "front_max": 0.0, "ruin_campaigns": 0, "ruin_campaigns_won": 0}
var _undead_seen := {}   # party id -> kind
var _undead_stand := {}  # party id -> hours standing idle in a row
var _diplo: Array = []  # a row a day at 12:00: wars, neighbour pairs at war, states at war with all neighbours, weariness
var _tick_usec := {"hour": [], "day": []}  # cost of WorldState.hour_tick: ordinary hours and the day tick (hour 0)
var _ops := {"campaigns": 0, "kept": 0, "lords_out": 0, "retreat_weak": 0, "retreat_home": 0, "relief": 0, "march_hours": 0, "march_share": 0.0}
var _fights := {}       # fight id -> {t0, size, start: {party id: side}, could: {party id: {side, kind, feasible, far}}, joined: {party id: side}}
var _fight_log: Array = []
var _danger := {}       # party id -> danger episode {fac, t0, foe, near, met, quiet, fight, side}
var _danger_log: Array = []
var _caravans := {}     # caravan id -> {x, y, sid}
var _caravan_log := {"seen": 0, "arrived": 0, "taken": 0, "taken_guarded": 0, "taken_danger": 0}
var _caravan_time := {"steps": 0, "guarded": 0, "sampled": 0, "threat": 0, "threat_guarded": 0}
var _cdanger := {}      # caravan id -> danger episode {t0, foe, own, near, met, quiet, chased, lost}
var _cdanger_log: Array = []
var heat_cols := 0
var heat_rows := 0
var heat_lords := PackedInt32Array()
var heat_fights := PackedInt32Array()
var heat_sieges := PackedInt32Array()

static func create_world(seed_value: int) -> RefCounted:
	var data := EuropeData.new()
	if not ContentLoader.populate(data):
		return null
	var w: RefCounted = WorldState.create(seed_value, data, CULTURE, ContentLoader.registry())
	w.player.away = true  # no player on the map: no meetings, no prey, no holdings
	return w

## Runs `hours` world hours exactly as the game does. on_step/on_hour run after world.step/world.hour_tick.
static func drive(w: RefCounted, total_hours: int, on_step: Callable, on_hour: Callable) -> void:
	var step_cb := func(dh: float) -> void:
		w.step(dh)
		on_step.call()
	var hour_cb := func() -> void:
		w.hour_tick()
		on_hour.call()
	while int(w.hours_passed) < total_hours:
		w.clock.advance(REAL_SECONDS_PER_CALL, step_cb, hour_cb)

## Creates the world for `seed_value`, runs it for `days` with the observer and returns {report, world}.
static func run(seed_value: int, days: int) -> Dictionary:
	var w := create_world(seed_value)
	if w == null:
		return {}
	var sim := new(w)
	var start := Time.get_ticks_usec()
	var step_cb := func(dh: float) -> void:
		w.step(dh)
		sim.observe_step()
	var hour_cb := func() -> void:
		var t0 := Time.get_ticks_usec()
		var day_tick: bool = int(w.clock.hour) == 0
		w.hour_tick()
		sim._tick_usec["day" if day_tick else "hour"].append(Time.get_ticks_usec() - t0)
		sim.observe_hour()
	while int(w.hours_passed) < days * 24:
		w.clock.advance(REAL_SECONDS_PER_CALL, step_cb, hour_cb)
	sim.wall_usec = Time.get_ticks_usec() - start
	return {"report": sim.report(seed_value, days), "world": w}

func _init(w: RefCounted) -> void:
	world = w
	heat_cols = ceili(PartyAI.WW / HEAT_CELL)
	heat_rows = ceili(PartyAI.WH / HEAT_CELL)
	heat_lords.resize(heat_cols * heat_rows)
	heat_fights.resize(heat_cols * heat_rows)
	heat_sieges.resize(heat_cols * heat_rows)
	world.threat_map()  # from now on hour_tick refreshes it; it spends no RNG
	if world.wars.has_signal("operation"):
		world.wars.operation.connect(_on_operation)
	world.undead.announced.connect(_on_undead_news)
	if world.undead.has_signal("wave"):
		world.undead.wave.connect(_on_wave)
	for k in world.wars.wars:
		_wars[k] = int(world.wars.wars[k].since)
	for s in world.map.settles:
		_owners[s.id] = s.fac
	_alive = world.wars.factions_alive()
	for p in world.roster.parties:
		if p.kind == "lord":
			_lords[p.id] = p.fac
		elif p.kind == "vassal":
			_vassals[p.id] = p.fac
	_snapshot_parties()

func _day() -> int:
	return int(world.clock.day)

func _goal(p: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [p.get("tid"), p.get("sid"), p.get("tpl", false), p.get("goal", ""), p.get("gid")]

func _snapshot_parties() -> void:
	for p in world.roster.parties:
		if p.kind == "camp":
			continue
		_party_last[p.id] = {"state": p.state, "goal": _goal(p), "prev_state": "", "prev_step": -1000}
		_party_stats[p.id] = {"kind": p.kind, "fac": p.fac, "steps": 0, "state": 0, "goal": 0, "flip": 0}

## After every world step (0.2 h): goal and state changes per party, flights.
func observe_step() -> void:
	steps += 1
	for p in world.roster.parties:
		if p.kind == "camp":
			continue
		var id: int = p.id
		var last: Variant = _party_last.get(id)
		if last == null:
			_party_last[id] = {"state": p.state, "goal": _goal(p), "prev_state": "", "prev_step": -1000}
			_party_stats[id] = {"kind": p.kind, "fac": p.fac, "steps": 1, "state": 0, "goal": 0, "flip": 0}
			continue
		var st: Dictionary = _party_stats[id]
		st.steps += 1
		var by_goal: Dictionary = _goal_steps.get(p.kind, {})
		var g := "army" if p.get("army", false) else ("inside" if p.hide else String(p.get("goal", "")))
		by_goal[g] = int(by_goal.get(g, 0)) + 1
		_goal_steps[p.kind] = by_goal
		var goal := _goal(p)
		if goal != last.goal:
			st.goal += 1
			last.goal = goal
		if p.state != last.state:
			st.state += 1
			if p.state == last.prev_state and steps - int(last.prev_step) <= FLIPFLOP_STEPS:
				st.flip += 1
			last.prev_state = last.state
			last.prev_step = steps
			last.state = p.state
			if p.state == "flee":
				_measure_flee(p)
	_observe_fight_starts()
	_observe_fights()
	_observe_danger()
	_observe_caravans()

## New fights of world_skirmish with the parties they started with (contact happens inside the step).
func _observe_fight_starts() -> void:
	for f in world.skirmish.fights:
		if _fights.has(int(f.id)):
			continue
		var start := {}
		for id in f.A:
			start[int(id)] = 0
		for id in f.B:
			start[int(id)] = 1
		_fights[int(f.id)] = {"t0": steps, "start": start, "could": {}, "joined": {}, "size": start.size()}

## Caravans that left the map: at their destination they arrived, anywhere else they were taken (#315: with an own lord
## or vassal at hand, or during a danger episode). Every step a caravan on the map counts as guarded when a free own lord or
## vassal is within JOIN_RADIUS, and as threatened when the outlaws (bandits, the dead) it fears are at least as strong as
## it at its place on the threat map.
func _observe_caravans() -> void:
	var now := {}
	var hunted := {}  # party id -> strength of its hunters
	var nobles: Array = []
	var cars: Array = []
	for p in world.roster.parties:
		if p.state == "hunt" and p.get("tid") != null:
			hunted[p.tid] = float(hunted.get(p.tid, 0.0)) + world.roster.strength_of(p)
		if p.kind == "caravan":
			cars.append(p)
		elif Rules.is_noble(p) and not p.hide and p.get("fight") == null and not p.get("lock", false) and not p.get("army", false):
			nobles.append(p)
	# The threat map only when this step has built it already: built here, it would be frozen before the next hour tick
	# spawns parties, and the world would no longer be the same with and without the observer.
	var m: ThreatMap = world.threat if world.get("_threat_built") == world.get("_threat_step") else null
	var outlaws := {}  # faction -> the outlaw layers it fears
	for p in cars:
		var id := int(p.id)
		now[id] = true
		if not _caravans.has(id):
			_caravan_log.seen += 1
		var guard := false
		for o in nobles:
			if o.fac == p.fac and Vector2(o.x - p.x, o.y - p.y).length() <= JOIN_RADIUS:
				guard = true
				break
		var own: float = maxf(0.001, world.roster.strength_of(p))
		if not outlaws.has(p.fac):
			outlaws[p.fac] = world.threat_enemies(p.fac).filter(func(f): return f == "bandit" or f == "undead")
		var felt := m.threat(p.x, p.y, outlaws[p.fac]) if m != null else -1.0
		if not p.hide:
			_caravan_time.steps += 1
			if guard:
				_caravan_time.guarded += 1
			if felt >= 0.0:
				_caravan_time.sampled += 1
			if felt >= own:
				_caravan_time.threat += 1
				if guard:
					_caravan_time.threat_guarded += 1
		_caravans[id] = {"x": float(p.x), "y": float(p.y), "sid": p.get("sid"), "guard": guard}
		_observe_caravan_danger(p, hunted, nobles, own, felt)
	for id in _caravans.keys():
		if now.has(id):
			continue
		var c: Dictionary = _caravans[id]
		var s: Dictionary = world.map.settlement_by_id(c.sid) if c.sid != null else {}
		var e: Variant = _cdanger.get(id)
		if not s.is_empty() and Vector2(s.x - c.x, s.y - c.y).length() < CARAVAN_ARRIVE:
			_caravan_log.arrived += 1
		else:
			_caravan_log.taken += 1
			if c.guard:
				_caravan_log.taken_guarded += 1
			if e != null:
				_caravan_log.taken_danger += 1
				e.lost = true
		if e != null:
			_end_cdanger(id)
		_caravans.erase(id)

## A caravan in danger (#315): an outlaw hunts it or it flees. As for lords (_observe_danger): whether a free own lord or
## vassal stood within HELP_RADIUS and together with the caravan was at least as strong as the danger (the hunters, else the
## outlaws felt on the threat map), whether one came within JOIN_RADIUS, and whether the caravan was lost. An episode ends
## after a quiet hour or with the caravan.
func _observe_caravan_danger(p: Dictionary, hunted: Dictionary, nobles: Array, own: float, felt: float) -> void:
	var id := int(p.id)
	var danger: bool = hunted.has(p.id) or p.state == "flee"
	var e: Variant = _cdanger.get(id)
	if e != null:
		for o in nobles:
			if o.fac == p.fac and Vector2(o.x - p.x, o.y - p.y).length() <= JOIN_RADIUS:
				e.met = true
				break
		e.quiet = 0 if danger else int(e.quiet) + 1
		if int(e.quiet) >= 5:
			_end_cdanger(id)
		return
	if not danger or p.hide:
		return
	var foe := float(hunted.get(p.id, maxf(0.0, felt)))
	var near := false
	for o in nobles:
		if o.fac == p.fac and Vector2(o.x - p.x, o.y - p.y).length() <= HELP_RADIUS and own + world.roster.strength_of(o) >= foe:
			near = true
			break
	_cdanger[id] = {"t0": steps, "foe": foe, "own": own, "near": near, "met": false, "quiet": 0, "chased": hunted.has(p.id), "lost": false}

func _end_cdanger(id: int) -> void:
	var e: Dictionary = _cdanger[id]
	_cdanger.erase(id)
	e.hours = (steps - int(e.t0)) * 0.2
	_cdanger_log.append(e)

## Caravan numbers of the summary (#315).
func _caravan_summary() -> Dictionary:
	for id in _cdanger.keys():
		_end_cdanger(id)
	var out := {"caravans": _caravan_log.seen, "caravans_arrived": _caravan_log.arrived, "caravans_taken": _caravan_log.taken,
		"caravans_taken_share": float(_caravan_log.taken) / maxf(1.0, _caravan_log.arrived + _caravan_log.taken),
		"caravans_taken_guarded": _caravan_log.taken_guarded, "caravans_taken_danger": _caravan_log.taken_danger,
		"caravan_guarded_share": float(_caravan_time.guarded) / maxf(1.0, _caravan_time.steps),
		"caravan_threat_share": float(_caravan_time.threat) / maxf(1.0, _caravan_time.sampled),
		"caravan_threat_guarded_share": float(_caravan_time.threat_guarded) / maxf(1.0, _caravan_time.threat),
		"cdanger": _cdanger_log.size(), "cdanger_chased": 0, "cdanger_near": 0, "cdanger_met": 0, "cdanger_near_met": 0,
		"cdanger_lost": 0, "cdanger_near_lost": 0, "cdanger_met_lost": 0}
	for e in _cdanger_log:
		if e.chased:
			out.cdanger_chased += 1
		if e.met:
			out.cdanger_met += 1
			if e.lost:
				out.cdanger_met_lost += 1
		if e.near:
			out.cdanger_near += 1
			if e.met:
				out.cdanger_near_met += 1
			if e.lost:
				out.cdanger_near_lost += 1
		if e.lost:
			out.cdanger_lost += 1
	out.cdanger_met_rate = float(out.cdanger_met) / maxf(1.0, _cdanger_log.size())
	out.cdanger_near_met_rate = float(out.cdanger_near_met) / maxf(1.0, out.cdanger_near)
	out.cdanger_lost_rate = float(out.cdanger_lost) / maxf(1.0, _cdanger_log.size())
	out.cdanger_met_lost_rate = float(out.cdanger_met_lost) / maxf(1.0, out.cdanger_met)
	return out

## A flight of the current AI: where it runs (end of its path) against the threat-map alternative.
func _measure_flee(p: Dictionary) -> void:
	_flees.count += 1
	if p.path.is_empty():
		return
	var enemies: Array = world.threat_enemies(p.fac)
	var m: ThreatMap = world.threat_map()
	var here := m.threat(p.x, p.y, enemies)
	if here <= 0.0:
		return
	var dest: Vector2 = p.path[p.path.size() - 1]
	var there := m.threat(dest.x, dest.y, enemies)
	var havens: Array = []
	for s in world.map.settles:
		if s.fac == p.fac and s.kind != "camp":
			havens.append(Vector2(s.x, s.y))
	var paths: RefCounted = world.map.paths
	var accept := func(c: Vector2) -> bool: return paths.passable_type(paths.terr_at(c.x, c.y))
	var safe := m.safe_cell(p.x, p.y, FLEE_SAFE_RADIUS, p.fac, enemies, havens, accept)
	var safe_threat := m.threat(safe.x, safe.y, enemies)
	_flees.measured += 1
	_flees.dest_ratio_sum += there / here
	_flees.safe_ratio_sum += safe_threat / here
	if there >= here:
		_flees.into_more_threat += 1
	if safe_threat < there:
		_flees.safe_better += 1

## After every world hour: wars, owners, factions, lords, crisis, sieges, edges, heat maps; daily summaries at 12:00.
func observe_hour() -> void:
	hours += 1
	var day := _day()
	_observe_wars(day)
	_observe_owners(day)
	_observe_lords(day)
	_observe_sieges(day)
	_observe_edges()
	_observe_heat()
	_observe_burns()
	_observe_marches()
	_observe_undead()
	var crisis: Dictionary = world.undead.crisis
	if crisis.get("on", false) and _crisis.start_day < 0:
		_crisis.start_day = day
	if crisis.get("done", false) and _crisis.end_day < 0:
		_crisis.end_day = day
	if int(world.clock.hour) == 12:
		_observe_day(day)

func _observe_wars(day: int) -> void:
	var now: Dictionary = world.wars.wars
	for k in now:
		if not _wars.has(k):
			_wars[k] = int(now[k].since)
			_war_log.append({"key": k, "declared": int(now[k].since), "ended": -1, "how": ""})
	for k in _wars.keys():
		if now.has(k):
			continue
		var parts: PackedStringArray = String(k).split("|")
		var alive: Array = world.wars.factions_alive()
		var how := "fall" if not parts[0] in alive or not parts[1] in alive else "peace"
		var found := false
		for w in _war_log:
			if w.key == k and w.ended < 0:
				w.ended = day
				w.how = how
				found = true
		if not found:
			_war_log.append({"key": k, "declared": int(_wars[k]), "ended": day, "how": how, "initial": true})
		_wars.erase(k)

func _observe_owners(day: int) -> void:
	for s in world.map.settles:
		var was: String = _owners.get(s.id, s.fac)
		if was != s.fac:
			_owner_log.append({"day": day, "id": s.id, "name": s.get("name", ""), "kind": s.kind, "from": was, "to": s.fac})
			if s.fac == "undead" and s.kind != "camp":
				_undead.captures.append({"day": day, "after": day - int(_crisis.start_day), "id": s.id, "kind": s.kind, "from": was, "dist": _barrow_dist(s)})
			elif was == "undead" and s.fac in Rules.REAL_FACTIONS and s.kind != "camp":
				_undead.retaken.append({"day": day, "id": s.id, "kind": s.kind, "by": s.fac})
			_owners[s.id] = s.fac
	var alive: Array = world.wars.factions_alive()
	for f in _alive:
		if not f in alive:
			_fallen.append({"fac": f, "day": day})
	_alive = alive

func _observe_lords(day: int) -> void:
	var seen := {}
	var seen_v := {}
	for p in world.roster.parties:
		if p.kind == "lord":
			seen[p.id] = p.fac
			if not _lords.has(p.id):
				_lord_log.new.append({"day": day, "fac": p.fac})
		elif p.kind == "vassal":
			seen_v[p.id] = true
			if not _vassals.has(p.id):
				_vassal_log.new += 1
	for id in _lords:
		if not seen.has(id):
			_lord_log.died.append({"day": day, "fac": _lords[id]})
	for id in _vassals:
		if not seen_v.has(id):
			_vassal_log.died += 1
	_lords = seen
	_vassals = seen_v

## Sieges of world_wars: was relief tried, and was an own lord close enough to try it.
func _observe_sieges(day: int) -> void:
	for s in world.map.settles:
		var sg: Variant = s.get("siege")
		var rec: Variant = _sieges.get(s.id)
		if sg == null:
			if rec != null:
				rec.end_day = day
				rec.outcome = "captured" if s.fac != rec.defender else "lifted"
				rec.skip = _skip.get(s.id, {}).keys()
				_skip.erase(s.id)
				_siege_log.append(rec)
				_sieges.erase(s.id)
			continue
		if rec == null:
			rec = {"id": s.id, "name": s.get("name", ""), "kind": s.kind, "defender": s.fac, "attacker": sg.get("f", ""),
				"start_day": day, "end_day": -1, "hours": 0, "relief": false, "defended": false, "helper_hours": 0, "outcome": ""}
			_sieges[s.id] = rec
		rec.hours += 1
		if int(sg.get("relN", 0)) > 0:
			rec.relief = true
		var relieving := false
		for p in world.roster.parties:
			if p.get("relief") == s.id:
				relieving = true
				break
		for p in world.roster.parties:
			if p.get("goal", "") == "defend" and p.get("gid") == s.id and p.fac == rec.defender:
				rec.defended = true
				break
		if relieving:
			continue
		for p in world.roster.parties:
			if p.kind != "lord" or p.fac != rec.defender or p.get("army", false) or p.get("fight", false) or p.get("lock", false):
				continue
			if Rules.troop_count(p.troops) >= RELIEF_MIN_TROOPS and Vector2(p.x - s.x, p.y - s.y).length() <= RELIEF_SCAN_RADIUS:
				rec.helper_hours += 1
				break

## Operations of world_wars as they happen (stage 2b).
func _on_operation(e: Dictionary) -> void:
	match String(e.get("what", "")):
		"start":
			if bool(e.get("ruin", false)):
				_undead.ruin_campaigns += 1
			_ops.campaigns += 1
			_ops.kept += int(e.get("keep", 0))
			_ops.lords_out += int(e.get("army", 0))
		"retreat":
			_ops["retreat_" + String(e.get("why", "weak"))] = int(_ops.get("retreat_" + String(e.get("why", "weak")), 0)) + 1
		"relief":
			_ops.relief += 1
		"retaken":
			_undead.ruin_campaigns_won += 1
		"no_relief":
			if not _skip.has(e.sid):
				_skip[e.sid] = {}
			_skip[e.sid][String(e.why)] = true
			return  # every 2 hours of such a siege; kept per siege, not logged
	var row := e.duplicate()
	row.day = _day()
	row.hour = int(world.clock.hour)
	_ops_log.append(row)

## Hourly: the share of followers that keep up with the marshal on the march (marshals exist since stage 2b).
func _observe_marches() -> void:
	for f in world.wars.campaigns:
		var c: Dictionary = world.wars.campaigns[f]
		if String(c.get("state", "")) != "march" or c.get("marshal") == null:
			continue
		var m: Dictionary = world.roster.party_by_id(c.marshal)
		if m.is_empty():
			continue
		var n := 0
		var close := 0
		for id in c.army:
			var p: Dictionary = world.roster.party_by_id(id)
			if p.is_empty() or p == m:
				continue
			n += 1
			if Vector2(p.x - m.x, p.y - m.y).length() <= HOST_RADIUS:
				close += 1
		if n > 0:
			_ops.march_hours += 1
			_ops.march_share += float(close) / n

## Villages that caught fire this hour: the dead burn them, since stage 2a lords raid them too.
func _observe_burns() -> void:
	for s in world.map.settles:
		var on := int(s.get("burnt", 0)) > 0
		if on and not _burnt.get(s.id, false):
			_burns += 1
			for p in world.roster.parties:
				if p.fac == "undead" and p.kind != "camp" and Vector2(p.x - s.x, p.y - s.y).length() < UNDEAD_BURN_RADIUS:
					_undead.burns += 1
					break
		_burnt[s.id] = on

## Distance from a point to the nearest barrow of the crisis (also destroyed ones: where the wave came from).
func _barrow_dist(s: Dictionary) -> float:
	var best := -1.0
	for id in world.undead.crisis.get("src", []):
		var b: Dictionary = world.map.settlement_by_id(int(id))
		if b.is_empty():
			continue
		var d := Vector2(b.x - s.x, b.y - s.y).length()
		if best < 0.0 or d < best:
			best = d
	return best

## Storms of towns and castles by the dead, from the chronicle (the text is the only trace of a failed storm).
func _on_undead_news(text: String) -> void:
	if "пал под натиском мертвецов" in text:
		_undead.storms += 1
		_undead.storms_won += 1
	elif "отбил натиск мертвецов" in text:
		_undead.storms += 1

## Decisions of the invasion director (stage 2c): a new target or a change between gathering and attacking.
func _on_wave(e: Dictionary) -> void:
	var row := e.duplicate()
	row.day = _day()
	row.hour = int(world.clock.hour)
	_undead.waves.append(row)

## Hourly: undead parties standing idle, gathering or roaming aimlessly; daily at noon how far the armies are from home.
func _observe_undead() -> void:
	if not world.undead.crisis.get("on", false):
		return
	var seen := {}
	var armies := 0
	for p in world.roster.parties:
		if p.fac != "undead" or p.kind == "camp":
			continue
		if not _undead_seen.has(p.id):
			_undead_seen[p.id] = p.kind
			if p.kind == "dead":
				_undead.armies += 1
			else:
				_undead.raids += 1
		if p.kind == "dead":
			armies += 1
		if p.hide or p.get("fight", false):
			continue
		_undead.party_hours += 1
		var goal := String(p.get("goal", ""))
		var standing: bool = p.pi >= p.path.size()
		if standing and goal == "muster":
			_undead.gather_hours += 1
		elif standing:
			_undead.idle_hours += 1
			seen[p.id] = true
			var n := int(_undead_stand.get(p.id, 0)) + 1
			_undead_stand[p.id] = n
			if n == UNDEAD_STAND_STREAK_HOURS:
				_undead.stuck += 1
			_undead.max_stand = maxi(int(_undead.max_stand), n)
		elif p.state == "roam" and goal == "":
			_undead.roam_hours += 1
	for id in _undead_stand.keys():
		if not seen.has(id):
			_undead_stand.erase(id)
	var day := _day()
	if armies == 0 and _undead.armies > 0 and int(_undead.armies_gone_day) < 0:
		_undead.armies_gone_day = day
	elif armies > 0:
		_undead.armies_gone_day = -1
	if int(world.clock.hour) != 12:
		return
	var sum := 0.0
	var n_armies := 0
	for p in world.roster.parties:
		if p.kind == "dead" and p.get("src") != null:
			var b: Dictionary = world.map.settlement_by_id(int(p.src))
			if not b.is_empty():
				sum += Vector2(p.x - b.x, p.y - b.y).length()
				n_armies += 1
	if n_armies > 0:
		_undead.reach_sum += sum / n_armies
		_undead.reach_days += 1
	for s in world.map.settles:
		if s.fac == "undead" and s.kind != "camp":
			_undead.front_max = maxf(float(_undead.front_max), _barrow_dist(s))

## Goal shares by kind of party: the part of party-steps spent on each goal ("army": in a faction campaign,
## "inside": resting inside a settlement, "none": no goal).
func _goal_shares() -> Dictionary:
	var out := {}
	for kind in _goal_steps:
		var total := 0
		for g in _goal_steps[kind]:
			total += int(_goal_steps[kind][g])
		var shares := {}
		for g in _goal_steps[kind]:
			shares["none" if g == "" else g] = float(_goal_steps[kind][g]) / maxf(1.0, total)
		out[kind] = shares
	return out

static func _share_text(shares: Dictionary) -> String:
	var keys := shares.keys()
	keys.sort_custom(func(x, y): return float(shares[x]) > float(shares[y]))
	return ", ".join(keys.map(func(k): return "%s %d%%" % [k, roundi(float(shares[k]) * 100.0)]))

## Parties standing at the map edge with nowhere to go.
func _observe_edges() -> void:
	var seen := {}
	for p in world.roster.parties:
		if p.kind == "camp" or p.hide or p.get("fight", false) or p.get("lock", false):
			continue
		var x: float = p.x
		var y: float = p.y
		var at_edge := x < EDGE_MARGIN or y < EDGE_MARGIN or x > PartyAI.WW - EDGE_MARGIN or y > PartyAI.WH - EDGE_MARGIN
		if not at_edge or p.pi < p.path.size() or p.get("army", false):
			continue
		seen[p.id] = true
		_edge.party_hours += 1
		_edge.by_kind[p.kind] = int(_edge.by_kind.get(p.kind, 0)) + 1
		var n: int = int(_edge_streak.get(p.id, 0)) + 1
		_edge_streak[p.id] = n
		if n == EDGE_STREAK_HOURS:
			_edge.streaks += 1
		_edge.max_streak = maxi(int(_edge.max_streak), n)
	for id in _edge_streak.keys():
		if not seen.has(id):
			_edge_streak.erase(id)

## After every step: who joined each fight since the start, and who could have come to help.
## A helper is a party that would join a side by the rule of hour_tick (hostile to someone on the other side, to no one on
## this one), free (not hidden, in a fight, locked or in a faction campaign), and not a caravan, a camp or a retinue. Its
## kind: "own" — a lord or vassal of a faction on that side; "other" — a lord or vassal of another faction (the enemy of
## my enemy); "bandit", "dead", "party" (anything else). Feasible: the side with it is at least as strong as the other.
## Timely: feasible, farther than JOIN_RADIUS, and the ride takes no longer than the fight has left (_hours_left).
## Needed: timely while the side without it is the weaker one.
func _observe_fights() -> void:
	var live := {}
	for f in world.skirmish.fights:
		var id := int(f.id)
		live[id] = true
		var rec: Variant = _fights.get(id)
		if rec == null:
			continue
		var sides: Array = world.skirmish.sides(f)
		var strength := [0.0, 0.0]
		var men := [0, 0]
		var facs := [{}, {}]
		for side in 2:
			for q in sides[side]:
				strength[side] += world.roster.strength_of(q)
				men[side] += Rules.troop_count(q.troops)
				facs[side][q.fac] = true
				if not rec.start.has(int(q.id)) and not rec.joined.has(int(q.id)):
					rec.joined[int(q.id)] = side
					if q.get("army", false):
						rec.army = int(rec.get("army", 0)) + 1
		if sides[0].is_empty() or sides[1].is_empty():
			continue
		if not rec.has("s0"):
			rec.s0 = strength.duplicate()
		var left := minf(_hours_left(men[0], float(f.a0), strength[1] / maxf(1.0, strength[0])),
			_hours_left(men[1], float(f.b0), strength[0] / maxf(1.0, strength[1])))
		for p in world.roster.parties:
			if p.hide or p.get("fight") or p.get("lock", false) or p.get("army", false) or p.kind == "caravan" or p.kind == "camp" or p.kind == "cvass":
				continue
			var d := Vector2(p.x - float(f.x), p.y - float(f.y)).length()
			if d > HELP_RADIUS:
				continue
			var ha: bool = sides[0].any(func(q): return world.roster.hostile(p, q))
			var hb: bool = sides[1].any(func(q): return world.roster.hostile(p, q))
			if ha == hb:
				continue
			var side := 0 if hb else 1
			var kind := "other"
			if p.fac == "undead":
				kind = "dead"
			elif p.kind == "bandit":
				kind = "bandit"
			elif not Rules.is_noble(p):
				kind = "party"
			elif facs[side].has(p.fac):
				kind = "own"
			var c: Dictionary = rec.could.get(int(p.id), {"side": side, "kind": kind, "feasible": false, "far": false, "timely": false, "needed": false})
			var turns: bool = strength[side] + world.roster.strength_of(p) >= strength[1 - side]
			c.feasible = c.feasible or turns
			c.far = c.far or d > JOIN_RADIUS
			var timely: bool = turns and d > JOIN_RADIUS and d / maxf(0.001, world.roster.speed_of(p)) <= left
			c.timely = c.timely or timely
			c.needed = c.needed or (timely and strength[side] < strength[1 - side])
			rec.could[int(p.id)] = c
	for id in _fights.keys():
		if not live.has(id):
			_close_fight(id)

## Hours until a side breaks at the loss rate of world_skirmish.hour_tick without the random spread (a copy, so the observer
## measures the same on code without WorldSkirmish.hours_left).
static func _hours_left(men: int, men0: float, odds: float) -> float:
	var floor_men := men0 * 0.25
	if men <= 0 or float(men) <= floor_men:
		return 0.0
	if floor_men <= 0.0:
		return INF
	var l := clampf(SKIRMISH_LOSS * odds, SKIRMISH_LOSS / 8.0, SKIRMISH_LOSS * 2.5)
	return log(floor_men / men) / log(1.0 - l)

## A fight is over: its side still standing won. world_skirmish sends the losers fleeing (or removes them), so a side whose
## parties are all gone, fleeing or in another fight lost; -1 when that does not tell (both or neither).
func _close_fight(id: int) -> void:
	var rec: Dictionary = _fights[id]
	_fights.erase(id)
	rec.hours = (steps - int(rec.t0)) * 0.2
	var standing := [0, 0]
	var members: Dictionary = rec.start.duplicate()
	members.merge(rec.joined)
	for pid in members:
		var p: Dictionary = world.roster.party_by_id(pid)
		if not p.is_empty() and p.get("state") != "flee" and p.get("fight") == null:
			standing[int(members[pid])] += 1
	rec.winner = 0 if standing[0] > 0 and standing[1] == 0 else (1 if standing[1] > 0 and standing[0] == 0 else -1)
	_fight_log.append(rec)
	for pid in _danger.keys():
		var e: Dictionary = _danger[pid]
		if e.get("fight") == id:
			e.helped = rec.joined.values().has(int(e.side))
			e.lost = world.roster.party_by_id(pid).is_empty()
			_end_danger(pid)

## After every step: lords and vassals in danger (#313). Danger: a hostile party hunts it, or it flees. An episode starts
## when a free lord or vassal (not hidden, locked, in a fight or in a faction campaign) is in danger. It notes whether a
## free own lord or vassal stood within HELP_RADIUS and could turn it (both together at least as strong as the hunters, or
## the threat-map enemies when nobody hunts it), and whether one came closer than JOIN_RADIUS. It ends quiet (an hour
## without danger), lost (the party is gone) or caught (a fight; its outcome is taken when the fight closes).
func _observe_danger() -> void:
	var hunted := {}  # party id -> strength of its hunters
	var nobles: Array = []
	for p in world.roster.parties:
		if p.state == "hunt" and p.get("tid") != null:
			hunted[p.tid] = float(hunted.get(p.tid, 0.0)) + world.roster.strength_of(p)
		if Rules.is_noble(p) and not p.hide:
			nobles.append(p)
	var by_id := {}
	for p in nobles:
		by_id[int(p.id)] = p
	for pid in _danger.keys():
		var e: Dictionary = _danger[pid]
		if e.get("fight") != null:
			continue
		var p: Dictionary = by_id.get(pid, {})
		if p.is_empty():
			e.lost = world.roster.party_by_id(pid).is_empty()  # else it is inside a settlement: safe
			_end_danger(pid)
			continue
		if p.get("fight") != null:
			var sk: Dictionary = world.skirmish.fight_of(p)
			e.fight = int(sk.id) if not sk.is_empty() else null
			e.side = 0 if not sk.is_empty() and p.id in sk.A else 1
			if e.fight == null:
				_end_danger(pid)
			continue
		for o in nobles:
			if o.fac == p.fac and not is_same(o, p) and o.get("fight") == null and Vector2(o.x - p.x, o.y - p.y).length() <= JOIN_RADIUS:
				e.met = true
				break
	for p in nobles:
		if p.get("fight") != null or p.get("lock", false) or p.get("army", false):
			continue
		var danger: bool = hunted.has(p.id) or p.state == "flee"
		var e: Variant = _danger.get(int(p.id))
		if e != null:
			e.quiet = 0 if danger else int(e.quiet) + 1
			if int(e.quiet) >= 5:
				_end_danger(int(p.id))
			continue
		if not danger:
			continue
		var own: float = world.roster.strength_of(p)
		var foe := float(hunted.get(p.id, 0.0))
		if foe <= 0.0:
			foe = world.threat_map().threat(p.x, p.y, world.threat_enemies(p.fac))
		var near := false
		for o in nobles:
			if o.fac != p.fac or is_same(o, p) or o.get("fight") != null or o.get("lock", false) or o.get("army", false):
				continue
			if Vector2(o.x - p.x, o.y - p.y).length() <= HELP_RADIUS and own + world.roster.strength_of(o) >= foe:
				near = true
				break
		_danger[int(p.id)] = {"fac": p.fac, "t0": steps, "foe": foe, "own": own, "near": near, "met": false, "quiet": 0,
			"fight": null, "side": -1, "helped": false, "lost": false, "chased": hunted.has(p.id)}

func _end_danger(pid: int) -> void:
	var e: Dictionary = _danger[pid]
	_danger.erase(pid)
	e.hours = (steps - int(e.t0)) * 0.2
	_danger_log.append(e)

## Danger episodes folded into the numbers of the summary.
func _danger_summary() -> Dictionary:
	for pid in _danger.keys():
		_end_danger(pid)
	var out := {"danger": _danger_log.size(), "danger_chased": 0, "danger_near": 0, "danger_near_met": 0, "danger_caught": 0,
		"danger_caught_helped": 0, "danger_lost": 0, "danger_near_lost": 0, "danger_hours_mean": 0.0}
	for e in _danger_log:
		out.danger_hours_mean += float(e.hours)
		if e.chased:
			out.danger_chased += 1
		if e.near:
			out.danger_near += 1
			if e.met:
				out.danger_near_met += 1
			if e.lost:
				out.danger_near_lost += 1
		if e.fight != null:
			out.danger_caught += 1
			if e.helped:
				out.danger_caught_helped += 1
		if e.lost:
			out.danger_lost += 1
	out.danger_hours_mean /= maxf(1.0, _danger_log.size())
	out.danger_near_met_rate = float(out.danger_near_met) / maxf(1.0, out.danger_near)
	out.danger_near_lost_rate = float(out.danger_near_lost) / maxf(1.0, out.danger_near)
	out.danger_caught_helped_rate = float(out.danger_caught_helped) / maxf(1.0, out.danger_caught)
	out.danger_lost_rate = float(out.danger_lost) / maxf(1.0, _danger_log.size())
	return out

## Fight records folded into the numbers of the summary.
func _help_summary() -> Dictionary:
	for id in _fights.keys():
		_close_fight(id)
	var out := {"fights": _fight_log.size(), "fights_own_near": 0, "fights_own_near_far": 0, "fight_hours_mean": 0.0, "fight_size_mean": 0.0,
		"joined": 0, "joined_far": 0, "joined_army": 0, "far_feasible_own": 0, "helped_far_own": 0, "timely_own": 0, "helped_timely_own": 0, "needed_own": 0, "helped_needed_own": 0}
	for k in ["own", "other", "bandit", "dead", "party"]:
		out["could_" + k] = 0
		out["feasible_" + k] = 0
		out["helped_" + k] = 0
		out["helped_feasible_" + k] = 0
	for rec in _fight_log:
		out.fight_hours_mean += float(rec.hours)
		out.fight_size_mean += float(rec.size)
		out.joined += rec.joined.size()
		out.joined_army += int(rec.get("army", 0))
		var own := false
		var own_far := false
		for pid in rec.could:
			var c: Dictionary = rec.could[pid]
			var k := String(c.kind)
			out["could_" + k] += 1
			var helped: bool = rec.joined.get(pid, -1) == int(c.side)
			if helped:
				out["helped_" + k] += 1
				if c.far:
					out.joined_far += 1
			if c.feasible:
				out["feasible_" + k] += 1
				if helped:
					out["helped_feasible_" + k] += 1
			if k == "own":
				own = true
				if c.far and c.feasible:
					out.far_feasible_own += 1
					if helped:
						out.helped_far_own += 1
				if c.get("timely", false):
					out.timely_own += 1
					if helped:
						out.helped_timely_own += 1
				if c.get("needed", false):
					out.needed_own += 1
					if helped:
						out.helped_needed_own += 1
				own_far = own_far or (c.far and c.feasible)
		if own:
			out.fights_own_near += 1
		if own_far:
			out.fights_own_near_far += 1
	out.fight_hours_mean /= maxf(1.0, _fight_log.size())
	out.fight_size_mean /= maxf(1.0, _fight_log.size())
	# who won: the side weaker at the start, and fights where someone joined the weaker side
	out.fight_size_end_mean = 0.0
	out.weak_fights = 0
	out.weak_won = 0
	out.weak_joined = 0
	out.weak_joined_won = 0
	for rec in _fight_log:
		out.fight_size_end_mean += float(rec.size + rec.joined.size())
		if not rec.has("s0") or int(rec.get("winner", -1)) < 0 or rec.s0[0] == rec.s0[1]:
			continue
		var weak := 0 if rec.s0[0] < rec.s0[1] else 1
		out.weak_fights += 1
		var won: bool = int(rec.winner) == weak
		if won:
			out.weak_won += 1
		if rec.joined.values().has(weak):
			out.weak_joined += 1
			if won:
				out.weak_joined_won += 1
	out.fight_size_end_mean /= maxf(1.0, _fight_log.size())
	out.weak_won_rate = float(out.weak_won) / maxf(1.0, out.weak_fights)
	out.weak_joined_rate = float(out.weak_joined) / maxf(1.0, out.weak_fights)
	out.help_rate_far_own = float(out.helped_far_own) / maxf(1.0, out.far_feasible_own)
	out.help_rate_timely_own = float(out.helped_timely_own) / maxf(1.0, out.timely_own)
	out.help_rate_needed_own = float(out.helped_needed_own) / maxf(1.0, out.needed_own)
	for k in ["own", "other", "bandit", "dead"]:
		out["help_rate_" + k] = float(out["helped_" + k]) / maxf(1.0, out["could_" + k])
		out["help_rate_feasible_" + k] = float(out["helped_feasible_" + k]) / maxf(1.0, out["feasible_" + k])
	return out

func _heat_index(x: float, y: float) -> int:
	return clampi(floori(y / HEAT_CELL), 0, heat_rows - 1) * heat_cols + clampi(floori(x / HEAT_CELL), 0, heat_cols - 1)

func _observe_heat() -> void:
	for p in world.roster.parties:
		if p.kind == "lord":
			heat_lords[_heat_index(p.x, p.y)] += 1
	for f in world.skirmish.fights:
		heat_fights[_heat_index(float(f.x), float(f.y))] += 1
	for s in world.map.settles:
		if s.get("siege") != null:
			heat_sieges[_heat_index(s.x, s.y)] += 1

func _observe_day(day: int) -> void:
	var total := 0
	var leader := ""
	var best := -1
	for f in Rules.REAL_FACTIONS:
		var n: int = world.wars.hold_of(f).all
		total += n
	var undead_n: int = world.wars.hold_of("undead").all
	var undead_core: int = world.wars.hold_of("undead").core
	var core_total := 0
	for s in world.map.settles:
		if s.kind == "town" or s.kind == "castle":
			core_total += 1
	total += undead_n
	for f in Rules.REAL_FACTIONS:
		var n: int = world.wars.hold_of(f).all
		if n > best:
			best = n
			leader = f
	var undead_troops := 0
	var undead_parties := 0
	var lords := {}
	for p in world.roster.parties:
		if p.fac == "undead":
			undead_parties += 1
			undead_troops += Rules.troop_count(p.troops)
		if p.kind == "lord":
			lords[p.fac] = int(lords.get(p.fac, 0)) + 1
	# Threat map: front length between warring states, and the cost of one rebuild (linear in parties).
	var m: ThreatMap = world.threat_map()
	var fronts := {}
	var front_cells := 0
	for k in world.wars.wars:
		var parts: PackedStringArray = String(k).split("|")
		var n_front := m.front(parts[0], parts[1]).size()
		fronts[k] = n_front
		front_cells += n_front
	var probe := ThreatMap.new(PartyAI.WW, PartyAI.WH)
	var src: Array = world.threat_sources()
	var t0 := Time.get_ticks_usec()
	probe.rebuild(src, hours)
	_threat_cost.usec += Time.get_ticks_usec() - t0
	_threat_cost.samples += 1
	_threat_cost.sources += probe.sources
	_threat_cost.cells += probe.stamped_cells
	_daily.append({"day": day, "leader": leader, "share": float(best) / maxf(1.0, float(total)), "wars": world.wars.wars.size(),
		"alive": world.wars.factions_alive().size(), "parties": world.roster.parties.size(), "lords": lords,
		"undead_parties": undead_parties, "undead_troops": undead_troops, "undead_settlements": undead_n,
		"undead_core_share": float(undead_core) / maxf(1.0, core_total),
		"front_cells": front_cells, "fronts": fronts})
	_observe_diplomacy(day)

## Diplomacy once a day (stage 2d). Neighbours are pairs of living states with towns or castles within the reach of
## world_wars.borders, the same test that allows a declaration of war.
func _observe_diplomacy(day: int) -> void:
	var alive: Array = world.wars.factions_alive()
	var pairs := 0
	var at_war := 0
	var neighbours := {}
	var hostile := {}
	var fronts := {}
	for i in alive.size():
		for j in range(i + 1, alive.size()):
			var a: String = alive[i]
			var b: String = alive[j]
			var war: bool = world.wars.at_war(a, b)
			if war:
				fronts[a] = int(fronts.get(a, 0)) + 1
				fronts[b] = int(fronts.get(b, 0)) + 1
			if not world.wars.borders(a, b):
				continue
			pairs += 1
			for f in [a, b]:
				neighbours[f] = int(neighbours.get(f, 0)) + 1
				if war:
					hostile[f] = int(hostile.get(f, 0)) + 1
			if war:
				at_war += 1
	var all_out := 0
	for f in alive:
		if int(neighbours.get(f, 0)) >= 2 and int(hostile.get(f, 0)) == int(neighbours[f]):
			all_out += 1
	var most := 0
	for f in fronts:
		most = maxi(most, int(fronts[f]))
	var weary := {}
	var tired: Variant = world.wars.get("weary")
	if tired is Dictionary:
		for f in tired:
			weary[f] = snappedf(float(tired[f]), 0.001)
	_diplo.append({"day": day, "wars": world.wars.wars.size(), "pairs": pairs, "pairs_at_war": at_war,
		"share": float(at_war) / maxf(1.0, pairs), "all_out": all_out, "most_fronts": most, "weary": weary})

static func _percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return float(v[clampi(ceili(q * v.size()) - 1, 0, v.size() - 1)])

func _jitter() -> Dictionary:
	var by_kind := {}
	for id in _party_stats:
		var st: Dictionary = _party_stats[id]
		var party_days: float = st.steps * 0.2 / 24.0
		if party_days < 1.0:
			continue  # too short-lived to give a rate
		if not by_kind.has(st.kind):
			by_kind[st.kind] = {"parties": 0, "goal": [], "state": [], "flip": 0, "days": 0.0, "over_limit": 0}
		var k: Dictionary = by_kind[st.kind]
		k.parties += 1
		k.goal.append(st.goal / party_days)
		k.state.append(st.state / party_days)
		k.flip += st.flip
		k.days += party_days
		if (st.goal + st.state) / party_days > JITTER_LIMIT_PER_DAY:
			k.over_limit += 1
	var out := {}
	for kind in by_kind:
		var k: Dictionary = by_kind[kind]
		var mean_goal := 0.0
		var mean_state := 0.0
		for v in k.goal:
			mean_goal += v
		for v in k.state:
			mean_state += v
		out[kind] = {"parties": k.parties, "goal_per_day_mean": mean_goal / k.parties, "goal_per_day_p95": _percentile(k.goal, 0.95),
			"goal_per_day_max": _percentile(k.goal, 1.0), "state_per_day_mean": mean_state / k.parties,
			"state_per_day_p95": _percentile(k.state, 0.95), "flipflops_per_day": k.flip / maxf(1.0, k.days), "over_limit": k.over_limit}
	return out

func _heat_land() -> PackedByteArray:
	var land := PackedByteArray()
	land.resize(heat_cols * heat_rows)
	var paths: RefCounted = world.map.paths
	for i in land.size():
		var x := (i % heat_cols + 0.5) * HEAT_CELL
		var y := (i / heat_cols + 0.5) * HEAT_CELL
		land[i] = 0 if int(paths.terr_at(x, y)) == 0 else 1  # terrain type 0 is sea
	return land

func _threat_final() -> Dictionary:
	var m: ThreatMap = world.threat_map()
	var facs := m.factions()
	var dominant := PackedInt32Array()
	var value := PackedFloat32Array()
	dominant.resize(m.cols * m.rows)
	value.resize(m.cols * m.rows)
	for i in m.cols * m.rows:
		var best := -1
		var bv := 0.0
		for j in facs.size():
			var v: float = m.layers[facs[j]][i]
			if v > bv:
				bv = v
				best = j
		dominant[i] = best
		value[i] = bv
	return {"cols": m.cols, "rows": m.rows, "cell": m.cell_size, "factions": facs, "dominant": Array(dominant), "value": Array(value)}

func report(seed_value: int, days: int) -> Dictionary:
	var ended := _war_log.filter(func(w): return w.ended >= 0)
	var peace := ended.filter(func(w): return w.how == "peace")
	var durations: Array = ended.map(func(w): return w.ended - w.declared)
	var ongoing: Array = []
	for k in _wars:
		ongoing.append({"key": k, "since": _wars[k], "days": _day() - int(_wars[k])})
	var mean_dur := 0.0
	for d in durations:
		mean_dur += d
	mean_dur /= maxf(1.0, durations.size())
	var max_share := 0.0
	var max_share_day := 0
	var max_leader := ""
	for d in _daily:
		if d.share > max_share:
			max_share = d.share
			max_share_day = d.day
			max_leader = d.leader
	var peak_troops := 0
	var peak_settlements := 0
	var peak_core := 0.0
	for d in _daily:
		peak_troops = maxi(peak_troops, d.undead_troops)
		peak_settlements = maxi(peak_settlements, d.undead_settlements)
		peak_core = maxf(peak_core, float(d.get("undead_core_share", 0.0)))
	var u_captures: Array = _undead.captures
	var u_core: Array = u_captures.filter(func(c): return c.kind == "town" or c.kind == "castle")
	var u_targets := 0
	for w in _undead.waves:
		if String(w.get("what", "")) == "target":
			u_targets += 1
	var sieges: Array = _siege_log.duplicate()
	for id in _sieges:
		var open: Dictionary = _sieges[id].duplicate()
		open.outcome = "ongoing"
		open.skip = _skip.get(id, {}).keys()
		sieges.append(open)
	var no_relief := sieges.filter(func(r): return not r.relief and r.helper_hours >= RELIEF_GRACE_HOURS)
	var no_help := no_relief.filter(func(r): return not r.get("defended", false))
	var declared := _war_log.filter(func(w): return not w.get("initial", false) and w.declared > 1)
	var diplo := _diplo_summary()
	var jitter := _jitter()
	var lord_j: Dictionary = jitter.get("lord", {})
	var help := _help_summary()
	help.merge(_danger_summary())
	help.merge(_caravan_summary())
	var summary := {
		"seed": seed_value, "days": days, "hours": hours, "wall_seconds": wall_usec / 1e6,
		"wars_declared": declared.size(), "wars_peace": peace.size(), "wars_ended": ended.size(), "war_days_mean": mean_dur,
		"wars_ongoing": ongoing.size(),
		"wars_at_once_mean": diplo.wars_mean, "wars_at_once_max": diplo.wars_max, "wars_day1": diplo.wars_day1, "wars_day50": diplo.wars_day50,
		"neighbour_war_share": diplo.share_mean, "neighbour_war_share_first30": diplo.share_first30, "neighbour_war_share_day50": diplo.share_day50,
		"all_neighbours_days": diplo.all_out_days, "most_fronts": diplo.most_fronts, "three_fronts_days": diplo.three_fronts_days,
		"initial_wars_end_day": diplo.initial_end, "peace_days_mean": diplo.peace_mean, "weary_max": diplo.weary_max,
		"hour_tick_usec": diplo.hour_usec, "hour_tick_p95_usec": diplo.hour_p95, "day_tick_usec": diplo.day_usec, "day_tick_p95_usec": diplo.day_p95,
		"owner_changes": _owner_log.size(), "owner_changes_to_undead": _owner_log.filter(func(o): return o.to == "undead").size(),
		"fallen": _fallen.map(func(f): return "%s@%d" % [f.fac, f.day]),
		"undead_start_day": _crisis.start_day, "undead_end_day": _crisis.end_day, "undead_peak_troops": peak_troops,
		"undead_peak_settlements": peak_settlements,
		"undead_armies": _undead.armies, "undead_raids": _undead.raids,
		"undead_first_capture_after": u_core[0].after if not u_core.is_empty() else -1,
		"undead_captures": u_core.size(), "undead_captures_by_day100": u_core.filter(func(c): return c.day <= 100).size(),
		"undead_storms": _undead.storms, "undead_storms_won": _undead.storms_won, "undead_burns": _undead.burns,
		"undead_retaken": _undead.retaken.size(), "undead_ruin_campaigns": _undead.ruin_campaigns, "undead_ruin_campaigns_won": _undead.ruin_campaigns_won,
		"undead_reach_mean": float(_undead.reach_sum) / maxf(1.0, _undead.reach_days), "undead_front_max": _undead.front_max,
		"undead_peak_core_share": peak_core, "undead_final_core_share": float(_daily.back().get("undead_core_share", 0.0)) if not _daily.is_empty() else 0.0,
		"undead_final_troops": _daily.back().undead_troops if not _daily.is_empty() else 0, "undead_armies_gone_day": _undead.armies_gone_day,
		"factions_alive_end": world.wars.factions_alive().size(),
		"undead_idle_share": float(_undead.idle_hours) / maxf(1.0, _undead.party_hours),
		"undead_gather_share": float(_undead.gather_hours) / maxf(1.0, _undead.party_hours),
		"undead_roam_share": float(_undead.roam_hours) / maxf(1.0, _undead.party_hours),
		"undead_stuck_12h": _undead.stuck, "undead_max_stand_hours": _undead.max_stand, "undead_targets": u_targets,
		"dead_goal_changes_per_day": jitter.get("dead", {}).get("goal_per_day_mean", 0.0),
		"raid_goal_changes_per_day": jitter.get("raid", {}).get("goal_per_day_mean", 0.0),
		"lords_died": _lord_log.died.size(), "lords_new": _lord_log.new.filter(func(l): return l.day > 1).size(),
		"lords_first_day": _lord_log.new.filter(func(l): return l.day <= 1).size(), "vassals_died": _vassal_log.died, "vassals_new": _vassal_log.new,
		"lord_goal_changes_per_day": lord_j.get("goal_per_day_mean", 0.0), "lord_goal_changes_p95": lord_j.get("goal_per_day_p95", 0.0),
		"lord_state_changes_per_day": lord_j.get("state_per_day_mean", 0.0), "lord_flipflops_per_day": lord_j.get("flipflops_per_day", 0.0),
		"parties_over_jitter_limit": jitter.values().reduce(func(a, k): return a + int(k.over_limit), 0),
		"max_share": max_share, "max_share_leader": max_leader, "max_share_day": max_share_day,
		"final_share": _daily.back().share if not _daily.is_empty() else 0.0, "final_leader": _daily.back().leader if not _daily.is_empty() else "",
		"sieges": sieges.size(), "sieges_with_relief": sieges.filter(func(r): return r.relief).size(),
		"sieges_no_relief_with_helper": no_relief.size(), "sieges_defended": sieges.filter(func(r): return r.get("defended", false)).size(),
		"sieges_no_help_with_helper": no_help.size(),
		"no_relief_busy": no_relief.filter(func(r): return "busy" in r.get("skip", [])).size(),
		"no_relief_weak": no_relief.filter(func(r): return "weak" in r.get("skip", []) and not "busy" in r.get("skip", [])).size(), "villages_burnt": _burns, "lord_goals": _share_text(_goal_shares().get("lord", {})),
		"campaigns": _ops.campaigns, "campaign_lords": float(_ops.lords_out) / maxf(1.0, _ops.campaigns),
		"campaign_kept": float(_ops.kept) / maxf(1.0, _ops.campaigns), "retreats_weak": _ops.retreat_weak, "retreats_home": _ops.retreat_home,
		"relief_sent": _ops.relief, "march_with_marshal": _ops.march_share / maxf(1.0, _ops.march_hours),
		"edge_idle_party_hours": _edge.party_hours, "edge_stuck_6h": _edge.streaks, "edge_max_streak_hours": _edge.max_streak,
		"flees": _flees.count, "flees_measured": _flees.measured,
		"flees_into_more_threat": float(_flees.into_more_threat) / maxf(1.0, _flees.measured),
		"flee_threat_ratio": _flees.dest_ratio_sum / maxf(1.0, _flees.measured),
		"threat_safe_cell_ratio": _flees.safe_ratio_sum / maxf(1.0, _flees.measured),
		"threat_safe_cell_better": float(_flees.safe_better) / maxf(1.0, _flees.measured),
		"threat_rebuild_usec": float(_threat_cost.usec) / maxf(1.0, _threat_cost.samples),
		"threat_cells_per_party": float(_threat_cost.cells) / maxf(1.0, _threat_cost.sources),
	}
	summary.merge(help)
	return {
		"summary": summary,
		"config": {"seed": seed_value, "days": days, "culture": CULTURE, "player": "away", "heat_cell": HEAT_CELL, "edge_margin": EDGE_MARGIN,
			"jitter_limit_per_day": JITTER_LIMIT_PER_DAY, "relief_scan_radius": RELIEF_SCAN_RADIUS, "relief_grace_hours": RELIEF_GRACE_HOURS},
		"wars": {"log": _war_log, "ongoing": ongoing},
		"diplomacy": _diplo,
		"owners": _owner_log,
		"fallen": _fallen,
		"undead": _crisis,
		"undead_detail": {"captures": _undead.captures, "retaken": _undead.retaken, "waves": _undead.waves},
		"lords": {"died": _lord_log.died, "new": _lord_log.new},
		"jitter": jitter,
		"goal_shares": _goal_shares(),
		"operations": _ops_log,
		"sieges": sieges,
		"edge": _edge,
		"daily": _daily,
		"heat": {"cols": heat_cols, "rows": heat_rows, "cell": HEAT_CELL, "land": Array(_heat_land()),
			"lords": Array(heat_lords), "fights": Array(heat_fights), "sieges": Array(heat_sieges)},
		"threat_final": _threat_final(),
		"settlements": world.map.settles.filter(func(s): return s.kind == "town" or s.kind == "castle").map(func(s): return {"x": s.x, "y": s.y, "kind": s.kind, "fac": s.fac}),
		"colors": _colors(),
	}

## Day rows of _observe_diplomacy and the tick costs folded into summary numbers.
func _diplo_summary() -> Dictionary:
	var out := {"wars_mean": 0.0, "wars_max": 0, "wars_day1": 0, "wars_day50": -1, "share_mean": 0.0, "share_first30": 0.0,
		"share_day50": -1.0, "all_out_days": 0, "most_fronts": 0, "three_fronts_days": 0, "initial_end": -1, "peace_mean": -1.0,
		"weary_max": 0.0, "hour_usec": 0.0, "hour_p95": 0.0, "day_usec": 0.0, "day_p95": 0.0}
	var first30 := 0
	for d in _diplo:
		out.wars_mean += float(d.wars)
		out.share_mean += float(d.share)
		out.wars_max = maxi(out.wars_max, int(d.wars))
		out.most_fronts = maxi(out.most_fronts, int(d.most_fronts))
		if int(d.all_out) > 0:
			out.all_out_days += 1
		if int(d.most_fronts) >= 3:
			out.three_fronts_days += 1
		if int(d.day) == 1:
			out.wars_day1 = int(d.wars)
		if int(d.day) == 50:
			out.wars_day50 = int(d.wars)
			out.share_day50 = float(d.share)
		if int(d.day) <= 30:
			out.share_first30 += float(d.share)
			first30 += 1
		for f in d.weary:
			out.weary_max = maxf(out.weary_max, float(d.weary[f]))
	out.wars_mean /= maxf(1.0, _diplo.size())
	out.share_mean /= maxf(1.0, _diplo.size())
	out.share_first30 /= maxf(1.0, first30)
	# the last of the wars the world started with ended on this day (or is still on)
	for w in _war_log:
		if w.get("initial", false) or int(w.declared) <= 1:
			out.initial_end = maxi(out.initial_end, int(w.ended) if int(w.ended) >= 0 else _day())
	for k in _wars:
		if int(_wars[k]) <= 1:
			out.initial_end = _day()
	# days of peace between the end of a war and the next war of the same pair
	var by_key := {}
	for w in _war_log:
		if not by_key.has(w.key):
			by_key[w.key] = []
		by_key[w.key].append(w)
	var gaps := 0
	var gap_sum := 0.0
	for k in by_key:
		var list: Array = by_key[k]
		list.sort_custom(func(x, y): return int(x.declared) < int(y.declared))
		for i in range(1, list.size()):
			if int(list[i - 1].ended) >= 0:
				gaps += 1
				gap_sum += float(int(list[i].declared) - int(list[i - 1].ended))
	if gaps > 0:
		out.peace_mean = gap_sum / gaps
	for kind in ["hour", "day"]:
		var v: Array = _tick_usec[kind]
		var sum := 0.0
		for x in v:
			sum += float(x)
		out[kind + "_usec"] = sum / maxf(1.0, v.size())
		out[kind + "_p95"] = _percentile(v, 0.95)
	return out

func _colors() -> Dictionary:
	var out := {}
	for f in Rules.REAL_FACTIONS + ["bandit", "undead"]:
		out[f] = String(world.roster.factions.get_faction(f).get("c1", "#888888"))
	out["player"] = "#d4a017"
	return out
