extends SceneTree
## AI arena (DESIGN.md 7.1): a headless series of whole battles on fixed seeds, AI against AI, with a JSON
## report and a short table. Not the quick battle from the menu and not a speed benchmark: the AI phase time
## is reported for comparison between profiles, the release budget is measured separately.
##
##   godot --headless --path godot --script res://tests/performance/battle_arena.gd -- \
##     --scenarios=mixed,infantry_cavalry,archers,siege,kite,spears --sizes=100,500,1000 --runs=8 --seed=4242 \
##     --profiles=reference,reference --max-seconds=240 --backend=native --mirror --out=arena.json
##
## Profiles are BattleSetup AI profiles (ADR-022): the first plays side 0, the second side 1; --mirror adds a
## run with sides swapped for every seed, so a profile is not favoured by its side. The hero leaves the
## field before the battle, except in "kite", where he rides a scripted circle in front of the enemy line
## and side 0 follows player orders (it holds), as in tests/integration/test_ai_kite.gd. In "hold" and
## "hold_archers" (stage 1g, DESIGN.md 4.2.1) side 0 follows player orders too and stands where it deployed, the
## hero gone: the second profile attacks a standing line with archers. These are not mirrored.
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")
const Benchmark = preload("res://tests/performance/battle_benchmark.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")

const VERSION := 9 # 2: volley metrics. 3: stage 1v doctrine metrics. 4: stage 1b morale metrics. 5: contact time, stuck (TERRAIN Р0). 6: terrain rules (Р1а): undrawn templates, wins by side in the table. 7: shooters on high ground (Р3). 8: hold scenarios and the time under fire before the first melee contact (1g; the number stayed 7 by mistake). 9: the first blow of the cavalry, on whom and when, and its first blow on shooters (1g part 4).
const SCENARIOS := ["mixed", "infantry_cavalry", "archers", "siege", "kite", "spears", "equal", "hold", "hold_archers"]
# Side 0 follows player orders: it stands where it deployed, the hero has left; side 1 plays the second profile.
const PLAYER_HOLDS := ["kite", "hold", "hold_archers"]
const SIZES := [100, 500, 1000]
const TICK_SECONDS := 1.0 / 60.0
const SAMPLE_TICKS := 30 # Idle sampling every 0.5 s.
const KITE_SAMPLE_TICKS := 15 # Chase check every 0.25 s.
const KITE_CHASE_SECONDS := 5.0 # DESIGN.md 7.3: share of enemy infantry chasing the hero longer than this.
const KITE_HERO_SPEED := 160.0
const KITE_ORBIT_RADIUS := 150.0
const KITE_SAMPLE_LIMIT := 64
const IDLE_MODES := [0, 1] # MotionStore.MODES: unassigned and slot.
const COMBAT_MODES := [2, 3, 4, 5] # MotionStore.MODES: melee, shoot, shootslot, skirm.
# Stage 1v doctrine modes (MotionStore.MODES), neither idle nor fighting: a man keeping his place in a formed line,
# a spearman braced against a rider, an archer stepping back from infantry.
const DOCTRINE_MODES := {"rank": 6, "brace": 7, "fallback": 8}
const VOLLEY_TICKS := 60 # Shots of one side within 1 s form a volley.
const VOLLEY_MIN_SHOTS := 10 # Shorter windows are stray shots, not volleys.
# TERRAIN.md 8: a fighter in melee mode whose target stays farther than STUCK_REACH and who does not close in by
# STUCK_PROGRESS for STUCK_SECONDS is stuck. On the open field these are the back ranks pressing on a crowd.
const MELEE_MODE := 2 # MotionStore.MODES "melee".
const STUCK_SECONDS := 5.0
const STUCK_REACH := 150.0
const STUCK_PROGRESS := 20.0
const CONTACT_ATTACKS := [Event.Attack.MELEE, Event.Attack.CHARGE, Event.Attack.COUNTER]

static func default_options() -> Dictionary:
	return {"scenarios": SCENARIOS.duplicate(), "sizes": [100], "runs": 4, "seed": 4242, "max_seconds": 240.0,
		"profiles": [Config.AI_PROFILE_REFERENCE, Config.AI_PROFILE_REFERENCE], "backend": "native",
		"mirror": false, "phase_profile": true, "terrain": ""}

func _initialize() -> void:
	var options := default_options()
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenarios="): options.scenarios = Array(arg.trim_prefix("--scenarios=").split(","))
		elif arg.begins_with("--sizes="): options.sizes = Array(arg.trim_prefix("--sizes=").split(",")).map(func(v): return int(v))
		elif arg.begins_with("--runs="): options.runs = int(arg.trim_prefix("--runs="))
		elif arg.begins_with("--seed="): options.seed = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--max-seconds="): options.max_seconds = float(arg.trim_prefix("--max-seconds="))
		elif arg.begins_with("--profiles="): options.profiles = Array(arg.trim_prefix("--profiles=").split(","))
		elif arg.begins_with("--backend="): options.backend = arg.trim_prefix("--backend=")
		elif arg == "--mirror": options.mirror = true
		# TERRAIN Р0б: a field template; Р1а scenarios (TERRAIN.md 8): edge (forest on a flank), center_hill, river.
		elif arg.begins_with("--terrain="): options.terrain = arg.trim_prefix("--terrain=")
		elif arg == "--no-phase-profile": options.phase_profile = false
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	var problem := validate(options)
	if not problem.is_empty():
		push_error(problem)
		quit(1)
		return
	var catalog := Catalog.new()
	if not Loader.populate(catalog):
		push_error("Catalog failed to load")
		quit(1)
		return
	var report := run_matrix(options, catalog)
	if report.has("error"):
		push_error(report.error)
		quit(1)
		return
	print(table(report))
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write arena report")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "  ") + "\n")
		print("Arena report: ", out)
	quit(0)

