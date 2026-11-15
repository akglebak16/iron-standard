extends Node
const Bank = preload("res://apps/godot/presentation/battle/audio/sound_bank.gd")

const SCALE := [146.83, 164.81, 174.61, 196.0, 220.0, 246.94]
const NOTE_INTERVAL := 0.5
const INTERVAL_MIN := 0.8
const INTERVAL_MAX := 1.5
const LOW_OCTAVE_CHANCE := 0.25
const DRUM_CHANCE := 0.5
const NOTE_SECONDS := 0.9
const NOTE_ATTACK := 0.04
const NOTE_GAIN := 0.06
const NOTE_CUTOFF := 500.0
const DRUM_START := 90.0
const DRUM_END := 40.0
const DRUM_SWEEP := 0.25
const DRUM_SECONDS := 0.3
const DRUM_GAIN := 0.35
const ECHO_SECONDS := 0.38
const ECHO_FEEDBACK := 0.45
const ECHO_TAPS := 6
const MUSIC_GAIN := 0.5
const NOTE_VOICES := 8
const DRUM_VOICES := 7
## Authored looping track; rendered by battle/tools/render_battle_theme.py (original work, CC0).
const THEME_PATH := "res://apps/godot/presentation/battle/audio/assets/battle_theme.ogg"

static var _notes: Array[AudioStreamWAV] = []
static var _drum: AudioStreamWAV
## Tests and comparisons may turn the authored track off to hear the procedural voice.
static var use_theme_asset := true
var _theme_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _until_note := 0.0
var _note_players: Array[AudioStreamPlayer] = []
var _drum_players: Array[AudioStreamPlayer] = []
var enabled := true:
	set(value):
		enabled = value
		for player in _note_players + _drum_players:
			player.stream_paused = not enabled
		if _theme_player:
			_theme_player.stream_paused = not enabled

func _ready() -> void:
	_rng.randomize()
	if enabled:
		_prepare()

func _exit_tree() -> void:
	for player in _note_players + _drum_players:
		player.stop()
		player.stream = null
	if _theme_player:
		_theme_player.stop()
		_theme_player.stream = null

func advance(dt: float) -> void:
	if not enabled or dt <= 0.0:
		return
	if _theme_player:
		return
	_until_note -= dt
	if _until_note > 0.0:
		return
	_until_note = NOTE_INTERVAL * _rng.randf_range(INTERVAL_MIN, INTERVAL_MAX)
	if _note_players.is_empty():
		_prepare()
	var pitch := _rng.randi_range(0, SCALE.size() - 1)
	if _rng.randf() < LOW_OCTAVE_CHANCE:
		pitch += SCALE.size()
	_play(_note_players, _notes[pitch])
	if _rng.randf() < DRUM_CHANCE:
		_play(_drum_players, _drum)

func _prepare() -> void:
	if use_theme_asset and _theme_player == null and _start_theme():
		return
	if _notes.is_empty():
		for octave in [1.0, 0.5]:
			for pitch in SCALE:
				_notes.append(_note(pitch * octave))
		_drum = _make_drum()
	for i in NOTE_VOICES:
		_note_players.append(_make_player())
	for i in DRUM_VOICES:
		_drum_players.append(_make_player())

## The asset replaces the generated notes and drum; reactions to battle events stay in combat_audio.gd.
func _start_theme() -> bool:
	if not ResourceLoader.exists(THEME_PATH):
		return false
	var theme := load(THEME_PATH) as AudioStreamOggVorbis
	if theme == null:
		return false
	theme.loop = true
	_theme_player = _make_player()
	_theme_player.stream = theme
	_theme_player.play()
	return true

func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = linear_to_db(Bank.MASTER_GAIN * MUSIC_GAIN)
	add_child(player)
	return player

static func _play(players: Array[AudioStreamPlayer], stream: AudioStreamWAV) -> void:
	for player in players:
		if not player.playing:
			player.stream = stream
			player.play()
			return

static func _note(frequency: float) -> AudioStreamWAV:
	var frames := ceili(NOTE_SECONDS * Bank.MIX_RATE)
	var dry := PackedFloat32Array()
	dry.resize(frames)
	var cutoff := 1.0 - exp(-TAU * NOTE_CUTOFF / Bank.MIX_RATE)
	var filtered := 0.0
	for i in frames:
		var time := float(i) / Bank.MIX_RATE
		var phase := fposmod(time * frequency, 1.0)
		filtered += (phase * 2.0 - 1.0 - filtered) * cutoff
		var gain := NOTE_GAIN * time / NOTE_ATTACK if time < NOTE_ATTACK else _decay(NOTE_GAIN, (time - NOTE_ATTACK) / (NOTE_SECONDS - NOTE_ATTACK))
		dry[i] = filtered * gain
	return _echo(dry)

static func _make_drum() -> AudioStreamWAV:
	var frames := ceili(DRUM_SECONDS * Bank.MIX_RATE)
	var dry := PackedFloat32Array()
	dry.resize(frames)
	var phase := 0.0
	for i in frames:
		var time := float(i) / Bank.MIX_RATE
		dry[i] = sin(phase * TAU) * _decay(DRUM_GAIN, time / DRUM_SECONDS)
		var frequency := DRUM_START * pow(DRUM_END / DRUM_START, minf(time / DRUM_SWEEP, 1.0))
		phase += frequency / Bank.MIX_RATE
	return _echo(dry)

static func _decay(gain: float, progress: float) -> float:
	return gain * pow(Bank.ENVELOPE_FLOOR / gain, progress)

static func _echo(dry: PackedFloat32Array) -> AudioStreamWAV:
	var samples := dry.duplicate()
	var delay := roundi(ECHO_SECONDS * Bank.MIX_RATE)
	samples.resize(dry.size() + delay * ECHO_TAPS)
	var gain := 1.0
	for tap in range(1, ECHO_TAPS + 1):
		var offset := tap * delay
		for i in dry.size():
			samples[offset + i] += dry[i] * gain
		gain *= ECHO_FEEDBACK
	return Bank.pcm_stream(samples)
