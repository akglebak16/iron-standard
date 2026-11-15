extends SceneTree
const Setup = preload("res://core/battle/data/battle_setup.gd")

func _initialize() -> void:
	var authored = load("res://content/scenarios/demo_battle.tres").duplicate(true)
	var setup: Setup = authored.to_setup()
	assert(setup.get_class() == "RefCounted")
	for field in Setup.FIELDS: assert(setup.get(field) == authored.get(field))
	var second: Setup = authored.to_setup()
	var original: int = setup.player_army[0].n
	authored.player_army[0].n = original + 100
	assert(setup.player_army[0].n == original and second.player_army[0].n == original)
	var clone: Setup = setup.duplicate(true)
	clone.hero_profile.name = "changed"
	assert(setup.hero_profile.name != "changed")
	print("Setup boundary tests passed")
	quit(0)
