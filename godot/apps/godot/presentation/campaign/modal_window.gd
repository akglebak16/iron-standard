extends CanvasLayer
## Base of the world windows: dimmed backdrop, titled panel, tab row, scrolling body and a close button (openModal in src/06_ui.js).
signal closed

const GameSkin = preload("res://ui/game_theme.gd")
const OriginalArt = preload("res://ui/original_art.gd")
const WIDTH := 900.0
const HEIGHT := 620.0
var title_label: Label
var sub_label: Label
var tabs_row: HFlowContainer
var body: VBoxContainer
var _tab_buttons := {}
var current_tab := ""
var _panel: PanelContainer
var _crest: TextureRect
var _scroll: ScrollContainer
var _body_tab := ""
var preferred_width := WIDTH
var close_button: Button

func _ready() -> void:
	layer = 9
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.5)
	add_child(dim)
	var center := MarginContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("margin_top", 48)
	center.add_theme_constant_override("margin_bottom", 18)
	center.add_theme_constant_override("margin_left", 12)
	center.add_theme_constant_override("margin_right", 12)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	_panel = panel
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", GameSkin.box("plank", 16))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	col.add_child(header)
	_crest = TextureRect.new()
	_crest.custom_minimum_size = Vector2(52, 52)
	_crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crest.texture = OriginalArt.crest("player")
	header.add_child(_crest)
	var headings := VBoxContainer.new()
	headings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(headings)
	title_label = Label.new()
	GameSkin.title(title_label)
	headings.add_child(title_label)
	sub_label = Label.new()
	sub_label.add_theme_font_size_override("font_size", 15)
	sub_label.add_theme_color_override("font_color", Color("#b8a880"))
	headings.add_child(sub_label)
	tabs_row = HFlowContainer.new()
	tabs_row.add_theme_constant_override("separation", 6)
	col.add_child(tabs_row)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	var close := Button.new()
	close_button = close
	close.text = "Закрыть"
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	GameSkin.primary(close)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_window)
	col.add_child(close)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	_panel.custom_minimum_size.x = minf(preferred_width, get_viewport().get_visible_rect().size.x - 24)

func set_width(width: float) -> void:
	preferred_width = width
	_fit()

func set_crest(faction: String) -> void:
	_crest.texture = OriginalArt.crest(faction)

func set_tabs(tabs: Array, active: String) -> void:
	for c in tabs_row.get_children():
		tabs_row.remove_child(c)
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
		_tab_buttons[t[0]] = b

func clear_body() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	if _body_tab != current_tab:
		_scroll.scroll_vertical = 0
		_body_tab = current_tab

func note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	l.add_theme_color_override("font_color", Color("#b8a880"))
	body.add_child(l)

func heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	GameSkin.title(l, 21)
	body.add_child(l)

## A row: left text (grows), then buttons [{text, disabled, call}].
func row(text: String, detail: String, buttons: Array = [], portrait := "") -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#00000026")
	style.border_color = Color("#150f0980")
	style.border_width_bottom = 1
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	card.add_child(h)
	h.add_theme_constant_override("separation", 6)
	if portrait != "":
		h.add_child(OriginalArt.portrait_control(portrait))
	var l := Label.new()
	l.text = text if detail.is_empty() else text + "\n" + detail
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color("#e6d9b5"))
	h.add_child(l)
	var actions := HFlowContainer.new()
	actions.custom_minimum_size.x = 180
	h.add_child(actions)
	for def in buttons:
		var b := Button.new()
		b.text = def.text
		b.disabled = def.get("disabled", false)
		b.focus_mode = Control.FOCUS_NONE
		var action: Callable = def.call
		b.pressed.connect(func(): action.call(); render())
		actions.add_child(b)
	body.add_child(card)

## Subclasses draw their current tab here.
func render() -> void:
	pass

func open_window() -> void:
	visible = true
	render()

func close_window() -> void:
	visible = false
	closed.emit()
