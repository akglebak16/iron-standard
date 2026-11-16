extends RefCounted
## Short PCM effects synthesized from the tone and noise layers in src/04_audio.js.
enum Sound { HIT, CLANG, SWING, BOW, ARROW_HIT, THUNK, DOWN, CHARGE, ORDER, HORN, ENEMY_HORN, WEAPON_CLICK }
enum Wave { SINE, TRIANGLE, SQUARE, SAW }
enum Filter { LOW, HIGH, BAND }

const MIX_RATE := 22050
const MASTER_GAIN := 0.55
const ATTACK_SECONDS := 0.006
const ENVELOPE_FLOOR := 0.0001
const PCM_MAX := 32767.0
const NOISE_SEED := 4171
const WEAPON_CLICK_SECONDS := 0.05
const WEAPON_CLICK_PITCH := Vector2(660, 440)
const WEAPON_CLICK_VOLUME := 0.06
const MIN_INTERVALS := [0.05, 0.06, 0.08, 0.05, 0.05, 0.06, 0.08, 0.1, 0.0, 0.0, 0.0, 0.0]
const HORN_PARTIALS := [1.0, 1.005, 2.01]
const HORN_START_RATIO := 0.96
const HORN_RAMP_SECONDS := 0.35
const HORN_ATTACK_SECONDS := 0.18
const HORN_SUSTAIN_SECONDS := 1.0
const HORN_DECAY_END_SECONDS := 1.7
const HORN_LENGTH := 1.8
const HORN_CUTOFF := 900.0
const HORN_GAIN := 0.11

## sfx('clang') draws its main tone from 1900–2300 Hz each time; five pre-rendered steps across that range.
const CLANG_PITCHES := [1900.0, 2000.0, 2100.0, 2200.0, 2300.0]

static func clang_variants() -> Array[AudioStreamWAV]:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	var variants: Array[AudioStreamWAV] = []
	for pitch: float in CLANG_PITCHES:
		variants.append(_render([_tone(pitch, pitch, 0.2, Wave.TRIANGLE, 0.22), _tone(2900, 2900, 0.12, Wave.SQUARE, 0.05)], [_noise(3000, 3000, 0.05, Filter.HIGH, 0.25)], rng))
	return variants

## Window sounds of the campaign (sfx 'click', 'coin', 'level', 'order' in src/04_audio.js).
static func ui_sounds() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	return {
		"click": _render([_tone(660, 440, 0.05, Wave.SQUARE, 0.06)], [], rng),
		"coin": _render([_tone(1320, 1320, 0.08, Wave.TRIANGLE, 0.14), _tone(1760, 1760, 0.18, Wave.TRIANGLE, 0.14, 0.07)], [], rng),
		"level": _render([_tone(392, 392, 0.2, Wave.TRIANGLE, 0.2), _tone(523, 523, 0.2, Wave.TRIANGLE, 0.2, 0.15), _tone(659, 659, 0.4, Wave.TRIANGLE, 0.2, 0.3)], [], rng),
		"order": _render([_tone(392, 392, 0.09, Wave.TRIANGLE, 0.18), _tone(523, 523, 0.12, Wave.TRIANGLE, 0.18, 0.08)], [], rng),
	}

static func build() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	return {
		Sound.HIT: _render([_tone(130, 60, 0.12, Wave.SINE, 0.5)], [_noise(1400, 300, 0.09, Filter.LOW, 0.55)], rng),
		Sound.CLANG: _render([_tone(2100, 2100, 0.2, Wave.TRIANGLE, 0.22), _tone(2900, 2900, 0.12, Wave.SQUARE, 0.05)], [_noise(3000, 3000, 0.05, Filter.HIGH, 0.25)], rng),
		Sound.SWING: _render([], [_noise(500, 1800, 0.14, Filter.BAND, 0.25, 2.0)], rng),
		Sound.BOW: _render([_tone(240, 120, 0.07, Wave.TRIANGLE, 0.1)], [_noise(2500, 900, 0.07, Filter.HIGH, 0.22)], rng),
		Sound.ARROW_HIT: _render([_tone(220, 110, 0.08, Wave.SINE, 0.3)], [_noise(1800, 400, 0.05, Filter.LOW, 0.4)], rng),
		Sound.THUNK: _render([_tone(160, 90, 0.07, Wave.SQUARE, 0.12)], [], rng),
		Sound.DOWN: _render([_tone(170, 55, 0.3, Wave.SAW, 0.13)], [_noise(700, 150, 0.18, Filter.LOW, 0.25)], rng),
		Sound.CHARGE: _render([_tone(80, 40, 0.2, Wave.SINE, 0.7)], [_noise(500, 120, 0.14, Filter.LOW, 0.5)], rng),
		Sound.ORDER: _render([_tone(392, 392, 0.09, Wave.TRIANGLE, 0.18), _tone(523, 523, 0.12, Wave.TRIANGLE, 0.18, 0.08)], [], rng),
		Sound.HORN: _horn(146.0),
		Sound.ENEMY_HORN: _horn(110.0),
		Sound.WEAPON_CLICK: _render([_tone(WEAPON_CLICK_PITCH.x, WEAPON_CLICK_PITCH.y, WEAPON_CLICK_SECONDS, Wave.SQUARE, WEAPON_CLICK_VOLUME)], [], rng),
	}

