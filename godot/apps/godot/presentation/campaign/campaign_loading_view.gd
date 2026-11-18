extends CanvasLayer
## The progress bar is indeterminate while a startup phase is running.
const Style = preload("res://apps/godot/visuals/game_theme.gd")
## Shown both for a new campaign and for a loaded save.
const ART: Texture2D = preload("res://apps/godot/presentation/campaign/assets/loading_art.png")
const PANEL_ROOM := 150.0

signal back_requested

var _message := Label.new()
var _progress := ProgressBar.new()
var _back := Button.new()

func _ready() -> void:
	layer = 10
	var shade := ColorRect.new()
	shade.color = Style.INK
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# Same art stretched and darkened behind, so wide screens have no empty bars.
	var backdrop := TextureRect.new()
	backdrop.texture = ART
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color(0.22, 0.2, 0.18)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var view := get_viewport().get_visible_rect().size
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)
	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var side := clampf(minf(view.y - PANEL_ROOM - 48.0, view.x - 32.0), 160.0, 900.0)
	art.custom_minimum_size = Vector2(side, side)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(art)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(420.0, view.x - 32.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", Style.box("plank", 16.0))
	layout.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	_progress.custom_minimum_size.y = 9
	_progress.show_percentage = false
	_progress.indeterminate = true
	column.add_child(_progress)
	_back.text = "Вернуться в меню"
	_back.pressed.connect(back_requested.emit)
	_back.hide()
	column.add_child(_back)

func show_stage(message: String) -> void:
	_message.text = message

func show_error(message: String) -> void:
	show_stage(message)
	_progress.hide()
	_back.show()
	_back.grab_focus()
