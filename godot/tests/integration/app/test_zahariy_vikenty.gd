extends SceneTree
## #39: Zahariy and Vikenty flirt in battle, while the party waits and after battles; the line grows with their levels.
const Dialogue = preload("res://apps/godot/presentation/battle/companion_dialogue.gd")
const Banter = preload("res://apps/godot/presentation/battle/banter_lines.gd")
const Remarks = preload("res://apps/godot/presentation/campaign/companion_remarks.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const Event = preload("res://core/battle/combat_event.gd")
const ZAHARIY_UNIT := 5
const VIKENTY_UNIT := 6
const VOICE := {"start": ["Поле"]}

func _initialize() -> void:
	# stages follow the lower level: 1–3, 4–6, 7+
	assert(Banter.stage(1, 9) == 0 and Banter.stage(4, 5) == 1 and Banter.stage(6, 7) == 1 and Banter.stage(7, 12) == 2)
	var pair: Dictionary = Banter.PAIRS[1]
	assert(pair.first == "zahariy" and pair.second == "vikenty")
	for kind in ["battle", "camp", "win", "lose"]:
		for stage in 3:
			var lines: Array = Banter.lines_for(pair, kind, stage)
			assert(not lines.is_empty(), "%s lines at stage %d" % [kind, stage])
			for exchange in lines:
				assert(exchange[0] in pair.tags and String(exchange[1]).length() <= 64 and String(exchange[2]).length() <= 64)
	assert(Banter.lines_for(pair, "battle", 0) != Banter.lines_for(pair, "battle", 2), "The line changes as they grow closer")
	_check_battle(1, 0)
	_check_battle(8, 2)
	_check_down()
	_check_outside()
	print("Zahariy and Vikenty tests passed")
	quit(0)

func _dialogue(level: int) -> Dialogue:
	var dialogue := Dialogue.new()
	dialogue._rng.seed = 3
	dialogue.configure({
		ZAHARIY_UNIT: {"name": "Захарий", "companion_id": "zahariy", "lines": VOICE, "level": level},
		VIKENTY_UNIT: {"name": "Викентий", "companion_id": "vikenty", "lines": VOICE, "level": level + 2},
	})
	return dialogue

func _frame(dead_id: int = -1) -> Array[Dictionary]:
	var frame: Array[Dictionary] = []
	for id in [ZAHARIY_UNIT, VIKENTY_UNIT]:
		frame.append({"id": id, "side": 0, "position": Vector2.ZERO, "dead": id == dead_id, "gone": false, "fleeing": false, "look": {}, "mounted": false})
	frame.append({"id": 9, "side": 1, "position": Vector2(2000, 0), "dead": false, "gone": false, "fleeing": false, "look": {}, "mounted": false})
	return frame

func _lines_in(journal: PackedStringArray) -> Array:
	return Array(journal).filter(func(l: String): return not l.contains("Поле"))

func _check_battle(level: int, stage: int) -> void:
	var dialogue := _dialogue(level)
	var frame := _frame()
	var lines := []
	var t := 0.0
	while lines.is_empty() and t < 30.0:
		lines.append_array(_lines_in(dialogue.advance(0.1, frame, [], false)))
		t += 0.1
	assert(lines.size() == 1, "The pair talks in battle")
	var ok := false
	for exchange in Banter.lines_for(Banter.PAIRS[1], "battle", stage):
		ok = ok or String(lines[0]).ends_with("«%s»" % exchange[1])
	assert(ok, "Stage %d opener: %s" % [stage, lines[0]])

func _check_down() -> void:
	var dialogue := _dialogue(5)
	dialogue.advance(0.1, _frame(), [], false)
	var down := {"kind": Event.Kind.DOWN, "target_id": VIKENTY_UNIT, "source_id": 9, "source_alive": true}
	var journal := PackedStringArray()
	journal.append_array(dialogue.advance(0.0, _frame(VIKENTY_UNIT), [down], false))
	for i in 20:
		journal.append_array(dialogue.advance(0.1, _frame(VIKENTY_UNIT), [], false))
	var replied := false
	for line in journal:
		for reply in Banter.ZV_DOWN.vikenty:
			replied = replied or String(line).ends_with("«%s»" % reply)
	assert(replied, "Zahariy answers when Vikenty falls")

func _check_outside() -> void:
	var catalog := CompanionCatalog.new()
	assert(ContentLoader.populate(catalog))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var hired := [{"id": "zahariy", "lvl": 7}, {"id": "vikenty", "lvl": 8}]
	var camp := Remarks.pair_exchange(hired, ["zahariy", "vikenty"], catalog, Remarks.CAMP, rng)
	assert(camp.size() == 2 and camp[0].contains(": «") and camp[1].contains(": «"))
	var stage_lines: Array = Banter.lines_for(Banter.PAIRS[1], "camp", 2)
	var found := false
	for exchange in stage_lines:
		found = found or camp[0].ends_with("«%s»" % exchange[1])
	assert(found, "Camp talk at the closest stage")
	assert(Remarks.pair_exchange(hired, ["zahariy"], catalog, Remarks.WIN, rng).is_empty(), "Both must have fought")
	assert(Remarks.pair_exchange([{"id": "zahariy", "lvl": 3}], ["zahariy", "vikenty"], catalog, Remarks.CAMP, rng).is_empty(), "Both must be hired")
