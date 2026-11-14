extends RefCounted
const Demo = preload("res://battle/presentation/demo_config.gd")
const Event = preload("res://battle/combat_event.gd")
const Config = preload("res://battle/config.gd")

const BLOCK_TEXT := "Блок"
const LAST_STAND_TEXT := "Не сдаюсь!"
const HERO_RECOVERED := "Герой поднялся на ноги."
const HERO_DOWN := "Герой ранен и вынесен из боя."
const COMPANION_DOWN := "%s ранен и вынесен из боя."
const LEADER_DOWN := "%s пал!"
const HERO_KILL := "Герой сразил: %s."
const BATTLE_STARTED := "Битва началась."
const ENEMY_CHARGE := "Враг идёт в атаку!"
const WALL_ALERT := "Враг у стен!"
const GARRISON_CAVALRY := "Конница гарнизона вышла в бой."
const VICTORY := "Победа! Враг разбит."
const DEFEAT := "Отряд разбит."
const GROUP_NAMES := ["Пехота", "Стрелки", "Конница", "Весь отряд"]
const ORDER_NAMES := {
	Config.ORDER_HOLD: "держать позицию",
	Config.ORDER_FOLLOW: "за мной",
	Config.ORDER_CHARGE: "в атаку!",
	Config.ORDER_RETREAT: "отойти назад",
}

var _labels: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _journal: PackedStringArray = []

func advance(dt: float, events: Array[Dictionary]) -> void:
	_age(_labels, dt)
	_age(_impacts, dt)
	for event in events:
		match event.kind:
			Event.Kind.BATTLE_STARTED:
				_log(BATTLE_STARTED)
			Event.Kind.ORDER_APPLIED:
				_log("%s: %s" % [GROUP_NAMES[event.selection], ORDER_NAMES[event.order]])
			Event.Kind.ENEMY_CHARGE:
				_log(ENEMY_CHARGE)
			Event.Kind.WALL_ALERT:
				_log(WALL_ALERT)
			Event.Kind.GARRISON_CAVALRY:
				_log(GARRISON_CAVALRY)
			Event.Kind.BATTLE_DECIDED:
				_log(VICTORY if event.won else DEFEAT)
			Event.Kind.HIT:
				if event.target_hero or event.source_hero:
					_label(event.position, str(event.amount), Demo.DAMAGE_RECEIVED_COLOR if event.target_hero else Demo.DAMAGE_DEALT_COLOR)
			Event.Kind.BLOCK:
				if event.target_hero:
					_label(event.position, BLOCK_TEXT, Demo.BLOCK_COLOR)
				_impact(event.position, Demo.BLOCK_COLOR)
			Event.Kind.CHARGE:
				_impact(event.position, Demo.LAST_STAND_COLOR)
			Event.Kind.LAST_STAND:
				_label(event.position, LAST_STAND_TEXT, Demo.LAST_STAND_COLOR)
				_log(HERO_RECOVERED)
			Event.Kind.DOWN:
				if event.target_hero:
					_log(HERO_DOWN)
				elif event.target_companion:
					_log(COMPANION_DOWN % event.target_name)
				elif event.target_leader:
					_log(LEADER_DOWN % event.target_name)
				elif event.source_hero and not event.target_name.is_empty():
					_log(HERO_KILL % event.target_name)

func journal() -> String:
	return "\n".join(_journal)

func has_effects() -> bool:
	return not _labels.is_empty() or not _impacts.is_empty()

func draw(canvas: CanvasItem) -> void:
	for mark in _impacts:
		var progress: float = mark.age / mark.lifetime
		var color: Color = mark.color
		color.a *= 1.0 - progress
		canvas.draw_arc(mark.position, Demo.IMPACT_RADIUS * (1.0 + progress), 0.0, TAU, Demo.HERO_RING_SEGMENTS, color, Demo.HERO_RING_WIDTH, true)
	for label in _labels:
		var color: Color = label.color
		color.a *= 1.0 - float(label.age) / float(label.lifetime)
		var position: Vector2 = label.position + Demo.FEEDBACK_OFFSET - Vector2(0, label.age * Demo.FEEDBACK_RISE_SPEED)
		canvas.draw_string(ThemeDB.fallback_font, position, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, Demo.FEEDBACK_FONT_SIZE, color)

func _label(position: Vector2, value: String, color: Color) -> void:
	if _labels.size() < Demo.FEEDBACK_MAX_LABELS:
		_labels.append({"position": position, "text": value, "color": color, "age": 0.0, "lifetime": Demo.FEEDBACK_LIFETIME})

func _impact(position: Vector2, color: Color) -> void:
	if _impacts.size() < Demo.IMPACT_MAX_MARKS:
		_impacts.append({"position": position, "color": color, "age": 0.0, "lifetime": Demo.IMPACT_DURATION})

func _log(value: String) -> void:
	_journal.append(value)
	if _journal.size() > Demo.BATTLE_LOG_MAX_ENTRIES:
		_journal.remove_at(0)

static func _age(entries: Array[Dictionary], dt: float) -> void:
	for i in range(entries.size() - 1, -1, -1):
		entries[i].age += dt
		if entries[i].age >= entries[i].lifetime:
			entries.remove_at(i)
