class_name QBOTVSystem
extends Node3D
## Sân khấu có hai màn hình:
##   • TV chính giữa (20:9)  — màn nhạc của booth DJ, hoặc video MP4 trực tiếp.
##   • TV nhỏ bên phải (16:9) — thông tin nhà phát triển.
##
## Không còn WebView/YouTube. Video MP4/MOV dùng GDExtension `native_video`
## (VideoStreamPlayer drop-in) và được tải về cache trước khi phát. Trạng thái
## video (URL, play/pause, thời gian, âm lượng) đồng bộ qua Net.

const SCREEN_SIZE := Vector2i(1280, 576)
const DEV_SIZE := Vector2i(1280, 720)
const VIDEO_CACHE_DIR := "user://tv_video_cache"
const MAX_VIDEO_BYTES := 300 * 1024 * 1024
## Tổng dung lượng cache video; vượt ngưỡng thì xoá tệp cũ nhất trước.
const MAX_CACHE_BYTES := 1536 * 1024 * 1024

var world: Nightclub
var viewport: SubViewport
var dev_viewport: SubViewport
var dev_screen: Control

var screen_root: Control
var music_layer: Control
var video_layer: Control
var video_player: VideoStreamPlayer
var video_status: Label
var cover_rect: TextureRect
var cover_placeholder: Control
var title_label: Label
var artist_label: Label
var meta_label: Label
var time_label: Label
var progress_bg: ColorRect
var progress_fill: ColorRect
var live_label: Label
var eq_bars: Control

var current_state: Dictionary = {}
var _cover_url := ""
var _cover_requested := ""
var _video_url := ""
var _video_loading_url := ""
var _video_seq := 0
var _download: HTTPRequest
var _sync_timer := 0.0
var _ui_check := 0.0


class DevInfoScreen:
	extends Control
	## Bảng thông tin tĩnh: viewport chỉ render một lần (UPDATE_ONCE) để tiết kiệm GPU.

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w < 4.0 or h < 4.0:
			return
		var font := ThemeDB.fallback_font
		# Nền gradient tím-xanh của quán.
		for i in 30:
			var t := float(i) / 30.0
			var c := Color(0.07, 0.02, 0.13).lerp(Color(0.008, 0.012, 0.035), t)
			draw_rect(Rect2(0.0, h * t, w, h / 30.0 + 1.0), c)
		# Quầng sáng tĩnh.
		for k in 3:
			var cx := w * (0.5 + 0.36 * sin(float(k) * 2.1))
			var cy := h * (0.42 + 0.26 * cos(float(k) * 1.6))
			draw_circle(Vector2(cx, cy), h * 0.5, Color(0.85, 0.14, 0.5, 0.04))
		# Hai dải màu hai bên.
		draw_rect(Rect2(0, 0, 10, h), Color(1.0, 0.3, 0.55, 0.85))
		draw_rect(Rect2(w - 10, 0, 10, h), Color(0.3, 0.8, 1.0, 0.75))
		# Monogram.
		var mono := Vector2(w * 0.5, h * 0.29)
		draw_circle(mono, h * 0.135, Color(1.0, 0.3, 0.55, 0.14))
		draw_arc(mono, h * 0.135, 0.0, TAU, 96, Color(1.0, 0.45, 0.7, 0.6), 3.0, true)
		draw_string(font, Vector2(mono.x - w * 0.25, mono.y + h * 0.05), "NPQ", HORIZONTAL_ALIGNMENT_CENTER, w * 0.5, int(h * 0.11), Color(1.0, 0.95, 0.92, 0.96))
		# Tên nhà phát triển.
		draw_string(font, Vector2(0, h * 0.55), "NHÀ PHÁT TRIỂN", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.038), Color(1.0, 0.72, 0.4, 0.9))
		draw_string(font, Vector2(0, h * 0.645), "NGUYỄN PHÚ QUYẾT", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.082), Color(1.0, 0.96, 0.9, 0.98))
		draw_string(font, Vector2(0, h * 0.70), "Lead Developer  •  Designer  •  QA", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.032), Color(0.6, 0.88, 1.0, 0.9))
		# Đường kẻ.
		draw_rect(Rect2(w * 0.22, h * 0.735, w * 0.56, 2.0), Color(0.35, 0.9, 1.0, 0.35))
		# Thông tin dự án.
		draw_string(font, Vector2(0, h * 0.79), "QUẨY BAR ONLINE  •  THE CHROME LOTUS", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.030), Color(0.92, 0.9, 0.98, 0.85))
		draw_string(font, Vector2(0, h * 0.835), "github.com/nguyenphuquyet  •  nguyenphuquyet.online", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.026), Color(0.7, 0.78, 0.95, 0.85))
		draw_string(font, Vector2(0, h * 0.885), "Âm nhạc: music.nguyenphuquyet.online", HORIZONTAL_ALIGNMENT_CENTER, w, int(h * 0.026), Color(0.7, 0.78, 0.95, 0.75))
		# Chân màn hình.
		draw_circle(Vector2(w * 0.5 - 150.0, h * 0.945), 6.0, Color(1.0, 0.3, 0.45))
		draw_string(font, Vector2(w * 0.5 - 136.0, h * 0.955), "GODOT 4.7  •  v0.1.0  •  CẢM ƠN BẠN ĐÃ GHÉ QUÁN", HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 0.026), Color(0.8, 0.84, 0.95, 0.7))


