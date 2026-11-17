extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const AutoBattle = preload("res://core/campaign/world/auto_battle.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(1, data, "emp", ContentLoader.registry())
	var info: Dictionary = state.roster.info
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var weak := [{"type": "e1", "n": 2}]
	var strong := [{"type": "e1", "n": 60}, {"type": "e2a", "n": 20}]
	var win: Dictionary = AutoBattle.resolve(strong, state.player.hero, weak, info, rng)
	assert(win.win and win.enemyDead == 2 and win.enemyLeft.is_empty())
	assert(win.heroHp >= 0.25 and win.heroHp <= 1.0)
	var lose: Dictionary = AutoBattle.resolve(weak, state.player.hero, strong, info, rng)
	assert(not lose.win and lose.enemyDead < 80 and lose.enemyLeft.size() > 0)
	for type in lose.left:
		assert(lose.left[type] >= 0)
	assert(AutoBattle.flee_chance(18.0, 18.0, false) == 0.45)
	assert(is_equal_approx(AutoBattle.flee_chance(14.4, 13.6, false), 0.51))
	assert(AutoBattle.flee_chance(40.0, 10.0, false) == 0.9)
	assert(AutoBattle.flee_chance(10.0, 40.0, true) == 0.12)
	assert(AutoBattle.relative_power(strong, weak, info)[0] == "Мы сильнее")
	assert(AutoBattle.relative_power(weak, strong, info)[0] == "Они намного сильнее")
	print("Auto battle tests passed")
	quit(0)
