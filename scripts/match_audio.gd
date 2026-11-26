extends Node
class_name MatchAudio
## §10.2 procedural audio bed: whistle + soft crowd (no authored WAV required).

var _whistle: AudioStreamPlayer
var _crowd: AudioStreamPlayer
var _enabled: bool = true


func _ready() -> void:
	_whistle = AudioStreamPlayer.new()
	_whistle.name = "WhistlePlayer"
	_whistle.bus = "Master"
	_whistle.volume_db = -6.0
	add_child(_whistle)
	_crowd = AudioStreamPlayer.new()
	_crowd.name = "CrowdPlayer"
	_crowd.bus = "Master"
	_crowd.volume_db = -22.0
	add_child(_crowd)
	_whistle.stream = _make_tone_stream(880.0, 0.18)
	_crowd.stream = _make_noise_loop(0.9)
	if _enabled:
		_crowd.play()


func set_enabled(on: bool) -> void:
	_enabled = on
	if _crowd == null:
		return
	if on:
		if not _crowd.playing:
			_crowd.play()
	else:
		_crowd.stop()


func play_whistle() -> void:
	if not _enabled or _whistle == null:
		return
	_whistle.stream = _make_tone_stream(980.0, 0.16)
	_whistle.play()


func play_goal_cheer() -> void:
	if not _enabled or _whistle == null:
		return
	_whistle.stream = _make_tone_stream(620.0, 0.28)
	_whistle.play()
	if _crowd:
		_crowd.volume_db = -14.0
		var tw := create_tween()
		tw.tween_property(_crowd, "volume_db", -22.0, 1.4)


func play_soft_bump() -> void:
	if not _enabled or _whistle == null:
		return
	_whistle.stream = _make_tone_stream(220.0, 0.06)
	_whistle.volume_db = -16.0
	_whistle.play()
	_whistle.volume_db = -6.0


## Short sine beep as AudioStreamWAV (mono 22050 Hz).
func _make_tone_stream(freq_hz: float, seconds: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t := float(i) / float(rate)
		var env := 1.0
		if t < 0.01:
			env = t / 0.01
		elif t > seconds - 0.04:
			env = maxf(0.0, (seconds - t) / 0.04)
		var sample := int(clampf(sin(TAU * freq_hz * t) * env, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


## Soft looping noise bed (crowd substitute).
func _make_noise_loop(seconds: float) -> AudioStreamWAV:
	var rate := 11025
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var prev := 0.0
	for i in range(n):
		var white := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, white, 0.08)
		var sample := int(clampf(prev * 0.22, -1.0, 1.0) * 32767.0)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = n
	stream.data = data
	return stream