static func validate(options: Dictionary) -> String:
	for scenario in options.scenarios:
		if scenario not in SCENARIOS: return "Unknown arena scenario: %s" % scenario
	for size in options.sizes:
		if int(size) < 4: return "Arena size must be at least 4 per side"
	if int(options.runs) < 1 or float(options.max_seconds) <= 0.0: return "Invalid runs or max seconds"
	if options.profiles.size() != 2: return "Two profiles are needed: side 0 and side 1"
	if options.backend not in ["native", "gdscript"]: return "Unknown backend: %s" % options.backend
	return ""

## Every scenario x size cell, runs seeds seed, seed+1, ...; with mirror, each seed is played both ways.
static func run_matrix(options: Dictionary, catalog: Catalog) -> Dictionary:
	var problem := validate(options)
	if not problem.is_empty(): return {"error": problem}
	var cells: Array[Dictionary] = []
	for scenario in options.scenarios:
		for size in options.sizes:
			var runs: Array[Dictionary] = []
			for run in int(options.runs):
				# The kite and the hold scenarios have a player side; mirroring them would only repeat the battle.
				for swapped in ([false, true] if options.mirror and scenario not in PLAYER_HOLDS else [false]):
					var battle := run_battle(scenario, int(size), int(options.seed) + run, options, catalog, swapped)
					if battle.has("error"): return {"error": "%s %d: %s" % [scenario, size, battle.error]}
					runs.append(battle)
			cells.append({"scenario": scenario, "size": int(size), "runs": runs, "summary": summarize(runs)})
	return {"version": VERSION, "engine": Engine.get_version_info().string, "debug": OS.is_debug_build(),
		"options": options.duplicate(true), "cells": cells,
		"note": "Headless arena; AI phase times are diagnostic samples, not the release budget."}

static func setup_for(scenario: String, size: int, seed: int, profiles: Array, swapped: bool, options_terrain := "") -> Setup:
	var setup: Setup = load("res://content/scenarios/demo_siege.tres" if scenario == "siege" else "res://content/scenarios/demo_battle.tres").to_setup()
	setup.seed = seed
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_unit_cap = size
	setup.enemy_unit_cap = size
	var armies := _armies(scenario, size)
	var sides := [0, 1] if not swapped else [1, 0]
	# In a siege the walls stay with side 1; swapping only exchanges the profiles there.
	setup.player_army.assign(armies[sides[0]] if scenario != "siege" else armies[0])
	setup.enemy_army.assign(armies[sides[1]] if scenario != "siege" else armies[1])
	setup.player_ai_profile = profiles[1 if swapped else 0]
	setup.enemy_ai_profile = profiles[0 if swapped else 1]
	setup.terrain = Templates.sample(str(options_terrain)) if scenario != "siege" else {}
	if scenario in PLAYER_HOLDS:
		setup.player_ai_profile = Config.AI_PROFILE_PLAYER
		setup.enemy_ai_profile = profiles[1]
	return setup

static func _armies(scenario: String, size: int) -> Array:
	match scenario:
		"infantry_cavalry":
			return [[{"type": "n1", "n": size}], [{"type": "e3c", "n": size}]]
		"archers":
			var archers := roundi(size * 0.6)
			return [[{"type": "n1", "n": size - archers}, {"type": "n2a", "n": archers}], [{"type": "e1", "n": size - archers}, {"type": "e2a", "n": archers}]]
		"kite", "hold_archers":
			# hold_archers (stage 1g): the kite army without the hero holds its ground against foot without bows.
			var foot := size / 2
			return [[{"type": "n1", "n": foot}, {"type": "n2a", "n": size - foot}], [{"type": "e1", "n": size}]]
		"equal", "hold":
			# hold (stage 1g): the same army as in "equal", side 0 holds its ground against the AI.
			# TERRAIN.md 8 (stage Р1а): the same mixed army on both sides, so the wins by side measure the ground alone.
			var army := [{"type": "n1", "n": size / 2}, {"type": "n2a", "n": size / 3}, {"type": "n3c", "n": size - size / 2 - size / 3}]
			return [army, army.duplicate(true)]
		"spears":
			# Stage 1v: foot with spearmen and archers against shock cavalry with foot.
			var spears := roundi(size * 0.3)
			var bows := roundi(size * 0.3)
			var riders := size / 2
			return [[{"type": "n1", "n": size - spears - bows}, {"type": "n2s", "n": spears}, {"type": "n2a", "n": bows}],
				[{"type": "e3c", "n": riders}, {"type": "e1", "n": size - riders}]]
	var infantry := size / 2
	var archers := size / 3
	var cavalry := size - infantry - archers
	return [[{"type": "n1", "n": infantry}, {"type": "n2a", "n": archers}, {"type": "n3c", "n": cavalry}],
		[{"type": "e1", "n": infantry}, {"type": "e2a", "n": archers}, {"type": "e3c", "n": cavalry}]]

