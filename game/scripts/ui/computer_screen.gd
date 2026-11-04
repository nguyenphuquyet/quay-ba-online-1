extends Control
## Máy tính trong bar — trung tâm điều khiển nhạc DJ và TV lớn sân khấu.
## Không còn trình duyệt nhúng/YouTube: TV lớn chỉ phát nhạc từ API hoặc MP4 trực tiếp.

var ui: CanvasLayer
var params: Dictionary = {}

var _window: PanelContainer
var _tabbar: Control
var _tabs: Dictionary = {}
var _content: Dictionary = {}
var _fullscreen := false

var _dj_title: Label
var _dj_artist: Label
var _dj_status: Label
var _dj_play: Button
var _dj_volume: HSlider
var _dj_library: Label
var _dj_playlist: VBoxContainer
var _dj_signature := ""
var _dj_cover: TextureRect
var _dj_cover_url := ""

var _tv_url: LineEdit
var _tv_state: Label
var _tv_provider: Label
var _tv_cache: Label
var _tv_volume: HSlider
var _tv_play: Button
var _tv_publish: Button
var _tv_stop: Button
var _tv_permission: Label

var _ui_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	var tab := str(params.get("tab", "music"))
	if tab == "browser":
		tab = "music"
	_switch_tab(tab if _tabs.has(tab) else "music")
	Net.dj_received.connect(func(_action, _payload): _refresh_dj())
	Net.tv_received.connect(func(_s): _refresh_tv_state())
	Net.room_settings_received.connect(func(_s):
		_refresh_dj_permission()
		_refresh_tv_permissions()
	)
	if App.world != null and App.world.dj != null:
		App.world.dj.library_changed.connect(_on_library_changed)
	_refresh_dj()
	_refresh_tv_state()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_window = PanelContainer.new()
	if AppConfig.is_mobile:
		_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.offset_left = 8
		_window.offset_top = 8
		_window.offset_right = -8
		_window.offset_bottom = -8
	else:
		_window.set_anchors_preset(Control.PRESET_CENTER)
		_window.offset_left = -700
		_window.offset_right = 700
		_window.offset_top = -430
		_window.offset_bottom = 430
	_window.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.04, 0.032, 0.05, 0.98), 16, Color(0.85, 0.7, 0.43, 0.35)))
	add_child(_window)
	var root := QBOTheme.vbox(0)
	_window.add_child(root)

	var titlebar := PanelContainer.new()
	titlebar.name = "TitleBar"
	var tb_style := QBOTheme.panel_style(Color(0.07, 0.05, 0.08, 1.0), 10)
	tb_style.content_margin_left = 14
	tb_style.content_margin_right = 14
	tb_style.content_margin_top = 4
	tb_style.content_margin_bottom = 4
	titlebar.add_theme_stylebox_override("panel", tb_style)
	titlebar.custom_minimum_size = Vector2(0, 48)
	root.add_child(titlebar)
	var trow := QBOTheme.hbox(10)
	titlebar.add_child(trow)
	for color in [Color(1, 0.35, 0.4), Color(1, 0.75, 0.35), Color(0.4, 0.85, 0.5)]:
		trow.add_child(QBOTheme.swatch(color, 12))
	trow.add_child(QBOTheme.label("LOTUS CONTROL  —  máy tính trong bar", 14, QBOTheme.GOLD_BRIGHT))
	trow.add_child(QBOTheme.spacer())
	var expand := QBOTheme.button("⛶")
	expand.custom_minimum_size = Vector2(38, 32)
	expand.tooltip_text = "Phóng to / thu nhỏ cửa sổ"
	expand.pressed.connect(_toggle_fullscreen)
	trow.add_child(expand)
	var close := QBOTheme.button("×")
	close.custom_minimum_size = Vector2(38, 32)
	close.pressed.connect(_close)
	trow.add_child(close)

	var tabbar := QBOTheme.hbox(6)
	tabbar.name = "TabBar"
	tabbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(tabbar)
	_tabbar = tabbar
	for entry in [
		{"key": "music", "label": "NHẠC / DJ"},
		{"key": "tv", "label": "TV SÂN KHẤU"},
		{"key": "info", "label": "THÔNG TIN"},
	]:
		var button := QBOTheme.button(str(entry["label"]))
		button.custom_minimum_size = Vector2(0, 40)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func(): _switch_tab(str(entry["key"])))
		tabbar.add_child(button)
		_tabs[entry["key"]] = button

	var content_host := Control.new()
	content_host.name = "ContentHost"
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.custom_minimum_size = Vector2(0, 600)
	root.add_child(content_host)
	_build_music(content_host)
	_build_tv(content_host)
	_build_info(content_host)
	_switch_tab("music")


