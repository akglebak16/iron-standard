extends RefCounted
const Event = preload("res://battle/combat_event.gd")
const Banter = preload("res://battle/presentation/banter_lines.gd")

const START := "start"
const SIEGE := "siege"
const KILL := "kill"
const KILL_UNDEAD := "killUndead"
const TAUNT := "taunt"
const HURT := "hurt"
const DOWN := "down"
const JOURNAL_LINE := "%s: «%s»"

const START_DELAY := Vector2(1.0, 2.2)
const INITIAL_TAUNT_DELAY := Vector2(24.0, 36.0) # Browser halved how often companions talk.
const TAUNT_INTERVAL := Vector2(24.0, 40.0)
const TAUNT_DISTANCE := 260.0
const HURT_DAMAGE_FRACTION := 0.1
const HURT_CHANCE := 0.35
const UNDEAD_KILL_CHANCE := 0.5
const COOLDOWN_INTERRUPT_CHANCE := 0.3
const KILL_COOLDOWN_LIMIT := 0.6
const KILL_COOLDOWN := 3.2
const GENERAL_COOLDOWN := 6.0
const KILL_SPEECH_CHANCE := 0.5
const INTRO_DURATION := 3.0
const REPLY_DURATION := 2.4
const BANTER_FIRST_DELAY := Vector2(9.0, 14.0)
const BANTER_INTERVAL := Vector2(20.0, 32.0)
const BANTER_RETRY_SECONDS := 3.0
const BANTER_REPLY_DELAY := 3.2
const BANTER_DOWN_DELAY := 1.3
const BANTER_DURATION := 3.0
const BANTER_COOLDOWN := 4.0

const FADE_DURATION := 0.3
const FONT_SIZE := 13
const BUBBLE_HEIGHT := 20.0
const HORIZONTAL_PADDING := 7.0
const FOOT_OFFSET := 47.0
const MOUNTED_OFFSET := 58.0
const DOWN_OFFSET := 15.0
const TAIL_LEFT := -2.0
const TAIL_RIGHT := 6.0
const TAIL_HEIGHT := 8.0
const BORDER_WIDTH := 1.6
const PAPER := Color("#f3e8c9")
const BORDER := Color("#1b130c")
const INK := Color("#2a1a0e")
const EMPHASIS := Color("#8f1a12")

var _rng := RandomNumberGenerator.new()
var _speakers := {}
var _banter_timer := 0.0
var _banter_reply := {}
var _banter_last := -1

func configure(roster: Dictionary) -> void:
	_speakers.clear()
	_banter_timer = _rng.randf_range(BANTER_FIRST_DELAY.x, BANTER_FIRST_DELAY.y)
	_banter_reply = {}
	_banter_last = -1
	for id in roster:
		var entry: Dictionary = roster[id]
		_speakers[id] = {
			"name": entry.name, "companion_id": entry.get("companion_id", ""), "lines": entry.lines.duplicate(true),
			"intro": _rng.randf_range(START_DELAY.x, START_DELAY.y),
			"taunt": _rng.randf_range(INITIAL_TAUNT_DELAY.x, INITIAL_TAUNT_DELAY.y),
			"cooldown": 0.0, "text": "", "remaining": 0.0, "unit": {},
		}

func age(dt: float) -> void:
	for speaker: Dictionary in _speakers.values():
		speaker.remaining = maxf(0.0, speaker.remaining - dt)

func has_bubbles() -> bool:
	for speaker: Dictionary in _speakers.values():
		if speaker.remaining > 0.0:
			return true
	return false

