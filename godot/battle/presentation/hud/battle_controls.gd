extends PanelContainer

const GameSkin = preload("res://ui/game_theme.gd")
const OriginalArt = preload("res://ui/original_art.gd")
const Config = preload("res://battle/config.gd")
const Demo = preload("res://battle/presentation/demo_config.gd")
const Session = preload("res://battle/application/session.gd")
const ORDERS := [
	[Config.ORDER_HOLD, "Держать [Q]"], [Config.ORDER_FOLLOW, "За мной [E]"],
	[Config.ORDER_CHARGE, "Атака [R]"], [Config.ORDER_RETREAT, "Отход [F]"],
]
const SLOTS := [Session.WEAPON_SLOT_MELEE, Session.WEAPON_SLOT_RANGED]
const SLOT_EMPTY := "Нет дальнего оружия"
const HERO_FALLBACK_NAME := "Герой"
const HERO_NAME := "%s · %d / %d ОЗ"
const DEFENSE_TEXT := "Броня %.1f · Блок %d%% · Мораль %s"
const TIMER_TEXT := "%d:%02d"
const GROUP_TEXT := "%s %d"
const PAUSE_TEXT := "Пауза [P]"
const RESUME_TEXT := "Продолжить [P]"
const SPEED_TEXT := "×%s [T]"
const RETREAT_TEXT := "Отступить"
const RETREAT_TOOLTIP := "Завершить встречу отступлением"
const MORALE_LABELS := ["Паникует", "Колеблется", "Держится", "Твёрдый"]
const MORALE_THRESHOLDS := [0.3, 0.5, 0.75]
const SECONDS_PER_MINUTE := 60
const BAR_HEIGHT := 25.0
const HEALTH_COLOR := Color("#a82418")
const STAMINA_COLOR := Color("#d17a12")
const BAR_BACKGROUND := Color("#252621")
const PANEL_BACKGROUND := Color("#24251dee")
const PANEL_BORDER := Color("#655b40")
const PANEL_PADDING := 8.0

signal group_selected(group: int)
signal order_selected(order: String)
signal weapon_selected(slot: String)
signal pause_pressed
signal speed_pressed
signal retreat_pressed

var _counter := Label.new()
var _clock := Label.new()
var _health_text := Label.new()
var _stamina_text := Label.new()
var _heading := Label.new()
var _defense := Label.new()
var _weapons := HBoxContainer.new()
var _health := ProgressBar.new()
var _stamina := ProgressBar.new()
var _pause := Button.new()
var _speed := Button.new()
var _retreat := Button.new()
var _slot_buttons: Dictionary = {}
var _group_buttons: Array[Button] = []
var _order_buttons: Array[Button] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var layout := Control.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)
	var hero := PanelContainer.new()
	hero.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hero.offset_left = 8
	hero.offset_right = minf(388, get_viewport().get_visible_rect().size.x * 0.29)
	hero.offset_top = -210
	hero.offset_bottom = -8
	hero.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hero.add_theme_stylebox_override("panel", GameSkin.box("plank", 12))
	layout.add_child(hero)
	var content := VBoxContainer.new()
	hero.add_child(content)
	GameSkin.title(_heading, 26)
	_heading.clip_text = true
	content.add_child(_heading)
	var bars := VBoxContainer.new()
	content.add_child(bars)
	_add_bar(bars, _health, HEALTH_COLOR)
	_add_bar(bars, _stamina, STAMINA_COLOR)
	_bar_label(_health, _health_text)
	_bar_label(_stamina, _stamina_text)
	_defense.add_theme_font_size_override("font_size", 14)
	_defense.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_defense)
	_build_weapons(content)
	var commands := VBoxContainer.new()
	commands.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	commands.grow_horizontal = Control.GROW_DIRECTION_BOTH
	commands.grow_vertical = Control.GROW_DIRECTION_BEGIN
	commands.offset_left = -190
	commands.offset_right = 190
	commands.offset_top = -152
	commands.offset_bottom = -8
	commands.add_theme_constant_override("separation", 6)
	layout.add_child(commands)
	_build_orders(commands)
	var playback := VBoxContainer.new()
	playback.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	playback.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	playback.offset_right = -8
	playback.offset_top = 8
	layout.add_child(playback)
	_build_playback_controls(playback)
	var score := PanelContainer.new()
	score.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	score.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score.offset_left = -180
	score.offset_right = 180
	score.offset_top = 6
	score.add_theme_stylebox_override("panel", GameSkin.box("plank", 8))
	layout.add_child(score)
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 18)
	score.add_child(score_row)
	for faction in ["player", "emp"]:
		var crest := TextureRect.new()
		crest.texture = OriginalArt.crest(faction)
		crest.custom_minimum_size = Vector2(40, 40)
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		score_row.add_child(crest)
		if faction == "player":
			GameSkin.title(_counter, 30)
			score_row.add_child(_counter)
			GameSkin.title(_clock, 19)
			score_row.add_child(_clock)

func _bar_label(bar: ProgressBar, label: Label) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)

