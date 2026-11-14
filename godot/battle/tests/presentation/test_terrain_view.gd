extends SceneTree
const TerrainView = preload("res://battle/presentation/terrain/terrain_view.gd")
const WallView = preload("res://battle/presentation/terrain/wall_view.gd")
const SiegeWall = preload("res://battle/model/siege_wall.gd")
const Config = preload("res://battle/config.gd")
const TEST_SEED := 4017

func _initialize() -> void:
	_check_biomes()
	_check_openings()
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

func _ground(biome: String, seed_value: int = TEST_SEED) -> ShaderMaterial:
	var terrain := TerrainView.new()
	terrain.configure(Config.ARENA_SIZE, [], seed_value, biome)
	assert(terrain._size == Config.ARENA_SIZE and terrain.get_child_count() == 0)
	var ground: ShaderMaterial = terrain.material
	terrain.free()
	return ground