func advance(dt: float, units: Array[Dictionary], events: Array[Dictionary], siege: bool, finished: bool = false) -> PackedStringArray:
	var journal := PackedStringArray()
	if _speakers.is_empty():
		return journal
	age(dt)
	for unit in units:
		if _speakers.has(unit.id):
			_speakers[unit.id].unit = unit
	for event in events:
		match event.kind:
			Event.Kind.HIT:
				if _speakers.has(event.target_id) and not event.lethal and event.damage_fraction > HURT_DAMAGE_FRACTION and _rng.randf() < HURT_CHANCE:
					_say(_speakers[event.target_id], HURT)
			Event.Kind.DOWN:
				if _speakers.has(event.source_id) and event.source_alive:
					var kind := KILL_UNDEAD if _has_undead_appearance(units, event.target_id) and _rng.randf() < UNDEAD_KILL_CHANCE else KILL
					_say(_speakers[event.source_id], kind)
				if _speakers.has(event.target_id):
					var speaker: Dictionary = _speakers[event.target_id]
					journal.append_array(_journal_line(speaker, DOWN))
					_queue_down_reply(speaker)
	if finished:
		return journal
	journal.append_array(_advance_banter(dt))
	for speaker: Dictionary in _speakers.values():
		var unit: Dictionary = speaker.unit
		if unit.is_empty() or unit.dead or unit.gone:
			continue
		speaker.cooldown -= dt
		if speaker.intro > 0.0:
			speaker.intro -= dt
			if speaker.intro <= 0.0:
				var kind := SIEGE if siege and speaker.lines.has(SIEGE) else START
				journal.append_array(_journal_line(speaker, kind))
		speaker.taunt -= dt
		if speaker.taunt <= 0.0:
			speaker.taunt = _rng.randf_range(TAUNT_INTERVAL.x, TAUNT_INTERVAL.y)
			if _enemy_near(unit, units):
				_say(speaker, TAUNT)
	return journal