## One battle to the decision or to max_seconds. Metrics only read the state and the events.
static func run_battle(scenario: String, size: int, seed: int, options: Dictionary, catalog: Catalog, swapped: bool = false) -> Dictionary:
	var setup := setup_for(scenario, size, seed, options.profiles, swapped, str(options.get("terrain", "")))
	var native: bool = options.backend == "native"
	var session = Factory.create(setup, catalog, null, null, null, Contacts.create() if native else Callable(),
		Movement.create() if native else Callable(), Columns.create() if native else null)
	if session == null: return {"error": "cannot create battle"}
	Benchmark.lay_undrawn(session, setup)
	var state = session._state
	var hero = session._hero
	var initial := [0, 0]
	for unit in state.units:
		if unit.hero or unit.companion: continue
		if unit.weight != 1.0: return {"error": "weighted units cannot stand in for soldiers"}
		initial[unit.side] += 1
	if initial[0] != size or initial[1] != size: return {"error": "population %s instead of %d" % [str(initial), size]}
	var kite := scenario == "kite"
	if kite:
		_prepare_kite(session)
	else:
		state.mark_gone(hero) # The hero leaves before the battle: AI against AI only.
	if options.phase_profile: state.profiler.clock = Time.get_ticks_usec
	var max_ticks := ceili(float(options.max_seconds) / TICK_SECONDS)
	var ai_samples: Array[int] = []
	var engaged := {}
	var idle_samples := [0, 0]
	var unit_samples := [0, 0]
	var doctrine_samples := {}
	for key in DOCTRINE_MODES: doctrine_samples[key] = [0, 0]
	var rallies := [0, 0]
	var rallying := [false, false]
	var decided_at := -1.0
	var chase := {}
	var chased_long := {}
	var reached_archers := -1.0
	var input := HeroInput.new()
	var volleys := volley_tracker()
	var morale := morale_tracker(state, initial)
	var riders := cavalry_tracker()
	var contact_at := -1.0
	var progress := {}
	var stuck := {}
	var high_samples := [0, 0]
	var shooter_samples := [0, 0]
	var started := Time.get_ticks_msec()
	var tick := 0
	while tick < max_ticks:
		if kite: _circle(session, input)
		session.step()
		tick += 1
		if options.phase_profile: ai_samples.append(int(state.profiler.samples.get("tactics_siege", 0)))
		for event in session.take_events():
			if event.kind == Event.Kind.BATTLE_DECIDED and decided_at < 0.0:
				decided_at = tick * TICK_SECONDS
			elif event.kind == Event.Kind.SHOT:
				track_shot(volleys, state, int(event.target_id), tick)
			elif event.kind in [Event.Kind.WAVERED, Event.Kind.FLED, Event.Kind.DOWN]:
				track_morale(morale, state, event, tick)
			if contact_at < 0.0 and event.kind in [Event.Kind.HIT, Event.Kind.BLOCK] and event.attack in CONTACT_ATTACKS:
				contact_at = tick * TICK_SECONDS
			if event.kind in [Event.Kind.HIT, Event.Kind.BLOCK] and event.attack in CONTACT_ATTACKS:
				track_cavalry(riders, morale, state, event, tick)
		advance_volleys(volleys, tick)
		if tick % SAMPLE_TICKS == 0 and decided_at < 0.0:
			_sample_idle(state, engaged, idle_samples, unit_samples, doctrine_samples)
			sample_stuck(state, progress, stuck, tick * TICK_SECONDS)
			sample_high(state, high_samples, shooter_samples)
			sample_rallies(morale)
			for side in 2:
				var rally: bool = state.groups[side][Config.GROUP_CAVALRY].get("rally") == true # Absent before stage 1v.
				if rally and not rallying[side]: rallies[side] += 1
				rallying[side] = rally
		if kite and tick % KITE_SAMPLE_TICKS == 0:
			_sample_chase(session, chase, chased_long)
			if reached_archers < 0.0 and _infantry_reached_archers(state):
				reached_archers = tick * TICK_SECONDS
		if session._outcome in [session.Outcome.VICTORY, session.Outcome.DEFEAT]: break
	var outcome = session._outcome
	var winner := -1
	if outcome == session.Outcome.VICTORY: winner = 0
	elif outcome == session.Outcome.DEFEAT: winner = 1
	var dead := [0, 0]
	var fled := [0, 0]
	var never := [0, 0]
	for unit in state.units:
		if unit.hero or unit.companion: continue
		if unit.dead: dead[unit.side] += 1
		elif unit.fleeing or unit.gone: fled[unit.side] += 1
		if not engaged.has(unit.id): never[unit.side] += 1
	var stuck_sides := [0, 0]
	for id in stuck: stuck_sides[stuck[id]] += 1
	var profile_side := [1, 0] if swapped and not kite else [0, 1] # Side of options.profiles[0] and [1].
	var result := {"scenario": scenario, "size": size, "seed": seed, "swapped": swapped,
		"profiles": session.ai_profiles(), "winner": winner,
		"winner_profile": profile_side.find(winner) if winner >= 0 else -1,
		"decided": decided_at >= 0.0, "duration_seconds": decided_at if decided_at >= 0.0 else tick * TICK_SECONDS,
		"ticks": tick, "initial": initial,
		"losses": [float(dead[0]) / initial[0], float(dead[1]) / initial[1]],
		"fled": [float(fled[0]) / initial[0], float(fled[1]) / initial[1]],
		"never_engaged": [float(never[0]) / initial[0], float(never[1]) / initial[1]],
		"idle_time": [float(idle_samples[0]) / maxi(1, unit_samples[0]), float(idle_samples[1]) / maxi(1, unit_samples[1])],
		"contact_seconds": contact_at,
		"under_fire_seconds": [under_fire_seconds(volleys, 0, contact_at, tick), under_fire_seconds(volleys, 1, contact_at, tick)],
		"stuck": [float(stuck_sides[0]) / initial[0], float(stuck_sides[1]) / initial[1]],
		"arena_size": [state.arena_size.x, state.arena_size.y], "terrain": state.terrain_template,
		"archers_high": [float(high_samples[0]) / shooter_samples[0] if shooter_samples[0] > 0 else -1.0, float(high_samples[1]) / shooter_samples[1] if shooter_samples[1] > 0 else -1.0],
		"wall_ms": Time.get_ticks_msec() - started}
	result.doctrine = {"rallies": rallies}
	for key in DOCTRINE_MODES:
		result.doctrine[key] = [float(doctrine_samples[key][0]) / maxi(1, unit_samples[0]), float(doctrine_samples[key][1]) / maxi(1, unit_samples[1])]
	if options.phase_profile: result.ai_phase = Benchmark.stats(ai_samples) if not ai_samples.is_empty() else {}
	result.volleys = volley_report(volleys)
	result.morale = morale_report(morale)
	result.cavalry = riders.duplicate(true)
	if kite:
		result.kite = {"chase_share": float(chased_long.size()) / maxi(1, initial[1]),
			"reached_archers_seconds": reached_archers}
	return result

