extends RefCounted
## The save file in the user's data folder (the browser used localStorage).
const WorldSave = preload("res://campaign/world/world_save.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const PATH := "user://iron_standard_save.json"

static func exists() -> bool:
	return FileAccess.file_exists(PATH)

static func save(state: RefCounted, path := PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(WorldSave.to_dict(state)))
	return true

static func load_state(europe: EuropeData, path := PATH) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return null
	return WorldSave.from_dict(parsed, europe)