class MusicBackdrop:
	extends Control
	var phase := 0.0

	func _process(delta: float) -> void:
		phase += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 24:
			var t := float(i) / 24.0
			var c := Color(0.055, 0.018, 0.09).lerp(Color(0.008, 0.012, 0.035), t)
			draw_rect(Rect2(0, h * t, w, h / 24.0 + 1.0), c)
		for k in 4:
			var cx := w * (0.5 + 0.42 * sin(phase * 0.16 + float(k) * 1.9))
			var cy := h * (0.5 + 0.34 * cos(phase * 0.21 + float(k) * 1.3))
			draw_circle(Vector2(cx, cy), h * 0.55, Color(0.9, 0.15, 0.45, 0.035))
		draw_rect(Rect2(0, 0, 8, h), Color(1.0, 0.3, 0.55, 0.75))
		draw_rect(Rect2(w - 8, 0, 8, h), Color(0.3, 0.8, 1.0, 0.65))


class EqBars:
	extends Control
	var phase := 0.0
	var active := false

	func _process(delta: float) -> void:
		phase += delta * 2.2
		queue_redraw()

	func _draw() -> void:
		var bars := 28
		var gap := 5.0
		var bar_w := (size.x - gap * float(bars - 1)) / float(bars)
		for i in bars:
			var speed := 1.0 + float(i % 4) * 0.22
			var level := 0.12
			if active:
				level = 0.12 + 0.88 * absf(sin(phase * speed + float(i) * 0.5))
			var h := size.y * clampf(level, 0.06, 1.0)
			var c := Color(1.0, 0.25, 0.5).lerp(Color(0.25, 0.75, 1.0), float(i) / float(bars))
			draw_rect(Rect2(float(i) * (bar_w + gap), size.y - h, bar_w, h), c, true)


func _ready() -> void:
	name = "TVSystem"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VIDEO_CACHE_DIR))
	_build_dev_viewport()
	_build_screen_viewport()
	_build_screen_ui()
	_build_dev_ui()
	_apply_materials()
	_update_music_screen(true)


func _build_dev_viewport() -> void:
	dev_viewport = SubViewport.new()
	dev_viewport.size = DEV_SIZE
	dev_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	dev_viewport.disable_3d = true
	dev_viewport.transparent_bg = false
	add_child(dev_viewport)


func _build_screen_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = SCREEN_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)


func _apply_materials() -> void:
	if world == null:
		return
	# TV lớn ở giữa: màn nhạc DJ / video MP4.
	var music_material := StandardMaterial3D.new()
	music_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	music_material.albedo_texture = viewport.get_texture()
	music_material.albedo_color = Color(0.92, 0.92, 0.94)
	music_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	world.stage_screen_material = music_material
	if world.stage_screen != null:
		world.stage_screen.material_override = music_material

	# TV nhỏ bên phải: thông tin nhà phát triển.
	var dev_material := StandardMaterial3D.new()
	dev_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dev_material.albedo_texture = dev_viewport.get_texture()
	dev_material.albedo_color = Color(0.9, 0.9, 0.93)
	dev_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	world.side_screen_material = dev_material
	if world.stage_side_screen != null:
		world.stage_side_screen.material_override = dev_material


# ------------------------------------------------------------------ small TV UI