func update_frame(frame: Dictionary, selection: int, paused: bool, speed: float, finished: bool) -> void:
	var hero: Dictionary = frame.hero_status
	var hero_name: String = hero.name if not hero.name.is_empty() else HERO_FALLBACK_NAME
	_counter.text = "%d ⚔ %d" % [frame.ally_strength, frame.enemy_strength]
	_clock.text = format_time(frame.elapsed_seconds)
	_health_text.text = "Здоровье %d / %d" % [maxi(0, roundi(hero.hp)), roundi(hero.max_hp)]
	_stamina_text.text = "Выносливость %d / %d" % [roundi(frame.stamina), Config.HERO_MAX_STAMINA]
	_heading.text = HERO_NAME % [hero_name, roundi(maxf(hero.hp, 0.0)), roundi(hero.max_hp)]
	_health.max_value = maxf(1.0, hero.max_hp)
	_health.value = hero.hp
	_stamina.max_value = Config.HERO_MAX_STAMINA
	_stamina.value = frame.stamina
	_defense.text = DEFENSE_TEXT % [hero.armor, roundi(hero.block * 100.0), _morale_name(frame.army_share)]
	_weapons.visible = not hero.weapon_names.is_empty()
	for slot in SLOTS:
		var name: String = hero.weapon_names.get(slot, "")
		var button: Button = _slot_buttons[slot]
		button.text = name if not name.is_empty() else SLOT_EMPTY
		button.disabled = frame.hero_down or finished or name.is_empty()
		button.set_pressed_no_signal(hero.slot == slot)
	var total := 0
	for i in Config.GROUP_KINDS:
		total += frame.group_strength[i]
		_update_group(i, frame.group_strength[i], selection, finished)
	_update_group(Config.ALL_GROUPS, total, selection, finished)
	for button in _order_buttons:
		button.disabled = finished
	_pause.text = RESUME_TEXT if paused else PAUSE_TEXT
	_speed.text = SPEED_TEXT % (str(int(speed)) if speed == floorf(speed) else str(speed))
	_pause.disabled = finished
	_speed.disabled = finished
	_retreat.disabled = frame.decided

func _update_group(group: int, count: int, selection: int, finished: bool) -> void:
	var button := _group_buttons[group]
	button.text = GROUP_TEXT % [Demo.GROUP_NAMES[group], count]
	button.set_pressed_no_signal(group == selection)
	button.disabled = finished

func _build_weapons(content: VBoxContainer) -> void:
	content.add_child(_weapons)
	for slot in SLOTS:
		var button := _make_button(_weapons, "")
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(weapon_selected.emit.bind(slot))
		_slot_buttons[slot] = button

func _build_orders(content: VBoxContainer) -> void:
	var orders := HBoxContainer.new()
	orders.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(orders)
	for i in ORDERS.size():
		var order: Array = ORDERS[i]
		var button := _make_button(orders, ["Q", "E", "R", "F"][i])
		button.icon = GameSkin.icon(["hold", "follow", "charge", "back"][i])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 28)
		button.custom_minimum_size = Vector2(68, 58)
		button.tooltip_text = order[1]
		button.add_theme_stylebox_override("normal", GameSkin.box("order", 8))
		button.pressed.connect(order_selected.emit.bind(order[0]))
		_order_buttons.append(button)
	var group_panel := PanelContainer.new()
	group_panel.add_theme_stylebox_override("panel", GameSkin.box("plank", 5))
	content.add_child(group_panel)
	var groups := HBoxContainer.new()
	groups.alignment = BoxContainer.ALIGNMENT_CENTER
	group_panel.add_child(groups)
	for group in Config.GROUP_KINDS + 1:
		var button := _make_button(groups, "")
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(88, 72)
		button.add_theme_font_size_override("font_size", 13)
		var style := GameSkin.box("button", 4)
		style.content_margin_top = 42
		button.add_theme_stylebox_override("normal", style)
		var selected := GameSkin.box("primary", 4)
		selected.content_margin_top = 42
		button.add_theme_stylebox_override("pressed", selected)
		var portrait := OriginalArt.portrait_control(["n2", "n2a", "n3c", "n3"][group], "player", 44)
		portrait.position = Vector2(12, -8)
		portrait.size = Vector2(64, 48)
		button.add_child(portrait)
		button.pressed.connect(group_selected.emit.bind(group))
		_group_buttons.append(button)

func _build_playback_controls(content: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	content.add_child(row)
	for button in [_pause, _speed, _retreat]:
		button.focus_mode = Control.FOCUS_NONE
		row.add_child(button)
	_pause.pressed.connect(pause_pressed.emit)
	_speed.pressed.connect(speed_pressed.emit)
	_retreat.text = RETREAT_TEXT
	_retreat.tooltip_text = RETREAT_TOOLTIP
	_retreat.pressed.connect(retreat_pressed.emit)

static func _make_button(parent: Container, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button

static func _add_bar(parent: Container, bar: ProgressBar, color: Color) -> void:
	bar.show_percentage = false
	bar.custom_minimum_size.y = BAR_HEIGHT
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var background := StyleBoxFlat.new()
	background.bg_color = BAR_BACKGROUND
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", background)
	parent.add_child(bar)

static func format_time(elapsed: float) -> String:
	var seconds := floori(elapsed)
	return TIMER_TEXT % [floori(float(seconds) / SECONDS_PER_MINUTE), seconds % SECONDS_PER_MINUTE]

static func _morale_name(share: float) -> String:
	for i in MORALE_THRESHOLDS.size():
		if share <= MORALE_THRESHOLDS[i]:
			return MORALE_LABELS[i]
	return MORALE_LABELS.back()
