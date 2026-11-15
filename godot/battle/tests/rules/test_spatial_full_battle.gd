extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## The spatial index must not change a full AI battle: the same seed with and without the index gives identical units.
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Config = preload("res://battle/config.gd")
const Movement = preload("res://battle/rules/movement.gd")
const TICKS := 900

func _run(catalog: Catalog, indexed: bool, mixed: bool) -> Array:
	var setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.hero_profile.clear()
	setup.seed = 4242
	if mixed:
		setup.player_army.assign([{"type": "n1", "n": 35}, {"type": "n2a", "n": 20}, {"type": "n2s", "n": 15}])
		setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 20}])
	else:
		setup.player_army.assign([{"type": "e1", "n": 45}, {"type": "e2a", "n": 25}])
		setup.enemy_army.assign([{"type": "z1", "n": 50}, {"type": "s1a", "n": 20}])
	var session = Factory.create(setup, catalog)
	session._state.use_spatial_index = indexed
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	for i in TICKS:
		session.advance(1.0 / 60.0)
	var out: Array = []
	for u in session._state.units:
		out.append([u.position, u.velocity, u.hp, u.dead, u.gone, u.target_index, u.kills])
	return out

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	for mixed in [true, false]:
		var fast := _run(catalog, true, mixed)
		var plain := _run(catalog, false, mixed)
		assert(fast.size() == plain.size() and fast.size() > Config.SPATIAL_MIN_UNITS)
		var dead := fast.filter(func(u): return u[3]).size()
		print("mixed=%s dead=%d" % [mixed, dead])
		assert(dead > 5, "the armies must actually fight in the compared window")
		for i in fast.size():
			assert(fast[i] == plain[i], "unit %d differs (mixed=%s): %s vs %s" % [i, mixed, str(fast[i]), str(plain[i])])
	print("Spatial full battle tests passed")
	quit(0)
