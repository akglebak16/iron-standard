extends "res://campaign/presentation/modal_window.gd"
## Pause menu with settings: save, sound, music, gore, back to the title (openMenu in src/06_ui.js).
const Preferences = preload("res://app/presentation_preferences.gd")

signal save_requested
signal title_requested
var preferences: Preferences

func open_menu(prefs: Preferences) -> void:
	preferences = prefs
	open_window()

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
	_menu_button("Сохранить игру", func(): save_requested.emit())
	_menu_button("Звук: %s" % ("включён" if audio.effects else "выключен"), func(): preferences.save(not audio.effects, audio.music))
	_menu_button("Музыка: %s" % ("включена" if audio.music else "выключена"), func(): preferences.save(audio.effects, not audio.music))
	_menu_button("Расчленёнка: %s" % ("включена" if blood else "выключена"), func(): preferences.save_blood(not blood))
	_menu_button("В главное меню", func(): title_requested.emit(), false, true)
	heading("Управление")
	note("Клик по карте — идти, по городу — войти, по отряду или логову — догнать и напасть. Колесо — масштаб, перетаскивание — сдвиг карты.")
	note("Пробел — пауза, 1/2/3 — скорость, P — отряд, H — герой, J — журнал, F5 — сохранить, Esc — закрыть окно или открыть это меню.")

func _menu_button(text: String, action: Callable, primary := false, danger := false) -> void:
	var button := Button.new()
	button.text = text
	if primary: GameSkin.primary(button)
	if danger: button.add_theme_stylebox_override("normal", GameSkin.box("danger", 12))
	button.pressed.connect(func(): action.call(); render())
	body.add_child(button)
