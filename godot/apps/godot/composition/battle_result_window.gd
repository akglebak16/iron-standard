extends "res://apps/godot/presentation/campaign/modal_window.gd"
## Battle report with a way out (showResult and quickEnded in src/07_main.js): victory or defeat, how long it took,
## enemies down, own fallen and wounded, loot, trophies, hero experience, losses by troop and companions.
## The campaign continues to the map; a quick battle goes back to the menu or starts another fight.
const AftermathText = preload("res://apps/godot/composition/aftermath_text.gd")

signal action_chosen(action: String)

var _subtitle := ""
var _rows: Array = []
var _notes: Array = []
var _actions: Array = []
var _default_action := ""

func _ready() -> void:
	super._ready()
	close_button.visible = false

## [[text, action], ...]; the first action is also taken by Enter, Esc or closing the window.
func show_report(win: bool, subtitle: String, rows: Array, notes: Array, actions: Array) -> void:
	_subtitle = subtitle
	_rows = rows
	_notes = notes
	_actions = actions
	_default_action = String(actions[0][1]) if not actions.is_empty() else ""
	set_width(560)
	set_tabs([], "")
	title_label.text = "Победа" if win else "Поражение"
	open_window()

func render() -> void:
	sub_label.text = _subtitle
	clear_body()
	for r in _rows:
		var line := HBoxContainer.new()
		line.name = "ResultRow"
		var key := Label.new()
		key.text = String(r[0])
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(key)
		var value := Label.new()
		value.text = String(r[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size.x = 220
		var tone: int = int(r[2]) if r.size() > 2 else 0
		if tone != 0:
			value.add_theme_color_override("font_color", Color("#8fc24f") if tone > 0 else Color("#e0705a"))
		line.add_child(value)
		body.add_child(line)
	for text in _notes:
		note(String(text))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	body.add_child(buttons)
	for i in _actions.size():
		var action: String = _actions[i][1]
		var b := Button.new()
		b.name = "Action_" + action
		b.text = String(_actions[i][0])
		if i == _actions.size() - 1:
			GameSkin.primary(b)
		b.pressed.connect(func(): _choose(action))
		buttons.add_child(b)

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		get_viewport().set_input_as_handled()
		_choose(_default_action)

func close_window() -> void:
	_choose(_default_action)

func _choose(action: String) -> void:
	if not visible:
		return
	visible = false
	action_chosen.emit(action)
	closed.emit()

static func duration(seconds: float) -> String:
	var total := maxi(0, roundi(seconds))
	return "Битва длилась %d мин %d сек" % [floori(total / 60.0), total % 60]

## Campaign report rows (showResult). `result` is the battle session result, `resolved` the applied aftermath.
static func campaign_rows(result: Dictionary, resolved: Dictionary, troops, gear, goods) -> Array:
	var s: Dictionary = resolved.summary
	var rows: Array = []
	if result.has("enemyTotal"):
		rows.append(["Враг убит или бежал", "%d из %d" % [int(result.get("enemyDead", 0)), int(result.enemyTotal)]])
	rows.append(["Твои павшие", str(int(s.lost)), -1 if int(s.lost) > 0 else 0])
	rows.append(["Раненые вернулись в строй", str(int(s.wounded))])
	if int(result.get("heroKills", 0)) > 0:
		rows.append(["Побед героя в бою", str(int(result.heroKills))])
	if s.win:
		rows.append(["Добыча", "+%d золота" % int(s.loot), 1])
	else:
		rows.append(["Потеряно золота", "−%d" % int(s.lost_gold), -1])
	var drops := AftermathText.drop_names(s.get("drops", []), gear, goods)
	if not drops.is_empty():
		rows.append(["Трофеи", ", ".join(drops), 1])
	rows.append(["Опыт героя", "+%d" % int(s.xp)])
	if int(s.get("levels_gained", 0)) > 0:
		rows.append(["Новый уровень", str(int(resolved.party.hero.lvl)), 1])
	var dead: Dictionary = result.get("dead", {})
	for type in dead:
		if int(dead[type]) <= 0:
			continue
		var troop: Dictionary = troops.get_troop(type) if troops != null else {}
		rows.append([troop.get("name", type), "−%d" % int(dead[type]), -1])
	for profile in resolved.party.get("comps", []):
		if not s.get("comps", {}).has(profile.id):
			continue
		var gain: Dictionary = s.comps[profile.id]
		var detail := "ур. %d" % int(profile.lvl) if int(gain.get("levels_gained", 0)) > 0 else "+%d опыта" % int(gain.get("xp", 0))
		rows.append([profile.name, detail, 1 if int(gain.get("levels_gained", 0)) > 0 else 0])
	return rows

static func campaign_notes(resolved: Dictionary) -> Array:
	var s: Dictionary = resolved.summary
	var notes: Array = []
	if s.has("recovery_town"):
		notes.append("Ты очнулся в городе %s. Отряд разбит, но жив." % s.recovery_town)
	var completed: Array = s.get("completed_quests", [])
	if not completed.is_empty():
		var reward := 0
		for quest in completed:
			reward += int(quest.gold)
		notes.append("Заданий выполнено: %d · награда %d золота." % [completed.size(), reward])
	if s.get("barrow_destroyed", false):
		notes.append("Чёрный курган разрушен.")
	return notes

## Quick battle rows (quickEnded): enemies down, own fallen, hero victories.
static func quick_rows(result: Dictionary) -> Array:
	var fallen := 0
	var dead: Dictionary = result.get("dead", {})
	for type in dead:
		fallen += int(dead[type])
	return [["Враг убит или бежал", "%d из %d" % [int(result.get("enemyDead", 0)), int(result.get("enemyTotal", 0))]],
		["Твои павшие", str(fallen), -1 if fallen > 0 else 0], ["Побед героя", str(int(result.get("heroKills", 0)))]]
