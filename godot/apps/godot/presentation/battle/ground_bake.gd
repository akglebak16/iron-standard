extends Node2D
## Settled marks and corpses painted once into a texture the size of the field, like the browser paints them into
## the ground canvas (B.gg). Only new items are drawn each time; the texture keeps the rest.
var last_paint_us := 0
var last_paint_frame := -1
var _viewport: SubViewport
var _painter: Node2D
var _sprite: Sprite2D
var _queue: Array[Callable] = []

func configure(arena: Vector2) -> void:
	show_behind_parent = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(ceili(arena.x), ceili(arena.y))
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_painter = Node2D.new()
	_painter.draw.connect(_paint)
	_viewport.add_child(_painter)
	add_child(_viewport)
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = _viewport.get_texture()
	_sprite.show_behind_parent = true
	add_child(_sprite)

## fn(canvas: CanvasItem) is called once, on the next render of the bake.
func paint(fn: Callable) -> void:
	if _viewport == null:
		return
	_queue.append(fn)
	if _queue.size() == 1:
		_painter.queue_redraw()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

## Wipes the texture; the caller paints everything that should stay.
func clear() -> void:
	if _viewport == null:
		return
	_queue.clear()
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func pending() -> int:
	return _queue.size()

func _paint() -> void:
	var started := Time.get_ticks_usec()
	last_paint_frame = Engine.get_process_frames()
	for fn in _queue:
		fn.call(_painter)
	_queue.clear()
	last_paint_us = Time.get_ticks_usec() - started
	# After the first (clearing) render keep the pixels: later renders only add.
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
