extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const World = preload("res://campaign/world/world_state.gd")
const Europe = preload("res://campaign/data/europe_data.gd")
const Rules = preload("res://campaign/world/party_rules.gd")

func _initialize() -> void:
	var europe := Europe.new()
	assert(ContentLoader.populate(europe))
	var first := World.create(4242, europe, "emp", ContentLoader.registry())
	var second := World.create(4242, europe, "emp", ContentLoader.registry())
	var noble := {"fac": "emp", "kind": "lord"}
	var enemy := {"fac": "nord", "kind": "lord"}
	var vassal := {"fac": "player", "kind": "cvass"}
	assert(first.roster.hostile(noble, enemy) and second.roster.hostile(noble, enemy))
	first.wars.wars.erase(Rules.war_key("emp", "nord"))
	assert(not first.roster.hostile(noble, enemy) and second.roster.hostile(noble, enemy))
	first.player.rel = {"nord": -60}
	second.player.rel = {"nord": 40}
	assert(first.roster.hostile(vassal, enemy) and not second.roster.hostile(vassal, enemy))
	var second_rng: int = second.roster.rng.state
	first.roster.rng.randf()
	assert(second.roster.rng.state == second_rng)
	# Advancing either world must not install its state in process-wide rules.
	first.advance(0.2)
	second.advance(0.2)
	assert(not first.roster.hostile(noble, enemy) and second.roster.hostile(noble, enemy))
	assert(first.roster.hostile(vassal, enemy) and not second.roster.hostile(vassal, enemy))
	first.dispose()
	assert(second.roster.hostile(noble, enemy))
	second.dispose()
	print("Campaign isolation tests passed")
	quit(0)
