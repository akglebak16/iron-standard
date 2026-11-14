extends SceneTree
const Catalog = preload("res://characters/data/perk_catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	assert(catalog.size() == 20)
	assert(catalog.get_perk("tactician").fx.ally == [0.03, 0.06, 0.09])
	var detached := catalog.get_perk("tactician")
	detached.fx.ally[0] = 9.0
	assert(catalog.get_perk("tactician").fx.ally[0] == 0.03)
	var invalid := {"zero": catalog.zero_effects(), "perks": [catalog.get_perk("tactician")]}
	invalid.perks[0].fx.ally = [0.1]
	assert(not catalog.replace_data(invalid))
	assert(catalog.size() == 20) # Invalid reload leaves old definitions intact.
	print("Perk catalog tests passed")
	quit(0)
