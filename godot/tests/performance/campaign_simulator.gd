extends RefCounted
## Campaign simulator (docs/modules/ai/DESIGN.md §7.2): the world runs without the player for N days on a fixed seed
## while an observer only reads it. The world goes through the same clock as the game (clock.advance -> step/hour_tick);
## the observer spends no RNG and changes nothing, so the same seed gives the same world with or without it.
## Invariants of §7.2 are measured, not enforced. Since stage 2a the goal of a party (party_goals.gd) is part of the
## "goal" that the jitter metric watches, next to tid/sid/chase of the player; before 2a parties had no goal field.
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
	drive(w, days * 24, sim.observe_step, sim.observe_hour)
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

## Villages that caught fire this hour: the dead burn them, since stage 2a lords raid them too.
func _observe_burns() -> void:
	for s in world.map.settles:
		var on := int(s.get("burnt", 0)) > 0
		if on and not _burnt.get(s.id, false):
			_burns += 1
		_burnt[s.id] = on

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
		"front_cells": front_cells, "fronts": fronts})

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
	for d in _daily:
		peak_troops = maxi(peak_troops, d.undead_troops)
		peak_settlements = maxi(peak_settlements, d.undead_settlements)
	var sieges: Array = _siege_log.duplicate()
	for id in _sieges:
		var open: Dictionary = _sieges[id].duplicate()
		open.outcome = "ongoing"
		sieges.append(open)
	var no_relief := sieges.filter(func(r): return not r.relief and r.helper_hours >= RELIEF_GRACE_HOURS)
	var no_help := no_relief.filter(func(r): return not r.get("defended", false))
	var declared := _war_log.filter(func(w): return not w.get("initial", false) and w.declared > 1)
	var jitter := _jitter()
	var lord_j: Dictionary = jitter.get("lord", {})
	var summary := {
		"seed": seed_value, "days": days, "hours": hours, "wall_seconds": wall_usec / 1e6,
		"wars_declared": declared.size(), "wars_peace": peace.size(), "wars_ended": ended.size(), "war_days_mean": mean_dur,
		"wars_ongoing": ongoing.size(),
		"owner_changes": _owner_log.size(), "owner_changes_to_undead": _owner_log.filter(func(o): return o.to == "undead").size(),
		"fallen": _fallen.map(func(f): return "%s@%d" % [f.fac, f.day]),
		"undead_start_day": _crisis.start_day, "undead_end_day": _crisis.end_day, "undead_peak_troops": peak_troops,
		"undead_peak_settlements": peak_settlements,
		"lords_died": _lord_log.died.size(), "lords_new": _lord_log.new.filter(func(l): return l.day > 1).size(),
		"lords_first_day": _lord_log.new.filter(func(l): return l.day <= 1).size(), "vassals_died": _vassal_log.died, "vassals_new": _vassal_log.new,
		"lord_goal_changes_per_day": lord_j.get("goal_per_day_mean", 0.0), "lord_goal_changes_p95": lord_j.get("goal_per_day_p95", 0.0),
		"lord_state_changes_per_day": lord_j.get("state_per_day_mean", 0.0), "lord_flipflops_per_day": lord_j.get("flipflops_per_day", 0.0),
		"parties_over_jitter_limit": jitter.values().reduce(func(a, k): return a + int(k.over_limit), 0),
		"max_share": max_share, "max_share_leader": max_leader, "max_share_day": max_share_day,
		"final_share": _daily.back().share if not _daily.is_empty() else 0.0, "final_leader": _daily.back().leader if not _daily.is_empty() else "",
		"sieges": sieges.size(), "sieges_with_relief": sieges.filter(func(r): return r.relief).size(),
		"sieges_no_relief_with_helper": no_relief.size(), "sieges_defended": sieges.filter(func(r): return r.get("defended", false)).size(),
		"sieges_no_help_with_helper": no_help.size(), "villages_burnt": _burns, "lord_goals": _share_text(_goal_shares().get("lord", {})),
		"edge_idle_party_hours": _edge.party_hours, "edge_stuck_6h": _edge.streaks, "edge_max_streak_hours": _edge.max_streak,
		"flees": _flees.count, "flees_measured": _flees.measured,
		"flees_into_more_threat": float(_flees.into_more_threat) / maxf(1.0, _flees.measured),
		"flee_threat_ratio": _flees.dest_ratio_sum / maxf(1.0, _flees.measured),
		"threat_safe_cell_ratio": _flees.safe_ratio_sum / maxf(1.0, _flees.measured),
		"threat_safe_cell_better": float(_flees.safe_better) / maxf(1.0, _flees.measured),
		"threat_rebuild_usec": float(_threat_cost.usec) / maxf(1.0, _threat_cost.samples),
		"threat_cells_per_party": float(_threat_cost.cells) / maxf(1.0, _threat_cost.sources),
	}
	return {
		"summary": summary,
		"config": {"seed": seed_value, "days": days, "culture": CULTURE, "player": "away", "heat_cell": HEAT_CELL, "edge_margin": EDGE_MARGIN,
			"jitter_limit_per_day": JITTER_LIMIT_PER_DAY, "relief_scan_radius": RELIEF_SCAN_RADIUS, "relief_grace_hours": RELIEF_GRACE_HOURS},
		"wars": {"log": _war_log, "ongoing": ongoing},
		"owners": _owner_log,
		"fallen": _fallen,
		"undead": _crisis,
		"lords": {"died": _lord_log.died, "new": _lord_log.new},
		"jitter": jitter,
		"goal_shares": _goal_shares(),
		"sieges": sieges,
		"edge": _edge,
		"daily": _daily,
		"heat": {"cols": heat_cols, "rows": heat_rows, "cell": HEAT_CELL, "land": Array(_heat_land()),
			"lords": Array(heat_lords), "fights": Array(heat_fights), "sieges": Array(heat_sieges)},
		"threat_final": _threat_final(),
		"settlements": world.map.settles.filter(func(s): return s.kind == "town" or s.kind == "castle").map(func(s): return {"x": s.x, "y": s.y, "kind": s.kind, "fac": s.fac}),
		"colors": _colors(),
	}

func _colors() -> Dictionary:
	var out := {}
	for f in Rules.REAL_FACTIONS + ["bandit", "undead"]:
		out[f] = String(world.roster.factions.get_faction(f).get("c1", "#888888"))
	out["player"] = "#d4a017"
	return out
