extends RefCounted
## App-owned persistence for audio preferences shared by game scenes.
const DEFAULT_PATH := "user://audio.cfg"
const SECTION := "audio"
const EFFECTS_KEY := "effects"
const MUSIC_KEY := "music"

var _path: String

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path

func read() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return {"effects": true, "music": true}
	return {"effects": _read_flag(config, EFFECTS_KEY), "music": _read_flag(config, MUSIC_KEY)}

func save(effects: bool, music: bool) -> Error:
	var config := ConfigFile.new()
	config.set_value(SECTION, EFFECTS_KEY, effects)
	config.set_value(SECTION, MUSIC_KEY, music)
	return config.save(_path)

static func _read_flag(config: ConfigFile, key: String) -> bool:
	var value: Variant = config.get_value(SECTION, key, true)
	return value if value is bool else true
