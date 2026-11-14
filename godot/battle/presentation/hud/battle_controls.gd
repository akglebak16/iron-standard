extends PanelContainer

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
const BAR_HEIGHT := 6.0
const HEALTH_COLOR := Color("#9d4846")
const STAMINA_COLOR := Color("#648941")
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
	_apply_panel_style()
	var content := VBoxContainer.new()
	add_child(content)
	content.add_child(_heading)
	var bars := HBoxContainer.new()
	content.add_child(bars)
	_add_bar(bars, _health, HEALTH_COLOR)
	_add_bar(bars, _stamina, STAMINA_COLOR)
	content.add_child(_defense)
	_build_weapons(content)
	_build_orders(content)
	_build_playback_controls(content)

func _apply_panel_style() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_BACKGROUND
	panel.border_color = PANEL_BORDER
	panel.set_border_width_all(1)
	for side in [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT]:
		panel.set_content_margin(side, PANEL_PADDING)
	add_theme_stylebox_override("panel", panel)

func update_frame(frame: Dictionary, selection: int, paused: bool, speed: float, finished: bool) -> void:
	var hero: Dictionary = frame.hero_status
	var hero_name: String = hero.name if not hero.name.is_empty() else HERO_FALLBACK_NAME
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
		button.toggle_mode = true
		button.pressed.connect(weapon_selected.emit.bind(slot))
		_slot_buttons[slot] = button

func _build_orders(content: VBoxContainer) -> void:
	var groups := HBoxContainer.new()
	content.add_child(groups)
	for group in Config.GROUP_KINDS + 1:
		var button := _make_button(groups, "")
		button.toggle_mode = true
		button.pressed.connect(group_selected.emit.bind(group))
		_group_buttons.append(button)
	var orders := HBoxContainer.new()
	content.add_child(orders)
	for order in ORDERS:
		var button := _make_button(orders, order[1])
		button.pressed.connect(order_selected.emit.bind(order[0]))
		_order_buttons.append(button)

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
