extends SceneTree
## The map scene: riding up to a fight between map parties shows who fights whom and lets the player help a side;
## after the choice the usual battle dialog counts the allies, and a calculated battle ends the map fight (#238).
const World = preload("res://apps/godot/composition/world_demo.tscn")
const Rules = preload("res://core/campaign/world/party_rules.gd")

func _buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			out.append(c)
		out.append_array(_buttons(c))
	return out

func _texts(node: Node) -> Array:
	return _buttons(node).map(func(b): return (b as Button).text)

func _press(node: Node, prefix: String) -> void:
	for b in _buttons(node):
		if (b as Button).text.begins_with(prefix):
			(b as Button).pressed.emit()
			return
	assert(false, "no button «%s» in %s" % [prefix, str(_texts(node))])

func _initialize() -> void:
	Engine.max_fps = 0
	var world = World.instantiate()
	world.sim_thread = false # the test changes the world between frames
	root.add_child(world)
	while not world._ready_to_play:
		await process_frame
	var s = world.state
	var pair: Array = []
	for x in Rules.REAL_FACTIONS:
		for y in Rules.REAL_FACTIONS:
			if pair.is_empty() and x != y and x != s.player.culture and y != s.player.culture and s.roster.hostile({"kind": "lord", "fac": x}, {"kind": "lord", "fac": y}):
				pair = [x, y]
	assert(not pair.is_empty())
	s.player.rel[pair[0]] = 0.0
	s.player.rel[pair[1]] = 0.0
	s.player.stop()
	s.player.troops = [{"type": "e3c", "n": 300}]
	var at := Vector2(s.player.x + 10.0, s.player.y)
	var ta: String = world._bridge.troops.for_faction(pair[0])[0].id
	var tb: String = world._bridge.troops.for_faction(pair[1])[0].id
	var a: Dictionary = s.roster.make_party("lord", pair[0], "Проба Левая", at.x, at.y, [{"type": ta, "n": 60}])
	var b: Dictionary = s.roster.make_party("lord", pair[1], "Проба Правая", at.x + 4.0, at.y, [{"type": tb, "n": 60}])
	s.skirmish.contact(a, b, s.ai.auto_fight)
	assert(not s.skirmish.fight_of(a).is_empty())
	world._on_party_met(a, false)
	await process_frame
	var dialog: CanvasLayer = world._dialog
	assert(dialog.visible and dialog._title.text == "Идёт сражение")
	var labels: Array = _texts(dialog)
	assert(labels.has("Не вмешиваться") and labels.filter(func(t): return t.begins_with("Помочь: ")).size() == 2, str(labels))
	assert("против" in dialog._sub.text and "испортятся отношения" in dialog._sub.text, "the dialog warns that helping attacks the other state")
	# take the left side: the right one becomes the enemy, the left one fights with the player
	_press(dialog, "Помочь: ")
	await process_frame
	assert(s.skirmish.fights.is_empty() and a.get("fight") == null, "the map fight became the player's battle")
	assert(dialog.visible and _texts(dialog).has("В бой!") and _texts(dialog).has("Рассчитать бой"), str(_texts(dialog)))
	assert(world._meeting == b and "с тобой ещё" in dialog._sub.text, dialog._sub.text)
	_press(dialog, "Рассчитать бой")
	for i in 3:
		await process_frame
	assert(world._result.visible, "the calculated battle shows its report")
	assert(s.journal.any(func(e): return "Проба Левая" in str(e)), "the journal names the ally")
	assert(world._join.is_empty() and world._meeting_fight.is_empty())
	# leaving a fight alone changes nothing
	world._result.visible = false
	var c: Dictionary = s.roster.make_party("lord", pair[0], "Проба Третья", at.x + 300.0, at.y, [{"type": ta, "n": 60}])
	var d: Dictionary = s.roster.make_party("lord", pair[1], "Проба Четвёртая", at.x + 304.0, at.y, [{"type": tb, "n": 60}])
	s.skirmish.contact(c, d, s.ai.auto_fight)
	var rel: Dictionary = s.player.rel.duplicate()
	world._on_party_met(d, false)
	await process_frame
	_press(dialog, "Не вмешиваться")
	assert(not s.skirmish.fight_of(c).is_empty() and s.player.rel == rel and not s.clock.paused)
	world.queue_free()
	await process_frame
	print("Join battle dialog tests passed")
	quit(0)
