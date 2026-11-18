extends SceneTree
## «Метание ножей» in the tavern (town_window.gd + tavern_knives_view.gd, #215): a game from the stake to the result
## through the tab, the gold right, «Ещё партию» / «Хватит», three games a day and the limit kept in a save.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const Knives = preload("res://core/campaign/rules/tavern_knives.gd")

var window

func _view():
	return window.body.find_child("KnivesGame", true, false)

## Throws three knives through the view, waiting for the regular after each.
func _play() -> void:
	for i in Knives.THROWS:
		while _view() == null or _view().game.phase != "aim":
			await process_frame
		_view().throw()
		assert(_view().game.phase == "their")
		while _view() == null or _view().game.phase == "their":
			await process_frame
	for i in 3:
		await process_frame

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var p = state.player
	var town: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.fac == "emp":
			town = s
			break
	p.gold = 100
	window = TownWindow.new()
	root.add_child(window)
	await process_frame
	window.open_for(state, town)
	window.current_tab = "tavern"
	window.render()
	await process_frame
	assert(window.body.find_child("Knives", true, false) != null, "the game card in the tavern")
	(window.body.find_child("Stake_25", true, false) as Button).pressed.emit()
	await process_frame
	assert(_view() != null and p.gold == 75, "the stake goes on the table")
	assert(window.body.find_child("Knives", true, false) == null, "the game takes the tab")
	await _play()
	var game: Dictionary = _view().game
	assert(game.phase == "done" and game.mine.size() == 3 and game.theirs.size() == 3)
	var mine := Knives.total(game.mine)
	var theirs := Knives.total(game.theirs)
	var expected := 75 + (50 if mine > theirs else (25 if mine == theirs else 0))
	assert(p.gold == expected, "payout %d vs %d: gold %d, expected %d" % [mine, theirs, p.gold, expected])
	assert((_view().find_child("Hint", true, false) as Label).text.contains("выиграл" if mine > theirs else ("Ничья" if mine == theirs else "проиграл")))
	# two more games, then the regulars are done for the day
	for n in 2:
		(_view().find_child("Again", true, false) as Button).pressed.emit()
		await process_frame
		await _play()
	assert(Knives.games_left(town, state.clock.day) == 0)
	var again := _view().find_child("Again", true, false) as Button
	assert(again.disabled and again.tooltip_text.contains("завтра"), again.tooltip_text)
	(_view().find_child("Quit", true, false) as Button).pressed.emit()
	await process_frame
	assert(_view() == null and window.body.find_child("Knives", true, false) != null)
	for stake in Knives.STAKES:
		assert((window.body.find_child("Stake_%d" % stake, true, false) as Button).disabled)
	# the limit survives a save (the settlement is saved whole); a settlement without the field allows three games
	var d := WorldSave.to_dict(state)
	assert(not d.is_empty(), "the state with a played tavern still saves")
	var back = WorldSave.from_dict(JSON.parse_string(JSON.stringify(d)), data, ContentLoader.registry())
	assert(back != null and Knives.games_left(back.map.settlement_by_id(town.id), state.clock.day) == 0)
	var other: Dictionary = back.map.settlement_by_id(town.id).duplicate()
	other.erase("knife")
	assert(Knives.games_left(other, state.clock.day) == 3, "old saves have no field: three games")
	# 1280×720: the target and the buttons fit
	town.erase("knife")
	window.render()
	(window.body.find_child("Stake_5", true, false) as Button).pressed.emit()
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	assert(_view().find_child("Target", true, false).get_global_rect().end.x <= panel.end.x)
	window.free()
	print("Tavern knives tests passed")
	quit()
