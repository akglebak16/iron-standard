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
	title_label.text = "Пауза"
	sub_label.text = "Настройки сохраняются сразу"
	set_tabs([], "")
	clear_body()
	var audio := preferences.read()
	var blood := preferences.read_blood()
	row("Продолжить", "", [{"text": "Продолжить", "call": func(): close_window()}])
	row("Сохранить игру", "Сохранение одно, его открывает «Продолжить» в главном меню (F5 — быстро).", [{"text": "Сохранить", "call": func(): save_requested.emit()}])
	row("Звук: %s" % ("включён" if audio.effects else "выключен"), "", [{"text": "Выключить" if audio.effects else "Включить", "call": func(): preferences.save(not audio.effects, audio.music)}])
	row("Музыка: %s" % ("включена" if audio.music else "выключена"), "", [{"text": "Выключить" if audio.music else "Включить", "call": func(): preferences.save(audio.effects, not audio.music)}])
	row("Расчленёнка: %s" % ("включена" if blood else "выключена"), "", [{"text": "Выключить" if blood else "Включить", "call": func(): preferences.save_blood(not blood)}])
	row("В главное меню", "Несохранённое пропадёт.", [{"text": "В меню", "call": func(): title_requested.emit()}])
	heading("Управление")
	note("Клик по карте — идти, по городу — войти, по отряду или логову — догнать и напасть. Колесо — масштаб, перетаскивание — сдвиг карты.")
	note("Пробел — пауза, 1/2/3 — скорость, P — отряд, H — герой, J — журнал, F5 — сохранить, Esc — закрыть окно или открыть это меню.")
