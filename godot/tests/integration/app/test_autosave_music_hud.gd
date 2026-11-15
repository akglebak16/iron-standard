extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const Autosave = preload("res://apps/godot/composition/autosave.gd")
const WorldMusic = preload("res://apps/godot/presentation/campaign/world_music.gd")
const BattleControls = preload("res://apps/godot/presentation/battle/hud/battle_controls.gd")
const MarksLayer = preload("res://apps/godot/presentation/campaign/world_marks_layer.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	# autosave: silent save on the map, never in battle, and a day boundary is noticed once
	var autosave := Autosave.new()
	autosave.path = "user://test_autosave.json"
	assert(not autosave.crossed_midnight(s), "the first look only remembers the day")
	assert(not autosave.crossed_midnight(s))
	s.clock.day += 1
	assert(autosave.crossed_midnight(s) and not autosave.crossed_midnight(s))
	assert(not autosave.save(s, true), "no autosave during a battle")
	assert(autosave.save(s, false) and SaveStore.exists(autosave.path))
	assert(SaveStore.load_state(data, autosave.path) != null, "the autosave loads back")
	# map music plays notes while on and stays silent while off
	var music := WorldMusic.new()
	root.add_child(music)
	await process_frame
	music.enabled = true
	for i in 10:
		music.advance(1.0)
	assert(music.notes_played >= 3, "a note every 1.3–2.4 s")
	var played: int = music.notes_played
	music.enabled = false
	for i in 10:
		music.advance(1.0)
	assert(music.notes_played == played)
	# battle HUD hero line as in updateBattleHud
	assert(BattleControls.hero_line(4, "Рыцарский меч", true, false) == "уровень 4 · Рыцарский меч [X]")
	assert(BattleControls.hero_line(0, "Рыцарский меч", false, false) == "Рыцарский меч", "quick battle: no level, no [X] without a bow")
	assert(BattleControls.hero_line(4, "Рыцарский меч", true, true) == "ранен")
	# the route end marker follows the remaining path
	s.player.path = [Vector2(10, 20), Vector2(50, 60)]
	s.player.pi = 0
	assert(MarksLayer.route_end(s.player) == Vector2(50, 60))
	s.player.pi = 2
	assert(MarksLayer.route_end(s.player) == null, "no marker once the party has arrived")
	s.dispose()
	print("Autosave, map music and HUD tests passed")
	quit(0)
