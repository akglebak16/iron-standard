extends Control
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Start screen: hero name, culture, new game (the menu and culture choice in src/06_ui.js and src/07_main.js).
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const GameOptions = preload("res://apps/godot/composition/game_options.gd")
const Preferences = preload("res://apps/godot/composition/presentation_preferences.gd")
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Modal = preload("res://apps/godot/presentation/campaign/modal_window.gd")
const CULTURES := ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]
const CULTURE_DESCRIPTIONS := {
	"nord":"Крепкая пехота, секиры и щиты. Охотники-лучники.",
	"emp":"Броня, дисциплина и арбалеты. Дорогие, но стойкие бойцы.",
	"khan":"Быстрые всадники и конные лучники. Ты начинаешь верхом.",
	"kin":"Рыцарская конница, длинные луки и крепкие сержанты. Сильны в прямой схватке.",
	"emi":"Лёгкая конница, лучники и мамлюки. Быстрые, ты начинаешь верхом.",
	"dom":"Стойкая лесная пехота, арбалеты и дружинная конница. Сильны в обороне и засадах.",
	"pact":"Тяжёлая конница гусар, ландскнехты и лучники. Мощный удар, дорогие бойцы.",
}
const QUICK_FACTIONS := [["nord","Нордмарк"],["emp","Империя"],["khan","Ханство"],["kin","Галлия"],["emi","Эмират"],["dom","Доминион"],["pact","Пакт"]]
signal campaign_requested
signal demo_requested(siege: bool)
signal quick_battle_requested(options: Dictionary)

var _factions := FactionCatalog.new()
var _name: LineEdit
var _picked := "emp"
var _buttons := {}
var _dialog: CanvasLayer
var _menu: VBoxContainer
var _background: Node2D
var _preferences := Preferences.new()
var _banner_buttons: Array[Button] = []
var _quick_options := {"me":"nord", "foe":"emp", "size":50}
var _quick_buttons := {}

class BannerSwatch extends Button:
	var colors: Dictionary
	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, 21, GameSkin.INK, true, -1, true)
		draw_circle(center, 18, Color(colors.c2), true, -1, true)
		draw_circle(center, 15, Color(colors.c1), true, -1, true)
		if button_pressed or has_focus(): draw_arc(center, 24.5, 0, TAU, 64, GameSkin.BRASS, 3, true)