static func _tone(start: float, finish: float, length: float, wave: Wave, volume: float, delay: float = 0.0) -> Dictionary:
	return {"start": start, "finish": finish, "length": length, "wave": wave, "volume": volume, "delay": delay}

static func _noise(start: float, finish: float, length: float, filter: Filter, volume: float, resonance: float = 1.0) -> Dictionary:
	return {"start": start, "finish": finish, "length": length, "filter": filter, "volume": volume, "resonance": resonance}

static func _render(tones: Array, noises: Array, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for layer in tones + noises:
		var frames := ceili(float(layer.length) * MIX_RATE)
		var offset := roundi(float(layer.get("delay", 0.0)) * MIX_RATE)
		if frames + offset > samples.size():
			samples.resize(frames + offset)
		if layer.has("wave"):
			_mix_tone(samples, layer, frames, offset)
		else:
			_mix_noise(samples, layer, frames, rng)
	return pcm_stream(samples)

static func pcm_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, roundi(clampf(samples[i], -1.0, 1.0) * PCM_MAX))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = pcm
	return stream

static func _mix_tone(samples: PackedFloat32Array, layer: Dictionary, frames: int, offset: int) -> void:
	var phase := 0.0
	var attack := roundi(ATTACK_SECONDS * MIX_RATE)
	for i in frames:
		var progress := float(i) / frames
		var frequency: float = layer.start * pow(layer.finish / layer.start, progress)
		var envelope: float = layer.volume * float(i) / attack if i < attack else _decay(layer.volume, float(i - attack) / (frames - attack))
		var value := sin(phase * TAU)
		match layer.wave:
			Wave.TRIANGLE: value = 1.0 - 4.0 * absf(phase - 0.5)
			Wave.SQUARE: value = 1.0 if phase < 0.5 else -1.0
			Wave.SAW: value = phase * 2.0 - 1.0
		samples[i + offset] += value * envelope
		phase = fposmod(phase + frequency / MIX_RATE, 1.0)

static func _mix_noise(samples: PackedFloat32Array, layer: Dictionary, frames: int, rng: RandomNumberGenerator) -> void:
	# Biquad with a sweeping cutoff, matching the source's low, high and band pass layers.
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in frames:
		var progress := float(i) / frames
		var frequency: float = layer.start * pow(layer.finish / layer.start, progress)
		var angle := TAU * frequency / MIX_RATE
		var cosine := cos(angle)
		var alpha: float = sin(angle) / (2.0 * layer.resonance)
		var b0 := (1.0 - cosine) * 0.5
		var b1 := 2.0 * b0
		var b2 := b0
		match layer.filter:
			Filter.HIGH:
				b0 = (1.0 + cosine) * 0.5
				b1 = -2.0 * b0
				b2 = b0
			Filter.BAND:
				b0 = alpha
				b1 = 0.0
				b2 = -alpha
		var input := rng.randf_range(-1.0, 1.0)
		var value := (b0 * input + b1 * x1 + b2 * x2 + 2.0 * cosine * y1 - (1.0 - alpha) * y2) / (1.0 + alpha)
		x2 = x1
		x1 = input
		y2 = y1
		y1 = value
		samples[i] += value * _decay(layer.volume, progress)

static func _decay(volume: float, progress: float) -> float:
	return volume * pow(ENVELOPE_FLOOR / volume, progress)

static func _horn(pitch: float) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(ceili(HORN_LENGTH * MIX_RATE))
	var filter_rate := 1.0 - exp(-TAU * HORN_CUTOFF / MIX_RATE)
	for partial in HORN_PARTIALS:
		var phase := 0.0
		var filtered := 0.0
		var gain: float = HORN_GAIN / partial
		for i in samples.size():
			var time := float(i) / MIX_RATE
			var ramp := minf(time / HORN_RAMP_SECONDS, 1.0)
			var frequency: float = pitch * partial * lerpf(HORN_START_RATIO, 1.0, ramp)
			filtered += (phase * 2.0 - 1.0 - filtered) * filter_rate
			var envelope := gain * minf(time / HORN_ATTACK_SECONDS, 1.0)
			if time > HORN_SUSTAIN_SECONDS:
				var release := minf((time - HORN_SUSTAIN_SECONDS) / (HORN_DECAY_END_SECONDS - HORN_SUSTAIN_SECONDS), 1.0)
				envelope = _decay(gain, release)
			samples[i] += filtered * envelope
			phase = fposmod(phase + frequency / MIX_RATE, 1.0)
	return pcm_stream(samples)
