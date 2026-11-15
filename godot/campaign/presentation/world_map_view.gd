extends Node2D
## The world map as a node: ground texture and (in later slices) relief icons, rivers, roads, settlements.
const Generator = preload("res://campaign/world/terrain_generator.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const TerrainLayer = preload("res://campaign/presentation/terrain_layer.gd")
const ReliefLayer = preload("res://campaign/presentation/relief_layer.gd")
const RiverLayer = preload("res://campaign/presentation/river_layer.gd")
const VIGNETTE := preload("res://campaign/presentation/vignette.gdshader")

signal ready_to_show

var world: Generator
var terrain: Node2D

func build(seed_value: int) -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	world = Generator.new()
	world.generate(seed_value, data)
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.painted.connect(func(): ready_to_show.emit())
	terrain.build(world)
	var relief := ReliefLayer.new()
	add_child(relief)
	relief.build(world)
	var rivers := RiverLayer.new()
	add_child(rivers)
	rivers.build(world)
	var vignette := ColorRect.new()
	vignette.size = Vector2(Generator.WW, Generator.WH)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = VIGNETTE
	vignette.material = material
	add_child(vignette)
