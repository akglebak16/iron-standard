extends RefCounted
## Save slots over SaveStore: one autosave slot, one quick slot (F5) and numbered manual slots.
## Each slot is its own file with its own generations, so the autosave never replaces a manual save.
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const AUTO := "auto"
const QUICK := "quick"
const MANUAL_COUNT := 6
const DAMAGED := "Сохранение повреждено или сделано в другой версии игры. Файл оставлен без изменений."
const EMPTY := "В этом слоте нет сохранения."

static func ids() -> Array[String]:
	var out: Array[String] = [AUTO, QUICK]
	for i in MANUAL_COUNT:
		out.append(str(i + 1))
	return out

static func manual(id: String) -> bool:
	return id.is_valid_int() and int(id) >= 1 and int(id) <= MANUAL_COUNT

static func title(id: String) -> String:
	if id == AUTO: return "Автосохранение"
	if id == QUICK: return "Быстрое сохранение"
	return "Слот %s" % id

## The autosave keeps the file name of the single save used before slots, so that save stays loadable.
static func path(id: String, base := SaveStore.PATH) -> String:
	if id == AUTO: return base
	if id != QUICK and not manual(id): return ""
	return "%s.slot_%s.json" % [base.trim_suffix(".json"), id]

static func save(state: RefCounted, id: String, base := SaveStore.PATH) -> bool:
	var file := path(id, base)
	return state != null and file != "" and SaveStore.save(state, file)

## One entry per slot, in screen order: {id, title, exists, ok, meta}.
static func list(base := SaveStore.PATH) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var entry := SaveStore.describe(path(id, base))
		entry["id"] = id
		entry["title"] = title(id)
		out.append(entry)
	return out

## The most recently written readable slot ("Продолжить"); "" when there is none.
static func latest(base := SaveStore.PATH) -> String:
	var best := ""
	var best_time := -1.0
	for entry in list(base):
		if entry.ok and float(entry.meta.get("saved_at", 0.0)) > best_time:
			best = entry.id
			best_time = float(entry.meta.get("saved_at", 0.0))
	return best

static func any(base := SaveStore.PATH) -> bool:
	for id in ids():
		if SaveStore.exists(path(id, base)): return true
	return false

## {state, error}: state is null and error says why when the slot cannot be loaded. An empty id means the latest slot.
static func load_slot(europe: EuropeData, id := "", base := SaveStore.PATH) -> Dictionary:
	if id == "":
		id = latest(base)
		if id == "":
			return {"state": null, "error": DAMAGED if any(base) else EMPTY}
	var file := path(id, base)
	if file == "" or not SaveStore.exists(file):
		return {"state": null, "error": EMPTY}
	var state := SaveStore.load_state(europe, file)
	return {"state": state, "error": "" if state != null else DAMAGED}

## "День 12 · Глеб · отряд 34 · 1200 зол. · 16.11.2026 19:04" for the save/load screen.
static func summary(entry: Dictionary) -> String:
	if not entry.exists: return "Пусто"
	if not entry.ok: return "Файл повреждён — загрузить нельзя"
	var meta: Dictionary = entry.meta
	var parts: Array[String] = []
	if meta.has("day"): parts.append("День %d" % int(meta.day))
	if str(meta.get("hero", "")) != "": parts.append(str(meta.hero))
	if meta.has("men"): parts.append("отряд %d" % int(meta.men))
	if meta.has("gold"): parts.append("%d зол." % int(meta.gold))
	if parts.is_empty(): parts.append("Сохранение прежней версии")
	parts.append(_date(float(meta.get("saved_at", 0.0))))
	return " · ".join(parts)

static func _date(unix: float) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	var d := Time.get_datetime_dict_from_unix_time(int(unix) + bias * 60)
	return "%02d.%02d.%d %02d:%02d" % [d.day, d.month, d.year, d.hour, d.minute]
