extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const World = preload("res://core/campaign/world/world_state.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const Encounter = preload("res://core/campaign/application/battle_encounter.gd")
const Checkpoint = preload("res://core/campaign/world/world_checkpoint.gd")

func _initialize() -> void:
	var europe := Europe.new()
	assert(Loader.populate(europe))
	var definitions := Loader.registry()
	var world := World.create(413, europe, "emp", definitions)
	var service := Encounter.new(definitions, world.roster.rng)
	var other := Encounter.new(definitions, RandomNumberGenerator.new())
	world.player.troops = [{"type": "e2a", "n": 900}]
	var weak: Dictionary = world.roster.make_party("bandit", "bandit", "Шайка", world.player.x, world.player.y, [{"type": "b1", "n": 3}])
	var ticket := service.begin(world, weak)
	assert(ticket != null and service.begin(world, weak) == null)
	var setup := service.battle_setup(ticket)
	setup.enemy_army[0].n = 999
	assert(weak.troops[0].n == 3)
	var before_rng: int = world.roster.rng.state
	assert(service.complete(ticket, {}).is_empty())
	assert(service.complete(RefCounted.new(), {}).is_empty())
	assert(other.calculate(ticket).is_empty())
	assert(world.roster.rng.state == before_rng, "invalid/foreign results must not consume RNG")
	var reply := service.calculate(ticket)
	assert(not reply.is_empty() and reply.summary.win)
	assert(not weak in world.roster.parties)
	var after := Checkpoint.capture(world)
	assert(service.calculate(ticket).is_empty())
	assert(service.complete(ticket, {"win": true}).is_empty())
	assert(Checkpoint.capture(world) == after, "replay must change neither campaign nor RNG")
	reply.party.hero.name = "mutation"
	reply.party.troops.clear()
	assert(Checkpoint.capture(world) == after, "returned aftermath must not alias the world")
	# Siege capture emits synchronous signals. Neither replay nor a new encounter
	# may enter the transaction while the original outcome is being committed.
	var town: Dictionary = {}
	for candidate in world.map.settles:
		if candidate.kind == "castle" and candidate.fac == "nord":
			town = candidate
			break
	assert(not town.is_empty())
	var opponent := service.siege_opponent(world, town)
	var siege_ticket := service.begin(world, opponent)
	var result := service.auto_result(world, opponent)
	assert(result.win)
	var signals_seen := [0]
	var on_change := func(_town):
		signals_seen[0] += 1
		assert(service.complete(siege_ticket, result).is_empty())
		assert(service.begin(world, opponent) == null)
	world.settlement_changed.connect(on_change)
	var siege_reply := service.complete(siege_ticket, result)
	world.settlement_changed.disconnect(on_change)
	assert(signals_seen[0] == 1 and town.fac == "player")
	assert(siege_reply.loot_settlement_id == town.id)
	assert(service.complete(siege_ticket, result).is_empty())
	var next: Dictionary = world.roster.make_party("bandit", "bandit", "Шайка 2", world.player.x, world.player.y, [{"type": "b1", "n": 1}])
	var canceled := service.begin(world, next)
	assert(service.cancel(canceled) and not service.cancel(canceled))
	assert(service.calculate(canceled).is_empty())
	var disposed := service.begin(world, next)
	service.dispose()
	assert(service.calculate(disposed).is_empty())
	other.dispose()
	world.dispose()
	print("Campaign result once tests passed")
	quit(0)