## Volley metrics (DESIGN.md 4.4, stage 1a-archers), read from SHOT events and the state only. A shot aims at
## the shooter's current target. It is "doomed" when arrows already in flight to that target are expected to kill
## it (expected damage per arrow: damage x TARGET_VOLLEY_HIT_SHARE), "dead" when the target died while the arrow
## was still in flight. An arrow landing on the tick its target dies counts as landed. Volleys: 1 s windows per
## side with at least VOLLEY_MIN_SHOTS shots; the first volley is each side's first such window.
## Stage 1g (DESIGN.md 4.2.1): seconds a side was shot at before the first melee contact of the battle (to the end
## without one); 0 when it was never shot at. The attacker of a holding line spends them walking under the arrows.
static func under_fire_seconds(tracker: Dictionary, side: int, contact_at: float, ticks: int) -> float:
	var first: int = tracker.first_shot_at[side]
	if first < 0: return 0.0
	var until := contact_at if contact_at >= 0.0 else ticks * TICK_SECONDS
	return maxf(0.0, until - first * TICK_SECONDS)

static func volley_tracker() -> Dictionary:
	return {"ids": {}, "flight": [], "expected": {}, "shots": 0, "aimed": 0, "doomed": 0, "dead": 0,
		"window": [{}, {}], "window_start": [-1, -1], "window_shots": [0, 0], "volleys": 0, "volley_targets": 0,
		"volley_shots": 0, "first": [{}, {}], "first_shot_at": [-1, -1]}

static func track_shot(tracker: Dictionary, state, shooter_id: int, tick: int) -> void:
	var ids: Dictionary = tracker.ids
	if not ids.has(shooter_id):
		for unit in state.units: ids[unit.id] = unit
	var shooter = ids.get(shooter_id)
	if shooter == null or shooter.hero: return
	tracker.shots += 1
	if tracker.first_shot_at[1 - shooter.side] < 0:
		tracker.first_shot_at[1 - shooter.side] = tick # The other side is under fire from now on.
	var target = state.unit_for(shooter.target_handle)
	if target == null: return
	tracker.aimed += 1
	var expected: Dictionary = tracker.expected
	var before: float = expected.get(target, 0.0)
	var doomed: bool = before >= target.hp
	if doomed: tracker.doomed += 1
	var arrow: float = shooter.damage * Config.TARGET_VOLLEY_HIT_SHARE
	expected[target] = before + arrow
	var duration: float = Combat._flight_duration(shooter, shooter.position.distance_to(target.position))
	tracker.flight.append([target, tick + maxi(0, ceili(duration / TICK_SECONDS) - 1), arrow, doomed])
	var side: int = shooter.side
	if tracker.window_start[side] < 0 or tick - tracker.window_start[side] >= VOLLEY_TICKS:
		_close_volley(tracker, side)
		tracker.window_start[side] = tick
	tracker.window[side][target] = true
	tracker.window_shots[side] += 1

static func advance_volleys(tracker: Dictionary, tick: int) -> void:
	var flight: Array = tracker.flight
	var expected: Dictionary = tracker.expected
	var kept := 0
	for arrow in flight:
		var target = arrow[0]
		var landed: bool = arrow[1] <= tick
		if landed or target.dead or target.gone:
			if not landed and not arrow[3]: tracker.dead += 1
			expected[target] = float(expected.get(target, 0.0)) - arrow[2]
			if expected[target] <= 1e-9: expected.erase(target)
			continue
		flight[kept] = arrow
		kept += 1
	flight.resize(kept)

static func _close_volley(tracker: Dictionary, side: int) -> void:
	var shots: int = tracker.window_shots[side]
	if shots >= VOLLEY_MIN_SHOTS:
		var targets: int = tracker.window[side].size()
		tracker.volleys += 1
		tracker.volley_targets += targets
		tracker.volley_shots += shots
		if tracker.first[side].is_empty(): tracker.first[side] = {"shots": shots, "targets": targets}
	tracker.window[side] = {}
	tracker.window_shots[side] = 0

static func volley_report(tracker: Dictionary) -> Dictionary:
	for side in 2: _close_volley(tracker, side)
	var first_shots := 0
	var first_targets := 0
	var first_sides := 0
	for side in 2:
		if tracker.first[side].is_empty(): continue
		first_sides += 1
		first_shots += int(tracker.first[side].shots)
		first_targets += int(tracker.first[side].targets)
	var aimed: int = maxi(1, tracker.aimed)
	return {"shots": tracker.shots, "aimed": tracker.aimed,
		"doomed_share": float(tracker.doomed) / aimed, "dead_share": float(tracker.dead) / aimed,
		"wasted_share": float(tracker.doomed + tracker.dead) / aimed,
		"volleys": tracker.volleys,
		"targets_per_volley": float(tracker.volley_targets) / tracker.volleys if tracker.volleys > 0 else 0.0,
		"shots_per_target": float(tracker.volley_shots) / tracker.volley_targets if tracker.volley_targets > 0 else 0.0,
		"first_volley_shots": float(first_shots) / first_sides if first_sides > 0 else 0.0,
		"first_volley_targets": float(first_targets) / first_sides if first_sides > 0 else 0.0}

## Cavalry metrics (DESIGN.md 4.2.4, stage 1g part 4), read from HIT and BLOCK events of melee blows: per side, the
## time and the target class (FieldAssessment.unit_class) of the first blow of a rider (mounted, no ranged attack) and
## the time of his side's first blow on a shooter on foot; -1 when it never came. A first blow on cavalry is the
## cavalry meeting the enemy cavalry instead of reaching the line or the shooters.
static func cavalry_tracker() -> Dictionary:
	return {"first_seconds": [-1.0, -1.0], "first_class": [-1, -1], "shooters_seconds": [-1.0, -1.0]}

static func track_cavalry(tracker: Dictionary, morale: Dictionary, state, event: Dictionary, tick: int) -> void:
	var source = _morale_unit(morale, state, int(event.get("source_id", -1)))
	if source == null or source.hero or source.companion or not source.mounted or source.attack_range > 0.0: return
	var target = _morale_unit(morale, state, int(event.target_id))
	if target == null: return
	var side: int = source.side
	var seconds := tick * TICK_SECONDS
	if float(tracker.first_seconds[side]) < 0.0:
		tracker.first_seconds[side] = seconds
		tracker.first_class[side] = FieldAssessment.unit_class(target.mounted, target.attack_range > 0.0, target.anti_cavalry)
	if float(tracker.shooters_seconds[side]) < 0.0 and not target.mounted and target.attack_range > 0.0:
		tracker.shooters_seconds[side] = seconds

