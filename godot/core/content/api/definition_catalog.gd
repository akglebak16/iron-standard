extends RefCounted
## Validated definitions can be sealed before injection into a running context.
var _sealed := false
var _valid := false

func seal() -> void:
	_sealed = true
	for property in get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: _freeze(get(property.name))
func is_ready() -> bool: return _valid

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: _freeze(child)
		value.make_read_only()