func _ready() -> void:
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/composition/main_menu.gd")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if DisplayServer.get_name() != "headless":
		_background = preload("res://apps/godot/composition/main.tscn").instantiate()
		add_child(_background)
		var battle = _background.get_node("Battle")
		battle.attract_mode = true
		battle._session.issue_order("charge", Vector2(battle.get_battle_snapshot().enemy_center), 3)
		battle.get_node("Hud").hide()
		battle.set_process_unhandled_input(false)
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.58)
	var shade_material := ShaderMaterial.new()
	shade_material.shader = preload("res://apps/godot/visuals/menu_shade.gdshader")
	shade.material = shade_material
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)
	var title := Label.new()
	title.text = "Железный\nСтяг"
	GameSkin.title(title, 104)
	var title_font := FontVariation.new()
	title_font.base_font = GameSkin.DISPLAY
	title_font.spacing_glyph = 8
	title.add_theme_font_override("font", title_font)
	title.add_theme_constant_override("line_spacing", -44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "ВОЙНА · НАЁМНИКИ · СЛАВА"
	GameSkin.title(sub, 22)
	sub.add_theme_color_override("font_color", GameSkin.PARCH)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_menu = VBoxContainer.new()
	_menu.custom_minimum_size.x = 330
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.add_theme_constant_override("separation", 10)
	col.add_child(_menu)
	_build_menu()
	var platform := Label.new()
	platform.text = "Игра для компьютера · клавиатура и мышь"
	platform.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	platform.add_theme_color_override("font_color", GameSkin.MUTED)
	col.add_child(platform)
	get_viewport().size_changed.connect(func():
		if is_instance_valid(_dialog) and _dialog.visible: _fit_start_dialog.call_deferred(_dialog))

func _button(parent: Node, text: String, action: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	if primary:
		GameSkin.primary(b)
	parent.add_child(b)
	return b

func _build_menu() -> void:
	for child in _menu.get_children():
		_menu.remove_child(child)
		child.queue_free()
	_button(_menu, "Новая игра", _create, true)
	if SaveStore.exists():
		_button(_menu, "Продолжить", func(): GameOptions.continue_game = true; campaign_requested.emit())
	_button(_menu, "Быстрый бой", _quick)
	_button(_menu, "Как играть", _help)
	_button(_menu, "Звук: %s" % ("вкл" if _preferences.read().effects else "выкл"), func():
		var audio := _preferences.read()
		_preferences.save(not audio.effects, audio.music)
		if _background != null:
			_background.get_node("Battle")._set_audio_preferences(not audio.effects, audio.music)
		_build_menu())
	for b in _menu.get_children():
		b.custom_minimum_size.y = 50
		b.add_theme_font_size_override("font_size", 21)

func _new_dialog(title: String, subtitle: String) -> CanvasLayer:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = Modal.new()
	add_child(_dialog)
	_dialog.title_label.text = title
	_dialog.sub_label.text = subtitle
	_dialog._crest.hide()
	_dialog.close_button.hide()
	_dialog.tabs_row.hide()
	_dialog.sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog.sub_label.add_theme_font_override("font", GameSkin.css_font(GameSkin.BODY, 15, 18))
	_dialog._panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dialog._panel.add_theme_stylebox_override("panel", GameSkin.box("plank", 3))
	var outer: MarginContainer = _dialog._panel.get_parent()
	outer.add_theme_constant_override("margin_top", 12)
	outer.add_theme_constant_override("margin_bottom", 12)
	var column: VBoxContainer = _dialog._panel.get_child(0)
	column.add_theme_constant_override("separation", 0)
	var header: Control = column.get_child(0)
	header.get_child(1).add_theme_constant_override("separation", 0)
	column.remove_child(header)
	var header_panel := PanelContainer.new()
	header_panel.add_theme_stylebox_override("panel", _region_style("modal_header"))
	column.add_child(header_panel)
	column.move_child(header_panel, 0)
	header_panel.add_child(header)
	_dialog.body.add_theme_constant_override("separation", 0)
	_dialog.visible = true
	_fit_start_dialog.call_deferred(_dialog)
	return _dialog

func _fit_start_dialog(d: CanvasLayer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(d) or d != _dialog: return
	var narrow := get_viewport_rect().size.x <= 760
	d._panel.custom_minimum_size.x = minf(d.preferred_width, minf(get_viewport_rect().size.x - 24, get_viewport_rect().size.x * 0.96))
	var heading_size := 23 if narrow else 30
	d.title_label.add_theme_font_size_override("font_size", heading_size)
	d.title_label.add_theme_font_override("font", GameSkin.css_font(GameSkin.DISPLAY, heading_size, heading_size * 1.3, heading_size * 0.04))
	var padding := StyleBoxEmpty.new()
	padding.content_margin_left = 10 if narrow else 18
	padding.content_margin_right = 10 if narrow else 18
	padding.content_margin_top = 10 if narrow else 14
	padding.content_margin_bottom = 10 if narrow else 14
	d._scroll.add_theme_stylebox_override("panel", padding)
	await get_tree().process_frame
	if not is_instance_valid(d) or d != _dialog: return
	for button in _buttons.values():
		if is_instance_valid(button) and d.is_ancestor_of(button):
			button.custom_minimum_size.y = button.get_child(0).get_combined_minimum_size().y
	await get_tree().process_frame
	if not is_instance_valid(d) or d != _dialog: return
	var fixed_height: float = d._panel.get_combined_minimum_size().y - d._scroll.get_combined_minimum_size().y
	var available := maxf(80, minf(get_viewport_rect().size.y - 24, get_viewport_rect().size.y * 0.94) - fixed_height)
	d._scroll.custom_minimum_size.y = minf(d.body.get_combined_minimum_size().y + padding.get_minimum_size().y, available)

func _region_style(kind: String) -> StyleBoxTexture:
	var style := GameSkin.box(kind, 0)
	style.set_texture_margin_all(0)
	style.set_texture_margin(SIDE_BOTTOM if kind == "modal_header" else SIDE_TOP, 3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12 if kind == "modal_header" else 15
	style.content_margin_bottom = 15 if kind == "modal_header" else 12
	return style

func _start_note(d: CanvasLayer, text: String, top := 4) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_bottom", 10)
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", GameSkin.css_font(GameSkin.BODY, 15, 19.5))
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("#c9b98f"))
	margin.add_child(label)
	d.body.add_child(margin)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(_dialog) and _dialog.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_dialog.close_window()
		get_viewport().set_input_as_handled()

func _footer(d: CanvasLayer, actions: Array) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _region_style("modal_footer"))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	var parent: Node = d.close_button.get_parent()
	parent.add_child(panel)
	parent.move_child(panel, d.close_button.get_index())
	panel.add_child(row)
	_button(row, "Назад", d.close_window)
	for action in actions:
		var b := _button(row, action[0], action[1], action.size() > 2 and action[2])
		b.set_meta("primary", action.size() > 2 and action[2])
	for b: Button in row.get_children():
		b.add_theme_font_override("font", GameSkin.css_font(GameSkin.DISPLAY, 17, 17, 0.85))
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style := GameSkin.box("primary" if b.get_meta("primary", false) or state in ["pressed","hover_pressed"] else "button", 13)
			style.content_margin_left = 18
			style.content_margin_right = 18
			b.add_theme_stylebox_override(state, style)

func _create() -> void:
	var d = _new_dialog("Создай героя", "Ты командир наёмного отряда без земли и титула")
	_start_note(d, "Имя")
	_name = LineEdit.new()
	_name.placeholder_text = "Имя героя"
	_name.text = GameOptions.hero_name
	_name.max_length = 18
	d.body.add_child(_name)
	_start_note(d, "Цвета твоего стяга", 14)
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 10)
	swatches.add_theme_constant_override("v_separation", 10)
	d.body.add_child(swatches)
	_banner_buttons.clear()
	for index in Art.BANNERS.size():
		var b := BannerSwatch.new()
		b.colors = Art.BANNERS[index]
		b.custom_minimum_size = Vector2(42, 42)
		b.toggle_mode = true
		b.button_pressed = index == GameOptions.banner
		b.tooltip_text = Art.BANNERS[index].n
		b.accessibility_name = Art.BANNERS[index].n
		for state in ["normal","hover","pressed","hover_pressed","focus"]: b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.pressed.connect(_pick_banner.bind(index))
		swatches.add_child(b)
		_banner_buttons.append(b)
	_start_note(d, "Откуда ты родом", 14)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	d.body.add_child(grid)
	_buttons.clear()
	for id in CULTURES:
		var b := _button(grid, "", func(): _pick(id))
		b.custom_minimum_size = Vector2(190, 148)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_pressed = id == _picked
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("#b78a3222") if state in ["pressed", "hover_pressed"] else Color("#00000040")
			box.border_color = GameSkin.BRASS if state in ["pressed", "hover_pressed"] else Color("#00000088")
			box.set_border_width_all(3)
			box.set_corner_radius_all(3)
			b.add_theme_stylebox_override(state, box)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side, 15)
		b.add_child(margin)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(col)
		var title := Label.new()
		GameSkin.title(title, 19)
		title.add_theme_font_override("font", GameSkin.css_font(GameSkin.DISPLAY, 19, 24.7, 0.76))
		title.add_theme_constant_override("line_spacing", 0)
		title.text = _factions.get_faction(id).name
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(title)
		var detail := Label.new()
		detail.text = CULTURE_DESCRIPTIONS[id]
		detail.add_theme_font_size_override("font_size", 14)
		detail.add_theme_font_override("font", GameSkin.css_font(GameSkin.BODY, 14, 18.2))
		detail.add_theme_constant_override("line_spacing", 0)
		detail.add_theme_color_override("font_color", Color("#c9b98f"))
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(detail)
		_buttons[id] = b
	_footer(d, [["В путь", _start, true]])

