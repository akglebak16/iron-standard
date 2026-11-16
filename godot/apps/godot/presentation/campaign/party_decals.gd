extends SubViewport
## Shared marker artwork. Draw the existing shapes once per appearance at
## a resolution above the maximum campaign zoom.
const EmblemArt = preload("res://apps/godot/presentation/campaign/emblem_art.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")
const SCALE := 3
const COLUMNS := 8
const CELL := Vector2i(64, 64)
const CENTER := Vector2(32, 32)
const MARKER_SCALES := [0.7, 0.9, 1.15]
const HOSTILE := Color(0.85, 0.2, 0.15, 0.85)

var ready_to_draw := false
var _flags := {}

class Painter extends Node2D:
	var palettes: Array[Dictionary]

	func _draw() -> void:
		for index in MARKER_SCALES.size() * 2:
			var center := _origin(index)
			var marker_scale: float = MARKER_SCALES[index / 2]
			draw_colored_polygon(Brush.ellipse(center.x + 2, center.y + 3, 20 * marker_scale, 7 * marker_scale, 14), Color(0, 0, 0, 0.28))
			if index % 2 == 1:
				draw_arc(center + Vector2(0, 1), 22.0 * marker_scale, 0, TAU, 24, HOSTILE, 1.8, true)
		for faction in palettes.size():
			for variant in 2:
				var marker_scale: float = MARKER_SCALES[variant + 1]
				var center := _origin(6 + faction * 2 + variant)
				EmblemArt.draw_banner(self, center.x + 13 * marker_scale, center.y + 2, palettes[faction], 9.0 * marker_scale)

	static func _origin(index: int) -> Vector2:
		return Vector2(CELL * Vector2i(index % COLUMNS, index / COLUMNS)) + CENTER

func bake(palettes: Dictionary) -> void:
	disable_3d = true
	transparent_bg = true
	size = CELL * SCALE * Vector2i(COLUMNS, ceili((6.0 + palettes.size() * 2) / COLUMNS))
	canvas_transform = Transform2D(0.0, Vector2.ONE * SCALE, 0.0, Vector2.ZERO)
	var painter := Painter.new()
	for faction in palettes:
		_flags[faction] = painter.palettes.size()
		painter.palettes.append(palettes[faction])
	add_child(painter)
	render_target_update_mode = UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	ready_to_draw = true
	painter.queue_free()

func draw_base(canvas: CanvasItem, at: Vector2, variant: int, hostile: bool) -> void:
	_draw_cell(canvas, at, variant * 2 + int(hostile))

func draw_flag(canvas: CanvasItem, at: Vector2, variant: int, faction: String) -> void:
	_draw_cell(canvas, at, 6 + int(_flags.get(faction, _flags["bandit"])) * 2 + variant - 1)

func _draw_cell(canvas: CanvasItem, at: Vector2, index: int) -> void:
	var source := Rect2(Vector2(CELL * SCALE * Vector2i(index % COLUMNS, index / COLUMNS)), Vector2(CELL * SCALE))
	# The view shader converts viewport pixels back to straight alpha. Plain
	# portraits are drawn with alpha 1 and are unaffected by this marker.
	canvas.draw_texture_rect_region(get_texture(), Rect2(at - CENTER, Vector2(CELL)), source, Color(1, 1, 1, 0.5))
