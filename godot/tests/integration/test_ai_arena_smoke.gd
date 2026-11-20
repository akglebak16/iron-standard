extends SceneTree
## Short arena run (DESIGN.md 7.1): every scenario once on small armies. Checks the report shape and ranges,
## that a battle repeats exactly on its seed, and that mirroring swaps the profiles' sides.
const Arena = preload("res://tests/performance/battle_arena.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Config = preload("res://core/battle/config.gd")
const SIZE := 16

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	var options := Arena.default_options()
	options.sizes = [SIZE]
	options.runs = 1
	options.max_seconds = 20.0
	var report := Arena.run_matrix(options, catalog)
	assert(not report.has("error"), str(report.get("error", "")))
	assert(report.cells.size() == Arena.SCENARIOS.size())
	for cell in report.cells:
		_check_cell(cell)
	print(Arena.table(report))
	_test_repeatable(catalog, options)
	_test_mirror(catalog, options)
	assert(Arena.validate({"scenarios": ["zz"], "sizes": [SIZE], "runs": 1, "max_seconds": 1.0, "profiles": ["", ""], "backend": "native"}) != "")
	print("AI arena smoke tests passed")
	quit(0)

func _check_cell(cell: Dictionary) -> void:
	assert(cell.runs.size() == 1 and cell.size == SIZE)
	var run: Dictionary = cell.runs[0]
	assert(run.initial == [SIZE, SIZE])
	assert(run.winner in [-1, 0, 1] and run.ticks > 0)
	assert(run.duration_seconds > 0.0 and run.duration_seconds <= 20.0 + 1e-6)
	for key in ["losses", "fled", "never_engaged", "idle_time"]:
		for side in 2:
			assert(run[key][side] >= 0.0 and run[key][side] <= 1.0, "%s out of range in %s" % [key, cell.scenario])
	assert(run.losses[0] + run.fled[0] <= 1.0 + 1e-6 and run.losses[1] + run.fled[1] <= 1.0 + 1e-6)
	assert(run.ai_phase.count == run.ticks and run.ai_phase.mean_ms >= 0.0, "AI phase sampled on every tick")
	assert(run.volleys.aimed <= run.volleys.shots)
	for key in ["doomed_share", "dead_share", "wasted_share"]:
		assert(run.volleys[key] >= 0.0 and run.volleys[key] <= 1.0, "%s out of range in %s" % [key, cell.scenario])
	assert(cell.summary.runs == 1 and cell.summary.wins[0] + cell.summary.wins[1] + cell.summary.draws == 1)
	if cell.scenario == "kite":
		assert(run.profiles == [Config.AI_PROFILE_PLAYER, Config.AI_PROFILE_REFERENCE], "The kite side 0 follows player orders")
		assert(run.kite.chase_share >= 0.0 and run.kite.chase_share <= 1.0)
		assert(cell.summary.has("kite"))
	elif cell.scenario in Arena.PLAYER_HOLDS:
		assert(run.profiles == [Config.AI_PROFILE_PLAYER, Config.AI_PROFILE_REFERENCE], "The hold side 0 follows player orders")
	else:
		assert(run.profiles == [Config.AI_PROFILE_REFERENCE, Config.AI_PROFILE_REFERENCE])
		assert(run.never_engaged[0] < 1.0 and run.never_engaged[1] < 1.0, "AI against AI fights in %s" % cell.scenario)

func _metrics(run: Dictionary) -> String:
	var copy := run.duplicate(true)
	copy.erase("wall_ms")
	copy.erase("ai_phase")
	return var_to_str(copy)

func _test_repeatable(catalog: Catalog, base: Dictionary) -> void:
	var options := base.duplicate(true)
	options.max_seconds = 12.0
	var first := Arena.run_battle("mixed", SIZE, 77, options, catalog)
	var second := Arena.run_battle("mixed", SIZE, 77, options, catalog)
	assert(_metrics(first) == _metrics(second), "A seed repeats its battle")
	var plain := options.duplicate(true)
	plain.phase_profile = false
	assert(_metrics(Arena.run_battle("mixed", SIZE, 77, plain, catalog)) == _metrics(first), "Timing the AI phase does not change the battle")

func _test_mirror(catalog: Catalog, options: Dictionary) -> void:
	var mirrored := options.duplicate(true)
	mirrored.profiles = [Config.AI_PROFILE_REFERENCE, Config.AI_PROFILE_PLAYER]
	mirrored.max_seconds = 5.0
	var normal := Arena.run_battle("infantry_cavalry", SIZE, 5, mirrored, catalog, false)
	var swapped := Arena.run_battle("infantry_cavalry", SIZE, 5, mirrored, catalog, true)
	assert(normal.profiles == [Config.AI_PROFILE_REFERENCE, Config.AI_PROFILE_PLAYER])
	assert(swapped.profiles == [Config.AI_PROFILE_PLAYER, Config.AI_PROFILE_REFERENCE])
	var setup := Arena.setup_for("infantry_cavalry", SIZE, 5, mirrored.profiles, true)
	assert(setup.player_army[0].type == "e3c" and setup.enemy_army[0].type == "n1", "Mirroring also swaps the armies")
