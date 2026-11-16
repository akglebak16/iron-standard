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
var _footer: HFlowContainer
var _fit_revision := 0

func _ready() -> void:
	super._ready()
	close_button.visible = false
	tabs_row.hide()
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_footer = HFlowContainer.new()
	_footer.alignment = FlowContainer.ALIGNMENT_END
	_footer.add_theme_constant_override("h_separation", 8)
	_footer.add_theme_constant_override("v_separation", 8)
	var column := close_button.get_parent()
	column.add_child(_footer)
	column.move_child(_footer, close_button.get_index())

func _fit() -> void:
	super._fit()
	if is_instance_valid(_footer): _fit_report.call_deferred()

func _fit_report() -> void:
	_fit_revision += 1
	var revision := _fit_revision
	_scroll.custom_minimum_size.y = 0
	# Width and text wrapping settle before the content height is measured.
	for i in 3: await get_tree().process_frame
	if revision != _fit_revision or not is_inside_tree(): return
	var fixed_height := _panel.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var available := maxf(64, get_viewport().get_visible_rect().size.y - 80 - fixed_height)
	_scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, available)

## [[text, action], ...]; the first action is also taken by Enter, Esc or closing the window.
func show_report(win: bool, subtitle: String, rows: Array, notes: Array, actions: Array) -> void:
	_subtitle = subtitle
	_rows = rows
	_notes = notes
	_actions = actions
	_default_action = String(actions[0][1]) if not actions.is_empty() else ""
	set_width(680)
	set_tabs([], "")
	title_label.text = "Победа" if win else "Поражение"
	open_window()

func render() -> void:
	sub_label.text = _subtitle
	clear_body()
	var table := VBoxContainer.new()
	table.name = "ResultRows"
	body.add_child(table)
	for r in _rows:
		if r.size() > 3 and r[3] == "section":
			var heading_label := Label.new()
			heading_label.text = String(r[0])
			GameSkin.title(heading_label, 19)
			table.add_child(heading_label)
			continue
		if r.size() > 3 and r[3] in ["loss", "loss_header"]:
			table.add_child(_loss_line(r))
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var key := Label.new()
		key.text = String(r[0])
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_child(key)
		var value := Label.new()
		value.text = String(r[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.size_flags_stretch_ratio = 0.8
		var tone: int = int(r[2]) if r.size() > 2 else 0
		if tone != 0:
			value.add_theme_color_override("font_color", Color("#8fc24f") if tone > 0 else Color("#e0705a"))
		line.add_child(value)
		table.add_child(line)
	for text in _notes:
		note(String(text))
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	for i in _actions.size():
		var action: String = _actions[i][1]
		var b := Button.new()
		b.name = "Action_" + action
		b.text = String(_actions[i][0])
		if i == _actions.size() - 1:
			GameSkin.primary(b)
		b.pressed.connect(func(): _choose(action))
		_footer.add_child(b)
	_fit_report.call_deferred()

func _loss_line(row: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = str(row[0])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	for i in 3:
		var value := Label.new()
		value.text = str(row[4][i])
		value.custom_minimum_size.x = 61
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 14)
		if row[3] == "loss_header":
			value.add_theme_color_override("font_color", GameSkin.MUTED)
		elif int(row[4][i]) > 0:
			value.add_theme_color_override("font_color", [Color("e0705a"), Color("d1a84c"), Color("8fc24f")][i])
		line.add_child(value)
	return line

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
		rows.append(["Павшие противники", "%d из %d" % [int(result.get("enemyDead", 0)), int(result.enemyTotal)]])
	rows.append(["Погибли в твоём отряде", str(int(s.lost)), -1 if int(s.lost) > 0 else 0])
	rows.append(["Раненые выжили", str(int(s.wounded))])
	if int(result.get("heroKills", 0)) > 0:
		rows.append(["Герой сразил врагов", str(int(result.heroKills))])
	if result.has("left"):
		rows.append(["Бойцы в строю", str(_count(result.left))])
	if result.has("heroDown"):
		rows.append(["Состояние героя", "Ранен" if result.heroDown else "%d%% здоровья" % roundi(float(result.get("heroHp", 1)) * 100), -1 if result.heroDown else 0])
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
	rows.append_array(_troop_rows(result, troops))
	var companion_heading := false
	for profile in resolved.party.get("comps", []):
		if not s.get("comps", {}).has(profile.id):
			continue
		var gain: Dictionary = s.comps[profile.id]
		if not companion_heading:
			rows.append(["Спутники", "", 0, "section"])
			companion_heading = true
		var detail := ("Ранен · " if gain.get("down", false) else "В строю · ") + "+%d опыта" % int(gain.get("xp", 0))
		if int(gain.get("kills", 0)) > 0: detail += " · побед: %d" % int(gain.kills)
		if int(gain.get("levels_gained", 0)) > 0: detail += " · уровень %d" % int(profile.lvl)
		rows.append([profile.name, detail, 1 if int(gain.get("levels_gained", 0)) > 0 else 0])
	return rows

static func _count(counts: Dictionary) -> int:
	var total := 0
	for value in counts.values(): total += int(value)
	return total

## Counts are already resolved by the battle; no loss or reward rules are repeated in UI.
static func _troop_rows(result: Dictionary, troops) -> Array:
	var types := {}
	for field in ["dead", "wounded", "left"]:
		for type in result.get(field, {}):
			if int(result[field][type]) > 0: types[type] = true
	if types.is_empty(): return []
	var rows: Array = [["Твой отряд", "", 0, "section"], ["Боец", "", 0, "loss_header", ["Погибли", "Ранены", "В строю"]]]
	var ids: Array = types.keys()
	ids.sort()
	for type in ids:
		var troop: Dictionary = troops.get_troop(type) if troops != null else {}
		var counts := []
		for field in ["dead", "wounded", "left"]: counts.append(int(result.get(field, {}).get(type, 0)))
		rows.append([troop.get("name", type), "", 0, "loss", counts])
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
static func quick_rows(result: Dictionary, troops = null) -> Array:
	var fallen := 0
	var dead: Dictionary = result.get("dead", {})
	for type in dead:
		fallen += int(dead[type])
	var rows: Array = [["Павшие противники", "%d из %d" % [int(result.get("enemyDead", 0)), int(result.get("enemyTotal", 0))]],
		["Погибли в твоём отряде", str(fallen), -1 if fallen > 0 else 0], ["Герой сразил врагов", str(int(result.get("heroKills", 0)))]]
	if result.has("wounded"): rows.append(["Раненые выжили", str(_count(result.wounded))])
	if result.has("left"): rows.append(["Бойцы в строю", str(_count(result.left))])
	if result.has("heroDown"): rows.append(["Состояние героя", "Ранен" if result.heroDown else "%d%% здоровья" % roundi(float(result.get("heroHp", 1)) * 100), -1 if result.heroDown else 0])
	rows.append_array(_troop_rows(result, troops))
	return rows