## Morale metrics (DESIGN.md 4.5, stage 1b), read from WAVERED, FLED and DOWN events and the state only. Who flees
## (share of each unit class that ever fled) and when (first flight, the flight that makes 10% of the side, mean time),
## how many came back (a fighter seen ready again after his flight, sampled every SAMPLE_TICKS) and how many were cut
## down while fleeing (the pursuit).
static func morale_tracker(state, initial: Array) -> Dictionary:
	var ids := {}
	var class_total := [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	for unit in state.units:
		ids[unit.id] = unit
		if unit.hero or unit.companion: continue
		class_total[unit.side][FieldAssessment.unit_class(unit.mounted, unit.attack_range > 0.0, unit.anti_cavalry)] += 1
	return {"ids": ids, "initial": initial.duplicate(), "class_total": class_total, "class_fled": [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]],
		"wavered": [{}, {}], "fled": [{}, {}], "rallied": [{}, {}], "in_flight": {}, "flights": [0, 0], "rallies": [0, 0],
		"killed_fleeing": [0, 0], "first": [-1.0, -1.0], "tenth": [-1.0, -1.0], "time_sum": [0.0, 0.0]}

static func _morale_unit(tracker: Dictionary, state, id: int):
	var ids: Dictionary = tracker.ids
	if not ids.has(id):
		for unit in state.units: ids[unit.id] = unit
	return ids.get(id)

static func track_morale(tracker: Dictionary, state, event: Dictionary, tick: int) -> void:
	var unit = _morale_unit(tracker, state, int(event.target_id))
	if unit == null or unit.hero or unit.companion: return
	var side: int = unit.side
	if event.kind == Event.Kind.WAVERED:
		tracker.wavered[side][unit.id] = true
	elif event.kind == Event.Kind.FLED:
		var seconds := tick * TICK_SECONDS
		tracker.flights[side] += 1
		tracker.time_sum[side] += seconds
		tracker.in_flight[unit.id] = unit
		if tracker.first[side] < 0.0: tracker.first[side] = seconds
		if not tracker.fled[side].has(unit.id):
			tracker.fled[side][unit.id] = true
			tracker.class_fled[side][FieldAssessment.unit_class(unit.mounted, unit.attack_range > 0.0, unit.anti_cavalry)] += 1
			if tracker.tenth[side] < 0.0 and tracker.fled[side].size() * 10 >= int(tracker.initial[side]):
				tracker.tenth[side] = seconds
	elif event.kind == Event.Kind.DOWN and unit.fleeing:
		tracker.killed_fleeing[side] += 1
		tracker.in_flight.erase(unit.id)

## A fighter who fled and stands ready again has rallied (before stage 1b nobody comes back).
static func sample_rallies(tracker: Dictionary) -> void:
	var in_flight: Dictionary = tracker.in_flight
	for id in in_flight.keys():
		var unit = in_flight[id]
		if unit.dead or unit.gone:
			in_flight.erase(id)
		elif not unit.fleeing:
			in_flight.erase(id)
			tracker.rallies[unit.side] += 1
			tracker.rallied[unit.side][id] = true

static func morale_report(tracker: Dictionary) -> Dictionary:
	var report := {"fled_ever": [0.0, 0.0], "rallied_share": [0.0, 0.0], "rallies": tracker.rallies.duplicate(),
		"flights": tracker.flights.duplicate(), "wavered": [0.0, 0.0], "killed_fleeing_share": [0.0, 0.0],
		"first_flight_seconds": tracker.first.duplicate(), "tenth_flight_seconds": tracker.tenth.duplicate(),
		"mean_flight_seconds": [-1.0, -1.0], "class_fled": [[], []]}
	for side in 2:
		var initial := maxi(1, int(tracker.initial[side]))
		var fled: int = tracker.fled[side].size()
		report.fled_ever[side] = float(fled) / initial
		report.wavered[side] = float(tracker.wavered[side].size()) / initial
		report.rallied_share[side] = float(tracker.rallied[side].size()) / fled if fled > 0 else 0.0
		report.killed_fleeing_share[side] = float(tracker.killed_fleeing[side]) / tracker.flights[side] if tracker.flights[side] > 0 else 0.0
		if tracker.flights[side] > 0: report.mean_flight_seconds[side] = tracker.time_sum[side] / tracker.flights[side]
		for klass in Config.AI_CLASSES:
			var total: int = tracker.class_total[side][klass]
			report.class_fled[side].append(float(tracker.class_fled[side][klass]) / total if total > 0 else -1.0)
	return report

## Never engaged: no combat mode (melee, shooting, skirmish) at any sample. Idle time: share of fighter
## samples in formation or unassigned while the battle is undecided. Doctrine modes (stage 1v) are counted apart:
## neither idle nor fighting.
static func _sample_idle(state, engaged: Dictionary, idle_samples: Array, unit_samples: Array, doctrine_samples: Dictionary = {}) -> void:
	var motion = state.motion
	var capacity: int = motion.capacity
	var flags: PackedInt64Array = motion.integer_fields
	var I = MotionStore.I
	for row in state.active_units.size():
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var side: int = flags[I.SIDE * capacity + row]
		unit_samples[side] += 1
		var mode: int = flags[I.MODE * capacity + row]
		if mode in IDLE_MODES:
			idle_samples[side] += 1
		elif mode in COMBAT_MODES:
			engaged[flags[I.ID * capacity + row]] = true
		else:
			for key in doctrine_samples:
				if DOCTRINE_MODES[key] == mode: doctrine_samples[key][side] += 1

