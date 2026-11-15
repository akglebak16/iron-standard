extends Node2D

const GroundShader = preload("res://battle/presentation/terrain/ground.gdshader")
const WallView = preload("res://battle/presentation/terrain/wall_view.gd")
const WallSceneView = preload("res://battle/presentation/terrain/wall_scene_view.gd")
const Config = preload("res://battle/config.gd")
const SNOW_BIOME := "snow"
const DRY_BIOMES := ["steppe", "arid"]
const PALETTES := {
	"grass": [Color("#5f6d2c"), Color("#6e7d34"), Color("#4d5a25"), Color("#6f6238"), Color("#8f8873"), Color("#3f4c1c"), Color("#e9e6d6")],
	"snow": [Color("#c3ccce"), Color("#dfe6e7"), Color("#a7b4b5"), Color("#8c8f80"), Color("#8a8d90"), Color("#7c8660"), Color("#f6f8f8")],
	"steppe": [Color("#978a48"), Color("#ab9d56"), Color("#82773f"), Color("#8a7446"), Color("#9a8f72"), Color("#6c6230"), Color("#e8d37a")],
	"arid": [Color("#bfa56a"), Color("#cfb97c"), Color("#aa9156"), Color("#a68a54"), Color("#a99c80"), Color("#8a7a3c"), Color("#e9dba8")],
}
const PALETTE_PARAMETERS := ["base_color", "light_color", "shade_color", "dirt_color", "stone_color", "tuft_color", "flower_color"]
const ROAD_AMPLITUDE := Vector2(160, 340)
const ROAD_CENTER_FRACTION := Vector2(0.3, 0.7)
const ROAD_SLOPE := 0.175
const SEED_OFFSET_RANGE := 512.0
const BACKGROUND_ORDER := -1

## Assemble the siege wall from scenes (editable in the editor); false draws it with code as before.
static var use_wall_scenes := true
static var use_original_ground := true
var _size := Vector2.ZERO

func configure(size: Vector2, walls: Array[Rect2], seed_value: int, biome: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var palette: Array = PALETTES.get(biome, PALETTES[Config.DEFAULT_BIOME])
	var ground_material := ShaderMaterial.new()
	ground_material.shader = GroundShader
	var ground_path := "res://battle/presentation/terrain/assets/ground_%s.png" % biome
	if use_original_ground and ResourceLoader.exists(ground_path):
		ground_material.set_shader_parameter("original_ground", load(ground_path))
		ground_material.set_shader_parameter("use_original_ground", true)
	ground_material.set_shader_parameter("arena_size", size)
	ground_material.set_shader_parameter("seed_offset", Vector2(rng.randf(), rng.randf()) * SEED_OFFSET_RANGE)
	ground_material.set_shader_parameter("road", Vector3(rng.randf_range(0.0, TAU),
		rng.randf_range(ROAD_AMPLITUDE.x, ROAD_AMPLITUDE.y),
		size.y * rng.randf_range(ROAD_CENTER_FRACTION.x, ROAD_CENTER_FRACTION.y)))
	ground_material.set_shader_parameter("road_slope", rng.randf_range(-ROAD_SLOPE, ROAD_SLOPE))
	ground_material.set_shader_parameter("snowy", biome == SNOW_BIOME)
	ground_material.set_shader_parameter("dry", biome in DRY_BIOMES)
	for i in PALETTE_PARAMETERS.size():
		ground_material.set_shader_parameter(PALETTE_PARAMETERS[i], palette[i])
	material = ground_material
	_size = size
	z_index = BACKGROUND_ORDER
	if not walls.is_empty():
		var wall: WallView = WallSceneView.new() if use_wall_scenes else WallView.new()
		wall.configure(walls, seed_value)
		add_child(wall)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _size), Color.WHITE)
