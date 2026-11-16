extends RefCounted
## Window sounds of the campaign: a click, coins for buying and selling, a short tune for a new level and the
## order signal (sfx in src/04_audio.js, called from src/06_*.js). Composition switches them with the sound setting.
const Bank = preload("res://apps/godot/presentation/battle/audio/sound_bank.gd")

static var enabled := true
static var played: Array[String] = [] # The last sounds, newest last; tests read it instead of listening.
static var _streams: Dictionary = {}

static func play(from: Node, kind: String) -> void:
	played.append(kind)
	if played.size() > 16:
		played.pop_front()
	if not enabled or from == null or not from.is_inside_tree():
		return
	if _streams.is_empty():
		_streams = Bank.ui_sounds()
	if not _streams.has(kind):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _streams[kind]
	player.volume_db = linear_to_db(Bank.MASTER_GAIN)
	player.finished.connect(player.queue_free)
	from.get_tree().root.add_child(player)
	player.play()