static func _prepare_kite(session) -> void:
	var state = session._state
	var hero = session._hero
	var spread := 200.0 + sqrt(float(state.units.size())) * 6.0
	var enemy_line := Vector2(1380, 850)
	_place(state, state.groups[0][Config.GROUP_INFANTRY], Vector2(700, 850 - spread), 0.0)
	_place(state, state.groups[0][Config.GROUP_ARCHERS], Vector2(700, 850 + spread), 0.0)
	_place(state, state.groups[1][Config.GROUP_INFANTRY], enemy_line, PI)
	hero.speed = KITE_HERO_SPEED
	hero.max_hp = 1000000.0
	hero.hp = hero.max_hp
	hero.position = _orbit_center() + Vector2(KITE_ORBIT_RADIUS, 0)

static func _orbit_center() -> Vector2:
	return Vector2(1180, 850)

static func _place(state, group, at: Vector2, facing: float) -> void:
	group.center = at
	group.direction = facing
	group.layout(true)
	for unit in group.units:
		unit.position = group.slot_position(unit, state.arena_size)
		unit.velocity = Vector2.ZERO

static func _circle(session, input: HeroInput) -> void:
	var hero = session._hero
	var offset: Vector2 = hero.position - _orbit_center()
	var radial := offset.normalized() if offset.length() > 1.0 else Vector2.RIGHT
	var move := Vector2(-radial.y, radial.x) + radial * clampf((KITE_ORBIT_RADIUS - offset.length()) / 40.0, -1.0, 1.0)
	input.move = move.normalized()
	input.face = move.angle()
	session.set_hero_input(input)

## Consecutive seconds each enemy infantryman runs after the hero beyond striking distance.
static func _sample_chase(session, chase: Dictionary, chased_long: Dictionary) -> void:
	var hero = session._hero
	for unit in session._state.groups[1][Config.GROUP_INFANTRY].units:
		if unit.dead or unit.gone or unit.fleeing: continue
		var chasing: bool = unit.target_handle == hero.unit_handle and unit.ai_mode == Config.AI_MODE_MELEE and unit.position.distance_to(hero.position) > Config.AI_KITE_CONTACT_DISTANCE
		var seconds: float = float(chase.get(unit.id, 0.0)) + KITE_SAMPLE_TICKS * TICK_SECONDS if chasing else 0.0
		chase[unit.id] = seconds
		if seconds > KITE_CHASE_SECONDS: chased_long[unit.id] = true

## Enemy infantry within contact of a player archer, on sampled fighters of both groups.
static func _infantry_reached_archers(state) -> bool:
	var enemy := _sample_points(state.groups[1][Config.GROUP_INFANTRY])
	var archers := _sample_points(state.groups[0][Config.GROUP_ARCHERS])
	for a in enemy:
		for b in archers:
			if a.distance_to(b) < Config.AI_KITE_CONTACT_DISTANCE: return true
	return false

static func _sample_points(group) -> PackedVector2Array:
	var points := PackedVector2Array()
	var stride := maxi(1, ceili(float(group.units.size()) / KITE_SAMPLE_LIMIT))
	for index in range(0, group.units.size(), stride):
		var unit = group.units[index]
		if not unit.dead and not unit.gone and not unit.fleeing: points.append(unit.position)
	return points

## Stuck fighters (TERRAIN.md 8), sampled with the idle metric. `progress` maps a unit id to [closest target
## distance, time it was reached]; `stuck` maps the ids that ever stalled to their side.
static func sample_stuck(state, progress: Dictionary, stuck: Dictionary, now: float) -> void:
	var flags: PackedInt64Array = state.motion.integer_fields
	var capacity: int = state.motion.capacity
	var I = MotionStore.I
	var seen := {}
	for row in state.active_units.size():
		if flags[I.MODE * capacity + row] != MELEE_MODE or flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var target = state.unit_for(flags[I.TARGET_HANDLE * capacity + row])
		if target == null or target.dead: continue
		var unit = state.active_units[row]
		var distance: float = unit.position.distance_to(target.position)
		seen[unit.id] = true
		var best: Array = progress.get(unit.id, [INF, now])
		if distance <= STUCK_REACH or distance < best[0] - STUCK_PROGRESS:
			progress[unit.id] = [distance, now]
		elif now - best[1] > STUCK_SECONDS:
			stuck[unit.id] = unit.side
		else:
			progress[unit.id] = best
	for id in progress.keys():
		if not seen.has(id): progress.erase(id)

## Shooters on high ground (TERRAIN.md 8, stage Р3), sampled with the idle metric: of the living shooters with a
## target, those standing at least TERRAIN_HIGHER_STEP above their target's cell. Only on a field with relief.
static func sample_high(state, high: Array, shooters: Array) -> void:
	var grid = state.terrain_rules
	if grid == null or not grid.relief: return
	var flags: PackedInt64Array = state.motion.integer_fields
	var capacity: int = state.motion.capacity
	var I = MotionStore.I
	for row in state.active_units.size():
		if flags[I.DEAD * capacity + row] or flags[I.GONE * capacity + row] or flags[I.FLEEING * capacity + row] or flags[I.HERO * capacity + row]:
			continue
		var unit = state.active_units[row]
		if unit.attack_range <= 0.0: continue
		var target = state.unit_for(flags[I.TARGET_HANDLE * capacity + row])
		if target == null or target.dead: continue
		shooters[unit.side] += 1
		if grid.elevation[grid.index(unit.position)] - grid.elevation[grid.index(target.position)] >= Config.TERRAIN_HIGHER_STEP:
			high[unit.side] += 1

