extends Node2D
## The world map as a node: ground texture, fields, relief icons, roads, rivers, bridges, settlements.
const WorldMap = preload("res://campaign/world/world_map.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Generator = preload("res://campaign/world/terrain_generator.gd")
const TerrainLayer = preload("res://campaign/presentation/terrain_layer.gd")
const FarmLayer = preload("res://campaign/presentation/farm_layer.gd")
const ReliefLayer = preload("res://campaign/presentation/relief_layer.gd")
const RoadLayer = preload("res://campaign/presentation/road_layer.gd")
const RiverLayer = preload("res://campaign/presentation/river_layer.gd")
const SettlementLayer = preload("res://campaign/presentation/settlement_layer.gd")
const VIGNETTE := preload("res://campaign/presentation/vignette.gdshader")

signal ready_to_show

var map: RefCounted
var terrain: Node2D

func build(seed_value: int) -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	map = WorldMap.create(seed_value, data)
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.painted.connect(func(): ready_to_show.emit())
	terrain.build(map.terrain)
	var farms := FarmLayer.new()
	add_child(farms)
	farms.build(map.terrain, map.paths.road, map.settles)
	var relief := ReliefLayer.new()
	add_child(relief)
	relief.build(map.terrain)
	var roads := RoadLayer.new()
	add_child(roads)
	roads.build(map.terrain, map.roads, map.settles)
	var rivers := RiverLayer.new()
	add_child(rivers)
	rivers.build(map.terrain)
	var vignette := ColorRect.new()
	vignette.size = Vector2(Generator.WW, Generator.WH)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE
	vignette.material = material
	add_child(vignette)
	var settlements := SettlementLayer.new()
	add_child(settlements)
	settlements.build(map.settles)
