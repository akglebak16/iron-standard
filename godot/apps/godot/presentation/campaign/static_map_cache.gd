extends Node2D
## Render immutable map artwork once. Settlements, parties and HUD stay outside.
## Two texels/world unit match the relief/settlement sheets and retain close zoom detail.
const TEXELS_PER_UNIT := 2
var viewport: SubViewport
var artwork: Node2D
var sprite: Sprite2D
var ready_to_show := false

func configure(world_size: Vector2i) -> void:
	viewport = SubViewport.new()
	viewport.size = world_size * TEXELS_PER_UNIT
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * TEXELS_PER_UNIT, 0.0, Vector2.ZERO)
	artwork = Node2D.new()
	viewport.add_child(artwork)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2.ONE / TEXELS_PER_UNIT
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.texture = viewport.get_texture()
	add_child(sprite)

func bake() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ready_to_show = true
	# The texture retains the rendered pixels; release commands and source viewports.
	artwork.queue_free()
	artwork = null
