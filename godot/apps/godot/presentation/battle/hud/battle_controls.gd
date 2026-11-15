extends PanelContainer
const AssetPaths = preload("res://apps/godot/visuals/asset_paths.gd")
## Native controls sized from style.css + polish.css, including responsive breakpoints.
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const Config = preload("res://core/battle/config.gd")
const Demo = preload("res://apps/godot/presentation/battle/demo_config.gd")
const Session = preload("res://core/battle/application/session.gd")
const ORDERS := [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT]
const ORDER_LABELS := ["Держать", "За мной", "В атаку", "Отойти"]
const ORDER_STATES := {"hold":"Держат", "follow":"За тобой", "charge":"В атаке", "back":"Отходят"}
const SLOTS := [Session.WEAPON_SLOT_MELEE, Session.WEAPON_SLOT_RANGED]
const MORALE_LABELS := ["Паникует", "Колеблется", "Держится", "Твёрдый"]
const MORALE_THRESHOLDS := [0.3, 0.5, 0.75]
const GROUP_NAMES := ["Пехота", "Стрелки", "Конница", "Все"]
signal group_selected(group: int)
signal order_selected(order: String)
signal weapon_selected(slot: String)
signal pause_pressed
signal speed_pressed
signal retreat_pressed
signal menu_pressed
var _layout := Control.new()
var _hero := Panel.new()
var _commands := Control.new()
var _orders_row := Control.new()
var _groups := Panel.new()
var _score := Panel.new()
var _playback := Control.new()
var _counter := Label.new()
var _enemy_counter := Label.new()
var _clock := Label.new()
var _heading := Label.new()
var _defense := Label.new()
var _command_state := Label.new()
var _health_text := Label.new()
var _stamina_text := Label.new()
var _armor_text := Label.new()
var _morale_text := Label.new()
var _weapons := Control.new()
var _health := ProgressBar.new()
var _stamina := ProgressBar.new()
var _armor := ProgressBar.new()
var _morale := ProgressBar.new()
var _pause := Button.new()
var _speed := Button.new()
var _retreat := Button.new()
var _menu := Button.new()
var _speed_label := Label.new()
var _slot_buttons: Dictionary = {}
var _group_buttons: Array[Button] = []
var _group_counts: Array[Label] = []
var _group_portraits: Array[TextureRect] = []
var _order_buttons: Array[Button] = []
var _crests: Array[TextureRect] = []
var _reserve_labels: Array[Label] = []
var _key := Label.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layout)
	for panel in [_hero, _groups, _score]: panel.add_theme_stylebox_override("panel", GameSkin.box("plank", 0))
	_layout.add_child(_hero)
	_label(_heading, _hero, 30, true)
	_heading.clip_text = true
	_label(_defense, _hero, 14)
	_defense.clip_text = true
	for item in [[_stamina, _stamina_text, "st"], [_morale, _morale_text, "mo"], [_armor, _armor_text, "ar"], [_health, _health_text, "hp"]]: _add_bar(item[0], item[1], item[2])
	_hero.add_child(_weapons)
	for slot in SLOTS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.clip_text = true
		button.toggle_mode = true
		button.add_theme_font_override("font", GameSkin.BODY_BOLD)
		button.add_theme_font_size_override("font_size", 13)
		button.icon = GameSkin.icon("sword" if slot == SLOTS[0] else "bow")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 18)
		button.add_theme_constant_override("h_separation", 6)
		for state in ["normal", "hover", "disabled", "pressed", "hover_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("#1a1510")
			box.border_color = GameSkin.BRASS if state in ["pressed", "hover_pressed"] else Color("#0d0905")
			box.set_border_width_all(2)
			box.content_margin_left = 8
			box.content_margin_right = 8
			button.add_theme_stylebox_override(state, box)
		button.pressed.connect(weapon_selected.emit.bind(slot))
		_weapons.add_child(button)
		_slot_buttons[slot] = button
	_label(_key, _weapons, 13)
	_key.text = "X"
	_key.add_theme_color_override("font_color", GameSkin.BRASS)
	_layout.add_child(_commands)
	_commands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(_command_state, _commands, 13)
	_command_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var command_box := StyleBoxFlat.new()
	command_box.bg_color = Color("#24190fea")
	command_box.border_color = Color("#ad873e")
	command_box.set_border_width_all(1)
	command_box.content_margin_left = 14
	command_box.content_margin_right = 14
	_command_state.add_theme_stylebox_override("normal", command_box)
	_commands.add_child(_orders_row)
	_commands.add_child(_groups)
	_build_orders()
	_build_groups()
	_layout.add_child(_playback)
	for i in 4:
		var button: Button = [_pause, _speed, _retreat, _menu][i]
		button.focus_mode = Control.FOCUS_NONE
		button.icon = GameSkin.icon(["pause", "hourglass", "retreat", "gear"][i], "item")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		for state in ["normal", "hover", "pressed", "disabled"]: button.add_theme_stylebox_override(state, GameSkin.box("square", 4))
		_playback.add_child(button)
	_pause.pressed.connect(pause_pressed.emit)
	_speed.pressed.connect(speed_pressed.emit)
	_retreat.pressed.connect(retreat_pressed.emit)
	_menu.pressed.connect(menu_pressed.emit)
	_pause.tooltip_text = "Пауза (P)"
	_speed.tooltip_text = "Скорость (T)"
	_retreat.tooltip_text = "Отступить"
	_menu.tooltip_text = "Меню (Esc)"
	_label(_speed_label, _speed, 11)
	_speed_label.add_theme_color_override("font_color", GameSkin.BRASS)
	_layout.add_child(_score)
	for faction in ["player", "emp"]:
		var crest := TextureRect.new()
		crest.texture = OriginalArt.crest(faction)
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_score.add_child(crest)
		_crests.append(crest)
		var reserve := Label.new()
		_label(reserve, _score, 13, true)
		_reserve_labels.append(reserve)
	_label(_counter, _score, 30, true)
	_label(_enemy_counter, _score, 30, true)
	_counter.add_theme_color_override("font_color", GameSkin.BRASS)
	_enemy_counter.add_theme_color_override("font_color", GameSkin.BRASS)
	var timer := TextureRect.new()
	timer.texture = load("res://apps/godot/visuals/assets/timer.png")
	timer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	timer.size = Vector2(62, 62)
	timer.position = Vector2(117, 8)
	_score.add_child(timer)
	_label(_clock, timer, 19, true)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout_controls)
	_layout_controls()

