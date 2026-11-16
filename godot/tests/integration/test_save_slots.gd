extends SceneTree
## Save slots: manual slots, the quick slot and the autosave are separate files; a damaged slot is reported, not loaded.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const SaveSlots = preload("res://adapters/persistence/save_slots.gd")
const Autosave = preload("res://apps/godot/composition/autosave.gd")
const SlotsWindow = preload("res://apps/godot/composition/save_slots_window.gd")
const BASE := "user://test_slots/save.json"
var failed := 0

func check(ok: bool, text: String) -> void:
	if not ok:
		failed += 1
		printerr("FAILED: " + text)

func _entry(id: String) -> Dictionary:
	for e in SaveSlots.list(BASE):
		if e.id == id: return e
	return {}

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _initialize() -> void:
	var data := EuropeData.new()
	var loaded_content := ContentLoader.populate(data)
	check(loaded_content, "content loads")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE.get_base_dir()))
	for name in DirAccess.get_files_at(BASE.get_base_dir()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BASE.get_base_dir().path_join(name)))
	var s := WorldState.create(5, data, "emp", ContentLoader.registry())
	s.player.hero.name = "Глеб"
	s.player.gold = 321
	# nothing saved yet
	check(not SaveSlots.any(BASE) and SaveSlots.latest(BASE) == "", "no saves at the start")
	check(SaveSlots.list(BASE).size() == SaveSlots.MANUAL_COUNT + 2, "autosave, quick and manual slots are listed")
	check(SaveSlots.load_slot(data, "", BASE).error == SaveSlots.EMPTY, "continue without saves explains itself")
	check(SaveSlots.path("7", BASE) == "" and SaveSlots.path("../x", BASE) == "" and not SaveSlots.save(s, "nope", BASE), "unknown slots are refused")
	# save -> load -> the same world
	check(SaveSlots.save(s, "1", BASE), "manual slot saves")
	var one := _entry("1")
	check(one.exists and one.ok and one.meta.hero == "Глеб" and int(one.meta.gold) == 321 and int(one.meta.day) == int(s.clock.day), "slot shows hero, gold and day")
	var men := 1
	for stack in s.player.troops: men += int(stack.n)
	check(int(one.meta.men) == men, "slot shows the party size")
	check(SaveSlots.summary(one).contains("Глеб") and SaveSlots.summary(one).contains("321 зол."), "summary line")
	var back = SaveSlots.load_slot(data, "1", BASE)
	check(back.state != null and back.error == "", "manual slot loads")
	check(WorldSave.to_dict(back.state).sha256 == WorldSave.to_dict(s).sha256, "loaded world equals the saved one")
	# the autosave and the quick save do not touch manual slots
	var slot_one := SaveStore._generations(SaveSlots.path("1", BASE))[0].path as String
	var before := FileAccess.get_file_as_string(slot_one)
	s.player.gold = 999
	var autosave := Autosave.new()
	autosave.path = SaveSlots.path(SaveSlots.AUTO, BASE)
	var autosaved := autosave.save(s, false)
	check(autosaved and SaveSlots.save(s, SaveSlots.QUICK, BASE), "autosave and quick save work")
	check(FileAccess.get_file_as_string(slot_one) == before and int(_entry("1").meta.gold) == 321, "manual slot is untouched by autosave and quick save")
	check(int(_entry(SaveSlots.AUTO).meta.gold) == 999 and int(_entry(SaveSlots.QUICK).meta.gold) == 999, "autosave and quick slots hold the new state")
	check(int(SaveSlots.load_slot(data, "1", BASE).state.player.gold) == 321, "manual slot still loads the old state")
	check(SaveSlots.latest(BASE) in [SaveSlots.AUTO, SaveSlots.QUICK], "continue takes the most recent save")
	check(Autosave.new().path == SaveStore.PATH, "the autosave keeps the pre-slot file name, so an existing save stays loadable")
	# a damaged file: clear error, no crash, file left alone
	var two := SaveSlots.path("2", BASE)
	_write(two, "{\"version\": 2, \"payload\": \"brok")
	check(_entry("2").exists and not _entry("2").ok, "torn file is listed as damaged")
	var broken = SaveSlots.load_slot(data, "2", BASE)
	check(broken.state == null and broken.error == SaveSlots.DAMAGED, "torn file gives a clear error")
	check(FileAccess.get_file_as_string(two).begins_with("{\"version\": 2"), "damaged file is not deleted")
	var envelope := WorldSave.to_dict(s)
	envelope.payload = envelope.payload.substr(0, envelope.payload.length() - 8) + "AAAAAAAA"
	_write(SaveSlots.path("3", BASE), JSON.stringify(envelope))
	check(not _entry("3").ok and SaveSlots.load_slot(data, "3", BASE).state == null, "changed payload fails the checksum")
	check(SaveSlots.load_slot(data, "4", BASE).error == SaveSlots.EMPTY, "empty slot explains itself")
	# a damaged newest generation falls back to the previous one, and the list describes that one
	s.player.gold = 111
	check(SaveSlots.save(s, "5", BASE), "first generation")
	s.player.gold = 222
	check(SaveSlots.save(s, "5", BASE), "second generation")
	_write(SaveStore._generations(SaveSlots.path("5", BASE))[0].path, "garbage")
	check(_entry("5").ok and int(_entry("5").meta.gold) == 111, "list shows the generation that will load")
	check(int(SaveSlots.load_slot(data, "5", BASE).state.player.gold) == 111, "previous generation loads")
	# an old-format file (v1, no description) in the autosave place still loads
	var old_base := "user://test_slots/old.json"
	_write(old_base, JSON.stringify(WorldSave.to_v1_dict(s)))
	var old_list := SaveSlots.list(old_base)
	check(old_list[0].id == SaveSlots.AUTO and old_list[0].ok and SaveSlots.summary(old_list[0]).begins_with("Сохранение прежней версии"), "old save shows up as the autosave")
	check(SaveSlots.load_slot(data, "", old_base).state != null, "old version loads through continue")
	# the screen: save mode offers only manual slots and asks before overwriting; load mode refuses damaged slots
	var window := SlotsWindow.new()
	window.base_path = BASE
	root.add_child(window)
	await process_frame
	s.player.gold = 555
	window.open_save(s)
	check(window.body.get_child_count() == SaveSlots.MANUAL_COUNT, "save mode lists manual slots only")
	check(_button(window, "1").text == "Перезаписать" and _button(window, "4").text == "Сохранить", "occupied and empty slots differ")
	_button(window, "1").pressed.emit()
	check(int(_entry("1").meta.gold) == 321 and _button(window, "1").text == "Точно перезаписать?", "first click only asks")
	_button(window, "1").pressed.emit()
	check(int(_entry("1").meta.gold) == 555, "second click overwrites")
	_button(window, "4").pressed.emit()
	check(int(_entry("4").meta.gold) == 555, "empty slot saves at once")
	var chosen: Array = []
	window.load_chosen.connect(func(id: String): chosen.append(id))
	window.open_load(true)
	check(window.body.get_child_count() == SaveSlots.MANUAL_COUNT + 2, "load mode lists every slot")
	check(_button(window, "2").disabled and _button(window, "6").disabled and not _button(window, "1").disabled, "damaged and empty slots cannot be loaded")
	_button(window, "1").pressed.emit()
	check(chosen.is_empty(), "loading inside a campaign asks first")
	_button(window, "1").pressed.emit()
	check(chosen == ["1"], "second click loads")
	window.open_load()
	_button(window, SaveSlots.AUTO).pressed.emit()
	check(chosen == ["1", SaveSlots.AUTO], "from the title screen one click loads")
	if failed == 0:
		print("Save slots tests passed")
	quit(1 if failed > 0 else 0)

func _button(window: CanvasLayer, id: String) -> Button:
	return window.body.get_node("Slot_" + id).find_children("", "Button", true, false)[0]
