extends SceneTree
const Catalog = preload("res://troops/data/catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	var original := catalog.get_troop("n1")
	var changed := catalog.get_troop("n1")
	changed.hp = 0
	changed.look.weapon = "changed"
	assert(catalog.get_troop("n1") == original)
	for field in ["hp", "spd", "cd", "block"]:
		var invalid := original.duplicate(true)
		invalid.erase(field)
		assert(not catalog.replace_data({"n1": invalid}))
	for bad_value in [NAN, INF, -1, "60"]:
		var invalid := original.duplicate(true)
		invalid.hp = bad_value
		assert(not catalog.replace_data({"n1": invalid}))
	var invalid_shield := original.duplicate(true)
	invalid_shield.shb = 1.1
	assert(not catalog.replace_data({"n1": invalid_shield}))
	assert(not catalog.replace_data([]))
	assert(catalog.size() == 67 and catalog.get_troop("n1") == original)
	var definitions := {"n1": original.duplicate(true)}
	assert(catalog.replace_data(definitions))
	definitions.n1.hp = 0
	assert(catalog.get_troop("n1").hp == original.hp)
	print("Catalog validation tests passed")
	quit(0)
