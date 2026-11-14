extends SceneTree
const Audio = preload("res://battle/presentation/audio/combat_audio.gd")
const Bank = preload("res://battle/presentation/audio/sound_bank.gd")
const Event = preload("res://battle/combat_event.gd")

func _initialize() -> void:
	var bank := Bank.build()
	assert(bank.size() == Bank.Sound.size())
	var distinct := {}
	for stream: AudioStreamWAV in bank.values():
		assert(stream.get_length() >= 0.07 and stream.get_length() <= 0.31)
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
	print("Combat audio tests passed")
	quit(0)
