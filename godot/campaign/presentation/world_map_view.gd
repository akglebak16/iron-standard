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
var _settlement_layer: Node2D
var _decor: SubViewport

func build(seed_value: int) -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	build_from(WorldMap.create(seed_value, data))

func build_from(world_map: RefCounted) -> void:
	map = world_map
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.painted.connect(func(): ready_to_show.emit())
	terrain.build(map.terrain)
	# Fields, relief icons, roads and rivers never change, yet as live canvas items their thousands of polygons
	# were sent to the GPU one by one every frame (about 6 FPS on the map). They are drawn once into a texture.
	_decor = SubViewport.new()
	_decor.size = Vector2i(Generator.WW, Generator.WH)
	_decor.transparent_bg = true
	_decor.disable_3d = true
	_decor.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_decor)
	var farms := FarmLayer.new()
	_decor.add_child(farms)
	farms.build(map.terrain, map.paths.road, map.settles)
	var relief := ReliefLayer.new()
	_decor.add_child(relief)
	relief.build(map.terrain)
	var roads := RoadLayer.new()
	_decor.add_child(roads)
	roads.build(map.terrain, map.roads, map.settles)
	var rivers := RiverLayer.new()
	_decor.add_child(rivers)
	rivers.build(map.terrain)
	var decor_sprite := Sprite2D.new()
	decor_sprite.centered = false
	decor_sprite.texture = _decor.get_texture()
	decor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# A transparent viewport stores colour already multiplied by alpha.
	var premultiplied := CanvasItemMaterial.new()
	premultiplied.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	decor_sprite.material = premultiplied
	add_child(decor_sprite)
	_bake_decor()
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
	_settlement_layer = settlements

## The relief layer draws from its own icon sheet viewport, which may render after this one in the first frame,
## so the picture is taken again on the next frames (the ground does the same in terrain_layer.gd).
func _bake_decor() -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
		_decor.render_target_update_mode = SubViewport.UPDATE_ONCE

## Owners changed (a capture): redraw banners and sprites.
func refresh_settlements() -> void:
	if _settlement_layer != null:
		_settlement_layer.queue_redraw()
