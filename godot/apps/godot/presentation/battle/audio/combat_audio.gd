extends Node
const Event = preload("res://core/battle/combat_event.gd")
const Bank = preload("res://apps/godot/presentation/battle/audio/sound_bank.gd")
const Config = preload("res://core/battle/config.gd")

const NEAR_GAIN := 1.15
const ATTENUATION_DISTANCE := 900.0
const MIN_DISTANCE_GAIN := 0.06
const MAX_VOICES := 12
var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			for voice in _voices:
				voice.stop()

static var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _last_played := {}
var _clock := 0.0

func _ready() -> void:
	if _bank.is_empty():
		_bank = Bank.build()
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)

func _exit_tree() -> void:
	for voice in _voices:
		voice.stop()
		voice.stream = null

func advance(dt: float, events: Array[Dictionary], listener: Vector2) -> void:
	_clock += dt
	if not enabled:
		return
	for event in events:
		var sound := sound_for(event)
		if sound < 0:
			continue
		if _clock - float(_last_played.get(sound, -INF)) < Bank.MIN_INTERVALS[sound]:
			continue
		for voice in _voices:
			if voice.playing:
				continue
			voice.stream = _bank[sound]
			voice.volume_db = linear_to_db(Bank.MASTER_GAIN * distance_gain(event, listener))
			voice.play()
			_last_played[sound] = _clock
			break

static func sound_for(event: Dictionary) -> int:
	match event.kind:
		Event.Kind.BATTLE_STARTED: return Bank.Sound.HORN
		Event.Kind.ORDER_APPLIED: return Bank.Sound.HORN if event.order == Config.ORDER_CHARGE else Bank.Sound.ORDER
		Event.Kind.ENEMY_CHARGE, Event.Kind.WALL_ALERT: return Bank.Sound.ENEMY_HORN
		Event.Kind.BATTLE_DECIDED: return Bank.Sound.HORN if event.won else Bank.Sound.ENEMY_HORN
		Event.Kind.STONE_THROWN: return Bank.Sound.SWING
		Event.Kind.STONE_LANDED: return Bank.Sound.CHARGE
		Event.Kind.OIL_POURED: return Bank.Sound.CLANG
		Event.Kind.RESERVE_WAVE: return Bank.Sound.ENEMY_HORN if event.side == 1 else Bank.Sound.HORN
		Event.Kind.WEAPON_SWAPPED: return Bank.Sound.WEAPON_CLICK
		Event.Kind.SHOT: return Bank.Sound.BOW
		Event.Kind.SWING: return Bank.Sound.SWING
		Event.Kind.CHARGE: return Bank.Sound.CHARGE
		Event.Kind.DOWN: return Bank.Sound.DOWN
		Event.Kind.BLOCK: return Bank.Sound.THUNK if event.attack == Event.Attack.PROJECTILE else Bank.Sound.CLANG
		Event.Kind.HIT:
			if event.attack == Event.Attack.PROJECTILE:
				return Bank.Sound.ARROW_HIT
			if event.attack == Event.Attack.MELEE or event.attack == Event.Attack.COUNTER:
				return Bank.Sound.HIT
	return -1

static func distance_gain(event: Dictionary, listener: Vector2) -> float:
	if not event.has("position") or event.kind in [Event.Kind.SWING, Event.Kind.WEAPON_SWAPPED] or event.get("target_hero", false):
		return 1.0
	var position: Vector2 = event.position
	return clampf(NEAR_GAIN - listener.distance_to(position) / ATTENUATION_DISTANCE, MIN_DISTANCE_GAIN, 1.0)
