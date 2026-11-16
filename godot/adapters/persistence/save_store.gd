extends RefCounted
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## The save file in the user's data folder (the browser used localStorage).
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const PATH := "user://iron_standard_save.json"
const MAX_FILE_BYTES := 24 * 1024 * 1024
const KEEP_GENERATIONS := 3
const MAX_NAME_LENGTH := 40

static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path) or not _generations(path).is_empty()

## `label` is the player's own name for the save; it is shown in the slot list.
static func save(state: RefCounted, path := PATH, label := "") -> bool:
	var data := WorldSave.to_dict(state)
	if data.is_empty(): return false
	# Shown on the save/load screen; not part of the checked payload, so a slot can be listed without restoring the world.
	data["meta"] = _meta(state)
	if clean_name(label) != "": data.meta["name"] = clean_name(label)
	var text := JSON.stringify(data)
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES: return false
	var generations := _generations(path)
	var sequence: int = 1 if generations.is_empty() else generations[0].sequence + 1
	if sequence <= 0: return false
	var destination := path + ".v2.%020d.json" % sequence
	# Publish to a previously nonexistent name. Windows rename-overwrite may first
	# remove its destination; immutable generations avoid that loss window entirely.
	if FileAccess.file_exists(destination): return false
	var temporary := destination + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != text: return false
	if DirAccess.rename_absolute(_native_path(temporary), _native_path(destination)) != OK: return false
	# Keep the previous two committed generations; v1 is never overwritten/deleted.
	for i in range(KEEP_GENERATIONS - 1, generations.size()):
		DirAccess.remove_absolute(_native_path(generations[i].path))
	return true

static func load_state(europe: EuropeData, path := PATH) -> RefCounted:
	for generation in _generations(path):
		var loaded := _load_file(europe, generation.path)
		if loaded != null: return loaded
	return _load_file(europe, path)

## What a slot holds without restoring the world: {exists, ok, meta}. `ok` is false when files exist but none can be read.
## Follows the same order as load_state, so the description matches the generation that would load.
static func describe(path := PATH) -> Dictionary:
	var files: Array[String] = []
	for generation in _generations(path): files.append(generation.path)
	if FileAccess.file_exists(path): files.append(path)
	for file in files:
		var data := _envelope(file)
		if not _readable(data): continue
		var meta: Dictionary = data.meta.duplicate() if data.get("meta") is Dictionary else {}
		if not (meta.get("saved_at") is float or meta.get("saved_at") is int):
			meta["saved_at"] = float(FileAccess.get_modified_time(file))
		return {"exists": true, "ok": true, "meta": meta}
	return {"exists": not files.is_empty(), "ok": false, "meta": {}}

## One line, no control characters, at most MAX_NAME_LENGTH characters.
static func clean_name(label: String) -> String:
	var out := ""
	for character in label:
		out += " " if character.unicode_at(0) < 32 or character.unicode_at(0) == 127 else character
	return out.strip_edges().left(MAX_NAME_LENGTH).strip_edges()

static func _meta(state: RefCounted) -> Dictionary:
	var player = state.player
	var men := 1 + (player.comps as Array).size()
	for stack in player.troops:
		men += int(stack.get("n", 0))
	return {"saved_at": Time.get_unix_time_from_system(), "day": int(state.clock.day), "hero": str(player.hero.get("name", "")),
		"men": men, "gold": int(player.gold)}

static func _readable(data: Dictionary) -> bool:
	if data.get("version") == 1: return true
	return data.get("version") == WorldSave.VERSION and data.get("payload") is String and data.get("sha256") is String \
		and data.payload.sha256_text() == data.sha256

static func _envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES: return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary: return {}
	return json.data

static func _load_file(europe: EuropeData, path: String) -> RefCounted:
	var data := _envelope(path)
	if data.is_empty(): return null
	return WorldSave.from_dict(data, europe, ContentLoader.registry())

static func _generations(path: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var directory := DirAccess.open(path.get_base_dir())
	if directory == null: return found
	var prefix := path.get_file() + ".v2."
	for name in directory.get_files():
		if not name.begins_with(prefix) or not name.ends_with(".json"): continue
		var number := name.substr(prefix.length()).trim_suffix(".json")
		if number.length() != 20 or not number.is_valid_int() or int(number) < 1: continue
		found.append({"sequence": int(number), "path": path.get_base_dir().path_join(name)})
	found.sort_custom(func(a, b): return a.sequence > b.sequence)
	return found

static func _native_path(path: String) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	if OS.get_name() == "Windows":
		absolute = absolute.replace("/", "\\")
		if not absolute.begins_with("\\\\"):
			return "\\\\?\\" + absolute
	return absolute
