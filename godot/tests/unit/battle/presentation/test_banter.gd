extends SceneTree
## src/03b_gore.js banterUpdate/banterDown: the Glebio/Zahariy pair talks to each other.
const Dialogue = preload("res://apps/godot/presentation/battle/companion_dialogue.gd")
const Banter = preload("res://apps/godot/presentation/battle/banter_lines.gd")
const Event = preload("res://core/battle/combat_event.gd")
const GLEBIO_UNIT := 4
const ZAHARIY_UNIT := 5
const FOE := 9
const VOICE := {"start": ["Поле"]}

func _initialize() -> void:
	_check_exchange()
	_check_waits_and_dead_partner()
	_check_down_reply()
	_check_voice_rarity_settings()
	print("Banter tests passed")
	quit(0)

func _dialogue() -> Dialogue:
	var dialogue := Dialogue.new()
	dialogue._rng.seed = 5
	dialogue.configure({
		GLEBIO_UNIT: {"name": "Глебио", "companion_id": "glebio", "lines": VOICE},
		ZAHARIY_UNIT: {"name": "Захарий", "companion_id": "zahariy", "lines": VOICE},
	})
	return dialogue

func _frame() -> Array[Dictionary]:
	var frame: Array[Dictionary] = []
	for id in [GLEBIO_UNIT, ZAHARIY_UNIT]:
		frame.append({"id": id, "side": 0, "position": Vector2.ZERO, "dead": false, "gone": false, "fleeing": false, "look": {}, "mounted": false})
	frame.append({"id": FOE, "side": 1, "position": Vector2(2000, 0), "dead": false, "gone": false, "fleeing": false, "look": {}, "mounted": false})
	return frame

func _lines_in(journal: PackedStringArray) -> Array:
	return Array(journal).filter(func(l: String): return not l.contains("Поле"))

func _check_exchange() -> void:
	var dialogue := _dialogue()
	var frame := _frame()
	var lines := []
	var t := 0.0
	while lines.is_empty() and t < 30.0:
		lines.append_array(_lines_in(dialogue.advance(0.1, frame, [], false)))
		t += 0.1
	assert(t >= Dialogue.BANTER_FIRST_DELAY.x - 0.2 and t <= Dialogue.BANTER_FIRST_DELAY.y + 0.2, "First exchange comes 9-14 s into the battle")
	assert(lines.size() == 1, "The opener speaks first; the reply waits")
	var opener_text: String = lines[0]
	var matched := false
	for exchange in Banter.EXCHANGES:
		matched = matched or opener_text.ends_with("«%s»" % exchange[1])
	assert(matched)
	var reply := PackedStringArray()
	for i in 35:
		reply.append_array(dialogue.advance(0.1, frame, [], false))
	var replies := _lines_in(reply)
	assert(replies.size() == 1, "The partner answers about 3.2 s later")
	var reply_ok := false
	for exchange in Banter.EXCHANGES:
		reply_ok = reply_ok or replies[0].ends_with("«%s»" % exchange[2])
	assert(reply_ok)
	assert(dialogue._banter_timer > Dialogue.BANTER_INTERVAL.x - 5.0 and dialogue._banter_timer <= Dialogue.BANTER_INTERVAL.y)
	# Consecutive exchanges never repeat.
	var seen := []
	for round in 12:
		var batch := PackedStringArray()
		dialogue._banter_timer = 0.0
		dialogue._speakers[GLEBIO_UNIT].remaining = 0.0
		dialogue._speakers[ZAHARIY_UNIT].remaining = 0.0
		batch.append_array(dialogue.advance(0.01, frame, [], false))
		seen.append(dialogue._banter_last)
		for i in 40:
			dialogue.advance(0.1, frame, [], false)
	for i in range(1, seen.size()):
		assert(seen[i] != seen[i - 1])

func _check_waits_and_dead_partner() -> void:
	var dialogue := _dialogue()
	var frame := _frame()
	dialogue._banter_timer = 0.0
	frame[1].dead = true
	var journal := dialogue.advance(0.1, frame, [], false)
	assert(_lines_in(journal).is_empty() and is_equal_approx(dialogue._banter_timer, Dialogue.BANTER_RETRY_SECONDS - 0.0) or dialogue._banter_timer > 2.0)
	frame[1].dead = false
	dialogue._speakers[GLEBIO_UNIT].remaining = 1.0
	dialogue._banter_timer = 0.0
	assert(_lines_in(dialogue.advance(0.0, frame, [], false)).is_empty(), "Nobody interrupts a speaking partner")
	# A different companion pair never banters.
	var other := Dialogue.new()
	other.configure({1: {"name": "A", "companion_id": "ingrid", "lines": VOICE}, 2: {"name": "B", "companion_id": "halvdan", "lines": VOICE}})
	other._banter_timer = 0.0
	assert(other.advance(0.1, [{"id": 1, "side": 0, "position": Vector2.ZERO, "dead": false, "gone": false, "fleeing": false, "look": {}}, {"id": 2, "side": 0, "position": Vector2.ZERO, "dead": false, "gone": false, "fleeing": false, "look": {}}], [], false).is_empty())

func _check_down_reply() -> void:
	var dialogue := _dialogue()
	var frame := _frame()
	dialogue.advance(0.0, frame, [], false)
	frame[0].dead = true
	var down := {"kind": Event.Kind.DOWN, "target_id": GLEBIO_UNIT, "source_id": FOE, "source_alive": true}
	var first := dialogue.advance(0.0, frame, [down], false)
	assert(first.size() == 0, "Glebio has no 'down' lines in this fixture")
	var journal := PackedStringArray()
	for i in 20:
		journal.append_array(dialogue.advance(0.1, frame, [], false))
	var replies := Array(journal).filter(func(l: String): return l.begins_with("Захарий"))
	assert(replies.size() == 1)
	var ok := false
	for line in Banter.DOWN_REPLIES.glebio:
		ok = ok or replies[0].ends_with("«%s»" % line)
	assert(ok)
	# Dead survivors stay silent.
	var silent := _dialogue()
	var silent_frame := _frame()
	silent.advance(0.0, silent_frame, [], false)
	silent_frame[0].dead = true
	silent_frame[1].dead = true
	silent.advance(0.0, silent_frame, [down], false)
	var after := PackedStringArray()
	for i in 20:
		after.append_array(silent.advance(0.1, silent_frame, [], false))
	assert(after.is_empty())

func _check_voice_rarity_settings() -> void:
	assert(Dialogue.TAUNT_INTERVAL == Vector2(24, 40) and Dialogue.INITIAL_TAUNT_DELAY == Vector2(24, 36))
	assert(Dialogue.KILL_COOLDOWN == 3.2 and Dialogue.GENERAL_COOLDOWN == 6.0)
	var dialogue := Dialogue.new()
	dialogue._rng.seed = 3
	dialogue.configure({1: {"name": "A", "companion_id": "x", "lines": {"kill": ["Ха"]}}})
	var spoke := 0
	for i in 200:
		dialogue._speakers[1].cooldown = 0.0
		dialogue._speakers[1].remaining = 0.0
		if dialogue._say(dialogue._speakers[1], "kill"):
			spoke += 1
	assert(spoke > 70 and spoke < 130, "Only about half of the kills get a line")
