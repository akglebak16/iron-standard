extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const Autosave = preload("res://apps/godot/composition/autosave.gd")
const WorldMusic = preload("res://apps/godot/presentation/campaign/world_music.gd")
const BattleControls = preload("res://apps/godot/presentation/battle/hud/battle_controls.gd")
const ResultWindow = preload("res://apps/godot/composition/battle_result_window.gd")
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
	# the battle report has a way out and the rows of the browser report
	var result := {"win": true, "dead": {"n1": 2}, "wounded": {}, "enemyDead": 9, "enemyTotal": 12, "heroKills": 3, "time": 95.0}
	var quick := ResultWindow.quick_rows(result)
	assert(quick[0][1] == "9 из 12" and quick[1][1] == "2" and quick[2][1] == "3")
	assert(ResultWindow.duration(95.0) == "Битва длилась 1 мин 35 сек")
	var resolved := {"summary": {"win": true, "lost": 2, "wounded": 1, "loot": 40, "lost_gold": 0, "xp": 30, "drops": [], "levels_gained": 1, "comps": {}},
		"party": {"hero": {"lvl": 3}, "comps": []}}
	var rows := ResultWindow.campaign_rows(result, resolved, s.roster.catalog, s.gear, null)
	var labels: Array = rows.map(func(r): return r[0])
	assert("Павшие противники" in labels and "Добыча" in labels and "Новый уровень" in labels and "Опыт героя" in labels)
	assert(not "Павшие противники" in ResultWindow.campaign_rows({}, resolved, null, s.gear, null).map(func(r): return r[0]), "auto battle has no enemy count")
	var window := ResultWindow.new()
	root.add_child(window)
	await process_frame
	var chosen: Array = []
	window.action_chosen.connect(func(a: String): chosen.append(a))
	window.show_report(true, "Расчётный бой", rows, ["Чёрный курган разрушен."], [["В меню", "menu"], ["Ещё бой", "again"]])
	assert(window.visible and window.title_label.text == "Победа")
	assert(window.body.find_child("ResultRows", true, false).get_child_count() == rows.size())
	var again := window._footer.find_child("Action_again", true, false) as Button
	assert(again != null)
	again.pressed.emit()
	assert(chosen == ["again"] and not window.visible)
	window.show_report(false, "", rows, [], [["Продолжить", "continue"]])
	window.close_window()
	assert(chosen == ["again", "continue"], "closing the report takes the first action")
	s.dispose()
	print("Autosave, map music and HUD tests passed")
	quit(0)