func _build_screen_ui() -> void:
	screen_root = Control.new()
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.theme = QBOTheme.theme()
	viewport.add_child(screen_root)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.008, 0.025)
	screen_root.add_child(bg)

	var backdrop := MusicBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(backdrop)

	music_layer = Control.new()
	music_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(music_layer)

	live_label = QBOTheme.label("●  LIVE FROM THE DJ BOOTH", 20, QBOTheme.ACCENT)
	live_label.position = Vector2(70, 40)
	music_layer.add_child(live_label)

	meta_label = QBOTheme.muted("QUẨY BAR ONLINE  •  THE CHROME LOTUS", 15)
	meta_label.position = Vector2(70, 74)
	music_layer.add_child(meta_label)

	var cover_frame := Panel.new()
	cover_frame.position = Vector2(70, 126)
	cover_frame.size = Vector2(320, 320)
	var cover_style := StyleBoxFlat.new()
	cover_style.bg_color = Color(0.03, 0.025, 0.06, 0.92)
	cover_style.border_color = Color(0.35, 0.9, 1.0, 0.35)
	cover_style.set_border_width_all(2)
	cover_style.set_corner_radius_all(8)
	cover_frame.add_theme_stylebox_override("panel", cover_style)
	music_layer.add_child(cover_frame)

	cover_rect = TextureRect.new()
	cover_rect.position = Vector2(10, 10)
	cover_rect.size = Vector2(300, 300)
	cover_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover_rect.visible = false
	cover_frame.add_child(cover_rect)

	cover_placeholder = Control.new()
	cover_placeholder.position = Vector2(10, 10)
	cover_placeholder.size = Vector2(300, 300)
	cover_frame.add_child(cover_placeholder)
	var ph := QBOTheme.label("QBO", 72, Color(1.0, 0.35, 0.58, 0.9))
	ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ph.position = Vector2(0, 70)
	ph.size = Vector2(300, 100)
	cover_placeholder.add_child(ph)
	var ph2 := QBOTheme.muted("DJ BOOTH", 16)
	ph2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ph2.position = Vector2(0, 180)
	ph2.size = Vector2(300, 30)
	cover_placeholder.add_child(ph2)

	title_label = QBOTheme.label("Đang tải thư viện nhạc…", 46, QBOTheme.TEXT)
	title_label.position = Vector2(430, 128)
	title_label.size = Vector2(790, 118)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.max_lines_visible = 2
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	music_layer.add_child(title_label)

	artist_label = QBOTheme.label("", 26, QBOTheme.ACCENT)
	artist_label.position = Vector2(430, 256)
	artist_label.size = Vector2(790, 40)
	artist_label.clip_text = true
	artist_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	music_layer.add_child(artist_label)

	var rule := ColorRect.new()
	rule.position = Vector2(430, 310)
	rule.size = Vector2(780, 2)
	rule.color = Color(0.35, 0.9, 1.0, 0.28)
	music_layer.add_child(rule)

	time_label = QBOTheme.muted("0:00 / 0:00", 18)
	time_label.position = Vector2(430, 324)
	music_layer.add_child(time_label)

	progress_bg = ColorRect.new()
	progress_bg.position = Vector2(430, 360)
	progress_bg.size = Vector2(780, 8)
	progress_bg.color = Color(1, 1, 1, 0.12)
	music_layer.add_child(progress_bg)
	progress_fill = ColorRect.new()
	progress_fill.position = Vector2(430, 360)
	progress_fill.size = Vector2(0, 8)
	progress_fill.color = QBOTheme.ACCENT_2
	music_layer.add_child(progress_fill)

	eq_bars = EqBars.new()
	eq_bars.position = Vector2(430, 392)
	eq_bars.size = Vector2(780, 100)
	music_layer.add_child(eq_bars)

	var footer := QBOTheme.muted("MP3  •  OGG  •  WAV     |     Đồng bộ cùng phòng", 15)
	footer.position = Vector2(70, 500)
	music_layer.add_child(footer)

	# Lớp video MP4 nằm trên màn nhạc; chỉ hiện khi TV đang ở chế độ video.
	video_layer = Control.new()
	video_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_layer.visible = false
	screen_root.add_child(video_layer)
	var video_bg := ColorRect.new()
	video_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_bg.color = Color.BLACK
	video_layer.add_child(video_bg)
	# Giữ đúng tỉ lệ 16:9 khi phát trên TV 20:9 (viền đen hai bên).
	var video_aspect := AspectRatioContainer.new()
	video_aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_aspect.ratio = 16.0 / 9.0
	video_aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	video_aspect.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	video_aspect.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	video_layer.add_child(video_aspect)
	video_player = VideoStreamPlayer.new()
	video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	video_player.expand = true
	video_player.visible = true
	video_aspect.add_child(video_player)
	video_status = QBOTheme.label("", 20, QBOTheme.TEXT)
	video_status.position = Vector2(60, 508)
	video_status.size = Vector2(1160, 46)
	video_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	video_layer.add_child(video_status)


