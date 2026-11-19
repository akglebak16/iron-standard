extends CanvasLayer
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
## The meeting window: who it is, how strong they are and what to do (openEncounter in src/06_ui.js).
signal chosen(action: String)

const PANEL_WIDTH := 560.0
const FIGHT_WIDTH := 720.0
const FIGHT_LINES := 5 # parties listed per side, the rest are counted
const WARN := Color("#d98a6a")
var _box: PanelContainer
var _title: Label
var _sub: Label
var _power: Label
var _rows: VBoxContainer
var _buttons: HFlowContainer

func _ready() -> void:
	layer = 8
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.45)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = PanelContainer.new()
	_box.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := GameSkin.box("plank", 16)
	_box.add_theme_stylebox_override("panel", style)
	center.add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_box.add_child(col)
	_title = Label.new()
	GameSkin.title(_title, 30)
	col.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_color_override("font_color", Color("#b8a880"))
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(420, 0)
	col.add_child(_sub)
	_power = Label.new()
	col.add_child(_power)
	_rows = VBoxContainer.new()
	col.add_child(_rows)
	_buttons = HFlowContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.alignment = FlowContainer.ALIGNMENT_END
	col.add_child(_buttons)

## troops: [{name, n}] sorted by the caller; actions: [{id, text, primary}].
func open(title: String, sub: String, power: Array, troops: Array, actions: Array) -> void:
	_frame(title, sub, power, PANEL_WIDTH)
	for t in troops:
		_rows.add_child(_line("%s  ×%d" % [t.name, t.n], Color("#d8cba8")))
	_actions(actions)

## A fight between map parties, one column per side:
## sides: [{fac, label, men, parties: [{name, n}], power: [text, color] if the player helps it, note}].
func open_fight(title: String, sub: String, sides: Array, actions: Array) -> void:
	_frame(title, sub, ["", Color.WHITE], FIGHT_WIDTH)
	var body := HBoxContainer.new()
	body.name = "FightSides"
	body.add_theme_constant_override("separation", 14)
	for i in sides.size():
		if i > 0:
			var versus := Label.new()
			versus.text = "против"
			versus.add_theme_font_override("font", GameSkin.DISPLAY)
			versus.add_theme_color_override("font_color", GameSkin.MUTED)
			versus.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			versus.custom_minimum_size = Vector2(0, 44)
			versus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			body.add_child(versus)
		body.add_child(_side_card(sides[i]))
	_rows.add_child(body)
	_actions(actions)

func _side_card(side: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0, 0, 0, 0.22)
	inner.border_color = Color(GameSkin.BRASS, 0.35)
	inner.set_border_width_all(1)
	inner.set_corner_radius_all(4)
	inner.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", inner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var crest := TextureRect.new()
	crest.texture = OriginalArt.crest(String(side.fac))
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.custom_minimum_size = Vector2(40, 44)
	head.add_child(crest)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := _line(String(side.label), GameSkin.BRASS)
	label.add_theme_font_override("font", GameSkin.BODY_BOLD)
	label.add_theme_font_size_override("font_size", 19)
	names.add_child(label)
	names.add_child(_line("%d бойцов" % int(side.men), GameSkin.MUTED))
	head.add_child(names)
	col.add_child(head)
	var parties: Array = side.parties
	for i in mini(parties.size(), FIGHT_LINES):
		col.add_child(_line("%s  ×%d" % [parties[i].name, parties[i].n], Color("#d8cba8")))
	if parties.size() > FIGHT_LINES:
		col.add_child(_line("и ещё отрядов: %d" % (parties.size() - FIGHT_LINES), GameSkin.MUTED))
	var power: Array = side.get("power", [])
	if not power.is_empty():
		var odds := _line("С тобой: %s" % String(power[0]).to_lower(), power[1])
		odds.add_theme_font_override("font", GameSkin.BODY_BOLD)
		col.add_child(odds)
	if not String(side.get("note", "")).is_empty():
		col.add_child(_line(String(side.note), WARN))
	return card

func _frame(title: String, sub: String, power: Array, width: float) -> void:
	_box.custom_minimum_size = Vector2(width, 0)
	_box.reset_size()
	_title.text = title
	_sub.text = sub
	_sub.visible = not sub.is_empty()
	_power.text = power[0]
	_power.visible = not String(power[0]).is_empty()
	_power.add_theme_color_override("font_color", power[1])
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()

func _line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l

func _actions(actions: Array) -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	for a in actions:
		var b := Button.new()
		b.text = a.text
		b.focus_mode = Control.FOCUS_NONE
		if a.get("primary", false):
			GameSkin.primary(b)
		b.pressed.connect(func(): close(); chosen.emit(a.id))
		_buttons.add_child(b)
	visible = true

func close() -> void:
	visible = false
