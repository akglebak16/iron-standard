extends Control
## Native title / renderCreate / renderQuick from src/06_ui.js and src/07_main.js.
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const SaveStore = preload("res://app/save_store.gd")
const GameOptions = preload("res://app/game_options.gd")
const Preferences = preload("res://app/presentation_preferences.gd")
const GameSkin = preload("res://ui/game_theme.gd")
const Art = preload("res://ui/original_art.gd")
const Modal = preload("res://campaign/presentation/modal_window.gd")
const CULTURES := ["nord", "emp", "khan", "kin", "dom", "pact", "emi"]
signal campaign_requested

var _factions := FactionCatalog.new()
var _name: LineEdit
var _picked := "emp"
var _buttons := {}
var _dialog: CanvasLayer
var _menu: VBoxContainer
var _background: Node2D
var _preferences := Preferences.new()

func _ready() -> void:
	if not (_factions.load_data()):
		push_error("Required content failed to load: app/main_menu.gd")
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if DisplayServer.get_name() != "headless":
		_background = preload("res://app/main.tscn").instantiate()
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
	shade_material.shader = preload("res://ui/menu_shade.gdshader")
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
	_dialog.visible = true
	return _dialog

func _create() -> void:
	var d = _new_dialog("Создай героя", "Ты командир наёмного отряда без земли и титула")
	d.heading("Имя")
	_name = LineEdit.new()
	_name.placeholder_text = "Имя героя"
	_name.text = GameOptions.hero_name
	_name.max_length = 18
	d.body.add_child(_name)
	d.heading("Откуда ты родом")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	d.body.add_child(grid)
	_buttons.clear()
	for id in CULTURES:
		var b := _button(grid, _factions.get_faction(id).name, func(): _pick(id))
		b.icon = Art.crest(id)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 44)
		b.custom_minimum_size = Vector2(196, 78)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.toggle_mode = true
		b.button_pressed = id == _picked
		_buttons[id] = b
	d.note("Родная культура определяет стартовый отряд и место начала пути.")
	_button(d.body, "В путь", _start, true)

func _quick() -> void:
	var d = _new_dialog("Быстрый бой", "Полевое сражение · командуй отрядом и сражайся сам")
	d.note("Пехота, лучники и конница. Q — держать, E — за мной, R — атака, F — отход.")
	_button(d.body, "Начать сражение", func(): get_tree().change_scene_to_file("res://app/main.tscn"), true)
	_button(d.body, "Штурм крепости", func(): get_tree().change_scene_to_file("res://app/siege_demo.tscn"))

func _help() -> void:
	var d = _new_dialog("Как играть", "Железный Стяг")
	d.heading("На карте")
	d.note("Клик — идти, войти в поселение или догнать отряд. Колесо — масштаб. WASD или перетаскивание — камера. C — к герою. Пробел — пауза, 1/2/3 — скорость.")
	d.heading("В сражении")
	d.note("WASD — движение, мышь — направление, ЛКМ — удар, ПКМ — блок, Shift — бег, X — оружие. 1/2/3/4 — группа, Q/E/R/F — приказы. P — пауза, T — темп.")
	d.heading("Твой отряд")
	d.note("Нанимай и улучшай бойцов, покупай провизию, выполняй задания и ищи спутников в тавернах. F5 — сохранить игру, Esc — меню.")

func _pick(id: String) -> void:
	_picked = id
	for k in _buttons:
		_buttons[k].button_pressed = k == id

func _start() -> void:
	GameOptions.continue_game = false
	GameOptions.culture = _picked
	GameOptions.hero_name = _name.text.strip_edges() if not _name.text.strip_edges().is_empty() else "Безымянный"
	campaign_requested.emit()
