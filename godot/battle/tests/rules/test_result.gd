extends SceneTree
const Config = preload("res://battle/config.gd")
const Result = preload("res://battle/rules/result.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const END_TIME := 23.5

func _initialize() -> void:
	_check_weighted_losses_and_experience()
	_check_survival_bonus()
	_check_companion_results()
	print("Battle result tests passed")
	quit(0)

func _battle() -> Dictionary:
	var state := State.new()
	var hero := Unit.new(0, 0, Vector2.ZERO, 100, 0, 3)
	hero.hero = true
	hero.hp = 50
	hero.kills = 2
	hero.perk_effects = {"surv": 0.3}
	state.add_unit(hero)
	for weight in [1.0, 2.0]:
		var lost := Unit.new(state.units.size(), 0, Vector2.ZERO, 100, 0, 1)
		lost.troop_id = "n1"
		lost.weight = weight
		lost.dead = true
		state.add_unit(lost)
	var fled := Unit.new(state.units.size(), 0, Vector2.ZERO, 100, 0, 2)
	fled.troop_id = "n2"
	fled.weight = 2.0
	fled.gone = true
	state.add_unit(fled)
	var survivor := Unit.new(state.units.size(), 0, Vector2.ZERO, 100, 0, 2)
	survivor.troop_id = "n2"
	survivor.weight = 1.5
	state.add_unit(survivor)
	var fallen_enemy := Unit.new(state.units.size(), 1, Vector2.ZERO, 100, 0, 2)
	fallen_enemy.troop_id = "e2"
	fallen_enemy.weight = 2.0
	fallen_enemy.xp_multiplier = 0.6
	fallen_enemy.mounted = true
	fallen_enemy.dead = true
	state.add_unit(fallen_enemy)
	var vanished_enemy := Unit.new(state.units.size(), 1, Vector2.ZERO, 100, 0, 1)
	vanished_enemy.troop_id = "e1"
	vanished_enemy.dead = true
	vanished_enemy.gone = true
	state.add_unit(vanished_enemy)
	var remaining_enemy := Unit.new(state.units.size(), 1, Vector2.ZERO, 100, 0, 1)
	remaining_enemy.troop_id = "e1"
	state.add_unit(remaining_enemy)
	return {"state": state, "hero": hero}

func _check_weighted_losses_and_experience() -> void:
	var pair := _battle()
	var rng := RandomNumberGenerator.new()
	rng.seed = 98
	var reference := RandomNumberGenerator.new()
	reference.seed = rng.seed
	var wounded_weight := 0.0
	for weight in [1.0, 2.0]:
		if reference.randf() < Config.BASE_WOUNDED_CHANCE + 0.3:
			wounded_weight += weight
	var result: Dictionary = Result.build(pair.state, pair.hero, rng, END_TIME, true)
	assert(result.win and not result.heroDown and result.heroHp == 0.5 and result.heroKills == 2)
	assert(result.time == END_TIME and result.comps.is_empty())
	assert(result.wounded.get("n1", 0) == roundi(wounded_weight))
	assert(result.dead.get("n1", 0) == roundi(3.0 - wounded_weight))
	assert(result.left.n2 == 4) # Fled + active figures, rounded once per type.
	assert(result.enemyDead == 2 and result.enemyTotal == 4)
	assert(result.enemyLeft.e1 == 2) # Dead-and-gone is reported as left in the browser.
	assert(result.xp == 40) # (tier 2 * 10 + mounted 5) * weight 2 * pw .6 + tier 1 * 10.
	assert(rng.state == reference.state)

func _check_survival_bonus() -> void:
	var pair := _battle()
	pair.hero.perk_effects.surv = 0.7
	var rng := RandomNumberGenerator.new()
	var result: Dictionary = Result.build(pair.state, pair.hero, rng, END_TIME, false)
	assert(not result.win and result.wounded.n1 == 3)
	assert(result.dead.is_empty())

func _check_companion_results() -> void:
	var pair := _battle()
	var active := Unit.new(pair.state.units.size(), 0, Vector2.ZERO, 100, 0, 3)
	active.companion = true
	active.companion_id = "healer"
	active.hp = 35
	active.kills = 2
	pair.state.add_unit(active)
	var down := Unit.new(pair.state.units.size(), 0, Vector2.ZERO, 100, 0, 3)
	down.companion = true
	down.companion_id = "scout"
	down.dead = true
	down.kills = 1
	pair.state.add_unit(down)
	var result: Dictionary = Result.build(pair.state, pair.hero, RandomNumberGenerator.new(), END_TIME, true)
	assert(result.comps.healer == {"hp": 0.35, "down": false, "kills": 2})
	assert(result.comps.scout == {"hp": 0.0, "down": true, "kills": 1})
	assert(not result.left.has(""))