static func summarize(runs: Array[Dictionary]) -> Dictionary:
	var count := runs.size()
	var wins := [0, 0]
	var profile_wins := [0, 0]
	var draws := 0
	var sums := {"duration_seconds": 0.0, "losses": [0.0, 0.0], "fled": [0.0, 0.0], "never_engaged": [0.0, 0.0], "idle_time": [0.0, 0.0], "stuck": [0.0, 0.0], "under_fire_seconds": [0.0, 0.0]}
	var contact := [0.0, 0]
	var high := [[0.0, 0], [0.0, 0]]
	var ai_mean := 0.0
	var ai_p95 := 0.0
	var kite_share := 0.0
	var kite_reached := 0
	var kite_seconds := 0.0
	var volley_keys := ["doomed_share", "dead_share", "wasted_share", "targets_per_volley", "shots_per_target", "first_volley_shots", "first_volley_targets"]
	var volley_sums := {}
	var volley_runs := 0
	var doctrine := {"rallies": [0.0, 0.0]}
	for key in DOCTRINE_MODES: doctrine[key] = [0.0, 0.0]
	var doctrine_runs := 0
	var morale_keys := ["fled_ever", "rallied_share", "rallies", "wavered", "killed_fleeing_share"]
	var morale_sums := {}
	for key in morale_keys: morale_sums[key] = [0.0, 0.0]
	var morale_times := {"first_flight_seconds": [[0.0, 0], [0.0, 0]], "tenth_flight_seconds": [[0.0, 0], [0.0, 0]], "mean_flight_seconds": [[0.0, 0], [0.0, 0]]}
	var morale_class := [[[0.0, 0], [0.0, 0], [0.0, 0], [0.0, 0], [0.0, 0]], [[0.0, 0], [0.0, 0], [0.0, 0], [0.0, 0], [0.0, 0]]]
	var morale_runs := 0
	# Cavalry (stage 1g part 4): battles where the side's riders struck at all, struck cavalry first, reached shooters.
	var cavalry := {"struck": [0, 0], "on_cavalry_first": [0, 0], "first_seconds": [0.0, 0.0], "on_shooters": [0, 0], "shooters_seconds": [0.0, 0.0]}
	var cavalry_runs := 0
	for run in runs:
		if run.has("cavalry"):
			cavalry_runs += 1
			for side in 2:
				if float(run.cavalry.first_seconds[side]) >= 0.0:
					cavalry.struck[side] += 1
					cavalry.first_seconds[side] += float(run.cavalry.first_seconds[side])
					if int(run.cavalry.first_class[side]) in [Config.AI_CLASS_CAVALRY, Config.AI_CLASS_HORSE_ARCHER]: cavalry.on_cavalry_first[side] += 1
				if float(run.cavalry.shooters_seconds[side]) >= 0.0:
					cavalry.on_shooters[side] += 1
					cavalry.shooters_seconds[side] += float(run.cavalry.shooters_seconds[side])
		if run.has("morale"):
			morale_runs += 1
			for side in 2:
				for key in morale_keys: morale_sums[key][side] += float(run.morale[key][side])
				for key in morale_times:
					if float(run.morale[key][side]) >= 0.0:
						morale_times[key][side][0] += float(run.morale[key][side])
						morale_times[key][side][1] += 1
				for klass in run.morale.class_fled[side].size():
					var share := float(run.morale.class_fled[side][klass])
					if share >= 0.0:
						morale_class[side][klass][0] += share
						morale_class[side][klass][1] += 1
		if run.has("doctrine"):
			doctrine_runs += 1
			for key in doctrine:
				for side in 2: doctrine[key][side] += float(run.doctrine[key][side])
		if run.has("volleys") and int(run.volleys.volleys) > 0:
			volley_runs += 1
			for key in volley_keys: volley_sums[key] = float(volley_sums.get(key, 0.0)) + float(run.volleys[key])
		if run.winner >= 0:
			wins[run.winner] += 1
			profile_wins[run.winner_profile] += 1
		else: draws += 1
		sums.duration_seconds += run.duration_seconds
		if float(run.get("contact_seconds", -1.0)) >= 0.0:
			contact[0] += float(run.contact_seconds)
			contact[1] += 1
		for side in 2:
			if float(run.get("archers_high", [-1.0, -1.0])[side]) >= 0.0:
				high[side][0] += float(run.archers_high[side])
				high[side][1] += 1
		for key in ["losses", "fled", "never_engaged", "idle_time", "stuck", "under_fire_seconds"]:
			if run.has(key):
				for side in 2: sums[key][side] += run[key][side]
		if run.has("ai_phase") and not run.ai_phase.is_empty():
			ai_mean += run.ai_phase.mean_ms
			ai_p95 = maxf(ai_p95, run.ai_phase.p95_ms)
		if run.has("kite"):
			kite_share += run.kite.chase_share
			if run.kite.reached_archers_seconds >= 0.0:
				kite_reached += 1
				kite_seconds += run.kite.reached_archers_seconds
	var summary := {"runs": count, "wins": wins, "profile_wins": profile_wins, "draws": draws,
		"win_rate": [float(wins[0]) / count, float(wins[1]) / count],
		"profile_win_rate": [float(profile_wins[0]) / count, float(profile_wins[1]) / count],
		"duration_seconds": sums.duration_seconds / count, "ai_phase_mean_ms": ai_mean / count, "ai_phase_worst_p95_ms": ai_p95}
	for key in ["losses", "fled", "never_engaged", "idle_time", "stuck", "under_fire_seconds"]:
		summary[key] = [sums[key][0] / count, sums[key][1] / count]
	summary.contact_seconds = contact[0] / contact[1] if contact[1] > 0 else -1.0
	summary.archers_high = [high[0][0] / high[0][1] if high[0][1] > 0 else -1.0, high[1][0] / high[1][1] if high[1][1] > 0 else -1.0]
	if not runs.is_empty() and runs[0].has("arena_size"): summary.arena_size = runs[0].arena_size
	if not runs.is_empty(): summary.terrain = runs[0].get("terrain", "open")
	if doctrine_runs > 0:
		for key in doctrine:
			for side in 2: doctrine[key][side] /= doctrine_runs
		summary.doctrine = doctrine
	if morale_runs > 0:
		var morale := {"runs": morale_runs, "class_fled": [[], []]}
		for key in morale_keys: morale[key] = [morale_sums[key][0] / morale_runs, morale_sums[key][1] / morale_runs]
		for key in morale_times:
			morale[key] = []
			for side in 2: morale[key].append(morale_times[key][side][0] / morale_times[key][side][1] if morale_times[key][side][1] > 0 else -1.0)
		for side in 2:
			for klass in Config.AI_CLASSES:
				morale.class_fled[side].append(morale_class[side][klass][0] / morale_class[side][klass][1] if morale_class[side][klass][1] > 0 else -1.0)
		summary.morale = morale
	if cavalry_runs > 0:
		var riders := {"runs": cavalry_runs, "struck": cavalry.struck.duplicate(), "on_cavalry_first": cavalry.on_cavalry_first.duplicate(),
			"on_shooters": cavalry.on_shooters.duplicate(), "first_seconds": [-1.0, -1.0], "shooters_seconds": [-1.0, -1.0]}
		for side in 2:
			if cavalry.struck[side] > 0: riders.first_seconds[side] = cavalry.first_seconds[side] / cavalry.struck[side]
			if cavalry.on_shooters[side] > 0: riders.shooters_seconds[side] = cavalry.shooters_seconds[side] / cavalry.on_shooters[side]
		summary.cavalry = riders
	if volley_runs > 0:
		summary.volleys = {"runs": volley_runs}
		for key in volley_keys: summary.volleys[key] = volley_sums[key] / volley_runs
	if kite_reached > 0 or runs.any(func(run): return run.has("kite")):
		summary.kite = {"chase_share": kite_share / count, "reached_runs": kite_reached,
			"reached_archers_seconds": kite_seconds / kite_reached if kite_reached > 0 else -1.0}
	return summary

