extends Node
## Haptics + squishy sounds.
##
## Sounds are synthesised at startup so the project works without audio files.
## To use your own, drop .wav/.ogg files into assets/audio/ named
## squelch*.ogg / boing*.ogg / pop*.ogg / plop*.ogg - they replace the
## synthesised ones (several files per kind = random variation).

const MIX_RATE := 22050
const VOICES := 10
const AUDIO_DIR := "res://assets/audio/"

var _streams := {}          # kind -> Array[AudioStream]
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_haptic_ms := 0
var _last_sound_ms := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_streams = {
		"squelch": [_synth_squelch(0.22, 1.0), _synth_squelch(0.16, 1.3)],
		"boing": [_synth_boing(0.42, 210.0), _synth_boing(0.36, 260.0)],
		"pop": [_synth_pop()],
		"plop": [_synth_boing(0.6, 150.0)],
		"wobble": [_synth_wobble(0.6, 95.0, 6.5), _synth_wobble(0.5, 120.0, 8.0)],
	}
	_load_custom_audio()


## Impact feedback scaled by speed (m/s). `wobble_hz` adds a decaying "tail"
## of haptic pulses in time with the jelly's wobble, so you feel it jiggle.
func impact(speed: float, wobble_hz: float = 0.0) -> void:
	var s := clampf((speed - 0.6) / 8.0, 0.0, 1.0)
	if s <= 0.02:
		return
	vibrate(int(lerpf(12, 45, s)), lerpf(0.25, 1.0, s))
	play("boing" if speed > 4.0 and randf() < 0.6 else "squelch", lerpf(-18.0, 0.0, s), 90)
	if speed > 2.5:
		play("wobble", lerpf(-16.0, -4.0, s), 250)
	if wobble_hz > 0.0 and s > 0.15:
		_wobble_tail(s, wobble_hz)


func _wobble_tail(strength: float, hz: float) -> void:
	var amp := lerpf(0.25, 0.8, strength)
	for i in 3:
		amp *= 0.55
		# Not ignoring time_scale: in slow-mo the pulses slow down with the wobble.
		await get_tree().create_timer(1.0 / hz, true, false, false).timeout
		if amp < 0.08:
			return
		_last_haptic_ms = 0
		vibrate(int(lerpf(8, 20, amp)), amp)


func poke() -> void:
	vibrate(10, 0.35)
	play("pop", -6.0, 40)


func grab() -> void:
	vibrate(8, 0.25)
	play("squelch", -12.0, 60)


func merge() -> void:
	vibrate(60, 1.0)
	play("plop", 0.0, 0)


func vibrate(duration_ms: int, amplitude: float = -1.0) -> void:
	if not GameState.options.haptics:
		return
	var now := Time.get_ticks_msec()
	if now - _last_haptic_ms < 40:
		return
	_last_haptic_ms = now
	# Needs the VIBRATE permission in the Android export preset.
	Input.vibrate_handheld(duration_ms, amplitude)


func play(kind: String, volume_db: float = 0.0, min_gap_ms: int = 50) -> void:
	if not GameState.options.sound or not _streams.has(kind):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_sound_ms.get(kind, -100000)) < min_gap_ms:
		return
	_last_sound_ms[kind] = now
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	var options: Array = _streams[kind]
	p.stream = options[randi() % options.size()]
	# Pitch variation keeps repeated hits from sounding mechanical; slow-mo
	# lowers pitch so the whole world feels slowed down.
	p.pitch_scale = randf_range(0.85, 1.2) * lerpf(0.6, 1.0, Engine.time_scale)
	p.volume_db = volume_db + linear_to_db(float(GameState.options.volume))
	p.play()


# ------------------------------------------------------------------ synthesis

func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


## Wet squelch: low-passed noise with a falling cutoff + a soft low thump.
func _synth_squelch(length: float, bright: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / length
		var env := minf(t / 0.01, 1.0) * pow(1.0 - u, 2.0)
		var cutoff := lerpf(0.35, 0.03, u) * bright
		lp += (randf_range(-1.0, 1.0) - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var f := lerpf(170.0, 70.0, u)
		phase += TAU * f / MIX_RATE
		# Wobbly amplitude modulation = "wet" character.
		var wob := 0.6 + 0.4 * sin(TAU * 32.0 * t)
		out[i] = (lp2 * 2.2 * wob + sin(phase) * 0.45) * env * 0.8
	return _make_wav(out)


## Cartoon boing: sine with falling pitch and decaying vibrato.
func _synth_boing(length: float, base_hz: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / length
		var env := minf(t / 0.005, 1.0) * exp(-4.0 * u)
		var f := base_hz * lerpf(1.6, 0.8, sqrt(u)) * (1.0 + 0.12 * exp(-3.0 * u) * sin(TAU * 14.0 * t))
		phase += TAU * f / MIX_RATE
		out[i] = (sin(phase) + 0.25 * sin(phase * 2.0)) * env * 0.55
	return _make_wav(out)


## Low "wub-wub": a soft tone with amplitude wobble, like a jelly settling.
func _synth_wobble(length: float, base_hz: float, wob_hz: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / length
		var env := minf(t / 0.02, 1.0) * exp(-3.5 * u)
		var wob := 0.5 + 0.5 * cos(TAU * wob_hz * t * (1.0 - 0.3 * u))
		var f := base_hz * (1.0 + 0.06 * sin(TAU * wob_hz * t))
		phase += TAU * f / MIX_RATE
		out[i] = (sin(phase) + 0.3 * sin(phase * 2.0) + 0.1 * sin(phase * 3.0)) * env * wob * 0.6
	return _make_wav(out)


func _synth_pop() -> AudioStreamWAV:
	var length := 0.09
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := t / length
		var f := lerpf(700.0, 260.0, u)
		phase += TAU * f / MIX_RATE
		out[i] = sin(phase) * pow(1.0 - u, 3.0) * 0.6
	return _make_wav(out)


func _load_custom_audio() -> void:
	var dir := DirAccess.open(AUDIO_DIR)
	if dir == null:
		return
	var custom := {}
	for f in dir.get_files():
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not (file.ends_with(".wav") or file.ends_with(".ogg") or file.ends_with(".mp3")):
			continue
		for kind in _streams.keys():
			if file.begins_with(kind):
				var s := load(AUDIO_DIR + file) as AudioStream
				if s:
					if not custom.has(kind):
						custom[kind] = []
					if not custom[kind].has(s):
						custom[kind].append(s)
	for kind in custom:
		_streams[kind] = custom[kind]
