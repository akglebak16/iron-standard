extends RefCounted
## The original style.css palette and fonts, shared by app, campaign and battle UI.
const DISPLAY = preload("res://ui/assets/fonts/AlegreyaSC-Bold.ttf")
const BODY = preload("res://ui/assets/fonts/AlegreyaSans-Medium.ttf")
const BODY_BOLD = preload("res://ui/assets/fonts/AlegreyaSans-Bold.ttf")
const INK := Color("#150f09")
const BRASS := Color("#d1a84c")
const PARCH := Color("#eadfc2")
const MUTED := Color("#b3a483")

static func box(kind := "plank", padding := 12.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://ui/assets/%s.png" % kind)
	style.set_texture_margin_all(5)
	if kind == "plank":
		style.set_texture_margin_all(12)
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	style.set_content_margin_all(padding)
	return style

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", box())
	t.set_stylebox("panel", "Panel", box())
	for type in ["Button", "OptionButton"]:
		t.set_font("font", type, DISPLAY)
		t.set_font_size("font_size", type, 17)
		t.set_color("font_color", type, PARCH)
		t.set_color("font_hover_color", type, Color("#fff6dc"))
		t.set_color("font_pressed_color", type, Color("#fff6dc"))
		t.set_color("font_disabled_color", type, Color("#b3a4836b"))
		t.set_color("font_shadow_color", type, Color.BLACK)
		t.set_constant("shadow_offset_y", type, 1)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var style := box("primary" if state in ["pressed", "hover_pressed"] else "button", 10)
			if state == "hover":
				style.modulate_color = Color(1.22, 1.22, 1.22)
			t.set_stylebox(state, type, style)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = BRASS
		focus.set_border_width_all(2)
		t.set_stylebox("focus", type, focus)
	t.set_color("font_color", "Label", PARCH)
	t.set_color("font_shadow_color", "Label", Color("#00000099"))
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_font("font", "LineEdit", BODY)
	t.set_stylebox("normal", "LineEdit", box("button", 10))
	t.set_stylebox("focus", "LineEdit", box("primary", 10))
	t.set_color("font_color", "LineEdit", PARCH)
	t.set_color("caret_color", "LineEdit", BRASS)
	t.set_color("font_color", "RichTextLabel", PARCH)
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color("#1a1510")
	bar_background.border_color = INK
	bar_background.set_border_width_all(1)
	t.set_stylebox("background", "ProgressBar", bar_background)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = BRASS
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_stylebox("panel", "TooltipPanel", box("plank", 9))
	t.set_color("font_color", "TooltipLabel", PARCH)
	return t

static func title(label: Label, size := 30) -> void:
	label.add_theme_font_override("font", DISPLAY)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", BRASS)
	label.add_theme_constant_override("shadow_offset_y", 2)

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", box("primary", 12))

static func icon(name: String, palette := "icon") -> Texture2D:
	var path := "res://ui/assets/%s_%s.svg" % [palette, name]
	return load(path) if ResourceLoader.exists(path) else null
