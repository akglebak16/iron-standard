extends SceneTree
const World = preload("res://campaign/rules/encounter_world.gd")
const Siege = preload("res://campaign/rules/siege_aftermath.gd")
const Catalog = preload("res://troops/data/catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var settlement := {"id": 4, "name": "Вентум", "kind": "town", "fac": "emp", "cult": "kin", "board": ["old"], "gar": [{"type": "k1", "n": 10}, {"type": "e1", "n": 1}]}
	var inside := {"id": 1, "kind": "lord", "fac": "emp", "name": "Lord", "hide": true, "home": 4, "troops": [{"type": "e1", "n": 9}]}
	var other_inside := {"id": 2, "kind": "lord", "fac": "nord", "hide": true, "home": 4}
	var outside := {"id": 3, "kind": "lord", "fac": "emp", "hide": false, "home": 4}
	var world := {"settlements": [settlement], "parties": [inside, other_inside, outside]}
	var player := {"id": 14, "rel": {"emp": -10}, "hostF": {"emp": false}}
	var opponent := Siege.defenders(settlement, world.parties, catalog, rng)
	assert(opponent.id == -4 and opponent.sid == 4 and opponent.gold == 350 and opponent.lord == "Lord")
	assert(opponent.troops == [{"type": "e1", "n": 10}, {"type": "k1", "n": 10}])
	assert(opponent.wall_damage == 0.0 and opponent.wall_defense == {"stones": 10, "oil": 2})
	settlement.dmg = 1.7
	var battered := Siege.defenders(settlement, world.parties, catalog, rng)
	assert(battered.wall_damage == 1.0, "Damage is clamped to 0..1")
	settlement.erase("dmg")
	assert(Siege.supplies({"kind": "castle"}) == {"stones": 14, "oil": 3} and Siege.supplies({"kind": "village"}) == {"stones": 10, "oil": 2})
	var before := rng.state
	var failed := World.apply(world, player, opponent, {"win": false, "enemyDead": 10, "enemyTotal": 20}, {}, 0.0, catalog, rng)
	assert(failed.settlements[0].gar == [{"type": "k1", "n": 5}])
	assert(failed.parties[0].troops[0].n == 9 and rng.state == before)
	assert(settlement.gar[0].n == 10)
	var zero_total := World.apply(world, player, opponent, {"win": false, "enemyDead": 10, "enemyTotal": 0}, {}, 0.0, catalog, rng)
	assert(zero_total.settlements[0].gar == settlement.gar)
	var summary := {}
	var won := World.apply(world, player, opponent, {"win": true}, summary, 0.0, catalog, rng)
	var captured: Dictionary = won.settlements[0]
	assert(captured.fac == "player" and captured.owner == 14 and captured.cult == "kin" and captured.board.is_empty())
	assert(_total(captured.gar) == 8 and _total(captured.recruits) >= 10 and _total(captured.recruits) <= 18)
	for stack in captured.gar + captured.recruits:
		assert(catalog.get_troop(stack.type).fac == "kin")
	for stack in captured.recruits:
		assert(catalog.get_troop(stack.type).tier <= 2)
	assert(won.parties == [outside] and world.parties.size() == 3)
	assert(summary.captured == settlement.name and player.rel.emp == -25)
	assert(summary.hostility_changes == [{"faction": "emp", "hostile": true}])
	var ruins := {"id": 5, "name": "Ruins", "kind": "castle", "fac": "undead", "cult": "emp", "ruinOf": "emp", "burnt": 1}
	opponent = Siege.defenders(ruins, [], catalog, rng)
	assert(opponent.gold == 180 and _total(ruins.gar) >= 260 and _total(ruins.gar) <= 350)
	var liberated := World.apply({"settlements": [ruins]}, player, opponent, {"win": true}, {}, 0.0, catalog, rng)
	assert(liberated.settlements[0].ruin == 240 and player.rel.emp == -16)
	assert(liberated.settlements[0].recruits.is_empty()) # Burnt settlements cannot recruit.
	print("Siege aftermath tests passed")
	quit(0)

func _total(stacks: Array) -> int:
	var sum := 0
	for stack in stacks:
		sum += int(stack.n)
	return sum
