extends SceneTree
## Smoke run of the campaign simulator (tests/performance/campaign_simulator.gd): one day on one seed.
## The observed world with an active threat map must end exactly like the same seed run without them:
## the simulator and the map only read the world and spend no RNG (DESIGN.md §7.2, ADR-023).
const Simulator = preload("res://tests/performance/campaign_simulator.gd")
const WorldCheckpoint = preload("res://core/campaign/world/world_checkpoint.gd")

const SEED := 7
const DAYS := 1

func _initialize() -> void:
	var result := Simulator.run(SEED, DAYS)
	assert(not result.is_empty(), "world created")
	var report: Dictionary = result.report
	var observed: RefCounted = result.world
	_check_report(report)
	var plain := Simulator.create_world(SEED)
	Simulator.drive(plain, DAYS * 24, func() -> void: pass, func() -> void: pass)
	assert(plain.threat == null, "the plain run never builds the map")
	assert(observed.threat != null and observed.threat.built_hour == observed.hours_passed, "the observed run refreshed it every hour")
	assert(plain.hours_passed == observed.hours_passed and plain.clock.day == observed.clock.day)
	assert(plain.roster.rng.state == observed.roster.rng.state, "same RNG with and without the observer")
	assert(plain.market.rng.state == observed.market.rng.state)
	assert(WorldCheckpoint.capture(plain) == WorldCheckpoint.capture(observed), "same world with and without the observer")
	plain.dispose()
	observed.dispose()
	print("Campaign simulator tests passed")
	quit(0)

func _check_report(report: Dictionary) -> void:
	var s: Dictionary = report.summary
	assert(s.seed == SEED and s.days == DAYS and s.hours == DAYS * 24, "ran %d hours" % s.hours)
	for key in ["wars_declared", "owner_changes", "lords_died", "lord_goal_changes_per_day", "max_share", "sieges",
			"sieges_no_relief_with_helper", "edge_idle_party_hours", "flees", "threat_rebuild_usec", "threat_cells_per_party"]:
		assert(s.has(key), "summary has %s" % key)
	assert(s.max_share > 0.0 and s.max_share <= 1.0)
	assert(s.lord_goal_changes_per_day >= 0.0 and s.lord_state_changes_per_day > 0.0, "lords do something")
	assert(s.threat_cells_per_party > 0.0 and s.threat_cells_per_party <= 49.0, "a party visits at most a 7×7 square")
	assert(report.daily.size() == DAYS, "one summary per day")
	assert(report.jitter.has("lord"))
	var heat: Dictionary = report.heat
	var cells: int = heat.cols * heat.rows
	for key in ["land", "lords", "fights", "sieges"]:
		assert(heat[key].size() == cells, "heat grid %s" % key)
	var visits := 0
	for v in heat.lords:
		visits += int(v)
	assert(visits >= 30 * DAYS * 24, "every lord is counted every hour: %d" % visits)
	var land := 0
	for v in heat.land:
		land += int(v)
	assert(land > cells / 4 and land < cells, "Europe has land and sea")
	var t: Dictionary = report.threat_final
	assert(t.dominant.size() == t.cols * t.rows and "emp" in t.factions)
	for r in report.sieges:
		assert(r.hours > 0 and r.defender != r.attacker)
