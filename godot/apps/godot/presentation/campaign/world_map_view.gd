extends Node2D
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## The world map as a node: ground texture, fields, relief icons, roads, rivers, bridges, settlements.
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const TerrainLayer = preload("res://apps/godot/presentation/campaign/terrain_layer.gd")
const FarmLayer = preload("res://apps/godot/presentation/campaign/farm_layer.gd")
const ReliefLayer = preload("res://apps/godot/presentation/campaign/relief_layer.gd")
const RoadLayer = preload("res://apps/godot/presentation/campaign/road_layer.gd")
const RiverLayer = preload("res://apps/godot/presentation/campaign/river_layer.gd")
const SettlementLayer = preload("res://apps/godot/presentation/campaign/settlement_layer.gd")
const VIGNETTE := preload("res://apps/godot/presentation/campaign/vignette.gdshader")
const StaticCache = preload("res://apps/godot/presentation/campaign/static_map_cache.gd")

signal ready_to_show

var map: RefCounted
var terrain: Node2D
var _settlement_layer: Node2D
## Diagnostic reference only; the normal game always caches immutable artwork.
var cache_static_artwork := true
var _static_cache: Node2D

func build(seed_value: int) -> void:
	var data := EuropeData.new()
	if not (ContentLoader.populate(data)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/world_map_view.gd")
		return
	build_from(WorldMap.create(seed_value, data))

func build_from(world_map: RefCounted) -> void:
	map = world_map
	var artwork: Node2D = self
	if cache_static_artwork and DisplayServer.get_name() != "headless":
		_static_cache = StaticCache.new()
		add_child(_static_cache)
		_static_cache.configure(Vector2i(Generator.WW, Generator.WH))
		artwork = _static_cache.artwork
	terrain = TerrainLayer.new()
	artwork.add_child(terrain)
	terrain.painted.connect(_finish_static_artwork)
	terrain.build(map.terrain)
	var farms := FarmLayer.new()
	artwork.add_child(farms)
	farms.build(map.terrain, map.paths.road, map.settles)
	var relief := ReliefLayer.new()
	artwork.add_child(relief)
	relief.build(map.terrain)
	var roads := RoadLayer.new()
	artwork.add_child(roads)
	roads.build(map.terrain, map.roads, map.settles, map.paths)
	var rivers := RiverLayer.new()
	artwork.add_child(rivers)
	rivers.build(map.terrain)
	var vignette := ColorRect.new()
	vignette.size = Vector2(Generator.WW, Generator.WH)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE
	vignette.material = material
	artwork.add_child(vignette)
	var settlements := SettlementLayer.new()
	add_child(settlements)
	settlements.build(map.settles)
	_settlement_layer = settlements

func _finish_static_artwork() -> void:
	if _static_cache != null:
		await _static_cache.bake()
		terrain = null
	ready_to_show.emit()

## Owners changed (a capture): redraw banners and sprites.
func refresh_settlements() -> void:
	if _settlement_layer != null:
		_settlement_layer.queue_redraw()

func landmark_at(at: Vector2) -> int:
	return _settlement_layer.landmark_at(at) if _settlement_layer != null else -1

func has_landmark(id: int) -> bool:
	return _settlement_layer != null and _settlement_layer.has_landmark(id)
