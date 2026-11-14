extends SceneTree
## Informational CPU benchmark, not a hardware-dependent pass/fail test.
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const Config = preload("res://battle/config.gd")
const WARMUP_TICKS := 10
const MEASURED_TICKS := 60
const TICK_SECONDS := 1.0 / 60.0
const MICROSECONDS_PER_MILLISECOND := 1000.0

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	for army_size in [24, Config.SOLO_UNIT_CAP]:
		var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
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
	quit(0)
