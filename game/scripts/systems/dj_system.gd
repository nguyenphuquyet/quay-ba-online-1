class_name QBODJSystem
extends Node3D
## DJ System — phát nhạc, playlist, beat detection, đồng bộ trạng thái qua Net.
## Nhạc demo được sinh tại chỗ (bản gốc) và mp3/ogg tải từ URL công khai.

const MUSIC_BUS := "Music"
const MAX_DOWNLOAD_BYTES := 30 * 1024 * 1024

var world: Nightclub
var music: AudioStreamPlayer3D
var current_track_id := "chrome_lotus_demo"
var current_title := "Chrome Lotus (QBO Original Demo)"
var current_url := ""
var playing := false
var volume := 0.8
var _playlist: Array = []
var _demo_stream: AudioStreamWAV
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _beat_cooldown := 0.0
var _sync_timer := 0.0
var _last_action := ""
var _loading_url := false
var _download: HTTPRequest


func _ready() -> void:
	name = "DJSystem"
	music = AudioStreamPlayer3D.new()
	music.bus = MUSIC_BUS
	music.unit_size = 18.0
	music.max_distance = 120.0
	music.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	music.max_db = 3.0
	music.position = Vector3(0, 2.2, -2.2)
	add_child(music)
	_setup_analyzer()
	_playlist = [
		{"id": "chrome_lotus_demo", "title": "Chrome Lotus (QBO Original Demo)", "artist": "QBO Studio", "kind": "demo"},
	]
	music.finished.connect(_on_finished)
	if SettingsManager.preset_name != "":
		volume = SettingsManager.music_volume
	music.volume_db = linear_to_db(maxf(volume, 0.001))


func _setup_analyzer() -> void:
	var bus_index := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_index < 0:
		return
	var has_analyzer := false
	for i in AudioServer.get_bus_effect_count(bus_index):
		if AudioServer.get_bus_effect(bus_index, i) is AudioEffectSpectrumAnalyzer:
			has_analyzer = true
			break
	if not has_analyzer:
		var analyzer := AudioEffectSpectrumAnalyzer.new()
		analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		analyzer.buffer_length = 0.15
		AudioServer.add_bus_effect(bus_index, analyzer)
	for i in AudioServer.get_bus_effect_count(bus_index):
		if AudioServer.get_bus_effect(bus_index, i) is AudioEffectSpectrumAnalyzer:
			_spectrum = AudioServer.get_bus_effect_instance(bus_index, i)
			break


func _process(delta: float) -> void:
	_beat_cooldown = maxf(0.0, _beat_cooldown - delta)
	if playing and _spectrum != null:
		_detect_beat()
	_sync_timer += delta
	if playing and is_controller() and _sync_timer > 6.0:
		_sync_timer = 0.0
		Net.send_dj("sync", build_state())


func _detect_beat() -> void:
	if _spectrum == null:
		return
	var magnitude := _spectrum.get_magnitude_for_frequency_range(30.0, 140.0).length()
	if magnitude > 0.004 and _beat_cooldown <= 0.0:
		_beat_cooldown = 0.18
		if world != null and world.lighting != null:
			world.lighting.beat(clampf(magnitude * 22.0, 0.2, 1.4))


func is_controller() -> bool:
	return Net.can_control("dj")


# ------------------------------------------------------------------ controls

func play_track(track_id: String) -> void:
	var track := _find_track(track_id)
	if track.is_empty():
		return
	_apply_track(track)
	Net.send_dj("play", build_state())
	if not Net.is_online():
		_apply_state(build_state())


func toggle_play() -> void:
	if music.stream == null:
		ensure_default_track()
	if playing:
		music.stream_paused = true
		playing = false
		Net.send_dj("pause", build_state())
	else:
		if music.stream == null:
			_load_demo()
		music.stream_paused = false
		if not music.playing:
			music.play()
		playing = true
		Net.send_dj("play", build_state())


func next_track() -> void:
	var idx := _index_of(current_track_id)
	idx = (idx + 1) % _playlist.size()
	play_track(str(_playlist[idx]["id"]))


func prev_track() -> void:
	var idx := _index_of(current_track_id)
	idx = (idx - 1 + _playlist.size()) % _playlist.size()
	play_track(str(_playlist[idx]["id"]))


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	music.volume_db = linear_to_db(maxf(volume, 0.001))
	Net.send_dj("volume", {"volume": volume})


func seek(seconds: float) -> void:
	if music.stream != null:
		music.seek(clampf(seconds, 0.0, _stream_length()))
	Net.send_dj("seek", {"position": music.get_playback_position()})


