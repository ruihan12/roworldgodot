extends SceneTree

## Records what the audio server actually mixes after play(), not an event log.
## Headless Dummy still runs the mixer; this is engine output, not a speaker recording.

var capture: AudioEffectCapture
var player: AudioStreamPlayer
var frames := 0
var mode := "music"
var out_path := "/tmp/captured.wav"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.substr(7)
		if arg.begins_with("--out="): out_path = arg.substr(6)
	var bus := AudioServer.get_bus_index("Master")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 10.0
	AudioServer.add_bus_effect(bus, capture)
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	root.add_child(player)
	var stream: AudioStream = null
	if mode == "click":
		stream = _mp3("res://sounds/click.mp3")
	elif mode == "boat":
		stream = _mp3("res://sounds/transport-ship.mp3")
	elif mode == "loadclick":
		stream = load("res://sounds/click.mp3")
	else:
		stream = load("res://sounds/music/frontline_pad.ogg")
		if stream is AudioStreamOggVorbis:
			stream.loop = false
	print("CAPTURE mode=", mode, " stream=", stream, " len=", stream.get_length() if stream else -1)
	if stream == null:
		print("CAPTURE FAIL no stream")
		quit(1)
		return
	player.stream = stream
	call_deferred("_start_play")

func _start_play() -> void:
	print("CAPTURE inside_tree=", player.is_inside_tree())
	player.play()

func _process(_dt: float) -> bool:
	frames += 1
	if not player.playing and player.get_playback_position() <= 0.0 and frames < 5:
		return false
	var need := 2.2 if mode != "music" else 4.0
	if player.get_playback_position() < need and frames < 400:
		return false
	var n := capture.get_frames_available()
	print("CAPTURE frames_available=", n, " pos=", player.get_playback_position(), " playing=", player.playing)
	if n < 100:
		print("CAPTURE FAIL mixer produced almost nothing")
		quit(2)
		return true
	var data := capture.get_buffer(n)
	var peak := 0.0
	var energy := 0.0
	for i in data.size():
		var a := absf(data[i].x)
		peak = maxf(peak, a)
		energy += data[i].x * data[i].x
	var rms := sqrt(energy / float(data.size()))
	print("CAPTURE samples=", data.size(), " peak=", peak, " rms=", rms)
	_write_wav(out_path, data)
	print("CAPTURE wrote ", out_path)
	quit(0 if peak > 0.01 else 3)
	return true

func _mp3(res: String) -> AudioStreamMP3:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(res))
	var s := AudioStreamMP3.new()
	s.data = bytes
	return s

func _write_wav(path: String, frames_in: PackedVector2Array) -> void:
	var mix := AudioServer.get_mix_rate()
	var f := FileAccess.open(path, FileAccess.WRITE)
	var ns := frames_in.size()
	var data_bytes := ns * 2
	f.store_string("RIFF")
	f.store_32(36 + data_bytes)
	f.store_string("WAVE")
	f.store_string("fmt ")
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(int(mix))
	f.store_32(int(mix) * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_string("data")
	f.store_32(data_bytes)
	for i in ns:
		var s := int(clampf(frames_in[i].x, -1.0, 1.0) * 32767.0)
		f.store_16(s)
	f.close()
