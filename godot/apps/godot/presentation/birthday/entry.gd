extends RefCounted
## One temporary integration point. No campaign data or calendar checks.
const ENABLED := false
const Scene = preload("res://apps/godot/presentation/birthday/celebration.tscn")

static func mount(menu: Control, ui: CanvasLayer, center: CenterContainer, title: Label, subtitle: Label, platform: Label, background: Node) -> Control:
	if not ENABLED: return null
	var celebration := Scene.instantiate()
	celebration.menu_center = center
	celebration.preferences = menu._preferences
	celebration.ordinary_music = menu._music
	menu._music.enabled = false
	menu._music.set_process(false)
	title.hide()
	subtitle.hide()
	platform.hide()
	if background != null:
		background.get_node("Battle")._music.enabled = false
		background.get_node("Battle")._audio.enabled = false
	ui.add_child(celebration)
	ui.move_child(celebration, 1)
	return celebration
