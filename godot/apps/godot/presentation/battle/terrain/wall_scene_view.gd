extends "res://apps/godot/presentation/battle/terrain/wall_view.gd"
## Same wall as WallView, assembled from scenes in terrain/wall/ so artists can edit it in the editor.
## Geometry and openings still come from the simulation segments; rubble stays seeded code.
const SEGMENT_SCENE := preload("res://apps/godot/presentation/battle/terrain/wall/wall_segment.tscn")
const TOWER_SCENE := preload("res://apps/godot/presentation/battle/terrain/wall/wall_tower.tscn")
const GATE_LEAF_SCENE := preload("res://apps/godot/presentation/battle/terrain/wall/wall_gate_leaf.tscn")

func configure(walls: Array[Rect2], seed_value: int) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	super.configure(walls, seed_value)
	for segment in _segments:
		var piece := SEGMENT_SCENE.instantiate()
		piece.configure(segment)
		add_child(piece)
	for opening in _openings:
		var center := opening.get_center()
		_add_tower(Vector2(center.x, opening.position.y))
		_add_tower(Vector2(center.x, opening.end.y))
		if opening.size.y > GATE_MIN_WIDTH:
			_add_gate_leaf(center, -1.0)
			_add_gate_leaf(center, 1.0)

func _draw() -> void:
	_draw_rubble()

func _add_tower(point: Vector2) -> void:
	var tower := TOWER_SCENE.instantiate()
	tower.position = point
	add_child(tower)

func _add_gate_leaf(center: Vector2, side: float) -> void:
	var leaf := GATE_LEAF_SCENE.instantiate()
	leaf.position = center + GATE_LEAF_OFFSET * Vector2(1, side)
	leaf.rotation = side * GATE_OPEN_ANGLE
	add_child(leaf)