static func table(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Arena: profiles %s, %d runs per cell%s" % [str(report.options.profiles), int(report.options.runs), " x2 mirrored" if report.options.mirror else ""])
	lines.append("scenario          size  runs  win A/B/draw   losses 0/1   fled 0/1     never 0/1    idle 0/1     time s  AI ms mean/p95")
	for cell in report.cells:
		var s: Dictionary = cell.summary
		lines.append("%-16s %5d %5d  %3d/%3d/%3d   %.2f/%.2f    %.2f/%.2f    %.2f/%.2f    %.2f/%.2f   %6.1f  %.3f/%.3f" % [
			cell.scenario, cell.size, s.runs, s.profile_wins[0], s.profile_wins[1], s.draws,
			s.losses[0], s.losses[1], s.fled[0], s.fled[1], s.never_engaged[0], s.never_engaged[1],
			s.idle_time[0], s.idle_time[1], s.duration_seconds, s.ai_phase_mean_ms, s.ai_phase_worst_p95_ms])
		if s.has("arena_size"):
			# Wins by side: side 0 stands on the left (on the hill of center_hill) whichever army it is (--mirror).
			lines.append("  field %dx%d %s: first melee contact %.1f s, under fire before it %.1f/%.1f s, stuck %.3f/%.3f, wins by side %d/%d" % [int(s.arena_size[0]), int(s.arena_size[1]), s.get("terrain", "open"), s.contact_seconds, s.get("under_fire_seconds", [0.0, 0.0])[0], s.get("under_fire_seconds", [0.0, 0.0])[1], s.stuck[0], s.stuck[1], s.wins[0], s.wins[1]])
		if s.has("archers_high") and (s.archers_high[0] >= 0.0 or s.archers_high[1] >= 0.0):
			lines.append("  shooters on high ground %.3f/%.3f" % [s.archers_high[0], s.archers_high[1]])
		if s.has("cavalry") and (s.cavalry.struck[0] > 0 or s.cavalry.struck[1] > 0):
			var c: Dictionary = s.cavalry
			lines.append("  cavalry: struck %d/%d, cavalry first %d/%d, first blow %.1f/%.1f s, on shooters %d/%d at %.1f/%.1f s" % [c.struck[0], c.struck[1], c.on_cavalry_first[0], c.on_cavalry_first[1], c.first_seconds[0], c.first_seconds[1], c.on_shooters[0], c.on_shooters[1], c.shooters_seconds[0], c.shooters_seconds[1]])
		if s.has("volleys"):
			var v: Dictionary = s.volleys
			lines.append("  volleys: first %.0f shots -> %.1f targets, %.1f targets per volley, %.1f shots per target, doomed %.3f, dead %.3f" % [v.first_volley_shots, v.first_volley_targets, v.targets_per_volley, v.shots_per_target, v.doomed_share, v.dead_share])
		if s.has("doctrine"):
			var d: Dictionary = s.doctrine
			lines.append("  doctrine: rank %.2f/%.2f, brace %.3f/%.3f, fallback %.3f/%.3f, rallies %.1f/%.1f per battle" % [d.rank[0], d.rank[1], d.brace[0], d.brace[1], d.fallback[0], d.fallback[1], d.rallies[0], d.rallies[1]])
		if s.has("morale"):
			var m: Dictionary = s.morale
			lines.append("  morale: fled ever %.2f/%.2f, rallied %.2f/%.2f (%.1f/%.1f per battle), killed fleeing %.2f/%.2f, wavered %.2f/%.2f, first flight %.1f/%.1f s, 10%% fled at %.1f/%.1f s" % [m.fled_ever[0], m.fled_ever[1], m.rallied_share[0], m.rallied_share[1], m.rallies[0], m.rallies[1], m.killed_fleeing_share[0], m.killed_fleeing_share[1], m.wavered[0], m.wavered[1], m.first_flight_seconds[0], m.first_flight_seconds[1], m.tenth_flight_seconds[0], m.tenth_flight_seconds[1]])
			var names := ["foot", "spear", "archer", "cavalry", "horse archer"]
			var parts: Array[String] = []
			for klass in names.size():
				if m.class_fled[0][klass] >= 0.0 or m.class_fled[1][klass] >= 0.0:
					parts.append("%s %s/%s" % [names[klass], "-" if m.class_fled[0][klass] < 0.0 else "%.2f" % m.class_fled[0][klass], "-" if m.class_fled[1][klass] < 0.0 else "%.2f" % m.class_fled[1][klass]])
			lines.append("  fled by class: " + ", ".join(parts))
		if s.has("kite"):
			lines.append("  kite: chasing hero > %.0f s %.2f, enemy reached archers in %d runs, mean %.1f s" % [KITE_CHASE_SECONDS, s.kite.chase_share, s.kite.reached_runs, s.kite.reached_archers_seconds])
	return "\n".join(lines)
