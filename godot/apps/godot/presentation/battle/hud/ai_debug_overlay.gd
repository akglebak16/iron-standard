extends RefCounted
## AI debug overlay (DESIGN.md 4.8, ADR-022), toggled with F3 in battle: commander plan and profile of both sides,
## order, morale, assessment and the latest decision with its reason for every group, fighters coloured by
## their decision mode, group centers with facing, waypoints, the commander's march points (stage 1g) and threat. It reads only the AI debug snapshot
## and never takes part in the battle. Texts and colours belong here, the codes come from the battle.
const Config = preload("res://core/battle/config.gd")
const TOGGLE_KEY := KEY_F3
const SIDE_NAMES := ["Свои", "Враги"]
const GROUP_NAMES := ["Пехота", "Стрелки", "Конница"]
const PROFILES := {"": "приказы игрока", "reference": "эталон", "commander": "командир"}
const PLANS := {"": "—", "deploy": "развёртывание", "advance": "сближение", "engage": "бой", "hold_walls": "держать стены", "sortie": "вылазка",
	"attack": "атака", "defence": "оборона", "waiting": "ожидание"}
const MORALE_STATES := ["стойкие", "колеблются", "бегут"] # Config.MORALE_GROUP_STEADY, _WAVERING, _ROUTED.
const ORDERS := {"hold": "держать", "follow": "за героем", "charge": "в атаку", "back": "отход"}
const DECISIONS := {"wait": "ждёт", "advance": "идёт вперёд", "stand": "стоит", "charge": "в атаку", "flank": "обход фланга",
	"call_off": "отмена погони", "sortie": "вылазка", "stand_down": "отмена атаки"}
const REASONS := {"deploying": "строится", "squad_in_reach": "отряд врага рядом", "fighter_in_reach": "враг рядом",
	"contact_after_call_off": "вплотную после отмены погони", "force_timer": "по таймеру", "on_focus": "на выбранный отряд",
	"on_enemy": "на центр врага", "enemy_close": "враг близко", "no_infantry": "нет своей пехоты",
	"out_of_range": "враг вне выстрела", "in_range": "враг на выстреле", "flank_timer": "время обхода",
	"waypoint_reached": "вышли на точку", "hopeless_chase": "безнадёжная погоня", "sortie_timer": "время вылазки",
	"attackers_inside": "враг за стеной", "on_flank_way": "идёт на точку обхода", "out_of_fire": "строем, вне выстрела",
	"under_fire": "быстро, под стрелами", "to_range": "на дальность выстрела", "with_line": "за своей линией",
	"outshot": "нас перестреливают", "stronger": "мы сильнее", "patience": "терпение кончилось",
	"not_stronger": "мы не сильнее", "enemy_coming": "враг идёт сам", "outshooting": "наши стрелки сильнее",
	"engaged": "бой не бросаем", "plan_kept": "план ещё в силе", "plan_changed": "план сменился", "hold_line": "держит место",
	"archers_reach": "стоит, где свои стрелки достают", "reserve": "в резерве", "counter": "встречный удар"}
const MODE_COLORS := {"": Color(0.6, 0.6, 0.6, 0.8), "slot": Color(0.75, 0.82, 0.9, 0.8), "melee": Color(0.95, 0.2, 0.15, 0.9),
	"shoot": Color(1.0, 0.85, 0.15, 0.9), "shootslot": Color(1.0, 0.55, 0.1, 0.9), "skirm": Color(0.7, 0.35, 0.95, 0.9),
	"rank": Color(0.3, 0.5, 0.95, 0.85), "brace": Color(0.2, 0.85, 0.75, 0.9), "fallback": Color(0.55, 0.85, 0.3, 0.9)}
