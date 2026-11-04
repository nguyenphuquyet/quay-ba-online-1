class_name QBODJSystem
extends Node3D
## DJ System — tải thư viện nhạc từ music.nguyenphuquyet.online, phát audio
## trực tiếp (MP3/OGG/WAV) và đồng bộ trạng thái cho cả phòng qua Net.
##
## TV lớn ở sân khấu đọc `current_*` từ hệ thống này để hiển thị bìa + tên bài.
## Các bài `.m4a` bị ẩn vì Godot không giải mã AAC native.

signal library_changed
signal track_changed

const MUSIC_BUS := "Music"
const MAX_DOWNLOAD_BYTES := 50 * 1024 * 1024
const API_TIMEOUT := 20.0
const SYNC_INTERVAL := 6.0
const MAX_DRIFT := 1.25

var world: Nightclub
var music: AudioStreamPlayer3D

var current_track_id := ""
var current_title := "Đang tải thư viện nhạc…"
var current_artist := ""
var current_cover_url := ""
var current_url := ""
var current_duration := 0.0
var playing := false
var volume := 0.8

var library_loading := false
var library_error := ""

var _playlist: Array = []
var _tracks_by_id: Dictionary = {}
var _streams: Dictionary = {}
var _cover_cache: Dictionary = {}
var _demo_stream: AudioStreamWAV
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _beat_cooldown := 0.0
var _sync_timer := 0.0
var _last_action := ""
var _paused_position := 0.0
var _load_seq := 0
var _pending_state: Dictionary = {}
var _loading_track_id := ""
var _library_http: HTTPRequest
var _reload_after_state := false


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
	music.finished.connect(_on_finished)
	if SettingsManager.preset_name != "":
		volume = SettingsManager.music_volume
	music.volume_db = linear_to_db(maxf(volume, 0.001))
	# Tải danh sách sau khi world dựng xong; UI có thể hiện trạng thái loading.
	call_deferred("reload_library")


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
	if playing and is_controller() and _sync_timer > SYNC_INTERVAL:
		_sync_timer = 0.0
		_publish("sync")


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


# ------------------------------------------------------------------ library

func reload_library() -> void:
	if library_loading:
		return
	library_loading = true
	library_error = ""
	library_changed.emit()
	if _library_http != null:
		_library_http.queue_free()
	_library_http = HTTPRequest.new()
	_library_http.timeout = API_TIMEOUT
	_library_http.max_redirects = 4
	add_child(_library_http)
	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: QuayBarOnline/%s (%s)" % [AppConfig.APP_VERSION, OS.get_name()],
	])
	var err := _library_http.request(AppConfig.music_songs_url(), headers)
	if err != OK:
		_finish_library_error("Không kết nối được thư viện nhạc (%s)." % error_string(err))
		return
	var response: Array = await _library_http.request_completed
	if _library_http != null:
		_library_http.queue_free()
		_library_http = null
	if not is_inside_tree():
		return
	var result: int = response[0]
	var code: int = response[1]
	var raw: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_library_error("Lỗi mạng khi tải thư viện nhạc (mã %d)." % result)
		return
	if code < 200 or code >= 300:
		_finish_library_error("Thư viện nhạc trả về HTTP %d." % code)
		return
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	_parse_library(parsed)
	library_loading = false
	library_changed.emit()
	if _playlist.is_empty():
		_finish_library_error("Thư viện nhạc trống hoặc không có bài MP3/OGG/WAV.")
		return
	if current_track_id == "":
		_set_current_track(_playlist[0])
	if not _pending_state.is_empty():
		var pending := _pending_state
		_pending_state = {}
		_apply_state(pending)
	print("[QBO] DJ library: %d bài phát được." % _playlist.size())


func _finish_library_error(reason: String) -> void:
	library_loading = false
	library_error = reason
	library_changed.emit()
	if _playlist.is_empty():
		_use_demo_fallback()
	if not AppConfig.is_dedicated:
		App.toast(reason, "error")


func _parse_library(data: Variant) -> void:
	var rows: Array = []
	if data is Array:
		rows = data
	elif data is Dictionary:
		var dict: Dictionary = data
		if dict.get("songs") is Array:
			rows = dict["songs"]
		elif dict.get("data") is Array:
			rows = dict["data"]
	var playlist: Array = []
	var by_id: Dictionary = {}
	for i in rows.size():
		if not (rows[i] is Dictionary):
			continue
		var track := _make_track(rows[i], i)
		if track.is_empty():
			continue
		playlist.append(track)
		by_id[str(track["id"])] = track
	_playlist = playlist
	_tracks_by_id = by_id


