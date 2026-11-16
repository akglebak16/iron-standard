extends SceneTree
const Bank = preload("res://apps/godot/presentation/battle/audio/sound_bank.gd")
const UiSounds = preload("res://apps/godot/presentation/campaign/ui_sounds.gd")
const WorldHud = preload("res://apps/godot/presentation/campaign/world_hud.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const BattleEncounter = preload("res://core/campaign/application/battle_encounter.gd")

func _initialize() -> void:
	# sfx('clang'): five pitches across 1900–2300 Hz instead of one fixed tone
	var clangs := Bank.clang_variants()
	assert(clangs.size() == 5 and clangs[0].data != clangs[4].data)
	# window sounds from src/04_audio.js
	var ui := Bank.ui_sounds()
	for k in ["click", "coin", "level", "order"]:
		assert(ui.has(k))
	assert(ui.level.data.size() > ui.click.data.size(), "The level tune is the longest")
	# a town button with a sound plays it once pressed
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	s.player.gold = 5000
	var town: Dictionary = s.map.settles.filter(func(t): return t.kind == "town" and t.fac == "emp")[0]
	var tw := TownWindow.new()
	root.add_child(tw)
	await process_frame
	tw.open_for(s, town)
	tw.current_tab = "market"
	tw.render()
	UiSounds.played.clear()
	var buy: Button = null
	for b in tw.body.find_children("", "Button", true, false):
		if b.text == "Купить" and not b.disabled:
			buy = b
			break
	assert(buy != null)
	buy.pressed.emit()
	assert(UiSounds.played.size() == 1 and UiSounds.played[0] == "coin", "Buying food rings coins")
	UiSounds.enabled = false
	buy = null
	for b in tw.body.find_children("", "Button", true, false):
		if b.text == "Купить" and not b.disabled:
			buy = b
			break
	buy.pressed.emit()
	assert(UiSounds.played.size() == 2, "Muted sounds are still recorded, just not played")
	UiSounds.enabled = true
	# toast: the notice clears after 2.2 seconds
	var hud := WorldHud.new()
	root.add_child(hud)
	await process_frame
	hud.show_notice("Проверка")
	hud._process(2.0)
	assert(hud._notice.text == "Проверка")
	hud._process(0.3)
	assert(hud._notice.text == "", "Gone after 2.2 s")
	# startBattle puts the hero at x = 730
	var bridge = BattleEncounter.new(ContentLoader.registry(), RandomNumberGenerator.new())
	var foe: Dictionary = s.roster.make_party("bandit", "bandit", "Шайка", s.player.x + 5, s.player.y, [{"type": "b1", "n": 3}])
	assert(bridge.make_setup(s, foe).hero_position == Vector2(730, 850))
	s.dispose()
	print("UI feedback tests passed")
	quit(0)
