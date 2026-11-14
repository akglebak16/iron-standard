extends SceneTree
const Dialogue = preload("res://battle/presentation/companion_dialogue.gd")
const Event = preload("res://battle/combat_event.gd")
const SPEAKER_ID := 3
const FOE_ID := 8
const VOICE := {"start": ["Поле"], "siege": ["Стена"], "kill": ["Победа"], "killUndead": ["Кости"], "hurt": ["Больно"], "taunt": ["Подойди"], "down": ["Я ранен"]}

func _initialize() -> void:
	var dialogue := Dialogue.new()
	_check_intro(dialogue)
	_check_events(dialogue)
	_check_taunt(dialogue)
	print("Companion dialogue tests passed")
	quit(0)

func _check_intro(dialogue: Dialogue) -> void:
	var frame := _frame()
	_reset(dialogue)
	assert(dialogue.advance(Dialogue.START_DELAY.x * 0.5, frame, [], true).is_empty())
	assert(dialogue.advance(Dialogue.START_DELAY.y, frame, [], true) == PackedStringArray(["Спутник: «Стена»"]))
	assert(dialogue.has_bubbles())
	assert(dialogue.advance(Dialogue.INTRO_DURATION, frame, [], true).is_empty())
	assert(not dialogue.has_bubbles())
	_reset(dialogue, {"start": ["Поле"]})
	assert(dialogue.advance(Dialogue.START_DELAY.y, frame, [], true) == PackedStringArray(["Спутник: «Поле»"]))
	_reset(dialogue)
	assert(dialogue.advance(Dialogue.START_DELAY.y, frame, [], false, true).is_empty())
	assert(not dialogue.has_bubbles())

func _check_events(dialogue: Dialogue) -> void:
	var frame := _frame()
	_reset(dialogue)
	var hit := {"kind": Event.Kind.HIT, "target_id": SPEAKER_ID, "lethal": false, "damage_fraction": Dialogue.HURT_DAMAGE_FRACTION}
	dialogue.advance(0.0, frame, [hit], false)
	assert(not dialogue.has_bubbles())
	hit.damage_fraction += 0.1
	hit.lethal = true
	dialogue.advance(0.0, frame, [hit], false)
	assert(not dialogue.has_bubbles())
	hit.lethal = false
	_seed_next_roll_below(dialogue, Dialogue.HURT_CHANCE)
	dialogue.advance(0.0, frame, [hit], false)
	assert(_speaker_text(dialogue) == "Больно")
	var kill := {"kind": Event.Kind.DOWN, "target_id": FOE_ID, "source_id": SPEAKER_ID, "source_alive": true}
	dialogue.advance(0.0, frame, [kill], false)
	assert(_speaker_text(dialogue) == "Больно")
	frame[1].look = {"undead": "skel"}
	_reset(dialogue)
	_seed_next_roll_below(dialogue, Dialogue.UNDEAD_KILL_CHANCE)
	dialogue.advance(0.0, frame, [kill], false)
	assert(_speaker_text(dialogue) == "Кости")
	_reset(dialogue, {"kill": ["Победа"]})
	_seed_next_roll_below(dialogue, Dialogue.UNDEAD_KILL_CHANCE)
	dialogue.advance(0.0, frame, [kill], false)
	assert(_speaker_text(dialogue) == "Победа")
	_reset(dialogue)
	kill.source_alive = false
	dialogue.advance(0.0, frame, [kill], false)
	assert(not dialogue.has_bubbles())
	frame[0].dead = true
	var down := {"kind": Event.Kind.DOWN, "target_id": SPEAKER_ID, "source_id": FOE_ID, "source_alive": true}
	assert(dialogue.advance(0.0, frame, [down], false, true) == PackedStringArray(["Спутник: «Я ранен»"]))
	dialogue.age(Dialogue.REPLY_DURATION)
	assert(not dialogue.has_bubbles())

func _check_taunt(dialogue: Dialogue) -> void:
	var frame := _frame()
	_reset(dialogue, {"taunt": ["Подойди"]})
	frame[1].fleeing = true
	dialogue.advance(Dialogue.INITIAL_TAUNT_DELAY.y, frame, [], false)
	assert(not dialogue.has_bubbles())
	frame[1].fleeing = false
	frame[1].position = Vector2.RIGHT * Dialogue.TAUNT_DISTANCE
	dialogue.advance(Dialogue.TAUNT_INTERVAL.y, frame, [], false)
	assert(not dialogue.has_bubbles())
	frame[1].position = Vector2.RIGHT
	dialogue.advance(Dialogue.TAUNT_INTERVAL.y, frame, [], false)
	assert(_speaker_text(dialogue) == "Подойди" and dialogue.has_bubbles())

func _reset(dialogue: Dialogue, lines: Dictionary = VOICE) -> void:
	dialogue._rng.seed = 17
	dialogue.configure({SPEAKER_ID: {"name": "Спутник", "lines": lines}})

func _seed_next_roll_below(dialogue: Dialogue, limit: float) -> void:
	for seed_value in 100:
		dialogue._rng.seed = seed_value
		var before := dialogue._rng.state
		if dialogue._rng.randf() < limit:
			dialogue._rng.state = before
			return
	assert(false, "Expected a deterministic sample below the requested probability")

func _speaker_text(dialogue: Dialogue) -> String:
	return dialogue._speakers[SPEAKER_ID].text

func _frame() -> Array[Dictionary]:
	return [
		{"id": SPEAKER_ID, "side": 0, "position": Vector2.ZERO, "dead": false, "gone": false, "fleeing": false, "look": {}},
		{"id": FOE_ID, "side": 1, "position": Vector2.RIGHT, "dead": false, "gone": false, "fleeing": false, "look": {}},
	]