func _make_track(song: Dictionary, index: int) -> Dictionary:
	var audio_raw := str(song.get("audioUrl", song.get("url", "")))
	var audio_url := QBOUrlGuard.absolute_url(audio_raw, AppConfig.music_api_url)
	if audio_url == "" or not QBOUrlGuard.is_supported_audio(audio_url):
		# .m4a/AAC không phát được bằng AudioStream native của Godot -> ẩn.
		return {}
	var cover_url := QBOUrlGuard.absolute_url(str(song.get("coverUrl", "")), AppConfig.music_api_url)
	var raw_id := str(song.get("id", song.get("_id", index)))
	var title := str(song.get("title", "")).strip_edges()
	if title == "":
		title = _title_from_url(audio_url)
	var artist := str(song.get("artist", "")).strip_edges()
	if artist == "":
		artist = "Không rõ nghệ sĩ"
	return {
		"id": "api_" + raw_id,
		"title": title,
		"artist": artist,
		"url": audio_url,
		"cover_url": cover_url,
		"duration": maxf(0.0, float(song.get("duration", 0.0))),
		"genre": str(song.get("genre", "")),
		"source": "api",
	}


func _title_from_url(url: String) -> String:
	var file := url.split("?")[0].split("#")[0].get_file()
	var base := file.get_basename()
	if base == "":
		return "Không rõ tên bài"
	return base.replace("_", " ").replace("-", " ").capitalize()


func _use_demo_fallback() -> void:
	ensure_default_track()
	_playlist = [{
		"id": "demo_chrome_lotus",
		"title": "Chrome Lotus (QBO Original Demo)",
		"artist": "QBO Studio",
		"cover_url": "",
		"url": "",
		"duration": _demo_stream.get_length() if _demo_stream != null else 0.0,
		"source": "demo",
	}]
	_tracks_by_id = {str(_playlist[0]["id"]): _playlist[0]}
	_set_current_track(_playlist[0])


# ------------------------------------------------------------------ controls

func play_track(track_id: String) -> void:
	if not is_controller():
		return
	var track := _find_track(track_id)
	if track.is_empty():
		return
	_begin_track(track, 0.0, true, true)


func toggle_play() -> void:
	if not is_controller():
		return
	if _playlist.is_empty():
		reload_library()
		return
	if current_track_id == "":
		play_track(str(_playlist[0]["id"]))
		return
	if playing:
		_paused_position = _current_position()
		playing = false
		music.stream_paused = true
		_publish("pause")
	else:
		var track := _find_track(current_track_id)
		if track.is_empty():
			return
		if music.stream == null:
			_begin_track(track, _paused_position, true, true)
		else:
			playing = true
			music.stream_paused = false
			if not music.playing:
				music.play(clampf(_paused_position, 0.0, maxf(0.0, _stream_length() - 0.05)))
			_publish("resume")


func next_track() -> void:
	if not is_controller():
		return
	_step_track(1, true)


func prev_track() -> void:
	if not is_controller():
		return
	_step_track(-1, true)


func _step_track(direction: int, broadcast: bool) -> void:
	if _playlist.is_empty():
		return
	var idx := _index_of(current_track_id)
	idx = (idx + direction + _playlist.size()) % _playlist.size()
	var track: Dictionary = _playlist[idx]
	_begin_track(track, 0.0, true, broadcast)


func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	music.volume_db = linear_to_db(maxf(volume, 0.001))
	_publish("volume")


func seek(seconds: float) -> void:
	if music.stream == null:
		return
	var target := clampf(seconds, 0.0, maxf(0.0, _stream_length() - 0.05))
	music.seek(target)
	_paused_position = target
	_publish("seek")


func _publish(action: String) -> void:
	_last_action = action
	var state := build_state()
	Net.dj_state = state.duplicate(true)
	if Net.is_online():
		Net.send_dj(action, state)


