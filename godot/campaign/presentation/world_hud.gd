extends CanvasLayer
## World HUD: date and speed controls, night tint, settlement tooltip, "near a settlement" label.
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const Economy = preload("res://campaign/economy/party_economy.gd")
const SettlementLayer = preload("res://campaign/presentation/settlement_layer.gd")

const GameSkin = preload("res://ui/game_theme.gd")

signal speed_changed(speed: int)
signal pause_toggled
signal panel_requested(tab: String)

var _date: Label
var _buttons: Dictionary = {}
var _night: ColorRect
var _tip: PanelContainer
var _tip_label: Label
var _near: Label
var _stats: Label
var _notice: Label
var _log: Label
var _gold: Label
var _food: Label
var _men: Label
var _factions := FactionCatalog.new()

func _ready() -> void:
	layer = 5
	if not (_factions.load_data()):
		push_error("Required content failed to load: campaign/presentation/world_hud.gd")
		return
	_night = ColorRect.new()
	_night.set_anchors_preset(Control.PRESET_FULL_RECT)
	_night.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_night.color = Color(8 / 255.0, 16 / 255.0, 48 / 255.0, 0.0)
	add_child(_night)
	var top := Control.new()
	top.set_anchors_preset(Control.PRESET_FULL_RECT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 8
	bar.add_theme_stylebox_override("panel", GameSkin.box("plank", 8))
	top.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_gold = _stat(row, "gold")
	_food = _stat(row, "food")
	_men = _stat(row, "men")
	_date = _stat(row, "hourglass")
	_stats = Label.new()
	_stats.hide()
	row.add_child(_stats)
	for def in [["pause", "Ⅱ"], ["1", "×1"], ["2", "×2"], ["4", "×4"]]:
		var b := Button.new()
		b.text = def[1]
		b.custom_minimum_size = Vector2(38, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.tooltip_text = "Пауза (пробел)" if def[0] == "pause" else "Скорость " + def[1]
		b.pressed.connect(func():
			if def[0] == "pause": pause_toggled.emit()
			else: speed_changed.emit(int(def[0])))
		row.add_child(b)
		_buttons[def[0]] = b
	var menu := VBoxContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.offset_right = -8
	menu.offset_top = 8
	menu.add_theme_constant_override("separation", 6)
	top.add_child(menu)
	for def in [["troops", "Отряд", "men", "P"], ["hero", "Герой", "helm", "H"], ["gear", "Обоз", "bag", "I"], ["journal", "Журнал", "book", "J"], ["menu", "Меню", "gear", "Esc"]]:
		var b := Button.new()
		b.text = "%s   %s" % [def[1], def[3]]
		b.icon = GameSkin.icon(def[2])
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 22)
		b.custom_minimum_size = Vector2(144, 36)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = def[1] + " (" + def[3] + ")"
		b.pressed.connect(func(): panel_requested.emit(def[0]))
		menu.add_child(b)
	var log_panel := PanelContainer.new()
	log_panel.position = Vector2(8, 8)
	log_panel.custom_minimum_size.x = 212
	log_panel.add_theme_stylebox_override("panel", GameSkin.box("parchment", 10))
	top.add_child(log_panel)
	_log = Label.new()
	_log.custom_minimum_size.x = 192
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.add_theme_color_override("font_color", Color("#2a1d10"))
	_log.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	_log.add_theme_font_size_override("font_size", 15)
	log_panel.add_child(_log)
	_near = Label.new()
	_near.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_near.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_near.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_near.offset_top = -48
	_near.offset_bottom = -14
	GameSkin.title(_near, 19)
	top.add_child(_near)
	_notice = Label.new()
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-220, 88)
	GameSkin.title(_notice, 20)
	top.add_child(_notice)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_stylebox_override("panel", GameSkin.box("plank", 9))
	_tip_label = Label.new()
	_tip.add_child(_tip_label)
	add_child(_tip)

func _stat(parent: Container, icon_name: String) -> Label:
	var group := HBoxContainer.new()
	parent.add_child(group)
	var image := TextureRect.new()
	image.texture = GameSkin.icon(icon_name)
	image.custom_minimum_size = Vector2(22, 22)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	group.add_child(image)
	var label := Label.new()
	GameSkin.title(label, 19)
	label.add_theme_color_override("font_color", GameSkin.PARCH)
	group.add_child(label)
	return label

func refresh(state: RefCounted, near_settlement: Dictionary) -> void:
	var clock = state.clock
	_date.text = "День %d · %02d:00%s" % [clock.day, clock.hour, "" if clock.paused else ""]
	_night.color.a = clock.night_level()
	_buttons.pause.button_pressed = clock.paused
	for key in ["1", "2", "4"]:
		_buttons[key].button_pressed = false
		_buttons[key].toggle_mode = true
		_buttons[key].button_pressed = int(key) == clock.speed and not clock.paused
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var portions: int = Economy.provisions(p)
	var men: int = Economy.troop_count(p.troops)
	_stats.text = "Золото %d   Порции %d (%d дн.)   Бойцов %d/%d" % [p.gold, portions, ceili(portions / maxf(1.0, ceilf(men / 6.0))), men, Economy.size_cap(p.hero, fx)]
	_gold.text = str(p.gold)
	_food.text = "%d · %d дн." % [portions, ceili(portions / maxf(1.0, ceilf(men / 6.0)))]
	_food.add_theme_color_override("font_color", Color("#ff8d79") if portions < 12 else GameSkin.PARCH)
	_men.text = "%d / %d" % [men, Economy.size_cap(p.hero, fx)]
	var lines := PackedStringArray()
	for i in range(maxi(0, state.journal.size() - 4), state.journal.size()):
		lines.append(String(state.journal[i].text))
	_log.text = "\n".join(lines) if not lines.is_empty() else "Твой путь начинается."
	_near.text = "Рядом: %s" % near_settlement.name if not near_settlement.is_empty() and near_settlement.kind != "camp" else ""

## Tooltip for the settlement under the mouse (worldTip in src/07_main.js); empty dict hides it.
func show_notice(text: String) -> void:
	_notice.text = text

func show_tip(settlement: Dictionary, screen_pos: Vector2, text := "") -> void:
	if settlement.is_empty() and text == "":
		_tip.visible = false
		return
	if text == "":
		var look := _factions.get_faction(settlement.fac)
		var kind_name: String = SettlementLayer.KIND_NAMES.get(settlement.kind, "")
		text = "%s\n%s · %s" % [settlement.name, kind_name, look.get("gen", "")]
	_tip_label.text = text
	_tip.visible = true
	var view := _tip.get_viewport().get_visible_rect().size
	_tip.position = Vector2(minf(screen_pos.x + 18.0, view.x - 270.0), minf(screen_pos.y + 14.0, view.y - 90.0))
