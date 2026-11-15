extends RefCounted

var position: Vector2
var trunk_radius: float
var variant: int

func _init(point: Vector2, radius: float, visual_variant: int) -> void:
	position = point
	trunk_radius = radius
	variant = visual_variant

func to_dictionary() -> Dictionary:
	return {"position": position, "tree": trunk_radius > 0.0, "variant": variant}
