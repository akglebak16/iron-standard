extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Economy = preload("res://core/campaign/economy/party_economy.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(1, data, "emp", ContentLoader.registry())
	var player = state.player
	var fx: Dictionary = state.player_effects()
	var e1: Dictionary = state.roster.catalog.get_troop("e1")
	assert(Economy.hire_cost(e1, fx) == 25)
	assert(Economy.size_cap(player.hero, fx) == 50, "cap: %d" % Economy.size_cap(player.hero, fx))
	# hiring from a town takes gold and recruits
	var town: Dictionary = state.settlement_near(player.x, player.y, 80.0)
	assert(not town.is_empty() and not town.recruits.is_empty(), "towns have recruits")
	var r: Dictionary = town.recruits[0]
	var troop: Dictionary = state.roster.catalog.get_troop(r.type)
	var before: int = Economy.troop_count(player.troops)
	var gold: int = player.gold
	var hired := Economy.hire(player, town, troop, 3, fx)
	assert(hired > 0 and Economy.troop_count(player.troops) == before + hired)
	assert(player.gold == gold - hired * Economy.hire_cost(troop, fx))
	# food: grain feeds the party, offers cost gold
	assert(Economy.provisions(player) == 60, "10 grain = 60 portions")
	assert(Economy.eat(player, 10) == 0 and Economy.provisions(player) == 50)
	assert(Economy.eat(player, 500) > 0 and Economy.provisions(player) == 0)
	player.gold = 100
	assert(Economy.buy_food(player, 30, 60) and player.gold == 40 and player.food == 30)
	assert(not Economy.buy_food(player, 80, 150))
	# attributes and day upkeep
	var pts: int = player.hero.pts
	assert(Economy.spend_attribute(player.hero, "str") and player.hero.pts == pts - 1 and player.hero.str == 2)
	player.gold = 0
	var log: Array = Economy.day_tick(player, func(t): return float(state.roster.catalog.get_troop(t).wage), fx, state.roster.rng, func(t): return "боец")
	assert(player.gold == 0)
	# the world clock drives the same upkeep at midnight
	player.gold = 1000
	state.clock.hour = 23
	var g: int = player.gold
	state.clock.hour = 0
	state.hour_tick()
	assert(player.gold < g, "wages paid at midnight")
	print("Party economy tests passed")
	quit(0)
