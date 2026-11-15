extends Node2D
## Ground of the world map. Two GPU passes render the whole continent once into a texture
## (see terrain_pass1/2.gdshader); afterwards the map is just a sprite.
const Generator = preload("res://campaign/world/terrain_generator.gd")
const PASS1 := preload("res://apps/godot/presentation/campaign/terrain_pass1.gdshader")
const PASS2 := preload("res://apps/godot/presentation/campaign/terrain_pass2.gdshader")

signal painted

## Texels per world unit step: 2 gives a 2600 x 1700 texture like the browser version.
var step_px := 2
var _pass1: SubViewport
var _pass2: SubViewport

func build(world: Generator) -> void:
	var size := Vector2i(Generator.WW / step_px, Generator.WH / step_px)
	var noise_tab := ImageTexture.create_from_image(world.noise_table_image())
	var fields := ImageTexture.create_from_image(world.field_image())
	var carve := ImageTexture.create_from_image(world.carve_image())
	_pass1 = _make_pass(size, PASS1, {"noise_tab": noise_tab, "fields": fields, "carve": carve, "step_px": float(step_px)})
	_pass2 = _make_pass(size, PASS2, {"noise_tab": noise_tab, "fields": fields, "carve": carve, "step_px": float(step_px), "size": size, "samples": _pass1.get_texture()})
	_pass2.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2.ONE * step_px
	sprite.texture = _pass2.get_texture()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	_finish()

func _make_pass(size: Vector2i, shader: Shader, params: Dictionary) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	rect.material = material
	vp.add_child(rect)
	add_child(vp)
	return vp

func _finish() -> void:
	await RenderingServer.frame_post_draw
	_pass2.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	painted.emit()

func image() -> Image:
	return _pass2.get_texture().get_image()
