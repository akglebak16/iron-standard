extends "res://core/content/api/definition_catalog.gd"
## Faction looks and names exported from FACTIONS in src/01_core.js (campaign/tools/export_world.cjs).
const CONTENT_KEY := "factions"

var factions: Dictionary = {}

func replace_data(parsed: Variant) -> bool:
	if _sealed: return false
	if not parsed is Dictionary or parsed.is_empty(): return false
	for id in parsed:
		if not id is String or not parsed[id] is Dictionary: return false
		if not parsed[id].get("name") is String: return false
	factions = parsed.duplicate(true)
	_valid = true
	return true

func get_faction(id: String) -> Dictionary:
	return factions.get(id, factions.get("bandit", {})).duplicate(true)
