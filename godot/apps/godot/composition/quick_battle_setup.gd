extends RefCounted
## Menu choices become authoring data here; army generation stays in its content owner.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Setup = preload("res://adapters/godot/resources/battle_setup_resource.gd")
const Troops = preload("res://core/troops/data/catalog.gd")
const Factions = preload("res://core/campaign/data/faction_catalog.gd")
const Generation = preload("res://core/troops/rules/generation.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const CULTURES := ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]
const SIZES := [50, 100, 200, 1000]

static func build(options: Dictionary, seed_value := 0) -> Setup:
	var own: String = str(options.get("me", "nord"))
	var foe: String = str(options.get("foe", "emp"))
	var raw_count = options.get("size", 50)
	if not (raw_count is int or raw_count is float): return null
	var count := int(raw_count)
	if own not in CULTURES or foe not in CULTURES + ["bandit"] or count not in SIZES: return null
	var troops := Troops.new()
	var factions := Factions.new()
	if not ContentLoader.populate(troops) or not ContentLoader.populate(factions): return null
	var setup := Setup.new()
	setup.seed = seed_value if seed_value != 0 else randi_range(1, 999999999)
	var rng := RandomNumberGenerator.new()
	rng.seed = setup.seed
	setup.player_army = Generation.army(troops, own, count, 0.6, rng)
	setup.enemy_army = Generation.army(troops, foe, count + 4, 0.35 if foe == "bandit" else 0.6, rng)
	setup.quick = true
	setup.player_faction = "player"
	setup.enemy_faction = foe
	setup.biome = str(factions.get_faction(own).get("biome", "grass"))
	# Reuse the campaign's faction naming rule without constructing a campaign map.
	setup.enemy_leader_name = Roster.new(null, setup.seed, troops, factions).lord_name(foe)
	setup.hero_troop = str(setup.player_army[0].type)
	setup.hero_position = Vector2(730, 850)
	setup.hero_profile = {"name":"Ты", "str":3, "vit":3, "agi":2, "int":2, "cha":2, "perks":[],
		"eq":{"head":"head_nasal", "body":"body_mail", "hands":"hands_leather", "legs":"legs_boots", "melee":"sword_knight", "ranged":"bow_long", "shield":"shield_banded", "horse":"horse_riding" if own == "khan" else null},
		"sel":"melee", "hp":1.0, "seed":7}
	return setup
