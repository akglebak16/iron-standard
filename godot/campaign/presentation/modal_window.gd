extends CanvasLayer
## Base of the world windows: dimmed backdrop, titled panel, tab row, scrolling body and a close button (openModal in src/06_ui.js).
signal closed

const WIDTH := 560.0
const HEIGHT := 520.0
var title_label: Label
var sub_label: Label
var tabs_row: HBoxContainer
var body: VBoxContainer
var _tab_buttons := {}
var current_tab := ""

func _ready() -> void:
	layer = 9
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.04, 0.97)
	style.border_color = Color("#8a6a30")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("#f4e2b0"))
	col.add_child(title_label)
	sub_label = Label.new()
	sub_label.add_theme_color_override("font_color", Color("#b8a880"))
	col.add_child(sub_label)
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 6)
	col.add_child(tabs_row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	var close := Button.new()
	close.text = "Закрыть"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_window)
	col.add_child(close)

func set_tabs(tabs: Array, active: String) -> void:
	for c in tabs_row.get_children():
		c.queue_free()
	_tab_buttons.clear()
	current_tab = active
	for t in tabs:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = t[0] == active
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): current_tab = t[0]; render())
		tabs_row.add_child(b)

func clear_body() -> void:
	for c in body.get_children():
		c.queue_free()

func note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 60.0, 0)
	l.add_theme_color_override("font_color", Color("#b8a880"))
	body.add_child(l)

func heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color("#f4e2b0"))
	body.add_child(l)

## A row: left text (grows), then buttons [{text, disabled, call}].
func row(text: String, detail: String, buttons: Array = []) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = text if detail.is_empty() else text + "\n" + detail
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("#e6d9b5"))
	h.add_child(l)
	for def in buttons:
		var b := Button.new()
		b.text = def.text
		b.disabled = def.get("disabled", false)
		b.focus_mode = Control.FOCUS_NONE
		var action: Callable = def.call
		b.pressed.connect(func(): action.call(); render())
		h.add_child(b)
	body.add_child(h)

## Subclasses draw their current tab here.
func render() -> void:
	pass

func open_window() -> void:
	visible = true
	render()

func close_window() -> void:
	visible = false
	closed.emit()