func _build_dev_ui() -> void:
	dev_screen = DevInfoScreen.new()
	dev_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dev_viewport.add_child(dev_screen)


# ------------------------------------------------------------------ TV state

func apply_state(state: Dictionary) -> void:
	current_state = state.duplicate(true)
	var kind := str(state.get("kind", ""))
	if kind == "video":
		var url := str(state.get("url", ""))
		if url != "":
			var position := float(state.get("position", 0.0))
			if bool(state.get("playing", false)):
				position += _elapsed_since(float(state.get("updated_at", 0.0)))
			_play_video(url, position, bool(state.get("playing", false)))
			return
	_stop_video()
	video_layer.visible = false


func play_video_url(url_input: String, title := "") -> Dictionary:
	var check := QBOUrlGuard.validate(url_input)
	if not check["ok"]:
		return {"ok": false, "reason": str(check["reason"])}
	if str(check["kind"]) != "video":
		return {"ok": false, "reason": "TV chỉ phát video trực tiếp: mp4, mov, m4v hoặc ogv."}
	var state := {
		"kind": "video",
		"url": str(check["url"]),
		"title": title if title != "" else "Video sân khấu",
		"playing": true,
		"position": 0.0,
		"volume": float(current_state.get("volume", 1.0)),
		"status": "Đang phát video trực tiếp trên TV lớn.",
		"by": GameState.display_name(),
		"updated_at": Time.get_unix_time_from_system(),
	}
	Net.send_tv(state)
	if not Net.is_online():
		apply_state(state)
	return {"ok": true, "state": state, "kind": "video"}


func stop_video() -> void:
	var state := {
		"kind": "idle",
		"url": "",
		"title": "DJ booth",
		"playing": false,
		"position": 0.0,
		"volume": float(current_state.get("volume", 1.0)),
		"status": "TV lớn trở về màn hình nhạc của DJ.",
		"by": GameState.display_name(),
		"updated_at": Time.get_unix_time_from_system(),
	}
	Net.send_tv(state)
	if not Net.is_online():
		apply_state(state)


func set_playing(value: bool) -> void:
	if current_state.is_empty() or str(current_state.get("kind", "")) != "video":
		return
	var state := current_state.duplicate(true)
	state["playing"] = value
	state["position"] = video_player.stream_position if video_player.stream != null else 0.0
	state["updated_at"] = Time.get_unix_time_from_system()
	Net.send_tv(state)
	if not Net.is_online():
		apply_state(state)


func set_volume(value: float) -> void:
	var state := current_state.duplicate(true)
	state["volume"] = clampf(value, 0.0, 1.0)
	state["updated_at"] = Time.get_unix_time_from_system()
	Net.send_tv(state)
	if not Net.is_online():
		apply_state(state)


func video_available() -> bool:
	return true


## Dung lượng cache video hiện tại (TV lớn tải mỗi video về đĩa một lần).
func video_cache_stats() -> Dictionary:
	var files := 0
	var total := 0
	var dir := DirAccess.open(VIDEO_CACHE_DIR)
	if dir == null:
		return {"files": files, "bytes": total}
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var file := FileAccess.open(VIDEO_CACHE_DIR + "/" + entry, FileAccess.READ)
			if file != null:
				files += 1
				total += file.get_length()
				file.close()
		entry = dir.get_next()
	dir.list_dir_end()
	return {"files": files, "bytes": total}


## Xoá cache video. Từ chối khi TV đang phát video để không làm hỏng stream.
func clear_video_cache() -> Dictionary:
	if str(current_state.get("kind", "")) == "video":
		return {"ok": false, "reason": "Hãy trở về màn nhạc DJ trước khi xoá cache video."}
	var removed := 0
	var dir := DirAccess.open(VIDEO_CACHE_DIR)
	if dir == null:
		return {"ok": true, "removed": removed}
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and dir.remove(entry) == OK:
			removed += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return {"ok": true, "removed": removed}


