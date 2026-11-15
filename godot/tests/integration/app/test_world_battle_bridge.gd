extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")
const Aftermath = preload("res://core/campaign/application/encounter_aftermath.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(1, data, "emp", ContentLoader.registry())
	var bridge = Bridge.new(ContentLoader.registry(), RandomNumberGenerator.new())
	bridge.rng.seed = 11
	# a played battle can be built from world parties
	var weak: Dictionary = state.roster.make_party("bandit", "bandit", "Шайка", state.player.x + 5, state.player.y, [{"type": "b1", "n": 3}])
	var setup = bridge.make_setup(state, weak)
	assert(setup.player_faction == "emp" and setup.enemy_faction == "bandit")
	assert(Factory.create(setup, bridge.troops, bridge.gear, bridge.perks, bridge.companions) != null, "battle session builds from a world meeting")
	# a won calculated battle removes the opponent and pays the hero
	var gold: int = state.player.gold
	state.player.troops = [{"type": "e1", "n": 60}]
	var result: Dictionary = bridge.auto_result(state, weak)
	assert(result.win)
	var opponent: Dictionary = bridge.opponent_dict(weak, {})
	var world := {"parties": [opponent.duplicate(true)], "settlements": [], "factions": Rules.REAL_FACTIONS}
	var resolved: Dictionary = Aftermath.resolve_result(result, bridge.party_dict(state), opponent, false, bridge.troops, bridge.gear, bridge.goods, bridge.rng, bridge.companions, bridge.perks, world)
	assert(not resolved.is_empty())
	bridge._encounter_apply(state, weak, resolved)
	assert(not (weak in state.roster.parties), "defeated party leaves the map")
	assert(state.player.gold > gold, "loot reaches the purse")
	assert(state.player.busy == "")
	# a lost battle leaves the opponent with its survivors and a cooldown
	var strong: Dictionary = state.roster.make_party("lord", "nord", "Лорд", state.player.x, state.player.y, [{"type": "n1", "n": 80}])
	state.player.troops = [{"type": "e1", "n": 3}]
	var lost: Dictionary = bridge.auto_result(state, strong)
	assert(not lost.win)
	var opp2: Dictionary = bridge.opponent_dict(strong, {})
	var world2 := {"parties": [opp2.duplicate(true)], "settlements": [], "factions": Rules.REAL_FACTIONS}
	var resolved2: Dictionary = Aftermath.resolve_result(lost, bridge.party_dict(state), opp2, false, bridge.troops, bridge.gear, bridge.goods, bridge.rng, bridge.companions, bridge.perks, world2)
	bridge._encounter_apply(state, strong, resolved2)
	assert(strong in state.roster.parties and strong.cd > 0.0)
	print("World battle bridge tests passed")
	quit(0)
