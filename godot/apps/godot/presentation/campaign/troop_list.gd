extends RefCounted
## Compact troop tables shared by the party window («Отряд») and the settlement recruits («Рекруты»):
## a summary card of chips, then a card per group with a table portrait · name and details · small action buttons.
## The look follows the market tables (town_window.gd): card_panel, small buttons, muted second lines.
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const ModalWindow = preload("res://apps/godot/presentation/campaign/modal_window.gd")

## Battle groups by the troop field `grp` (the same names as the battle orders).
const GROUP_NAMES := ["Пехота", "Стрелки", "Конница"]
const PORTRAIT := 36.0
const WARN := Color("#e0705a")
const GOOD := Color("#a5c77b")

static func tier_pips(tier: int) -> String:
	return "◆".repeat(clampi(tier, 0, 3)) + "◇".repeat(maxi(0, 3 - tier))

## «1 боец», «3 бойца», «12 бойцов».
static func men(n: int) -> String:
	var tail := n % 100
	var word := "бойцов"
	if tail < 11 or tail > 14:
		word = {1: "боец", 2: "бойца", 3: "бойца", 4: "бойца"}.get(n % 10, "бойцов")
	return "%d %s" % [n, word]

static func group_name(troop: Dictionary) -> String:
	return GROUP_NAMES[clampi(int(troop.get("grp", 0)), 0, GROUP_NAMES.size() - 1)]

## «Пехота 12 · Стрелки 4 · Конница 2» for stacks [{type, n}]; empty groups are left out.
static func composition(stacks: Array, catalog) -> String:
	var counts := [0, 0, 0]
	for s in stacks:
		counts[clampi(int(catalog.get_troop(s.type).get("grp", 0)), 0, 2)] += int(s.n)
	var parts: PackedStringArray = []
	for i in counts.size():
		if counts[i] > 0:
			parts.append("%s %d" % [GROUP_NAMES[i], counts[i]])
	return " · ".join(parts) if not parts.is_empty() else "никого"

## A card with a wrapping line of chips; returns the line for `chip`.
static func summary(parent: Control, node_name: String) -> HFlowContainer:
	var card := ModalWindow.card_panel()
	card.name = node_name
	parent.add_child(card)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 26)
	line.add_theme_constant_override("v_separation", 6)
	card.add_child(line)
	return line

static func chip(line: Control, icon_name: String, text: String, color := GameSkin.PARCH, hint := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.tooltip_text = hint
	h.mouse_filter = Control.MOUSE_FILTER_STOP if hint != "" else Control.MOUSE_FILTER_IGNORE
	h.add_child(icon(GameSkin.icon(icon_name), 22))
	h.add_child(cell(text, color, 16))
	line.add_child(h)

## A card with a coloured left edge, a header (title, count) and a three-column table; returns the table.
static func table(parent: Control, node_name: String, title: String, detail: String, accent: Color) -> GridContainer:
	var card := ModalWindow.card_panel()
	card.name = node_name
	var style := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = accent.darkened(0.25)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var t := Label.new()
	t.name = "Title"
	t.text = title
	GameSkin.title(t, 18)
	t.add_theme_color_override("font_color", accent)
	head.add_child(t)
	var d := cell(detail, GameSkin.MUTED, 14)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(d)
	var grid := GridContainer.new()
	grid.name = "Table"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	return grid

## One table row: portrait, the name with up to two small lines under it, then the action controls.
static func row(grid: GridContainer, troop_id: String, row_name: String, title: String, lines: Array, actions: Array) -> void:
	var portrait := OriginalArt.portrait_control(troop_id, "player", PORTRAIT)
	portrait.name = "Portrait_" + row_name
	portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	grid.add_child(portrait)
	var block := VBoxContainer.new()
	block.name = "Troop_" + row_name
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_theme_constant_override("separation", -2)
	var n := cell(title, GameSkin.PARCH, 15)
	n.name = "Name"
	n.add_theme_font_override("font", GameSkin.BODY_BOLD)
	n.clip_text = true
	n.tooltip_text = title
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	block.add_child(n)
	for text in lines:
		var l := cell(String(text), GameSkin.MUTED, 12)
		l.clip_text = true
		l.tooltip_text = String(text)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		block.add_child(l)
	grid.add_child(block)
	var box := HBoxContainer.new()
	box.name = "Actions_" + row_name
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for control in actions:
		box.add_child(control)
	grid.add_child(box)

## The market's small button: 13 px text, slim margins.
static func small(button: Button) -> Button:
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(34, 24)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBox = button.get_theme_stylebox(state_name)
		if box == null:
			continue
		box = box.duplicate()
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		box.content_margin_left = 6
		box.content_margin_right = 6
		button.add_theme_stylebox_override(state_name, box)
	return button

## Toggle buttons in a row, like the market's «Товары / Снаряжение»; `pick` gets the chosen key.
static func switch(parent: Control, node_name: String, caption: String, options: Array, current: String, pick: Callable) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = node_name
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	if caption != "":
		line.add_child(cell(caption, GameSkin.MUTED, 14))
	for option in options:
		var b := Button.new()
		b.name = node_name + "_" + String(option[0])
		b.text = option[1]
		b.tooltip_text = option[2] if option.size() > 2 else ""
		b.toggle_mode = true
		b.button_pressed = current == option[0]
		b.focus_mode = Control.FOCUS_NONE
		small(b)
		var key: String = option[0]
		b.pressed.connect(func(): pick.call(key))
		line.add_child(b)
	return line

static func cell(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

static func icon(texture: Texture2D, extent: int) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = Vector2(extent, extent)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
