extends Node2D
## One stone wall segment built from editable nodes; the simulation only supplies the rectangle.
const MERLON_SIZE := Vector2(9, 22)
const OUTLINE_WIDTH := 2.0

func configure(rect: Rect2) -> void:
	position = rect.position
	var size := rect.size
	$Shadow.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	$Stone.size = size
	var slots := floori(size.y / MERLON_SIZE.y)
	$Merlons.position = Vector2(size.x - MERLON_SIZE.x, 0.0)
	$Merlons.size = Vector2(MERLON_SIZE.x, slots * MERLON_SIZE.y)
	var inset := OUTLINE_WIDTH * 0.5
	$Outline.points = PackedVector2Array([Vector2(inset, inset), Vector2(size.x - inset, inset), size - Vector2.ONE * inset, Vector2(inset, size.y - inset)])