const MODE_LEGEND := "Режимы: серо-голубой — в строю, красный — ближний бой, жёлтый — стрельба,\nоранжевый — стрельба со строя, фиолетовый — кружение, белый — бегство,\nсиний — ряд строя в атаке, бирюзовый — копья против конницы, зелёный — стрелок отходит;\nоранжевое кольцо — боец дрогнул"
const FLEEING_COLOR := Color(1, 1, 1, 0.9)
const WAVERING_RING := Color(1.0, 0.6, 0.1, 0.95)
const SIDE_COLORS := [Color(0.35, 0.65, 1.0, 0.85), Color(1.0, 0.4, 0.3, 0.85)]
const UNIT_MARK_RADIUS := 4.5
const UNIT_MARK_EDGE := Color(0, 0, 0, 0.7)
const GROUP_RING_RADIUS := 26.0
const TASK_MARK_RADIUS := 5.0 # The commander's march point of a group (stage 1g).
const FACING_LENGTH := 60.0
const LINE_WIDTH := 2.0
const LABEL_OFFSET := Vector2(30, -30)
const LABEL_SIZE := 13
const PANEL_WIDTH := 640.0
const PANEL_MARGIN := Vector2(12, 76) # Below the top-right buttons.
const PANEL_BACKGROUND := Color(0, 0, 0, 0.55)
const FLEEING := 1
const WAVERING := 4

var enabled := false
var _debug: Dictionary = {}
var _label: Label

## Toggles the trace in the simulation; the label is created on the first use only.
func toggle(simulation, hud: Node) -> void:
	enabled = not enabled
	simulation.set_ai_debug(enabled)
	if enabled and _label == null and hud != null:
		_label = Label.new()
		_label.name = "AiDebug"
		_label.add_theme_font_size_override("font_size", LABEL_SIZE)
		_label.add_theme_color_override("font_color", Color(1, 1, 0.92))
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_label.add_theme_constant_override("outline_size", 4)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var background := StyleBoxFlat.new()
		background.bg_color = PANEL_BACKGROUND
		background.set_content_margin_all(8)
		background.set_corner_radius_all(4)
		_label.add_theme_stylebox_override("normal", background)
		hud.add_child(_label)
	if _label != null:
		_label.visible = enabled
	update(simulation)

func update(simulation) -> void:
	_debug = simulation.ai_debug_snapshot() if enabled else {}
	if _label == null or not enabled: return
	var viewport := _label.get_viewport_rect().size if _label.is_inside_tree() else Vector2(1280, 720)
	var width := minf(PANEL_WIDTH, viewport.x - 2.0 * PANEL_MARGIN.x)
	_label.text = text(_debug)
	_label.position = Vector2(maxf(PANEL_MARGIN.x, viewport.x - width - PANEL_MARGIN.x), PANEL_MARGIN.y)
	_label.size = Vector2(width, 0.0) # Height shrinks back to the wrapped text.

func snapshot() -> Dictionary:
	return _debug

static func mode_color(mode: String, fleeing: bool) -> Color:
	return FLEEING_COLOR if fleeing else MODE_COLORS.get(mode, MODE_COLORS[""])

static func morale_state_name(state: int) -> String:
	return MORALE_STATES[state] if state >= 0 and state < MORALE_STATES.size() else str(state)

static func text(debug: Dictionary) -> String:
	if debug.is_empty(): return ""
	var lines: Array[String] = ["ИИ [F3] · %.1f с · оценка поля: тик %d" % [debug.elapsed_seconds, debug.assessment_tick]]
	for entry in debug.sides:
		var head := "%s — %s, план: %s" % [SIDE_NAMES[entry.side], PROFILES.get(entry.profile, entry.profile), PLANS.get(entry.plan, entry.plan)]
		head += plan_line(entry.get("plan_details", {}))
		if entry.has("assessment"):
			head += " · бойцов %d, сила %.1f, бежит %d" % [entry.assessment.count, entry.assessment.strength, entry.assessment.fleeing]
		if entry.missile_losses >= 0.05:
			head += " · потери от стрел %.1f" % entry.missile_losses
		lines.append(head)
		for group in entry.groups:
			lines.append("  " + group_line(group, debug.elapsed_seconds))
	lines.append(MODE_LEGEND)
	return "\n".join(lines)

## The commander's choice (stage 1g): the two best plan scores, the reason, the strength ratio, the outshot share and,
## from part 2, the patience and whether the enemy comes; empty for the reference brain, which weighs no plans.
static func plan_line(details: Dictionary) -> String:
	if details.is_empty(): return ""
	var scores: Array[String] = []
	for best in details.get("best", []):
		scores.append("%s %.2f" % [PLANS.get(best.plan, best.plan), best.score])
	var line := " (%s; %s; перевес %.2f, перестрелка %+.2f" % [", ".join(scores), REASONS.get(details.reason, details.reason), details.ratio, details.outshot]
	if float(details.get("patience", 0.0)) > 0.0:
		line += ", терпение %.2f" % details.patience
	if details.get("advancing", false):
		line += ", враг идёт"
	return line + ")"