func _begin_track(track: Dictionary, position: float, should_play: bool, broadcast: bool) -> void:
	_load_seq += 1
	var seq := _load_seq
	_set_current_track(track)
	playing = should_play
	if broadcast:
		_publish("play")
	if str(track.get("source", "")) == "demo":
		ensure_default_track()
		music.stream = _demo_stream
		music.volume_db = linear_to_db(maxf(volume, 0.001))
		music.play(clampf(position, 0.0, maxf(0.0, _demo_stream.get_length() - 0.05)))
		music.stream_paused = not should_play
		track_changed.emit()
		return
	var track_id := str(track.get("id", ""))
	var cached: AudioStream = _streams.get(track_id)
	if cached != null:
		_activate_stream(cached, position, should_play)
		return
	_loading_track_id = track_id
	if not AppConfig.is_dedicated:
		App.toast("Đang tải “%s”…" % str(track.get("title", "bài hát")))
	var stream := await _download_stream(track)
	if seq != _load_seq or not is_inside_tree():
		return
	_loading_track_id = ""
	if stream == null:
		playing = false
		music.stream_paused = true
		App.toast("Không phát được bài này.", "error")
		return
	_streams[track_id] = stream
	_activate_stream(stream, position, should_play)


func _activate_stream(stream: AudioStream, position: float, should_play: bool) -> void:
	music.stream = stream
	music.volume_db = linear_to_db(maxf(volume, 0.001))
	var target := clampf(position, 0.0, maxf(0.0, stream.get_length() - 0.05))
	music.play(target)
	music.stream_paused = not should_play
	playing = should_play
	_paused_position = target
	track_changed.emit()


func _download_stream(track: Dictionary) -> AudioStream:
	var url := str(track.get("url", ""))
	var check := QBOUrlGuard.validate(url)
	if not check["ok"] or str(check["kind"]) != "audio":
		return null
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.max_redirects = 4
	add_child(http)
	var headers := PackedStringArray([
		"Accept: audio/*,*/*;q=0.8",
		"User-Agent: QuayBarOnline/%s (%s)" % [AppConfig.APP_VERSION, OS.get_name()],
	])
	var err := http.request(str(check["url"]), headers)
	if err != OK:
		http.queue_free()
		return null
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return null
	if body.is_empty() or body.size() > MAX_DOWNLOAD_BYTES:
		return null
	return _decode_audio(body, str(check["url"]))


