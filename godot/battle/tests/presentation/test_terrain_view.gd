extends SceneTree
const TerrainView = preload("res://apps/godot/presentation/battle/terrain/terrain_view.gd")
const WallView = preload("res://apps/godot/presentation/battle/terrain/wall_view.gd")
const WallSceneView = preload("res://apps/godot/presentation/battle/terrain/wall_scene_view.gd")
const SiegeWall = preload("res://battle/model/siege_wall.gd")
const VegetationView = preload("res://apps/godot/presentation/battle/terrain/vegetation_view.gd")
const Config = preload("res://battle/config.gd")
const TEST_SEED := 4017

func _initialize() -> void:
	_check_biomes()
	_check_openings()
	_check_scene_wall()
	_check_vegetation()
	print("Terrain view tests passed")
	quit(0)

func _check_biomes() -> void:
	var grass := _ground("grass")
	var snow := _ground("snow")
	var steppe := _ground("steppe")
	var arid := _ground("arid")
	var fallback := _ground("unknown")
	var alternate_seed := _ground("grass", TEST_SEED + 1)
	assert(grass.get_shader_parameter("road") == snow.get_shader_parameter("road"))
	assert(grass.get_shader_parameter("road") != alternate_seed.get_shader_parameter("road"))
	assert(grass.get_shader_parameter("base_color") == fallback.get_shader_parameter("base_color"))
	var colors := {}
	for ground in [grass, snow, steppe, arid]:
		colors[ground.get_shader_parameter("base_color")] = true
	assert(colors.size() == 4)
	assert(snow.get_shader_parameter("snowy") and not snow.get_shader_parameter("dry"))
	assert(steppe.get_shader_parameter("dry") and arid.get_shader_parameter("dry"))

func _check_openings() -> void:
	var model := SiegeWall.new(Config.ARENA_SIZE)
	var reversed := model.segments()
	reversed.reverse()
	var view := WallView.new()
	view.configure(reversed, TEST_SEED)
	assert(view._segments == model.segments())
	assert(view._openings.size() == 3)
	var wide_openings := 0
	for opening in view._openings:
		assert(opening.get_center().x == model.x)
		var gap := model.gap_at(opening.get_center().y)
		assert(gap == Vector2(opening.position.y, opening.end.y))
		if opening.size.y > WallView.GATE_MIN_WIDTH:
			wide_openings += 1
	assert(wide_openings == 1)
	var rubble := view._rubble.duplicate(true)
	assert(rubble.size() == view._openings.size() * WallView.RUBBLE_COUNT)
	view.configure(model.segments(), TEST_SEED)
	assert(view._rubble == rubble)
	assert(view._rubble.all(func(piece):
		return view._openings.any(func(gap): return piece.position.y > gap.position.y and piece.position.y < gap.end.y)))
	view.configure([], TEST_SEED)
	assert(view._openings.is_empty() and view._rubble.is_empty())
	view.free()

func _check_scene_wall() -> void:
	var model := SiegeWall.new(Config.ARENA_SIZE)
	var view := WallSceneView.new()
	view.configure(model.segments(), TEST_SEED)
	# 4 segments, 2 towers per opening, 2 gate leaves for the one wide opening.
	assert(view._segments.size() == 4 and view._openings.size() == 3)
	assert(view.get_child_count() == 4 + view._openings.size() * 2 + 2)
	var first := view.get_child(0)
	assert(first.position == view._segments[0].position)
	assert(first.get_node("Stone").size == view._segments[0].size)
	assert(first.get_node("Merlons").size.y == floorf(view._segments[0].size.y / 22.0) * 22.0)
	var rubble := view._rubble.duplicate(true)
	view.configure(model.segments(), TEST_SEED)
	assert(view.get_child_count() == 4 + view._openings.size() * 2 + 2 and view._rubble == rubble)
	view.configure([], TEST_SEED)
	assert(view.get_child_count() == 0)
	view.free()
	# The scene wall is the default; the code-drawn wall stays available for comparison.
	assert(TerrainView.use_wall_scenes)

func _ground(biome: String, seed_value: int = TEST_SEED) -> ShaderMaterial:
	var terrain := TerrainView.new()
	terrain.configure(Config.ARENA_SIZE, [], seed_value, biome)
	assert(terrain._size == Config.ARENA_SIZE and terrain.get_child_count() == 0)
	var ground: ShaderMaterial = terrain.material
	terrain.free()
	return ground

func _check_vegetation() -> void:
	var view := VegetationView.new()
	var layout: Array[Dictionary] = [
		{"position": Vector2(30, 90), "tree": true, "variant": 0},
		{"position": Vector2(30, 20), "tree": false, "variant": 0},
		{"position": Vector2(100, 120), "tree": true, "variant": 0},
	]
	view.configure(layout, "grass", TEST_SEED)
	assert(view.entries[0].position == layout[1].position)
	assert(view.entries[1].bounds.position == layout[0].position - VegetationView.TREE_ANCHOR)
	assert(view.entries[2].texture == view.entries[1].texture)
	assert(view.entries[0].texture != view.entries[1].texture)
	var grass: Image = view.entries[1].texture.get_image()
	assert(grass.get_used_rect().has_area())
	view.configure(layout, "snow", TEST_SEED)
	assert(view.entries.size() == layout.size())
	assert(view.entries[1].texture.get_image().get_data() != grass.get_data())