func draw(canvas: CanvasItem) -> void:
	var font := preload("res://ui/game_theme.gd").BODY_BOLD
	for speaker: Dictionary in _speakers.values():
		var unit: Dictionary = speaker.unit
		if speaker.remaining <= 0.0 or unit.is_empty():
			continue
		var center: Vector2 = unit.position
		center.y -= MOUNTED_OFFSET if unit.mounted else FOOT_OFFSET
		if unit.dead:
			center.y += DOWN_OFFSET
		var width := font.get_string_size(speaker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + HORIZONTAL_PADDING * 2.0
		var bounds := Rect2(center - Vector2(width, BUBBLE_HEIGHT) * 0.5, Vector2(width, BUBBLE_HEIGHT))
		var bottom := bounds.end.y
		var outline := PackedVector2Array([
			bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end,
			Vector2(center.x + TAIL_RIGHT, bottom), Vector2(center.x + TAIL_LEFT, bottom + TAIL_HEIGHT),
			Vector2(center.x + TAIL_LEFT, bottom), Vector2(bounds.position.x, bottom), bounds.position,
		])
		var opacity := minf(1.0, speaker.remaining / FADE_DURATION)
		var ink := EMPHASIS if speaker.text.ends_with("!") else INK
		canvas.draw_colored_polygon(outline.slice(0, -1), Color(PAPER, opacity))
		canvas.draw_polyline(outline, Color(BORDER, opacity), BORDER_WIDTH, true)
		var baseline := center.y + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
		canvas.draw_string(font, Vector2(bounds.position.x + HORIZONTAL_PADDING, baseline), speaker.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(ink, opacity))

## The pair flirts while both are on the field; when one falls, the other reacts (src/03b_gore.js banterUpdate/banterDown).
func _advance_banter(dt: float) -> PackedStringArray:
	var journal := PackedStringArray()
	if not _banter_reply.is_empty():
		_banter_reply.remaining -= dt
		if _banter_reply.remaining <= 0.0:
			var reply := _banter_reply
			_banter_reply = {}
			if _banter_speaker_ready(reply.speaker):
				journal.append_array(_banter_say(reply.speaker, reply.text))
	_banter_timer -= dt
	if _banter_timer > 0.0 or not _banter_reply.is_empty():
		return journal
	var first := _speaker_by_companion(Banter.FIRST_ID)
	var second := _speaker_by_companion(Banter.SECOND_ID)
	if not _banter_speaker_ready(first) or not _banter_speaker_ready(second) or first.remaining > 0.0 or second.remaining > 0.0:
		_banter_timer = BANTER_RETRY_SECONDS
		return journal
	_banter_timer = _rng.randf_range(BANTER_INTERVAL.x, BANTER_INTERVAL.y)
	var index := _rng.randi_range(0, Banter.EXCHANGES.size() - 1)
	while index == _banter_last and Banter.EXCHANGES.size() > 1:
		index = _rng.randi_range(0, Banter.EXCHANGES.size() - 1)
	_banter_last = index
	var exchange: Array = Banter.EXCHANGES[index]
	var opener := first if exchange[0] == "g" else second
	var other := second if opener == first else first
	journal.append_array(_banter_say(opener, exchange[1]))
	_banter_reply = {"remaining": BANTER_REPLY_DELAY, "speaker": other, "text": exchange[2]}
	return journal

func _queue_down_reply(fallen: Dictionary) -> void:
	var lines: Array = Banter.DOWN_REPLIES.get(fallen.companion_id, [])
	if lines.is_empty():
		return
	var other := _speaker_by_companion(Banter.SECOND_ID if fallen.companion_id == Banter.FIRST_ID else Banter.FIRST_ID)
	if not _banter_speaker_ready(other):
		return
	_banter_reply = {"remaining": BANTER_DOWN_DELAY, "speaker": other, "text": lines[_rng.randi_range(0, lines.size() - 1)]}

func _banter_say(speaker: Dictionary, text: String) -> PackedStringArray:
	speaker.text = text
	speaker.remaining = BANTER_DURATION
	speaker.cooldown = BANTER_COOLDOWN
	return PackedStringArray([JOURNAL_LINE % [speaker.name, text]])

func _banter_speaker_ready(speaker: Dictionary) -> bool:
	if speaker.is_empty() or speaker.unit.is_empty():
		return false
	return not speaker.unit.dead and not speaker.unit.gone

func _speaker_by_companion(companion_id: String) -> Dictionary:
	for speaker: Dictionary in _speakers.values():
		if speaker.companion_id == companion_id:
			return speaker
	return {}

func _journal_line(speaker: Dictionary, kind: String) -> PackedStringArray:
	if _say(speaker, kind, true):
		return PackedStringArray([JOURNAL_LINE % [speaker.name, speaker.text]])
	return PackedStringArray()

func _say(speaker: Dictionary, kind: String, force: bool = false) -> bool:
	var lines: Array = speaker.lines.get(kind, speaker.lines.get(KILL, []) if kind == KILL_UNDEAD else [])
	if lines.is_empty():
		return false
	var kill := kind == KILL or kind == KILL_UNDEAD
	if not force:
		if kill and (speaker.cooldown > KILL_COOLDOWN_LIMIT or _rng.randf() > KILL_SPEECH_CHANCE):
			return false
		if not kill and speaker.cooldown > 0.0 and _rng.randf() > COOLDOWN_INTERRUPT_CHANCE:
			return false
	var line: String = lines[_rng.randi_range(0, lines.size() - 1)]
	if lines.size() > 1 and line == speaker.text:
		line = lines[_rng.randi_range(0, lines.size() - 1)]
	speaker.text = line
	speaker.remaining = INTRO_DURATION if kind in [START, SIEGE] else REPLY_DURATION
	speaker.cooldown = KILL_COOLDOWN if kill else GENERAL_COOLDOWN
	return true

static func _has_undead_appearance(units: Array[Dictionary], target_id: int) -> bool:
	for unit in units:
		if unit.id == target_id:
			return not str(unit.look.get("undead", "")).is_empty()
	return false

static func _enemy_near(unit: Dictionary, units: Array[Dictionary]) -> bool:
	for other in units:
		if other.side != unit.side and not other.dead and not other.gone and not other.fleeing:
			if Vector2(unit.position).distance_squared_to(other.position) < TAUNT_DISTANCE * TAUNT_DISTANCE:
				return true
	return false
