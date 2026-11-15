extends Control
## Start screen: hero name, culture, new game (the menu and culture choice in src/06_ui.js and src/07_main.js).
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const SaveStore = preload("res://app/save_store.gd")
const GameOptions = preload("res://app/game_options.gd")
const CULTURES := ["nord", "emp", "khan", "kin", "dom", "pact", "emi"]
const WORLD_SCENE := "res://app/world_demo.tscn"

var _factions := FactionCatalog.new()
var _name: LineEdit
var _picked := "emp"
var _buttons := {}

func _ready() -> void:
	assert(_factions.load_data())
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#17120b")
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(460, 0)
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := Label.new()
	title.text = "ЖЕЛЕЗНЫЙ СТЯГ"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#f4e2b0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Наёмный отряд в средневековой Европе"
	sub.add_theme_color_override("font_color", Color("#b8a880"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_name = LineEdit.new()
	_name.placeholder_text = "Имя героя"
	_name.text = GameOptions.hero_name
	_name.max_length = 18
	col.add_child(_name)
	var label := Label.new()
	label.text = "Родная культура"
	label.add_theme_color_override("font_color", Color("#f4e2b0"))
	col.add_child(label)
	for id in CULTURES:
		var b := Button.new()
		b.text = _factions.get_faction(id).name
		b.toggle_mode = true
		b.button_pressed = id == _picked
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _pick(id))
		col.add_child(b)
		_buttons[id] = b
	if SaveStore.exists():
		var cont := Button.new()
		cont.text = "Продолжить сохранённую игру"
		cont.pressed.connect(func():
			GameOptions.continue_game = true
			get_tree().change_scene_to_file(WORLD_SCENE))
		col.add_child(cont)
	var start := Button.new()
	start.text = "Начать игру"
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(_start)
	col.add_child(start)

func _pick(id: String) -> void:
	_picked = id
	for k in _buttons:
		_buttons[k].button_pressed = k == id

func _start() -> void:
	GameOptions.continue_game = false
	GameOptions.culture = _picked
	GameOptions.hero_name = _name.text.strip_edges() if not _name.text.strip_edges().is_empty() else "Безымянный"
	get_tree().change_scene_to_file(WORLD_SCENE)
