extends SceneTree
const Obstacles = preload("res://runtime/spatial/static_obstacle_index.gd")
const Workspace = preload("res://runtime/spatial/contact_workspace.gd")
const Grid = preload("res://core/battle/rules/collision_grid.gd")

func _initialize() -> void:
	var workspace := Workspace.new()
	workspace.resize(2000)
	var alias := workspace.positions
	workspace.resize(2000)
	alias[5] = Vector2(4, 5)
	assert(workspace.positions[5] == Vector2(4, 5), "same-size passes must retain their storage")
	var second := Workspace.new()
	second.resize(2000)
	assert(second.positions[5] == Vector2.ZERO)
	workspace.resize(2001)
	assert(workspace.positions[5] == Vector2(4, 5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var positions := PackedVector2Array()
	var radii := PackedFloat64Array()
	for i in 300:
		positions.append(Vector2(rng.randf_range(-1000, 1000), rng.randf_range(-1000, 1000)))
		radii.append(rng.randf_range(4, 45))
	# Coincident centers and a long chain test re-query after a constraint moves us.
	for i in 30:
		positions.append(Vector2(i * 20, 0))
		radii.append(30.0)
	positions.append(Vector2.ZERO)
	radii.append(100.0)
	var index := Obstacles.new()
	index.rebuild(positions, radii)
	assert(index.revision == 1)
	for i in 600:
		var at := positions[i] if i < positions.size() else Vector2(rng.randf_range(-1000, 1000), rng.randf_range(-1000, 1000))
		var radius := rng.randf_range(4, 40)
		assert(index.constrain(at, radius) == _plain(at, radius, positions, radii), "indexed constraints must preserve original obstacle order")
	var result := index.constrain(Vector2.ZERO, 10)
	positions.fill(Vector2(9999, 9999))
	assert(index.constrain(Vector2.ZERO, 10) == result, "geometry must detach input buffers")
	index.rebuild(PackedVector2Array(), PackedFloat64Array())
	assert(index.revision == 2 and index.constrain(Vector2.ZERO, 10) == Vector2.ZERO)
	var live := PackedByteArray([1, 0, 1])
	var grid := Grid.new(PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]), Vector2(100,100), live)
	assert(grid.query(Vector2.ZERO, 10, 0) == PackedInt32Array([0, 2]))
	grid.move(1, Vector2.ZERO)
	assert(grid.query(Vector2.ZERO, 10, 0) == PackedInt32Array([0, 1, 2]))
	print("Spatial workspace tests passed")
	quit(0)

func _plain(at: Vector2, radius: float, positions: PackedVector2Array, radii: PackedFloat64Array) -> Vector2:
	for i in positions.size():
		var reach := radius + radii[i]
		var offset := at - positions[i]
		var distance_squared := offset.length_squared()
		if distance_squared >= reach * reach: continue
		var normal := Vector2.RIGHT if distance_squared == 0.0 else offset / sqrt(distance_squared)
		at = positions[i] + normal * reach
	return at
