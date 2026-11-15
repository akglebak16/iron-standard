extends SceneTree
## The new equipment UI must preserve real inventory actions, including its two-click gesture.
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const PartyWindow = preload("res://campaign/presentation/party_window.gd")
const Art = preload("res://ui/original_art.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var state := WorldState.create(4017, data, "emp")
	var window := PartyWindow.new()
	root.add_child(window)
	await process_frame
	state.player.inv["head_nasal"] = 1
	window.open_for(state, "gear")
	await process_frame
	var before: String = state.player.hero.eq.head
	var portrait_before := (window.body.find_child("EquipmentFigure", true, false) as TextureRect).texture.get_image().get_data()
	var tile := window.body.find_child("Cargo_head_nasal", true, false) as Button
	assert(tile != null and not tile.disabled)
	var quantity := tile.find_child("Quantity", true, false) as Label
	assert(quantity != null and tile.get_global_rect().encloses(quantity.get_global_rect()), "quantity stays on its own item tile")
	tile.pressed.emit()
	assert(state.player.hero.eq.head == before, "one click inspects, without equipping")
	tile = window.body.find_child("Cargo_head_nasal", true, false) as Button
	tile.pressed.emit()
	assert(state.player.hero.eq.head == "head_nasal", "double click equips from cargo")
	assert(int(state.player.inv.get("head_nasal", 0)) == 0)
	var portrait_after := (window.body.find_child("EquipmentFigure", true, false) as TextureRect).texture.get_image().get_data()
	assert(portrait_after != portrait_before, "equipped headgear changes the figure")
	tile = window.body.find_child("Equipped_head", true, false) as Button
	tile.pressed.emit()
	assert(state.player.hero.eq.head == "head_nasal")
	tile = window.body.find_child("Equipped_head", true, false) as Button
	tile.pressed.emit()
	assert(state.player.hero.eq.head == null and int(state.player.inv.head_nasal) == 1, "double click returns gear to cargo")
	assert(Art.sprite("n1", "player") != null and Art.crest("emp") != null)
	window.free()
	print("Visual interface tests passed")
	quit()