## Giữ tổng cache dưới `limit_bytes` bằng cách xoá tệp cũ nhất (LRU theo mtime).
## `keep_path` luôn được giữ lại (tệp vừa tải xong).
func _trim_video_cache(keep_path: String, limit_bytes := MAX_CACHE_BYTES) -> void:
	var stats := video_cache_stats()
	var total := int(stats.get("bytes", 0))
	if total <= limit_bytes:
		return
	var entries: Array = []
	var dir := DirAccess.open(VIDEO_CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			var path := VIDEO_CACHE_DIR + "/" + entry
			entries.append({
				"name": entry,
				"path": path,
				"time": FileAccess.get_modified_time(path),
			})
		entry = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["time"]) < int(b["time"])
	)
	for item in entries:
		if total <= limit_bytes:
			break
		if str(item["path"]) == keep_path:
			continue
		var size := 0
		var file := FileAccess.open(str(item["path"]), FileAccess.READ)
		if file != null:
			size = file.get_length()
			file.close()
		if dir.remove(str(item["name"])) == OK:
			total -= size


func video_can_present() -> bool:
	# native_video cần RenderingDevice (Forward+ hoặc Mobile). OpenGL Compatibility
	# vẫn giải mã được nhưng không đưa được khung hình lên texture.
	return RenderingServer.get_rendering_device() != null


func video_backend_name() -> String:
	if not video_can_present():
		return "native_video (MP4/H.264) — máy đang dùng OpenGL, không hiển thị được video"
	return "native_video (MP4/H.264)"


# ------------------------------------------------------------------ MP4 playback

func _play_video(url: String, position: float, should_play: bool) -> void:
	video_layer.visible = true
	video_status.text = ""
	if video_player.stream == null or _video_url != url:
		_load_video(url, position, should_play)
		return
	video_player.paused = not should_play
	if should_play and absf(video_player.stream_position - position) > 1.0:
		video_player.stream_position = clampf(position, 0.0, maxf(0.0, _video_length() - 0.1))


func _load_video(url: String, position: float, should_play: bool) -> void:
	_video_seq += 1
	var seq := _video_seq
	_video_loading_url = url
	video_status.text = "Đang tải video…"
	video_status.visible = true
	var ext := _video_extension(url)
	var cache_path := "%s/%s%s" % [VIDEO_CACHE_DIR, url.md5_text(), ext]
	if not FileAccess.file_exists(cache_path):
		if _download != null:
			_download.queue_free()
		_download = HTTPRequest.new()
		_download.timeout = 60.0
		_download.max_redirects = 5
		add_child(_download)
		var headers := PackedStringArray([
			"Accept: video/*,*/*;q=0.8",
			"User-Agent: QuayBarOnline/%s (%s)" % [AppConfig.APP_VERSION, OS.get_name()],
		])
		var err := _download.request(url, headers)
		if err != OK:
			video_status.text = "Không tải được video (%s)." % error_string(err)
			return
		var response: Array = await _download.request_completed
		if _download != null:
			_download.queue_free()
			_download = null
		if seq != _video_seq or not is_inside_tree():
			return
		var result: int = response[0]
		var code: int = response[1]
		var body: PackedByteArray = response[3]
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300 or body.is_empty():
			video_status.text = "Video không tải được (HTTP %d)." % code
			return
		if body.size() > MAX_VIDEO_BYTES:
			video_status.text = "Video quá lớn (giới hạn 300 MB)."
			return
		var file := FileAccess.open(cache_path, FileAccess.WRITE)
		if file == null:
			video_status.text = "Không ghi được cache video."
			return
		file.store_buffer(body)
		file.close()
		_trim_video_cache(cache_path)
	if seq != _video_seq or not is_inside_tree():
		return
	var stream := _load_video_stream(cache_path, ext)
	if stream == null:
		video_status.text = "Không giải mã được video. Cần addon native_video cho MP4/H.264."
		return
	_video_url = url
	_video_loading_url = ""
	video_player.stream = stream
	video_player.play()
	var stream_length := video_player.get_stream_length()
	video_player.stream_position = clampf(position, 0.0, maxf(0.0, stream_length - 0.1))
	video_player.paused = not should_play
	if not video_can_present():
		video_status.text = "Đã giải mã video nhưng máy chưa có Vulkan/D3D12 nên không hiển thị được. Hãy chạy Forward+ trên GPU hỗ trợ."
		video_status.visible = true
		return
	video_status.text = ""
	video_status.visible = false


