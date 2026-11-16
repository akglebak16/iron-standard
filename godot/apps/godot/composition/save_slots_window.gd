extends "res://apps/godot/presentation/campaign/modal_window.gd"
## «Сохранить / Загрузить»: the list of save slots with day, hero, party size, gold and the time of saving.
## Saving goes only into the numbered slots; the autosave and the quick save can only be loaded.
const SaveSlots = preload("res://adapters/persistence/save_slots.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")

signal load_chosen(id: String)
var mode := "load"
var state: RefCounted
## Loading from inside a campaign drops the current progress, so it asks once more.
var confirm_load := false
var base_path := SaveStore.PATH
var message := ""
var _armed := ""
var _name_text := ""

func open_save(world: RefCounted) -> void:
	mode = "save"
	state = world
	_open()

func open_load(ask_first := false, notice := "") -> void:
	mode = "load"
	confirm_load = ask_first
	_open()
	message = notice
	render()

func _open() -> void:
	message = ""
	_armed = ""
	_name_text = ""
	open_window()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_window()

func render() -> void:
	set_width(720)
	var saving := mode == "save"
	title_label.text = "Сохранить игру" if saving else "Загрузить игру"
	sub_label.text = message if message != "" else ("Можно дать сохранению название, затем выбрать слот. Автосохранение и быстрое сохранение (F5) ручные слоты не затирают." if saving else "Выберите сохранение.")
	set_tabs([], "")
	clear_body()
	_crest.hide()
	if saving:
		var field := LineEdit.new()
		field.name = "SaveName"
		field.placeholder_text = "Название сохранения (необязательно)"
		field.max_length = SaveStore.MAX_NAME_LENGTH
		field.text = _name_text
		field.caret_column = _name_text.length()
		field.custom_minimum_size.y = 40
		field.text_changed.connect(func(text: String): _name_text = text)
		body.add_child(field)
	for entry in SaveSlots.list(base_path):
		var id: String = entry.id
		if saving and not SaveSlots.manual(id):
			continue
		var buttons: Array = []
		if saving:
			var text := "Сохранить"
			if entry.exists: text = "Точно перезаписать?" if _armed == id else "Перезаписать"
			buttons.append({"text": text, "call": _save.bind(id, entry.exists)})
		else:
			buttons.append({"text": "Точно загрузить?" if _armed == id else "Загрузить", "disabled": not entry.ok, "call": _load.bind(id)})
		row(SaveSlots.label(entry), SaveSlots.summary(entry), buttons)
		body.get_child(body.get_child_count() - 1).name = "Slot_" + id

func _save(id: String, occupied: bool) -> void:
	if occupied and _armed != id:
		_armed = id
		return
	_armed = ""
	var saved := SaveSlots.save(state, id, base_path, _name_text)
	message = "Не удалось сохранить"
	if saved:
		message = "Игра сохранена: %s" % SaveSlots.label({"title": SaveSlots.title(id), "meta": SaveStore.describe(SaveSlots.path(id, base_path)).meta})
		_name_text = ""

func _load(id: String) -> void:
	if confirm_load and _armed != id:
		_armed = id
		message = "Несохранённый прогресс текущей игры пропадёт."
		return
	_armed = ""
	load_chosen.emit(id)
