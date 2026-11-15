extends CanvasLayer
const GameSkin = preload("res://ui/game_theme.gd")
## The meeting window: who it is, how strong they are and what to do (openEncounter in src/06_ui.js).
signal chosen(action: String)

const PANEL_WIDTH := 560.0
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
	_title.text = title
	_sub.text = sub
	_power.text = power[0]
	_power.add_theme_color_override("font_color", power[1])
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for t in troops:
		var l := Label.new()
		l.text = "%s  ×%d" % [t.name, t.n]
		l.add_theme_color_override("font_color", Color("#d8cba8"))
		_rows.add_child(l)
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