static func group_line(group: Dictionary, now: float) -> String:
	var order: String = ORDERS.get("back" if group.backing else group.order, group.order)
	var line := "%s: %s" % [GROUP_NAMES[group.kind], order]
	if group.kited: line += " (бросил погоню)"
	var assessment: Dictionary = group.get("assessment", {})
	if not assessment.is_empty():
		if assessment.count == 0 and assessment.fleeing == 0: return line + " · нет бойцов"
		line += " · %d бойц., %s, мораль %d%%, в бою %d%%" % [assessment.count, morale_state_name(group.get("morale_state", 0)), roundi(assessment.morale_share * 100.0), roundi(assessment.engaged_share * 100.0)]
		if assessment.wavering > 0: line += ", дрогнули %d" % assessment.wavering
		if assessment.fleeing > 0: line += ", бегут %d" % assessment.fleeing
		if group.get("morale_pressure", 0.0) >= 0.05: line += ", давление %.2f" % group.morale_pressure
		if assessment.threat_flank > 0.0 or assessment.threat_rear > 0.0:
			line += " · угроза фланг %.1f, тыл %.1f" % [assessment.threat_flank, assessment.threat_rear]
	var last: Dictionary = group.last
	if not last.is_empty():
		line += " · %s: %s (%.1f с назад)" % [DECISIONS.get(last.decision, last.decision), REASONS.get(last.reason, last.reason), maxf(0.0, now - last.elapsed_seconds)]
	return line

## World-space marks; called from the battle view's _draw.
func draw_world(canvas: CanvasItem) -> void:
	if not enabled or _debug.is_empty(): return
	var units: Dictionary = _debug.units
	var names: Array = units.mode_names
	for index in units.positions.size():
		var mode: int = units.modes[index]
		var color := mode_color(names[mode] if mode >= 0 and mode < names.size() else "", (units.flags[index] & FLEEING) != 0)
		canvas.draw_circle(units.positions[index], UNIT_MARK_RADIUS + 1.0, UNIT_MARK_EDGE)
		canvas.draw_circle(units.positions[index], UNIT_MARK_RADIUS, color)
		if units.flags[index] & WAVERING:
			canvas.draw_arc(units.positions[index], UNIT_MARK_RADIUS + 2.5, 0.0, TAU, 12, WAVERING_RING, 1.5, true)
	var font := ThemeDB.fallback_font
	for entry in _debug.sides:
		var side_color: Color = SIDE_COLORS[entry.side]
		for group in entry.groups:
			var assessment: Dictionary = group.get("assessment", {})
			var center: Vector2 = assessment.get("center", Vector2.INF)
			if not center.is_finite(): continue
			canvas.draw_arc(center, GROUP_RING_RADIUS, 0.0, TAU, 32, side_color, LINE_WIDTH, true)
			canvas.draw_line(center, center + Vector2.from_angle(group.direction) * FACING_LENGTH, side_color, LINE_WIDTH, true)
			if group.tactic_state == Config.AI_TACTIC_FLANK and group.order != Config.ORDER_CHARGE:
				canvas.draw_dashed_line(center, group.waypoint, side_color, LINE_WIDTH, 8.0)
			if group.order == Config.ORDER_HOLD and group.center.distance_to(center) > GROUP_RING_RADIUS:
				canvas.draw_dashed_line(center, group.center, side_color, 1.0, 6.0)
			var task_point: Vector2 = group.get("task_point", Vector2.INF)
			if task_point.is_finite():
				canvas.draw_dashed_line(group.center, task_point, side_color.lightened(0.3), 1.0, 4.0)
				canvas.draw_circle(task_point, TASK_MARK_RADIUS, side_color.lightened(0.3))
			var title := "%s: %s, %s" % [GROUP_NAMES[group.kind], ORDERS.get(group.order, group.order), morale_state_name(group.get("morale_state", 0))]
			if not group.last.is_empty(): title += " · " + REASONS.get(group.last.reason, group.last.reason)
			canvas.draw_string_outline(font, center + LABEL_OFFSET, title, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 4, Color(0, 0, 0, 0.85))
			canvas.draw_string(font, center + LABEL_OFFSET, title, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, side_color.lightened(0.4))
