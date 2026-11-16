extends CanvasLayer
## The progress bar is indeterminate while a startup phase is running.
const Style = preload("res://apps/godot/visuals/game_theme.gd")

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
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(420.0, get_viewport().get_visible_rect().size.x - 32.0)
	panel.add_theme_stylebox_override("panel", Style.box("plank", 24.0))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Железный Стяг"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.title(title)
	column.add_child(title)
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
