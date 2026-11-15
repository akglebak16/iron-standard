extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Troops = preload("res://core/troops/data/catalog.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const World = preload("res://core/campaign/world/world_state.gd")

func _initialize() -> void:
	var first := Loader.registry()
	var second := Loader.registry()
	assert(first.size() == 6 and first.is_read_only())
	for key in first:
		assert(first[key].is_ready() and first[key] != second[key])
		assert(not first[key].replace_data({}))
	var troop: Dictionary = first.troops.get_troop("e1")
	var original_hp: float = troop.hp
	troop.hp = -10
	assert(first.troops.get_troop("e1").hp == original_hp)
	assert(not first.troops.replace_data({"e1": second.troops.get_troop("e1")}))
	assert(first.factions.factions.is_read_only())
	assert(first.factions.factions.emp.is_read_only())
	var faction: Dictionary = first.factions.get_faction("emp")
	faction.name = "changed"
	assert(first.factions.get_faction("emp").name != "changed")
	var europe := Europe.new()
	assert(not europe.is_ready())
	assert(Loader.populate(europe))
	assert(not europe.replace_data({"eu": {}}))
	assert(europe.is_ready()) # Failed replacement keeps valid definitions intact.
	assert(World.create(4242, europe, "emp", {}) == null)
	var invalid := first.duplicate()
	invalid.troops = Troops.new()
	assert(World.create(4242, europe, "emp", invalid) == null)
	print("Content registry tests passed")
	quit(0)
