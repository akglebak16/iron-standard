extends CanvasLayer
## Base of the world windows: dimmed backdrop, titled panel, tab row, scrolling body and a close button (openModal in src/06_ui.js).
signal closed

const UiSounds = preload("res://apps/godot/presentation/campaign/ui_sounds.gd")
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
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
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var tab_icons := {"troops":"men", "hero":"helm", "gear":"bag", "quests":"flag", "factions":"shield", "comps":"heart", "journal":"book", "recruit":"men", "goods":"sack", "market":"sword", "tavern":"ale", "oath":"shield", "hold":"flag"}
		if tab_icons.has(t[0]):
			b.icon = GameSkin.icon(tab_icons[t[0]])
			b.add_theme_constant_override("icon_max_width", 19)
		b.add_theme_font_size_override("font_size", 16)
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
	style.bg_color = Color("#20170fe6")
	style.border_color = Color("#695338")
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	var h := HBoxContainer.new()
	card.add_child(h)
	h.add_theme_constant_override("separation", 6)
	if portrait != "":
		h.add_child(OriginalArt.portrait_control(portrait))
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 4)
	h.add_child(text_col)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameSkin.title(l, 20)
	text_col.add_child(l)
	if not detail.is_empty():
		var description := Label.new()
		description.text = detail
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_color_override("font_color", GameSkin.MUTED)
		description.add_theme_font_size_override("font_size", 15)
		text_col.add_child(description)
	var actions := HFlowContainer.new()
	actions.custom_minimum_size.x = minf(420, preferred_width * 0.4) if not buttons.is_empty() else 0
	h.add_child(actions)
	for def in buttons:
		var b := Button.new()
		b.text = def.text
		b.disabled = def.get("disabled", false)
		b.tooltip_text = def.get("hint", "")
		b.focus_mode = Control.FOCUS_NONE
		var action: Callable = def.call
		var sound: String = def.get("sound", "")
		b.pressed.connect(func():
			action.call()
			if sound != "": UiSounds.play(self, sound)
			render())
		actions.add_child(b)
	body.add_child(card)

## The item card (itemDock): name in its tier colour, what it is, figures with ▲/▼ against the worn item,
## traits, armour piercing bars and the damage type note, then the action buttons.
func item_card(card: Dictionary, buttons: Array) -> void:
	var box := VBoxContainer.new()
	box.name = "ItemCard"
	box.add_theme_constant_override("separation", 3)
	body.add_child(box)
	var title := Label.new()
	title.text = card.title
	GameSkin.title(title, 19)
	title.add_theme_color_override("font_color", card.color)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = card.subtitle
	subtitle.add_theme_color_override("font_color", GameSkin.MUTED)
	box.add_child(subtitle)
	var grid := GridContainer.new()
	grid.name = "ItemStats"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	box.add_child(grid)
	for stat in card.stats:
		var label := Label.new()
		label.text = stat.label
		label.add_theme_color_override("font_color", GameSkin.MUTED)
		grid.add_child(label)
		var value := Label.new()
		value.text = stat.value
		grid.add_child(value)
		var change := Label.new()
		change.text = stat.delta.get("text", "")
		if not stat.delta.is_empty():
			change.add_theme_color_override("font_color", Color("#8fc24f") if stat.delta.trend > 0 else Color("#e0705a"))
		grid.add_child(change)
	if not card.traits.is_empty():
		var traits := Label.new()
		traits.name = "ItemTraits"
		traits.text = " · ".join(PackedStringArray(card.traits))
		traits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		traits.add_theme_color_override("font_color", GameSkin.BRASS)
		box.add_child(traits)
	for bar in card.pierce:
		var line := HBoxContainer.new()
		line.name = "PierceBar"
		box.add_child(line)
		var label := Label.new()
		label.text = "%s %s" % [bar.label, bar.value]
		label.custom_minimum_size.x = 170
		line.add_child(label)
		var meter := ProgressBar.new()
		meter.max_value = 1.0
		meter.step = 0.01
		meter.value = bar.fill
		meter.show_percentage = false
		meter.custom_minimum_size = Vector2(120, 8)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(meter)
	if card.note != "":
		var note_label := Label.new()
		note_label.text = card.note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_color_override("font_color", GameSkin.MUTED)
		box.add_child(note_label)
	if not buttons.is_empty():
		row("", "", buttons)

## Subclasses draw their current tab here.
func render() -> void:
	pass

func open_window() -> void:
	visible = true
	render()

func close_window() -> void:
	visible = false
	closed.emit()