func play_url(url: String) -> void:
	var check := QBOUrlGuard.validate(url)
	if not check["ok"]:
		App.toast(str(check["reason"]), "error")
		return
	if check["kind"] != "audio":
		App.toast("URL này không phải tệp âm thanh trực tiếp (mp3/ogg/wav). YouTube cần TV/Browser provider.", "error")
		return
	if _loading_url:
		return
	_loading_url = true
	App.toast("Đang tải nhạc từ URL…")
	_download = HTTPRequest.new()
	_download.timeout = 25.0
	_download.max_redirects = 3
	add_child(_download)
	var err := _download.request(str(check["url"]))
	if err != OK:
		_loading_url = false
		App.toast("Không tải được nhạc.", "error")
		return
	var res: Array = await _download.request_completed
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	_download.queue_free()
	_loading_url = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		App.toast("Tải nhạc thất bại (HTTP %d)." % code, "error")
		return
	if body.size() > MAX_DOWNLOAD_BYTES:
		App.toast("Tệp nhạc quá lớn (giới hạn 30MB).", "error")
		return
	var stream := _decode_audio(body, str(check["url"]))
	if stream == null:
		App.toast("Định dạng nhạc chưa hỗ trợ. Dùng MP3, OGG hoặc WAV.", "error")
		return
	_playlist.append({
		"id": "url_%d" % Time.get_ticks_msec(),
		"title": str(check["host"]),
		"artist": "URL",
		"kind": "url",
		"url": str(check["url"]),
		"stream": stream,
	})
	var track: Dictionary = _playlist[_playlist.size() - 1]
	_apply_track(track)
	Net.send_dj("play", build_state())
	if not Net.is_online():
		_apply_state(build_state())


func _decode_audio(bytes: PackedByteArray, url: String) -> AudioStream:
	var lower := url.to_lower()
	if lower.contains(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	if lower.contains(".ogg") or lower.contains(".oga"):
		# AudioStreamOggVorbis cần file; ghi cache tạm.
		var path := "user://cache_track_%d.ogg" % Time.get_ticks_msec()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return null
		f.store_buffer(bytes)
		f.close()
		return AudioStreamOggVorbis.load_from_file(path)
	if lower.contains(".wav"):
		var wav := AudioStreamWAV.new()
		wav.data = bytes
		return wav
	# Thử MP3 mặc định.
	var fallback := AudioStreamMP3.new()
	fallback.data = bytes
	return fallback


# ------------------------------------------------------------------ remote sync

func handle_remote(action: String, payload: Dictionary) -> void:
	match action:
		"play":
			_apply_state(payload)
		"pause":
			playing = false
			music.stream_paused = true
		"resume":
			playing = true
			music.stream_paused = false
			if not music.playing:
				music.play(music.get_playback_position())
		"volume":
			volume = clampf(float(payload.get("volume", volume)), 0.0, 1.0)
			music.volume_db = linear_to_db(maxf(volume, 0.001))
		"seek":
			if music.stream != null:
				music.seek(float(payload.get("position", 0.0)))
		"next":
			next_track()
		"prev":
			prev_track()
		"sync":
			_apply_state(payload)
		"load":
			var url := str(payload.get("url", ""))
			if url != "":
				play_url(url)
			else:
				_apply_state(payload)
		_:
			pass


func _apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var track_id := str(state.get("track_id", current_track_id))
	var url := str(state.get("url", ""))
	var position := float(state.get("position", 0.0))
	if track_id == "chrome_lotus_demo":
		ensure_default_track()
		if music.stream != _demo_stream:
			music.stream = _demo_stream
		current_track_id = "chrome_lotus_demo"
		current_title = "Chrome Lotus (QBO Original Demo)"
		current_url = ""
	elif url != "":
		var existing := _find_track(track_id)
		if not existing.is_empty():
			music.stream = existing.get("stream", music.stream)
			current_track_id = track_id
			current_title = str(existing.get("title", current_title))
			current_url = url
		else:
			# Chưa có track này: tải theo URL rồi đồng bộ tiếp.
			play_url(url)
			return
	playing = bool(state.get("playing", true))
	music.volume_db = linear_to_db(maxf(float(state.get("volume", volume)), 0.001))
	if playing:
		music.stream_paused = false
		if not music.playing:
			music.play(position)
		music.seek(position)
	else:
		music.stream_paused = true


func build_state() -> Dictionary:
	return {
		"track_id": current_track_id,
		"title": current_title,
		"url": current_url,
		"playing": playing,
		"position": music.get_playback_position() if music.stream != null else 0.0,
		"volume": volume,
	}


# ------------------------------------------------------------------ helpers

func ensure_default_track() -> void:
	if _demo_stream == null:
		_demo_stream = QBODemoTrack.generate()
	if music.stream == null:
		music.stream = _demo_stream


func _load_demo() -> void:
	ensure_default_track()
	music.stream = _demo_stream
	current_track_id = "chrome_lotus_demo"
	current_title = "Chrome Lotus (QBO Original Demo)"
	current_url = ""


func _apply_track(track: Dictionary) -> void:
	current_track_id = str(track.get("id", current_track_id))
	current_title = str(track.get("title", current_title))
	current_url = str(track.get("url", ""))
	if track.get("kind", "") == "demo":
		_load_demo()
		music.play()
	else:
		var stream: AudioStream = track.get("stream", null)
		if stream == null:
			if current_url != "":
				play_url(current_url)
				return
			_load_demo()
		else:
			music.stream = stream
			music.play()
	playing = true
	music.stream_paused = false


func playlist() -> Array:
	return _playlist.duplicate()


func _find_track(track_id: String) -> Dictionary:
	for track in _playlist:
		if str(track.get("id", "")) == track_id:
			return track
	return {}


func _index_of(track_id: String) -> int:
	for i in _playlist.size():
		if str(_playlist[i].get("id", "")) == track_id:
			return i
	return 0


func _stream_length() -> float:
	if music.stream == null:
		return 0.0
	return music.stream.get_length()


func _on_finished() -> void:
	if music.stream == null:
		return
	if current_track_id == "chrome_lotus_demo" and music.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		music.play()
		return
	next_track()
