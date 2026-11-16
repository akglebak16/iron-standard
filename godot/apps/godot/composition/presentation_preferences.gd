extends RefCounted
## App-owned persistence shared by game scenes. Keep the existing path for audio settings.
const DEFAULT_PATH := "user://audio.cfg"
const SECTION := "audio"
const EFFECTS_KEY := "effects"
const MUSIC_KEY := "music"
const VISUAL_SECTION := "visual"
const BLOOD_KEY := "blood"
const FPS_KEY := "fps"

var _path: String

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path

func read() -> Dictionary:
	var config := ConfigFile.new()
	config.load(_path)
	return {"effects": _read_flag(config, SECTION, EFFECTS_KEY), "music": _read_flag(config, SECTION, MUSIC_KEY)}

func read_blood() -> bool:
	var config := ConfigFile.new()
	config.load(_path)
	return _read_flag(config, VISUAL_SECTION, BLOOD_KEY)

func save(effects: bool, music: bool) -> Error:
	var config := ConfigFile.new()
	config.load(_path)
	config.set_value(SECTION, EFFECTS_KEY, effects)
	config.set_value(SECTION, MUSIC_KEY, music)
	return config.save(_path)

func save_blood(enabled: bool) -> Error:
	var config := ConfigFile.new()
	config.load(_path)
	config.set_value(VISUAL_SECTION, BLOOD_KEY, enabled)
	return config.save(_path)

## The FPS counter is off unless the player switched it on.
func read_fps() -> bool:
	var config := ConfigFile.new()
	config.load(_path)
	return config.get_value(VISUAL_SECTION, FPS_KEY, false) == true

func save_fps(enabled: bool) -> Error:
	var config := ConfigFile.new()
	config.load(_path)
	config.set_value(VISUAL_SECTION, FPS_KEY, enabled)
	return config.save(_path)

static func _read_flag(config: ConfigFile, section: String, key: String) -> bool:
	var value: Variant = config.get_value(section, key, true)
	return value if value is bool else true