func _build_orders() -> void:
	for i in ORDERS.size():
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.tooltip_text = ORDER_LABELS[i] + " (" + ["Q", "E", "R", "F"][i] + ")"
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var style := GameSkin.box("order", 0)
			if state in ["pressed", "hover_pressed"]: style.modulate_color = Color(1.35, 1.3, 1.1)
			button.add_theme_stylebox_override(state, style)
		_orders_row.add_child(button)
		var icon := TextureRect.new()
		icon.texture = GameSkin.icon(["hold", "follow", "charge", "back"][i], "white")
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		var label := Label.new()
		_label(label, button, 12)
		label.text = ORDER_LABELS[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var key := Label.new()
		_label(key, button, 11)
		key.text = ["Q", "E", "R", "F"][i]
		key.add_theme_color_override("font_color", Color("#f1d27a"))
		button.pressed.connect(order_selected.emit.bind(ORDERS[i]))
		_order_buttons.append(button)

func _build_groups() -> void:
	for group in 4:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		for state in ["normal", "hover", "disabled", "pressed", "hover_pressed"]: button.add_theme_stylebox_override(state, GameSkin.box("group_on" if state in ["pressed", "hover_pressed"] else "group", 0))
		# Accessible name stays on the button; count and caption have separate original typography.
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "font_shadow_color"]: button.add_theme_color_override(state, Color.TRANSPARENT)
		button.add_theme_font_size_override("font_size", 1)
		_groups.add_child(button)
		var portrait := OriginalArt.portrait_control(["n2", "n2a", "n3c", "n3"][group], "player", 44)
		portrait.custom_minimum_size = Vector2.ZERO
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(portrait)
		_group_portraits.append(portrait)
		var count := Label.new()
		_label(count, button, 17, true)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_group_counts.append(count)
		var caption := Label.new()
		_label(caption, button, 13)
		caption.text = GROUP_NAMES[group]
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var key := Label.new()
		_label(key, button, 11)
		key.text = str(group + 1)
		key.add_theme_color_override("font_color", GameSkin.BRASS)
		button.pressed.connect(group_selected.emit.bind(group))
		_group_buttons.append(button)