func _load_video_stream(path: String, ext: String) -> VideoStream:
	if ext == ".ogv":
		var theora := VideoStreamTheora.new()
		theora.file = path
		return theora
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is VideoStream:
		return resource as VideoStream
	return null


func _stop_video() -> void:
	if video_player != null and video_player.stream != null:
		video_player.stop()
		video_player.stream = null
	_video_url = ""
	_video_loading_url = ""
	_video_seq += 1


func _video_length() -> float:
	if video_player == null or video_player.stream == null:
		return 0.0
	return video_player.get_stream_length()


func _video_extension(url: String) -> String:
	var lower := url.to_lower().split("?")[0].split("#")[0]
	for ext in [".mp4", ".m4v", ".mov", ".ogv"]:
		if lower.ends_with(ext):
			return ext
	return ".mp4"


# ------------------------------------------------------------------ per-frame UI

func _process(delta: float) -> void:
	_ui_check -= delta
	if _ui_check <= 0.0:
		_ui_check = 0.2
		_update_music_screen(false)
	if bool(current_state.get("playing", false)) and str(current_state.get("kind", "")) == "video":
		_sync_timer += delta
		if _sync_timer >= 6.0 and Net.can_control("tv"):
			_sync_timer = 0.0
			_publish_video_position()
		if video_status != null and video_player != null and video_player.stream != null and video_can_present():
			video_status.text = "%s  •  %s" % [_format_time(video_player.stream_position), _format_time(_video_length())]
			video_status.visible = true


## Gửi vị trí video hiện tại định kỳ để người vào sau / client khác bám theo.
func _publish_video_position() -> void:
	if video_player == null or video_player.stream == null:
		return
	var state := current_state.duplicate(true)
	state["position"] = video_player.stream_position
	state["updated_at"] = Time.get_unix_time_from_system()
	Net.send_tv(state)
	if not Net.is_online():
		apply_state(state)


func _update_music_screen(force: bool) -> void:
	if world == null or world.dj == null:
		return
	var dj: QBODJSystem = world.dj
	title_label.text = dj.current_title
	artist_label.text = dj.current_artist
	live_label.text = "●  LIVE FROM THE DJ BOOTH" if dj.playing else "❚❚  DJ BOOTH PAUSED"
	live_label.add_theme_color_override("font_color", QBOTheme.ACCENT if dj.playing else QBOTheme.MUTED)
	eq_bars.set("active", dj.playing)
	var duration := dj.current_duration
	var position := dj.playback_position()
	time_label.text = "%s / %s" % [_format_time(position), _format_time(duration)]
	var ratio := 0.0
	if duration > 0.0:
		ratio = clampf(position / duration, 0.0, 1.0)
	progress_fill.size = Vector2(780.0 * ratio, 8.0)
	meta_label.text = "QUẨY BAR ONLINE  •  THE CHROME LOTUS  •  %d BÀI" % dj.track_count()
	if dj.current_cover_url != _cover_requested or force:
		_request_cover(dj.current_cover_url)


func _request_cover(url: String) -> void:
	_cover_requested = url
	_cover_url = url
	if url == "":
		cover_rect.texture = null
		cover_rect.visible = false
		cover_placeholder.visible = true
		return
	var dj: QBODJSystem = world.dj if world != null else null
	if dj == null:
		return
	var texture: Texture2D = await dj.load_cover(url)
	if _cover_requested != url or not is_inside_tree():
		return
	if texture == null:
		cover_rect.visible = false
		cover_placeholder.visible = true
		return
	cover_rect.texture = texture
	cover_rect.visible = true
	cover_placeholder.visible = false


func _exit_tree() -> void:
	_stop_video()
	if _download != null:
		_download.queue_free()
		_download = null


func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]


## Chênh lệch thời gian kể từ lúc state được tạo. Bỏ qua nếu đồng hồ hai máy
## lệch quá nhiều (không thể tin `updated_at` xuyên máy).
func _elapsed_since(updated_at: float) -> float:
	if updated_at <= 0.0:
		return 0.0
	var delta := Time.get_unix_time_from_system() - updated_at
	if delta < 0.0 or delta > 15.0:
		return 0.0
	return delta
