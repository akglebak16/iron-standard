extends "res://apps/godot/presentation/campaign/modal_window.gd"
## Pause menu with settings: save, sound, music, gore, back to the title (openMenu in src/06_ui.js).
const Preferences = preload("res://apps/godot/composition/presentation_preferences.gd")

signal save_requested
signal title_requested
signal settings_changed(effects: bool, music: bool, blood: bool)
var preferences: Preferences
var battle_mode := false

func open_menu(prefs: Preferences) -> void:
	preferences = prefs
	open_window()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_window()

func render() -> void:
	if preferences == null:
		return
	set_width(560)
	title_label.text = "Пауза"
	sub_label.text = "Настройки сохраняются сразу"
	set_tabs([], "")
	clear_body()
	sub_label.hide()
	_crest.hide()
	close_button.hide()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scroll.custom_minimum_size.y = 410
	var audio := preferences.read()
	var blood := preferences.read_blood()
	_menu_button("Продолжить", close_window, true)
	if not battle_mode: _menu_button("Сохранить игру", func(): save_requested.emit())
	_menu_button("Звук: %s" % ("включён" if audio.effects else "выключен"), func(): _audio_setting(not audio.effects, audio.music))
	_menu_button("Музыка: %s" % ("включена" if audio.music else "выключена"), func(): _audio_setting(audio.effects, not audio.music))
	_menu_button("Расчленёнка: %s" % ("включена" if blood else "выключена"), func(): _blood_setting(not blood))
	_menu_button("В главное меню", func(): title_requested.emit(), false, true)
	heading("Управление")
	if battle_mode:
		note("WASD — движение, Shift — бег, ЛКМ — удар, ПКМ — блок, X — смена оружия. Колесо — масштаб.")
		note("1–4 — группа, Q — держать, E — за мной, R — в атаку, F — отойти. P — пауза, T — скорость, Esc — меню.")
	else:
		note("Клик по карте — идти, по городу — войти, по отряду или логову — догнать и напасть. Колесо — масштаб, перетаскивание — сдвиг карты.")
		note("Пробел — пауза, 1/2/3 — скорость, P — отряд, H — герой, J — журнал, F5 — сохранить, Esc — закрыть окно или открыть это меню.")

func _audio_setting(effects: bool, music: bool) -> void:
	preferences.save(effects, music)
	settings_changed.emit(effects, music, preferences.read_blood())

func _blood_setting(blood: bool) -> void:
	preferences.save_blood(blood)
	var audio := preferences.read()
	settings_changed.emit(audio.effects, audio.music, blood)

func _menu_button(text: String, action: Callable, primary := false, danger := false) -> void:
	var button := Button.new()
	button.text = text
	if primary: GameSkin.primary(button)
	if danger: button.add_theme_stylebox_override("normal", GameSkin.box("danger", 12))
	button.pressed.connect(func(): action.call(); render())
	body.add_child(button)
