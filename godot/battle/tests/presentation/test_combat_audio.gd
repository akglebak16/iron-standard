extends SceneTree
const Audio = preload("res://battle/presentation/audio/combat_audio.gd")
const Bank = preload("res://battle/presentation/audio/sound_bank.gd")
const Event = preload("res://battle/combat_event.gd")

func _initialize() -> void:
	var bank := Bank.build()
	assert(bank.size() == Bank.Sound.size())
	var distinct := {}
	for sound in bank:
		var stream: AudioStreamWAV = bank[sound]
		var expected_long: bool = sound == Bank.Sound.HORN or sound == Bank.Sound.ENEMY_HORN
		assert(stream.get_length() >= 0.07 and stream.get_length() <= (1.81 if expected_long else 0.31))
		assert(not expected_long or stream.get_length() >= 1.8)
		var audible := false
		for i in range(0, stream.data.size(), 2):
			if absi(stream.data.decode_s16(i)) > 100:
				audible = true
				break
		assert(audible)
		distinct[hash(stream.data)] = true
	assert(distinct.size() == bank.size())
	var block := {"kind": Event.Kind.BLOCK, "attack": Event.Attack.PROJECTILE, "position": Vector2(450, 0), "target_hero": false}
	assert(Audio.sound_for(block) == Bank.Sound.THUNK)
	assert(is_equal_approx(Audio.distance_gain(block, Vector2.ZERO), 0.65))
	block.attack = Event.Attack.MELEE
	block.target_hero = true
	assert(Audio.sound_for(block) == Bank.Sound.CLANG and Audio.distance_gain(block, Vector2.ZERO) == 1.0)
	assert(Audio.sound_for({"kind": Event.Kind.ORDER_APPLIED, "order": "hold"}) == Bank.Sound.ORDER)
	assert(Audio.sound_for({"kind": Event.Kind.ORDER_APPLIED, "order": "charge"}) == Bank.Sound.HORN)
	assert(Audio.sound_for({"kind": Event.Kind.WALL_ALERT}) == Bank.Sound.ENEMY_HORN)
	assert(Audio.distance_gain({"kind": Event.Kind.BATTLE_STARTED}, Vector2(3000, 1000)) == 1.0)
	print("Combat audio tests passed")
	quit(0)