func _quick() -> void:
	var d = _new_dialog("Быстрый бой", "Сразу на поле: ты ведёшь своего героя, остальные слушаются приказов")
	d.set_width(560)
	_quick_buttons.clear()
	_start_note(d, "Твоя армия")
	_quick_row(d, "me", QUICK_FACTIONS)
	_start_note(d, "Противник", 0)
	_quick_row(d, "foe", QUICK_FACTIONS + [["bandit","Разбойники"]])
	_start_note(d, "Размер армий", 0)
	_quick_row(d, "size", [[50,"Отряд (50)"],[100,"Войско (100)"],[200,"Великая битва (200)"],[1000,"Побоище (1000)"]])
	_footer(d, [["Штурм крепости", func(): demo_requested.emit(true)], ["В бой", func(): quick_battle_requested.emit(_quick_options.duplicate()), true]])

func _quick_row(d: CanvasLayer, kind: String, choices: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.add_child(flow)
	d.body.add_child(margin)
	_quick_buttons[kind] = {}
	for choice in choices:
		var value = choice[0]
		var b := _button(flow, choice[1], func(): _pick_quick(kind, value))
		b.toggle_mode = true
		b.button_pressed = _quick_options[kind] == value
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_font_override("font", GameSkin.css_font(GameSkin.DISPLAY, 14, 14, 0.7))
		for state in ["normal","hover","pressed","hover_pressed"]:
			var style := GameSkin.box("primary" if state in ["pressed","hover_pressed"] else "button", 9)
			style.content_margin_left = 12
			style.content_margin_right = 12
			b.add_theme_stylebox_override(state, style)
		_quick_buttons[kind][value] = b

func _pick_quick(kind: String, value: Variant) -> void:
	_quick_options[kind] = value
	for key in _quick_buttons[kind]: _quick_buttons[kind][key].set_pressed_no_signal(key == value)

func _pick_banner(index: int) -> void:
	GameOptions.banner = index
	Art.select_player_banner(index)
	for i in _banner_buttons.size():
		_banner_buttons[i].set_pressed_no_signal(i == index)
		_banner_buttons[i].queue_redraw()

func _help() -> void:
	var d = _new_dialog("Как играть", "Железный Стяг")
	d.heading("На карте")
	d.note("Клик — идти, войти в поселение или догнать отряд. Колесо — масштаб. WASD или перетаскивание — камера. C — к герою. Пробел — пауза, 1/2/3 — скорость.")
	d.heading("В сражении")
	d.note("WASD — движение, мышь — направление, ЛКМ — удар, ПКМ — блок, Shift — бег, X — оружие. 1/2/3/4 — группа, Q/E/R/F — приказы. P — пауза, T — темп.")
	d.heading("Твой отряд")
	d.note("Нанимай и улучшай бойцов, покупай провизию, выполняй задания и ищи спутников в тавернах. F5 — сохранить игру, Esc — меню.")
	_footer(d, [])

func _pick(id: String) -> void:
	_picked = id
	for k in _buttons:
		_buttons[k].button_pressed = k == id

func _start() -> void:
	GameOptions.continue_game = false
	GameOptions.culture = _picked
	GameOptions.hero_name = _name.text.strip_edges() if not _name.text.strip_edges().is_empty() else "Безымянный"
	campaign_requested.emit()
