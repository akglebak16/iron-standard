extends SceneTree
## Informational CPU benchmark, not a hardware-dependent pass/fail test.
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Config = preload("res://battle/config.gd")
const Movement = preload("res://battle/rules/movement.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const Morale = preload("res://battle/rules/morale.gd")
const WARMUP_TICKS := 10
const MEASURED_TICKS := 60
const TICK_SECONDS := 1.0 / 60.0
const MICROSECONDS_PER_MILLISECOND := 1000.0

func _initialize() -> void:
	var catalog := Catalog.new()
	if not (catalog.load_data()):
		push_error("Required content failed to load: battle/tools/benchmark.gd")
		return
	for army_size in [24, Config.SOLO_UNIT_CAP]:
		var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
		setup.companion_profiles.clear()
		setup.hero_profile.clear()
		setup.player_army = [{"type": "n1", "n": army_size}]
		setup.enemy_army = [{"type": "e1", "n": army_size}]
		var session := Factory.create(setup, catalog)
		session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
		for tick in WARMUP_TICKS:
			session.advance(TICK_SECONDS)
		var simulation_us := 0
		var snapshot_us := 0
		for tick in MEASURED_TICKS:
			var start := Time.get_ticks_usec()
			session.advance(TICK_SECONDS)
			simulation_us += Time.get_ticks_usec() - start
			start = Time.get_ticks_usec()
			session.snapshot()
			snapshot_us += Time.get_ticks_usec() - start
		var divisor := MEASURED_TICKS * MICROSECONDS_PER_MILLISECOND
		print("%d vs %d + hero: simulation %.3f ms/tick; snapshot %.3f ms/tick" % [army_size, army_size, simulation_us / divisor, snapshot_us / divisor])
		# Internal profiling fixture: use fresh state so phase timing does not alter the session above.
		var profile := Factory.create(setup, catalog)
		var state = profile._state
		var rng := RandomNumberGenerator.new()
		rng.seed = setup.seed
		state.give_order(Config.ORDER_CHARGE, Vector2.ZERO)
		var movement_and_attacks_us := 0
		var projectiles_us := 0
		var morale_us := 0
		for tick in MEASURED_TICKS:
			var start := Time.get_ticks_usec()
			Movement.step(state, TICK_SECONDS, rng)
			movement_and_attacks_us += Time.get_ticks_usec() - start
			start = Time.get_ticks_usec()
			CombatStep.resolve_projectiles(state, TICK_SECONDS, rng)
			projectiles_us += Time.get_ticks_usec() - start
			start = Time.get_ticks_usec()
			Morale.advance(state, TICK_SECONDS)
			morale_us += Time.get_ticks_usec() - start
		print("%d vs %d phase: movement + attacks %.3f ms; projectiles %.3f ms; morale %.3f ms" % [army_size, army_size, movement_and_attacks_us / divisor, projectiles_us / divisor, morale_us / divisor])
	quit(0)