static func layout_for(viewport: Vector2, ally := "26", enemy := "26") -> Dictionary:
	var small := viewport.x <= 1100
	var mobile := viewport.x <= 900
	var narrow := viewport.x <= 760
	var hero_width := minf(340, viewport.x * 0.29) if not mobile else minf(380, viewport.x * 0.44)
	var hero_height := 158.0 if small else 167.0
	if narrow:
		hero_width = viewport.x * 0.48
		hero_height = 138
	var score_width := 258.0
	if narrow: score_width = 216 + GameSkin.DISPLAY.get_string_size(ally, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + GameSkin.DISPLAY.get_string_size(enemy, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	else: score_width = 300
	var command_size := Vector2(290 if small else 354, (186 if mobile else 188) if small else 192)
	var center := viewport.x * 0.5 + (0 if mobile else 15)
	return {"hero":Rect2(Vector2(8, viewport.y - 8 - hero_height), Vector2(hero_width, hero_height)),
		"commands":Rect2(Vector2(center - command_size.x / 2, viewport.y - (155 if mobile else 8) - command_size.y), command_size),
		"score":Rect2(Vector2(viewport.x / 2 - score_width / 2, 6), Vector2(score_width, 58)),
		"playback":Rect2(Vector2(viewport.x - (202 if narrow else 234), 8), Vector2(194, 44) if narrow else Vector2(226, 52)),
		"order_size":Vector2(65, 62) if small else Vector2(78, 66), "group_width":68.0 if small else 84.0}

func _layout_controls() -> void:
	if not is_node_ready(): return
	var boxes := layout_for(size, _counter.text if not _counter.text.is_empty() else "26", _enemy_counter.text if not _enemy_counter.text.is_empty() else "26")
	_set_rect(_hero, boxes.hero)
	_set_rect(_commands, boxes.commands)
	_set_rect(_score, boxes.score)
	_set_rect(_playback, boxes.playback)
	var small := size.x <= 1100
	var narrow := size.x <= 760
	var inset := 11.0 if narrow else 15.0
	var padding_top := 8.0 if narrow else 11.0
	var name_height := 31.0 if small else 40.0
	_heading.add_theme_font_size_override("font_size", 23 if small else 30)
	var name_width := minf(GameSkin.DISPLAY.get_string_size(_heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 23 if small else 30).x, _hero.size.x * 0.5)
	_set_rect(_heading, Rect2(inset, padding_top, name_width, name_height))
	_set_rect(_defense, Rect2(inset + 10 + name_width, padding_top, maxf(1, _hero.size.x - name_width - inset * 2 - 10), name_height))
	_defense.add_theme_font_size_override("font_size", 12 if small else 14)
	var column := (_hero.size.x - inset * 2 - 10) / 2
	var top := padding_top + name_height + 8
	var bar_height := 19.0 if narrow else 25.0
	_set_rect(_stamina, Rect2(inset, top, column, bar_height))
	_set_rect(_morale, Rect2(inset + 10 + column, top, column, bar_height))
	_set_rect(_armor, Rect2(inset, top + bar_height + 6, column, bar_height))
	_set_rect(_health, Rect2(inset + 10 + column, top + bar_height + 6, column, bar_height))
	for label in [_stamina_text, _morale_text, _armor_text, _health_text]: label.add_theme_font_size_override("font_size", 13 if narrow else 16)
	_set_rect(_weapons, Rect2(inset, _hero.size.y - (38 if narrow else 43), _hero.size.x - inset * 2, 30))
	var weapon_width := (_weapons.size.x - 24) / 2
	for i in 2: _set_rect(_slot_buttons[SLOTS[i]], Rect2(i * (weapon_width + 6), 0, weapon_width, 30))
	_set_rect(_key, Rect2(_weapons.size.x - 12, 0, 12, 30))
	var state_height := 26.0 if size.x <= 900 else 28.0
	_command_state.add_theme_font_size_override("font_size", 12 if size.x <= 900 else 13)
	var state_width := minf(_commands.size.x, GameSkin.BODY_BOLD.get_string_size(_command_state.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12 if size.x <= 900 else 13).x + 30)
	_set_rect(_command_state, Rect2((_commands.size.x - state_width) / 2, 0, state_width, state_height))
	var order_size: Vector2 = boxes.order_size
	_set_rect(_orders_row, Rect2((_commands.size.x - order_size.x * 4 - 15) / 2, state_height + 6, order_size.x * 4 + 15, order_size.y))
	for i in 4:
		var button := _order_buttons[i]
		_set_rect(button, Rect2(Vector2(i * (order_size.x + 5), 0), order_size))
		_set_rect(button.get_child(0), Rect2((order_size.x - 25) / 2, 7, 25, 25))
		_set_rect(button.get_child(1), Rect2(2, 35, order_size.x - 4, 16))
		button.get_child(1).add_theme_font_size_override("font_size", 11 if small else 12)
		_set_rect(button.get_child(2), Rect2(order_size.x - 13, order_size.y - 15, 9, 14))
	_set_rect(_groups, Rect2(0, _commands.size.y - 86, _commands.size.x, 86))
	var group_width: float = boxes.group_width
	for i in 4:
		var button := _group_buttons[i]
		_set_rect(button, Rect2(9 + i * group_width, 7, group_width, 72))
		var h := 38.0 if small else 44.0
		var texture_size := _group_portraits[i].texture.get_size()
		var w := h * texture_size.x / texture_size.y
		_set_rect(_group_portraits[i], Rect2((group_width - w) / 2, -8 if small else -14, w, h))
		_set_rect(_group_counts[i], Rect2(0, 30, group_width, 23))
		_set_rect(button.get_child(2), Rect2(0, 52, group_width, 18))
		_set_rect(button.get_child(3), Rect2(4, 2, 9, 14))
	var square := 44.0 if narrow else 52.0
	for i in 4: _set_rect([_pause, _speed, _retreat, _menu][i], Rect2(i * (square + 6), 0, square, square))
	_set_rect(_speed_label, Rect2(square - 22, square - 17, 20, 15))
	_set_rect(_crests[0], Rect2(17, 9, 40, 40))
	_set_rect(_counter, Rect2(67, 6, 45, 44))
	_set_rect(_enemy_counter, Rect2(_score.size.x / 2 + 37, 6, 45, 44))
	_set_rect(_crests[1], Rect2(_score.size.x - 61, 9, 40, 40))
	for count in [_counter, _enemy_counter]: count.add_theme_font_size_override("font_size", 22 if narrow else 30)
	_score.get_child(_score.get_child_count() - 1).position.x = _score.size.x / 2 - 33
	for i in 2: _set_rect(_reserve_labels[i], Rect2(17 + 170 * i, 48, 110, 18))

func update_frame(frame: Dictionary, selection: int, paused: bool, speed: float, finished: bool) -> void:
	var hero: Dictionary = frame.hero_status
	var previous_counts := _counter.text + "|" + _enemy_counter.text
	_counter.text = str(frame.ally_strength)
	_enemy_counter.text = str(frame.enemy_strength)
	_clock.text = format_time(frame.elapsed_seconds)
	var previous_name := _heading.text
	_heading.text = hero.name if not hero.name.is_empty() else "Герой"
	_defense.text = "ранен" if frame.hero_down else frame.hero_weapon_name + " [X]"
	_health_text.text = "%d / %d" % [maxi(0, roundi(hero.hp)), roundi(hero.max_hp)]
	_stamina_text.text = "Силы %d / 100" % roundi(frame.stamina)
	_armor_text.text = "Броня %s%s" % [str(int(hero.armor)) if hero.armor == floorf(hero.armor) else str(hero.armor), " · щит %d%%" % roundi(hero.block * 100) if hero.block else ""]
	_morale_text.text = "Мораль: " + _morale_name(frame.army_share)
	_health.max_value = maxf(1, hero.max_hp)
	_health.value = hero.hp
	_stamina.value = frame.stamina
	_armor.value = 100
	_morale.value = clampf(frame.army_share * 130, 6, 100)
	for slot in SLOTS:
		var weapon_name: String = hero.weapon_names.get(slot, "")
		var button: Button = _slot_buttons[slot]
		button.text = weapon_name if not weapon_name.is_empty() else "нет дальнего"
		button.tooltip_text = button.text
		button.disabled = frame.hero_down or finished or weapon_name.is_empty()
		button.set_pressed_no_signal(hero.slot == slot)
	var total := 0
	for i in Config.GROUP_KINDS:
		total += frame.group_strength[i]
		_update_group(i, frame.group_strength[i], selection, finished)
	_update_group(Config.ALL_GROUPS, total, selection, finished)
	for button in _order_buttons: button.disabled = finished
	_pause.icon = GameSkin.icon("play" if paused else "pause", "item")
	_speed_label.text = "×" + (str(int(speed)) if speed == floorf(speed) else str(speed))
	_pause.disabled = finished
	_speed.disabled = finished
	_retreat.disabled = frame.decided
	for i in 2: _reserve_labels[i].text = "+%d в запасе" % frame.reserve[i] if frame.reserve[i] else ""
	if previous_name != _heading.text or previous_counts != _counter.text + "|" + _enemy_counter.text: _layout_controls()

func show_commands(selection: int, orders: Array[String]) -> void:
	var state := "нет бойцов" if orders.is_empty() else ("разные приказы" if orders.size() > 1 else str(ORDER_STATES.get(orders[0], "Ждут приказа")))
	var previous := _command_state.text
	_command_state.text = ["Пехота", "Стрелки", "Конница", "Все отряды"][selection] + " · " + state
	for i in 4:
		_order_buttons[i].disabled = _order_buttons[i].disabled or orders.is_empty()
		_order_buttons[i].set_pressed_no_signal(orders.size() == 1 and orders[0] == ORDERS[i])
	if previous != _command_state.text: _layout_controls()

func configure_portraits(units: Array, identities: Dictionary) -> void:
	var done := {}
	for unit: Dictionary in units:
		if unit.side != 0: continue
		var group: int = 3 if unit.hero else int(unit.group_kind)
		if done.has(group) or group < 0 or group > 3: continue
		var layers := OriginalArt.layers_for(unit, identities.get(unit.id, ""))
		if layers.has("portrait"):
			_group_portraits[group].texture = layers.portrait
			done[group] = true
	_layout_controls()

func _update_group(group: int, count: int, selection: int, finished: bool) -> void:
	var button := _group_buttons[group]
	button.text = "%s %d" % [Demo.GROUP_NAMES[group], count]
	_group_counts[group].text = str(count)
	button.set_pressed_no_signal(group == selection)
	button.disabled = finished
	button.modulate.a = 1.0 if count else 0.35

func _add_bar(bar: ProgressBar, label: Label, kind: String) -> void:
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#1a1510")
	background.border_color = Color("#0d0905")
	background.set_border_width_all(2)
	var fill := StyleBoxTexture.new()
	fill.texture = load(AssetPaths.path("bar_%s" % kind))
	fill.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	fill.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	fill.expand_margin_left = -2
	fill.expand_margin_top = -2
	fill.expand_margin_right = -2
	fill.expand_margin_bottom = -2
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	_hero.add_child(bar)
	_label(label, bar, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.clip_text = true

static func _label(label: Label, parent: Node, font_size: int, display := false) -> void:
	label.add_theme_font_override("font", GameSkin.DISPLAY if display else GameSkin.BODY_BOLD)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

static func _set_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

static func format_time(elapsed: float) -> String:
	var seconds := floori(elapsed)
	return "%d:%02d" % [floori(float(seconds) / 60), seconds % 60]

static func _morale_name(share: float) -> String:
	for i in MORALE_THRESHOLDS.size():
		if share <= MORALE_THRESHOLDS[i]: return MORALE_LABELS[i]
	return MORALE_LABELS.back()
