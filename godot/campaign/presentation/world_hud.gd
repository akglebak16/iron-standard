extends CanvasLayer
## World HUD: date and speed controls, night tint, settlement tooltip, "near a settlement" label.
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const SettlementLayer = preload("res://campaign/presentation/settlement_layer.gd")

signal speed_changed(speed: int)
signal pause_toggled

var _date: Label
var _buttons: Dictionary = {}
var _night: ColorRect
var _tip: PanelContainer
var _tip_label: Label
var _near: Label
var _factions := FactionCatalog.new()

func _ready() -> void:
	layer = 5
	assert(_factions.load_data())
	_night = ColorRect.new()
	_night.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night.color = Color(8 / 255.0, 16 / 255.0, 48 / 255.0, 0.0)
	add_child(_night)
	var bar := PanelContainer.new()
	bar.position = Vector2(16, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.03, 0.82)
	style.border_color = Color("#6b5530")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", style)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_date = Label.new()
	_date.add_theme_color_override("font_color", Color("#f0e6c8"))
	row.add_child(_date)
	for def in [["pause", "⏸"], ["1", "1×"], ["2", "2×"], ["4", "4×"]]:
		var b := Button.new()
		b.text = def[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(40, 0)
		if def[0] == "pause":
			b.pressed.connect(func(): pause_toggled.emit())
		else:
			b.pressed.connect(func(): speed_changed.emit(int(def[0])))
		row.add_child(b)
		_buttons[def[0]] = b
	_near = Label.new()
	_near.position = Vector2(16, 64)
	_near.add_theme_color_override("font_color", Color("#ffe9a0"))
	_near.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.9))
	_near.add_theme_constant_override("outline_size", 4)
	add_child(_near)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_stylebox_override("panel", style)
	_tip_label = Label.new()
	_tip_label.add_theme_color_override("font_color", Color("#f0e6c8"))
	_tip.add_child(_tip_label)
	add_child(_tip)

func refresh(state: RefCounted, near_settlement: Dictionary) -> void:
	var clock = state.clock
	_date.text = "День %d   %02d:00%s" % [clock.day, clock.hour, "   (пауза)" if clock.paused else ""]
	_night.color.a = clock.night_level()
	for key in ["1", "2", "4"]:
		_buttons[key].button_pressed = false
		_buttons[key].toggle_mode = true
		_buttons[key].button_pressed = int(key) == clock.speed and not clock.paused
	_near.text = "Рядом: %s" % near_settlement.name if not near_settlement.is_empty() and near_settlement.kind != "camp" else ""

## Tooltip for the settlement under the mouse (worldTip in src/07_main.js); empty dict hides it.
func show_tip(settlement: Dictionary, screen_pos: Vector2) -> void:
	if settlement.is_empty():
		_tip.visible = false
		return
	var look := _factions.get_faction(settlement.fac)
	var kind_name: String = SettlementLayer.KIND_NAMES.get(settlement.kind, "")
	_tip_label.text = "%s\n%s · %s" % [settlement.name, kind_name, look.get("gen", "")]
	_tip.visible = true
	var view := _tip.get_viewport().get_visible_rect().size
	_tip.position = Vector2(minf(screen_pos.x + 18.0, view.x - 270.0), minf(screen_pos.y + 14.0, view.y - 90.0))
