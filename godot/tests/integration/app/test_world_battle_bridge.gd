extends SceneTree
const Bridge = preload("res://apps/godot/composition/world_battle_bridge.gd")
const Aftermath = preload("res://apps/godot/composition/encounter_aftermath.gd")
const Factory = preload("res://battle/application/factory.gd")
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Rules = preload("res://campaign/world/party_rules.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var state := WorldState.create(1, data, "emp")
	var bridge = Bridge.new()
	bridge.rng.seed = 11
	# a played battle can be built from world parties
	var weak: Dictionary = state.roster.make_party("bandit", "bandit", "Шайка", state.player.x + 5, state.player.y, [{"type": "b1", "n": 3}])
	var setup: Resource = bridge.make_setup(state, weak)
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
	bridge.apply(state, weak, resolved)
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
	bridge.apply(state, strong, resolved2)
	assert(strong in state.roster.parties and strong.cd > 0.0)
	print("World battle bridge tests passed")
	quit(0)
