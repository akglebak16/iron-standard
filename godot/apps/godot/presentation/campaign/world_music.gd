extends Node
## Map and title music (musicTick(dt, 'world') in src/04_audio.js): soft triangle notes on a D Dorian scale every
## 1.6 s × 0.8–1.5 through a 900 Hz low-pass, and a 73.4 Hz drone under four notes in ten. Plays only while both
## sound and music are on, like the browser (AU.on && AU.music).
const Bank = preload("res://apps/godot/presentation/battle/audio/sound_bank.gd")

const SCALE := [146.83, 164.81, 174.61, 196.0, 220.0, 246.94, 261.63, 293.66, 349.23]
const NOTE_INTERVAL := 1.6
const INTERVAL_MIN := 0.8
const INTERVAL_MAX := 1.5
const LOW_OCTAVE_CHANCE := 0.25
const NOTE_SECONDS := 2.6
const NOTE_ATTACK := 0.04
const NOTE_GAIN := 0.09
const NOTE_CUTOFF := 900.0
const DRONE_CHANCE := 0.4
const DRONE_FREQUENCY := 73.4
const DRONE_ATTACK := 0.8
const DRONE_SECONDS := 4.0
const DRONE_GAIN := 0.1
const MUSIC_GAIN := 0.5
const NOTE_VOICES := 4
const DRONE_VOICES := 3

static var _notes: Array[AudioStreamWAV] = []
static var _drone: AudioStreamWAV
var _rng := RandomNumberGenerator.new()
var _until_note := 0.0
var _note_players: Array[AudioStreamPlayer] = []
var _drone_players: Array[AudioStreamPlayer] = []
## Notes played since creation; tests read it instead of listening.
var notes_played := 0
var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			for player in _note_players + _drone_players:
				player.stop()

func _ready() -> void:
	_rng.randomize()

func _process(dt: float) -> void:
	advance(dt)

func advance(dt: float) -> void:
	if not enabled or dt <= 0.0:
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
	notes_played += 1
	if _rng.randf() < DRONE_CHANCE:
		_play(_drone_players, _drone)

func _exit_tree() -> void:
	for player in _note_players + _drone_players:
		player.stop()
		player.stream = null

func _prepare() -> void:
	if _notes.is_empty():
		for octave in [1.0, 0.5]:
			for pitch in SCALE:
				_notes.append(_note(pitch * octave))
		_drone = _make_drone()
	for i in NOTE_VOICES:
		_note_players.append(_make_player())
	for i in DRONE_VOICES:
		_drone_players.append(_make_player())

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
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var cutoff := 1.0 - exp(-TAU * NOTE_CUTOFF / Bank.MIX_RATE)
	var filtered := 0.0
	for i in frames:
		var time := float(i) / Bank.MIX_RATE
		var phase := fposmod(time * frequency, 1.0)
		var triangle := 1.0 - 4.0 * absf(phase - 0.5)
		filtered += (triangle - filtered) * cutoff
		var gain := NOTE_GAIN * time / NOTE_ATTACK if time < NOTE_ATTACK else _decay(NOTE_GAIN, (time - NOTE_ATTACK) / (NOTE_SECONDS - NOTE_ATTACK))
		samples[i] = filtered * gain
	return Bank.pcm_stream(samples)

static func _make_drone() -> AudioStreamWAV:
	var frames := ceili(DRONE_SECONDS * Bank.MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i in frames:
		var time := float(i) / Bank.MIX_RATE
		var gain := DRONE_GAIN * time / DRONE_ATTACK if time < DRONE_ATTACK else _decay(DRONE_GAIN, (time - DRONE_ATTACK) / (DRONE_SECONDS - DRONE_ATTACK))
		samples[i] = sin(TAU * DRONE_FREQUENCY * time) * gain
	return Bank.pcm_stream(samples)

static func _decay(gain: float, progress: float) -> float:
	return gain * pow(Bank.ENVELOPE_FLOOR / gain, progress)
