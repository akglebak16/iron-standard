extends RefCounted

const DATA_PATH := "res://campaign/data/goods.json"
var _goods: Dictionary = {}

func load_data() -> bool:
	return replace_data(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))

func replace_data(data: Variant) -> bool:
	if not data is Dictionary or data.is_empty():
		return false
	for id in data:
		var item: Variant = data[id]
		if not id is String or id.is_empty() or not item is Dictionary or not item.get("n") is String:
			return false
		if not _positive_number(item.get("p")) or not _positive_number(item.get("w")) or not item.get("make") is Array:
			return false
	_goods = data.duplicate(true)
	return true

func definitions() -> Dictionary:
	return _goods.duplicate(true)

static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0