# ------------------------------------------------------------------ music tab

func _build_music(host: Control) -> void:
	var tab := QBOTheme.vbox(10)
	tab.name = "MusicTab"
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["music"] = tab

	var now := QBOTheme.hbox(12)
	tab.add_child(now)
	var cover_panel := Panel.new()
	cover_panel.custom_minimum_size = Vector2(104, 104)
	cover_panel.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.02, 0.02, 0.05, 0.9), 6, Color(0.35, 0.9, 1.0, 0.3)))
	now.add_child(cover_panel)
	_dj_cover = TextureRect.new()
	_dj_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dj_cover.offset_left = 5
	_dj_cover.offset_top = 5
	_dj_cover.offset_right = -5
	_dj_cover.offset_bottom = -5
	_dj_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dj_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_dj_cover.visible = false
	cover_panel.add_child(_dj_cover)

	var info := QBOTheme.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now.add_child(info)
	_dj_title = QBOTheme.label("", 22, QBOTheme.TEXT)
	_dj_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dj_title.max_lines_visible = 2
	info.add_child(_dj_title)
	_dj_artist = QBOTheme.label("", 15, QBOTheme.ACCENT)
	info.add_child(_dj_artist)
	_dj_status = QBOTheme.muted("", 12)
	_dj_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_dj_status)

	var transport := QBOTheme.hbox(8)
	tab.add_child(transport)
	var prev := QBOTheme.button("⏮")
	prev.custom_minimum_size = Vector2(60, 44)
	prev.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			App.world.dj.prev_track()
			_refresh_dj()
	)
	transport.add_child(prev)
	_dj_play = QBOTheme.button("Phát", true)
	_dj_play.custom_minimum_size = Vector2(116, 44)
	_dj_play.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			App.world.dj.toggle_play()
			_refresh_dj()
	)
	transport.add_child(_dj_play)
	var next := QBOTheme.button("⏭")
	next.custom_minimum_size = Vector2(60, 44)
	next.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			App.world.dj.next_track()
			_refresh_dj()
	)
	transport.add_child(next)
	var reload := QBOTheme.button("Tải lại thư viện")
	reload.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			App.world.dj.reload_library()
	)
	transport.add_child(reload)
	var vol_label := QBOTheme.muted("Âm lượng", 12)
	transport.add_child(vol_label)
	_dj_volume = HSlider.new()
	_dj_volume.min_value = 0.0
	_dj_volume.max_value = 1.0
	_dj_volume.step = 0.05
	_dj_volume.custom_minimum_size = Vector2(150, 24)
	_dj_volume.value_changed.connect(func(value: float):
		if App.world != null and App.world.dj != null:
			App.world.dj.set_volume(value)
	)
	transport.add_child(_dj_volume)

	var lib_head := QBOTheme.hbox(8)
	tab.add_child(lib_head)
	lib_head.add_child(QBOTheme.section("PLAYLIST TỪ API"))
	_dj_library = QBOTheme.muted("", 12)
	lib_head.add_child(_dj_library)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_dj_playlist = QBOTheme.vbox(4)
	_dj_playlist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_dj_playlist)

	var note := QBOTheme.muted("Thư viện: music.nguyenphuquyet.online/api/songs  •  MP3/OGG/WAV phát được; M4A bị ẩn.", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)


func _refresh_dj() -> void:
	if _dj_title == null or App.world == null or App.world.dj == null:
		return
	var dj: QBODJSystem = App.world.dj
	_dj_title.text = dj.current_title
	_dj_artist.text = dj.current_artist if dj.current_artist != "" else "—"
	_dj_status.text = ("Đang phát" if dj.playing else "Đã tạm dừng") + "  •  " + ("đang tải bài…" if dj.is_loading_track() else "sẵn sàng")
	_dj_play.text = "Tạm dừng" if dj.playing else "Phát"
	_dj_volume.set_value_no_signal(dj.volume)
	if dj.library_loading:
		_dj_library.text = "Đang tải API…"
	elif dj.library_error != "":
		_dj_library.text = "%d bài  •  %s" % [dj.track_count(), dj.library_error]
	else:
		_dj_library.text = "%d bài phát được" % dj.track_count()
	_rebuild_dj_playlist(dj)
	_update_dj_cover(dj)
	_refresh_dj_permission()


