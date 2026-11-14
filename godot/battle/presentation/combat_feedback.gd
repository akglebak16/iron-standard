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
const BONDED_LEADER_DOWN := "%s пал — мертвецы рассыпаются в прах!"
const WAVERED := "%s дрогнул."
const FLED := "%s бежит с поля боя."
const RESERVE_UNDEAD := "Из-за холма выходят ещё %d мертвецов"
const RESERVE_ENEMY := "К врагу подходит подкрепление: %d"
const RESERVE_ALLY := "К нам подходит подкрепление: %d"
const RESERVE_LEFT := " (в запасе %d)."
const RESERVE_LAST := " — последняя волна."
const UNDEAD_FACTION := "undead" # Presentation text choice only; rules read battle traits.
const ROUT_MESSAGE_CHANCE := 0.5 # Browser logs every second waver/rout to keep the journal readable.
const HERO_KILL := "Герой сразил: %s."
const RANGED_UNAVAILABLE_TEXT := "Нет дальнего оружия"
const WEAPON_TEXT_COLOR := Color("#f1e3b0")
const WEAPON_TEXT_OFFSET := Vector2(0, -8)
const FATAL_IMPACT_COLOR := Color("#ff8d79")
const FATAL_IMPACT_OFFSET := Vector2(0, -26)
const BATTLE_STARTED := "Битва началась."
const ENEMY_CHARGE := "Враг идёт в атаку!"
const WALL_ALERT := "Враг у стен!"
const GARRISON_CAVALRY := "Конница гарнизона вышла в бой."
const VICTORY := "Победа! Враг разбит."
const DEFEAT := "Отряд разбит."
const RETREATED := "Отряд отступает!"
const ORDER_NAMES := {
	Config.ORDER_HOLD: "держать позицию",
	Config.ORDER_FOLLOW: "за мной",
	Config.ORDER_CHARGE: "в атаку!",
	Config.ORDER_RETREAT: "отойти назад",
}

var _labels: Array[Dictionary] = []
var _journal: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

func set_seed(value: int) -> void:
	_rng.seed = value

func advance(dt: float, events: Array[Dictionary]) -> void:
	_age(_labels, dt)
	for event in events:
		match event.kind:
			Event.Kind.BATTLE_STARTED:
				_log(BATTLE_STARTED)
			Event.Kind.ORDER_APPLIED:
				_log("%s: %s" % [Demo.GROUP_NAMES[event.selection], ORDER_NAMES[event.order]])
			Event.Kind.ENEMY_CHARGE:
				_log(ENEMY_CHARGE)
			Event.Kind.WALL_ALERT:
				_log(WALL_ALERT)
			Event.Kind.GARRISON_CAVALRY:
				_log(GARRISON_CAVALRY)
			Event.Kind.BATTLE_DECIDED:
				_log(VICTORY if event.won else DEFEAT)
			Event.Kind.BATTLE_RETREATED:
				_log(RETREATED)
			Event.Kind.RESERVE_WAVE:
				var text: String = RESERVE_UNDEAD % event.count if UNDEAD_FACTION in event.troop_factions else (RESERVE_ENEMY if event.side == 1 else RESERVE_ALLY) % event.count
				_log(text + (RESERVE_LEFT % event.remaining if event.remaining > 0 else RESERVE_LAST))
			Event.Kind.WAVERED:
				if _rng.randf() < ROUT_MESSAGE_CHANCE:
					_log(WAVERED % event.target_name)
			Event.Kind.FLED:
				if _rng.randf() < ROUT_MESSAGE_CHANCE:
					_log(FLED % event.target_name)
			Event.Kind.HIT:
				if event.target_hero or event.source_hero:
					_label(event.position, str(event.amount), Demo.DAMAGE_RECEIVED_COLOR if event.target_hero else Demo.DAMAGE_DEALT_COLOR)
			Event.Kind.BLOCK:
				if event.target_hero or (event.source_hero and event.attack == Event.Attack.MELEE):
					_label(event.position, BLOCK_TEXT, Demo.BLOCK_COLOR)
			Event.Kind.LAST_STAND:
				_label(event.position, LAST_STAND_TEXT, Demo.LAST_STAND_COLOR)
				_log(HERO_RECOVERED)
			Event.Kind.WEAPON_SWAPPED:
				_label(event.position + WEAPON_TEXT_OFFSET, event.weapon_name, WEAPON_TEXT_COLOR)
			Event.Kind.RANGED_WEAPON_UNAVAILABLE:
				_label(event.position + WEAPON_TEXT_OFFSET, RANGED_UNAVAILABLE_TEXT, Demo.BLOCK_COLOR)
			Event.Kind.DOWN:
				if event.target_hero:
					_log(HERO_DOWN)
				elif event.target_companion:
					_log(COMPANION_DOWN % event.target_name)
				elif event.target_leader:
					_log((BONDED_LEADER_DOWN if event.target_bonded else LEADER_DOWN) % event.target_name)
				elif event.source_hero and not event.target_name.is_empty():
					_log(HERO_KILL % event.target_name)

func journal() -> String:
	return "\n".join(_journal)

func add_dialogue(lines: PackedStringArray) -> void:
	for line in lines:
		_log(line)

func add_fatal_impacts(labels: Array[Dictionary]) -> void:
	for label in labels:
		_label(label.position + FATAL_IMPACT_OFFSET, label.text, FATAL_IMPACT_COLOR)

func has_effects() -> bool:
	return not _labels.is_empty()

func draw(canvas: CanvasItem) -> void:
	for label in _labels:
		var color: Color = label.color
		color.a *= 1.0 - float(label.age) / float(label.lifetime)
		var position: Vector2 = label.position + Demo.FEEDBACK_OFFSET - Vector2(0, label.age * Demo.FEEDBACK_RISE_SPEED)
		canvas.draw_string(ThemeDB.fallback_font, position, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, Demo.FEEDBACK_FONT_SIZE, color)

func _label(position: Vector2, value: String, color: Color) -> void:
	if _labels.size() < Demo.FEEDBACK_MAX_LABELS:
		_labels.append({"position": position, "text": value, "color": color, "age": 0.0, "lifetime": Demo.FEEDBACK_LIFETIME})

func _log(value: String) -> void:
	_journal.append(value)
	if _journal.size() > Demo.BATTLE_LOG_MAX_ENTRIES:
		_journal.remove_at(0)

static func _age(entries: Array[Dictionary], dt: float) -> void:
	for i in range(entries.size() - 1, -1, -1):
		entries[i].age += dt
		if entries[i].age >= entries[i].lifetime:
			entries.remove_at(i)
