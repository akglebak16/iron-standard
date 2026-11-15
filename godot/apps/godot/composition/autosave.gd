extends RefCounted
## Silent autosave (saveGame(true) in src/07_main.js and src/06_ui.js): after a battle, on entering a settlement,
## before leaving the map for the title screen and at midnight of every game day. Only on the map, never in battle.
const SaveStore = preload("res://adapters/persistence/save_store.gd")

var path := SaveStore.PATH
var _day := -1

## The clock moved into a new day since the last call (the first call only remembers the day).
func crossed_midnight(state: RefCounted) -> bool:
	var day := int(state.clock.day)
	var crossed := _day >= 0 and day > _day
	_day = day
	return crossed

func save(state: RefCounted, in_battle: bool) -> bool:
	if state == null or in_battle:
		return false
	return SaveStore.save(state, path)
