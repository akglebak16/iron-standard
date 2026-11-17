extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## The new equipment UI must preserve real inventory actions, including its two-click gesture.
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const PartyWindow = preload("res://apps/godot/presentation/campaign/party_window.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	var loaded := ContentLoader.populate(data)
	assert(loaded)
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var window := PartyWindow.new()
	root.add_child(window)
	await process_frame
	assert(ThemeDB.get_project_theme().default_font != null, "runtime theme installs imported fonts")
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
	# Faction cards must handle nobles without destinations and keep navigation usable.
	window.open_for(state, "factions")
	var pick := window.body.find_child("FactionPick_pact", true, false) as Button
	assert(pick != null and not pick.disabled)
	pick.pressed.emit()
	assert(window._faction == "pact", "faction selection switches the inspected state")
	assert(window.body.find_child("DiplomacyMatrix", true, false) != null)
	assert(window.body.find_child("FamilyLoyalty", true, false) != null)
	assert(window.body.find_child("FactionRelation", true, false) != null)
	var relation := window.body.find_child("FactionRelation", true, false) as ProgressBar
	assert(is_equal_approx(relation.value, float(state.player.rel.get("pact", 0)) + 100))
	# A long faction name and a 1280px window must not push content past the right edge.
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var identity := window.body.find_child("FactionIdentity", true, false) as Control
	assert(identity.get_global_rect().end.x <= window._panel.get_global_rect().end.x, "long titles stay in the window")
	assert(window.close_button.get_global_rect().end.y <= root.size.y, "close remains available")
	window.free()
	print("Visual interface tests passed")
	quit()