func _rebuild_dj_playlist(dj: QBODJSystem) -> void:
	if _dj_playlist == null:
		return
	var signature := "%s|%d|%s" % [dj.current_track_id, dj.track_count(), dj.library_loading]
	if signature == _dj_signature:
		return
	_dj_signature = signature
	for child in _dj_playlist.get_children():
		child.queue_free()
	var tracks := dj.playlist()
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var row := QBOTheme.hbox(8)
		var active := str(track.get("id", "")) == dj.current_track_id
		var label := QBOTheme.label("%02d  %s  —  %s" % [i + 1, str(track.get("title", "?")), str(track.get("artist", ""))], 12, QBOTheme.ACCENT if active else QBOTheme.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		var play := QBOTheme.button("Phát" if not active else "Đang phát")
		play.custom_minimum_size = Vector2(80, 26)
		play.add_theme_font_size_override("font_size", 10)
		play.disabled = active or not Net.can_control("dj")
		var track_id := str(track.get("id", ""))
		play.pressed.connect(func():
			dj.play_track(track_id)
			_refresh_dj()
		)
		row.add_child(play)
		_dj_playlist.add_child(row)


func _update_dj_cover(dj: QBODJSystem) -> void:
	if dj.current_cover_url == _dj_cover_url:
		return
	_dj_cover_url = dj.current_cover_url
	if _dj_cover_url == "":
		_dj_cover.visible = false
		return
	var texture: Texture2D = await dj.load_cover(_dj_cover_url)
	if _dj_cover_url != dj.current_cover_url or not is_inside_tree():
		return
	if texture == null:
		_dj_cover.visible = false
		return
	_dj_cover.texture = texture
	_dj_cover.visible = true


func _refresh_dj_permission() -> void:
	if _dj_play == null:
		return
	var can := Net.can_control("dj")
	_dj_play.disabled = not can
	_dj_volume.editable = can


func _on_library_changed() -> void:
	_dj_signature = ""
	_refresh_dj()


# ------------------------------------------------------------------ TV tab

func _build_tv(host: Control) -> void:
	var tab := QBOTheme.vbox(12)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["tv"] = tab
	tab.add_child(QBOTheme.section("TV LỚN Ở SÂN KHẤU"))
	var note := QBOTheme.muted("TV lớn giữa sân khấu phát màn nhạc DJ. Khi cần, bạn có thể phát video MP4/MOV trực tiếp trên TV này; trạng thái được đồng bộ cho cả phòng. TV nhỏ bên phải hiển thị thông tin nhà phát triển.", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	_tv_permission = QBOTheme.label("", 13, QBOTheme.GOLD)
	tab.add_child(_tv_permission)

	var row: BoxContainer = QBOTheme.vbox(8) if AppConfig.is_mobile else QBOTheme.hbox(8)
	tab.add_child(row)
	var input_row := QBOTheme.hbox(8)
	input_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input_row)
	_tv_url = QBOTheme.line_edit("Dán link MP4/MOV trực tiếp (https://…/video.mp4)", false, 1000)
	_tv_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tv_url.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	input_row.add_child(_tv_url)
	input_row.add_child(_paste_button(_tv_url))
	_tv_publish = QBOTheme.button("▶ Phát trên TV", true)
	_tv_publish.pressed.connect(_publish_tv)
	row.add_child(_tv_publish)

	var state_panel := QBOTheme.panel(16)
	tab.add_child(state_panel)
	var state_box := QBOTheme.vbox(6)
	state_panel.add_child(state_box)
	state_box.add_child(QBOTheme.section("TRẠNG THÁI HIỆN TẠI"))
	_tv_state = QBOTheme.label("TV lớn đang hiển thị màn nhạc DJ.", 14, QBOTheme.TEXT)
	_tv_state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_box.add_child(_tv_state)
	_tv_provider = QBOTheme.muted("", 12)
	_tv_provider.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_box.add_child(_tv_provider)

	var controls := QBOTheme.hbox(10)
	tab.add_child(controls)
	_tv_play = QBOTheme.button("Tạm dừng / Tiếp tục")
	_tv_play.pressed.connect(func():
		if App.world == null or App.world.tv == null:
			return
		var playing := bool(App.world.tv.current_state.get("playing", false))
		App.world.tv.set_playing(not playing)
	)
	controls.add_child(_tv_play)
	_tv_stop = QBOTheme.button("Trở về màn nhạc DJ")
	_tv_stop.pressed.connect(func():
		if App.world != null and App.world.tv != null:
			App.world.tv.stop_video()
	)
	controls.add_child(_tv_stop)
	var vol_label := QBOTheme.muted("Âm lượng TV", 12)
	controls.add_child(vol_label)
	_tv_volume = HSlider.new()
	_tv_volume.min_value = 0.0
	_tv_volume.max_value = 1.0
	_tv_volume.step = 0.05
	_tv_volume.value = 1.0
	_tv_volume.custom_minimum_size = Vector2(160, 24)
	_tv_volume.value_changed.connect(func(value: float):
		if App.world != null and App.world.tv != null:
			App.world.tv.set_volume(value)
	)
	controls.add_child(_tv_volume)

	var cache_row := QBOTheme.hbox(10)
	tab.add_child(cache_row)
	_tv_cache = QBOTheme.muted("", 12)
	_tv_cache.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cache_row.add_child(_tv_cache)
	var clear_cache := QBOTheme.button("Xoá cache video")
	clear_cache.pressed.connect(_clear_video_cache)
	cache_row.add_child(clear_cache)

	var policy := QBOTheme.muted("Video phát trực tiếp bằng VideoStreamPlayer + addon native_video (MP4/H.264). Không dùng WebView, iframe hay tải video từ YouTube.", 12)
	policy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(policy)


func _publish_tv() -> void:
	if not Net.can_control("tv"):
		ui.call("toast", "Bạn không có quyền điều khiển TV. Chủ phòng có thể cấp quyền.", "error")
		return
	var url := _tv_url.text.strip_edges()
	if url == "":
		ui.call("toast", "Dán link video MP4/MOV trực tiếp trước.", "warn")
		return
	if App.world == null or App.world.tv == null:
		ui.call("toast", "Chưa ở trong phòng.", "error")
		return
	var result: Dictionary = App.world.tv.play_video_url(url)
	if bool(result.get("ok", false)):
		ui.call("toast", "Đang phát video trên TV lớn.", "success")
		_tv_url.text = ""
	else:
		ui.call("toast", str(result.get("reason", "Không phát được video.")), "error")
	_refresh_tv_state()


func _refresh_tv_state() -> void:
	if _tv_state == null:
		return
	var state: Dictionary = Net.tv_state
	if state.is_empty() or str(state.get("kind", "")) != "video":
		_tv_state.text = "TV lớn đang hiển thị màn nhạc DJ."
		_tv_provider.text = "MP4/MOV: addon native_video"
	else:
		_tv_state.text = "%s\n%s\nNgười gửi: %s" % [
			str(state.get("title", "—")),
			str(state.get("status", "")),
			str(state.get("by", "—")),
		]
		_tv_provider.text = "%s  •  %s" % [str(state.get("url", "")), "đang phát" if bool(state.get("playing", false)) else "tạm dừng"]
	_refresh_tv_cache()
	_refresh_tv_permissions()


func _refresh_tv_cache() -> void:
	if _tv_cache == null:
		return
	var stats: Dictionary = App.world.tv.video_cache_stats() if App.world != null and App.world.tv != null else {}
	var files := int(stats.get("files", 0))
	var total := int(stats.get("bytes", 0))
	_tv_cache.text = "Cache video: %d tệp • %s (tự dọn khi vượt 1.5 GB)" % [files, _format_bytes(total)]


func _clear_video_cache() -> void:
	if App.world == null or App.world.tv == null:
		return
	var result: Dictionary = App.world.tv.clear_video_cache()
	if bool(result.get("ok", false)):
		ui.call("toast", "Đã xoá %d tệp cache video." % int(result.get("removed", 0)), "success")
	else:
		ui.call("toast", str(result.get("reason", "Không xoá được cache.")), "warn")
	_refresh_tv_cache()


func _format_bytes(value: int) -> String:
	if value >= 1024 * 1024 * 1024:
		return "%.2f GB" % (float(value) / (1024.0 * 1024.0 * 1024.0))
	if value >= 1024 * 1024:
		return "%.1f MB" % (float(value) / (1024.0 * 1024.0))
	if value >= 1024:
		return "%.0f KB" % (float(value) / 1024.0)
	return "%d B" % value


func _refresh_tv_permissions() -> void:
	if _tv_permission == null:
		return
	var can := Net.can_control("tv")
	_tv_permission.text = "Bạn có quyền điều khiển TV." if can else "Bạn chưa có quyền điều khiển TV — chỉ chủ phòng hoặc người được cấp quyền."
	_tv_permission.add_theme_color_override("font_color", QBOTheme.SUCCESS if can else QBOTheme.GOLD)
	_tv_publish.disabled = not can
	_tv_play.disabled = not can
	_tv_stop.disabled = not can
	_tv_volume.editable = can


# ------------------------------------------------------------------ info tab

func _build_info(host: Control) -> void:
	var tab := QBOTheme.vbox(12)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["info"] = tab
	tab.add_child(QBOTheme.section("LOTUS CONTROL — THÔNG TIN"))
	tab.add_child(QBOTheme.label("Máy tính này điều khiển booth DJ và TV lớn ở sân khấu.", 15))
	for line in [
		"Thư viện nhạc: %s" % AppConfig.music_songs_url(),
		"Định dạng audio: MP3, OGG, WAV (M4A/AAC bị ẩn).",
		"Định dạng video TV: MP4, MOV, M4V, OGV.",
		"MP4/H.264 dùng addon native_video (Windows/macOS/Linux, Forward+).",
		"Không còn WebView, iframe YouTube hay tải video từ YouTube.",
		"Trạng thái DJ/TV được server giữ lại để người vào sau đồng bộ đúng.",
		"",
		"Bảo mật:",
		"• Chặn localhost, mạng nội bộ và địa chỉ metadata (chống SSRF).",
		"• Chỉ cho phép http/https và media trực tiếp.",
		"• Không lưu cookie/mật khẩu website.",
	]:
		var label := QBOTheme.label(str(line), 13, QBOTheme.MUTED if str(line).begins_with("•") or str(line) == "" else QBOTheme.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tab.add_child(label)


# ------------------------------------------------------------------ helpers

func _switch_tab(key: String) -> void:
	for tab_key in _content.keys():
		var node: Control = _content[tab_key]
		node.visible = tab_key == key
	for tab_key in _tabs.keys():
		var button: Button = _tabs[tab_key]
		button.disabled = tab_key == key
	if key == "tv":
		_refresh_tv_state()
	elif key == "music":
		_refresh_dj()


func _paste_button(field: LineEdit) -> Button:
	var button := QBOTheme.button("📋 Dán")
	button.custom_minimum_size = Vector2(84, 44)
	button.tooltip_text = "Dán nội dung đang có trong bộ nhớ tạm"
	button.pressed.connect(func():
		var clip := DisplayServer.clipboard_get().strip_edges()
		clip = clip.replace("\r", "").replace("\n", "").replace("\t", "")
		if clip == "":
			ui.call("toast", "Bộ nhớ tạm đang trống — hãy sao chép link trước.", "warn")
			return
		field.grab_focus()
		field.text = clip
		field.caret_column = field.text.length()
	)
	return button


func _process(delta: float) -> void:
	_ui_timer -= delta
	if _ui_timer > 0.0:
		return
	_ui_timer = 0.5
	if _content.get("music", null) != null and _content["music"].visible:
		_refresh_dj()


func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	_apply_layout()


func _apply_layout() -> void:
	if AppConfig.is_mobile:
		_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window.offset_left = 8
		_window.offset_top = 8
		_window.offset_right = -8
		_window.offset_bottom = -8
	elif _fullscreen:
		_window.offset_left = -780
		_window.offset_right = 780
		_window.offset_top = -440
		_window.offset_bottom = 440
	else:
		_window.offset_left = -700
		_window.offset_right = 700
		_window.offset_top = -430
		_window.offset_bottom = 430
	if _tabbar != null:
		_tabbar.visible = not _fullscreen


func _close() -> void:
	ui.call("close_overlay")
