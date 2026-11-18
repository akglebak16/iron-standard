extends SceneTree
## «Задания» in a town (town_window.gd, #213): a card per board order with kind, task, reward and deadline; «Взять»
## moves it into the journal; a full journal disables it and says why; «На карте» marks the target; an empty board
## shows its card; the player's own errands are listed with progress.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")
const QuestCard = preload("res://apps/godot/presentation/campaign/quest_card.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(4017, data, "emp", ContentLoader.registry())
	var p = state.player
	var town: Dictionary = {}
	for s in state.map.settles:
		if s.kind == "town" and s.fac == "emp" and s.get("board", []).size() >= 2:
			town = s
			break
	assert(not town.is_empty(), "a town with orders")
	p.quests = []
	var window := TownWindow.new()
	root.add_child(window)
	await process_frame
	var marks: Array = []
	window.map_target.connect(func(x: float, y: float): marks.append(Vector2(x, y)))
	window.open_for(state, town)
	window.current_tab = "quests"
	window.render()
	await process_frame
	var first: Dictionary = town.board[0]
	var card: Node = window.body.find_child("Board_%d" % int(first.id), true, false)
	assert(card != null, "a card per order")
	var bonus := float(state.player_effects().get("quest", 0.0))
	assert((card.find_child("Reward", true, false) as Label).text == str(roundi(float(first.reward) * (1.0 + bonus))))
	assert((card.find_child("Kind", true, false) as Label).text == String(QuestCard.TYPES[first.type][0]).to_upper())
	assert((card.find_child("Deadline", true, false) as Label).text.contains("до дня %d" % int(first.dl)))
	# «На карте» marks the target and closes the window
	var go := window.body.find_child("Map_%d" % int(first.id), true, false) as Button
	if go != null:
		go.pressed.emit()
		var t: Dictionary = QuestCard.target(first, state.map)
		assert(marks == [Vector2(t.x, t.y)] and not window.visible)
		window.open_for(state, town)
		window.current_tab = "quests"
		window.render()
	# «Взять» moves the order into the journal
	(window.body.find_child("Take_%d" % int(first.id), true, false) as Button).pressed.emit()
	assert(p.quests.size() == 1 and int(p.quests[0].id) == int(first.id))
	assert(window.body.find_child("Board_%d" % int(first.id), true, false) == null, "taken orders leave the board")
	assert(window.body.find_child("Mine_%d" % int(first.id), true, false) != null, "and show up among the player's errands")
	assert(window.sub_label.text.contains("взято задание"), window.sub_label.text)
	# a full journal: «Взять» is disabled and says why
	while p.quests.size() < state.quests.MAX_QUESTS:
		p.quests.append(first.duplicate())
	window.render()
	for b in window.body.find_children("Take_*", "Button", true, false):
		assert((b as Button).disabled and (b as Button).tooltip_text.contains("Журнал полон"))
	# an empty board
	town.board = []
	window.render()
	assert(window.body.find_child("BoardEmpty", true, false) != null)
	# 1280×720: buttons stay inside the window
	town.board = [first.duplicate()]
	p.quests = []
	window.render()
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	var panel: Rect2 = window._panel.get_global_rect()
	for b in window.body.find_children("Take_*", "Button", true, false):
		assert((b as Control).get_global_rect().end.x <= panel.end.x)
	window.free()
	print("Town quests tests passed")
	quit()