func _decode_audio(bytes: PackedByteArray, url: String) -> AudioStream:
	var lower := url.to_lower()
	if lower.contains(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	if lower.contains(".ogg") or lower.contains(".oga"):
		var path := "user://cache_track_%d.ogg" % Time.get_ticks_msec()
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return null
		file.store_buffer(bytes)
		file.close()
		return AudioStreamOggVorbis.load_from_file(path)
	if lower.contains(".wav"):
		var wav := AudioStreamWAV.new()
		wav.data = bytes
		return wav
	var fallback := AudioStreamMP3.new()
	fallback.data = bytes
	return fallback


# ------------------------------------------------------------------ remote sync

func handle_remote(action: String, payload: Dictionary) -> void:
	match action:
		"play", "sync", "load":
			_apply_state(payload)
		"pause":
			_paused_position = _current_position()
			playing = false
			music.stream_paused = true
		"resume":
			playing = true
			music.stream_paused = false
			if not music.playing:
				music.play(clampf(_paused_position, 0.0, maxf(0.0, _stream_length() - 0.05)))
		"volume":
			volume = clampf(float(payload.get("volume", volume)), 0.0, 1.0)
			music.volume_db = linear_to_db(maxf(volume, 0.001))
		"seek":
			var position := float(payload.get("position", 0.0))
			_paused_position = position
			if music.stream != null:
				music.seek(clampf(position, 0.0, maxf(0.0, _stream_length() - 0.05)))
		"next":
			_step_track(1, false)
		"prev":
			_step_track(-1, false)
		_:
			pass


func _apply_state(state: Dictionary) -> void:
	if state.is_empty() or not state.has("track_id"):
		return
	var track_id := str(state.get("track_id", ""))
	var track := _find_track(track_id)
	if track.is_empty():
		if library_loading:
			_pending_state = state.duplicate(true)
			return
		if not _reload_after_state:
			_reload_after_state = true
			_pending_state = state.duplicate(true)
			reload_library()
		return
	_reload_after_state = false
	var target_playing := bool(state.get("playing", true))
	var target_position := float(state.get("position", 0.0))
	var updated_at := float(state.get("updated_at", 0.0))
	if target_playing and updated_at > 0.0:
		target_position += clampf(Time.get_unix_time_from_system() - updated_at, 0.0, 3600.0)
	volume = clampf(float(state.get("volume", volume)), 0.0, 1.0)
	music.volume_db = linear_to_db(maxf(volume, 0.001))
	var same_track := current_track_id == track_id and music.stream != null
	if same_track:
		playing = target_playing
		if playing:
			music.stream_paused = false
			if not music.playing:
				music.play(clampf(target_position, 0.0, maxf(0.0, _stream_length() - 0.05)))
			elif absf(_current_position() - target_position) > MAX_DRIFT:
				music.seek(clampf(target_position, 0.0, maxf(0.0, _stream_length() - 0.05)))
		else:
			_paused_position = _current_position()
			music.stream_paused = true
		return
	_begin_track(track, target_position, target_playing, false)


func build_state() -> Dictionary:
	return {
		"track_id": current_track_id,
		"title": current_title,
		"artist": current_artist,
		"cover_url": current_cover_url,
		"url": current_url,
		"playing": playing,
		"position": _current_position(),
		"volume": volume,
		"duration": current_duration,
		"updated_at": Time.get_unix_time_from_system(),
	}


func _current_position() -> float:
	if music == null or music.stream == null:
		return 0.0
	if music.playing:
		return music.get_playback_position()
	return _paused_position


# ------------------------------------------------------------------ helpers

func ensure_default_track() -> void:
	if _demo_stream == null:
		_demo_stream = QBODemoTrack.generate()


func _set_current_track(track: Dictionary) -> void:
	current_track_id = str(track.get("id", ""))
	current_title = str(track.get("title", "Không rõ tên bài"))
	current_artist = str(track.get("artist", ""))
	current_cover_url = str(track.get("cover_url", ""))
	current_url = str(track.get("url", ""))
	current_duration = float(track.get("duration", 0.0))
	if current_duration <= 0.0 and str(track.get("source", "")) == "demo" and _demo_stream != null:
		current_duration = _demo_stream.get_length()


func playlist() -> Array:
	return _playlist.duplicate(true)


func track_count() -> int:
	return _playlist.size()


func is_loading_track() -> bool:
	return _loading_track_id != ""


func playback_position() -> float:
	return _current_position()


func current_progress() -> float:
	if current_duration <= 0.0:
		return 0.0
	return clampf(_current_position() / current_duration, 0.0, 1.0)


func _find_track(track_id: String) -> Dictionary:
	if _tracks_by_id.has(track_id):
		return _tracks_by_id[track_id]
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
	if music == null or music.stream == null:
		return 0.0
	return music.stream.get_length()


func _on_finished() -> void:
	if music.stream == null:
		return
	if not is_controller():
		return
	if _playlist.size() <= 1:
		music.play()
		return
	_step_track(1, true)


# ------------------------------------------------------------------ cover art

## Tải ảnh bìa từ URL (dùng chung cho DJ panel và TV lớn).
func load_cover(url: String) -> Texture2D:
	if url == "":
		return null
	if _cover_cache.has(url):
		return _cover_cache[url]
	var check := QBOUrlGuard.validate(url)
	if not check["ok"]:
		return null
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 4
	add_child(http)
	var headers := PackedStringArray([
		"Accept: image/*,*/*;q=0.8",
		"User-Agent: QuayBarOnline/%s (%s)" % [AppConfig.APP_VERSION, OS.get_name()],
	])
	var err := http.request(str(check["url"]), headers)
	if err != OK:
		http.queue_free()
		return null
	var response: Array = await http.request_completed
	http.queue_free()
	if not is_inside_tree():
		return null
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return null
	var code := int(response[1])
	var body: PackedByteArray = response[3]
	if code < 200 or code >= 300 or body.is_empty():
		return null
	var image := Image.new()
	var load_err := ERR_CANT_OPEN
	var lower := url.to_lower()
	if lower.contains(".png"):
		load_err = image.load_png_from_buffer(body)
	elif lower.contains(".webp"):
		load_err = image.load_webp_from_buffer(body)
	else:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		load_err = image.load_png_from_buffer(body)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		return null
	image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var texture := ImageTexture.create_from_image(image)
	_cover_cache[url] = texture
	return texture
