extends Control
## DJ Panel — bảng điều khiển booth: thư viện nhạc API, transport, volume.

var ui: CanvasLayer
var params: Dictionary = {}

var _title: Label
var _artist: Label
var _status: Label
var _permission: Label
var _play_button: Button
var _volume: HSlider
var _playlist_box: VBoxContainer
var _library_status: Label
var _search: LineEdit
var _cover: TextureRect
var _cover_placeholder: Label
var _beat_bar: ProgressBar
var _time := 0.0
var _ui_timer := 0.0
var _playlist_signature := ""
var _cover_url := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.dj_received.connect(func(_action, _payload): _refresh())
	Net.room_settings_received.connect(func(_s): _refresh_permission())
	if App.world != null and App.world.dj != null:
		App.world.dj.library_changed.connect(_on_library_changed)
	_refresh()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -590
	window.offset_right = 590
	window.offset_top = -410
	window.offset_bottom = 410
	window.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.04, 0.03, 0.055, 0.98), 18, Color(0.62, 0.4, 0.95, 0.4)))
	add_child(window)
	var root := QBOTheme.vbox(10)
	window.add_child(root)

	var head := QBOTheme.hbox(10)
	root.add_child(head)
	head.add_child(QBOTheme.title("DJ BOOTH", 30))
	head.add_child(QBOTheme.spacer())
	var refresh := QBOTheme.button("Tải lại thư viện")
	refresh.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			App.world.dj.reload_library()
	)
	head.add_child(refresh)
	var close := QBOTheme.button("Đóng")
	close.pressed.connect(func(): ui.call("close_overlay"))
	head.add_child(close)

	var now := QBOTheme.hbox(14)
	root.add_child(now)
	var cover_panel := Panel.new()
	cover_panel.custom_minimum_size = Vector2(132, 132)
	cover_panel.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.02, 0.02, 0.05, 0.9), 6, Color(0.35, 0.9, 1.0, 0.3)))
	now.add_child(cover_panel)
	_cover = TextureRect.new()
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.offset_left = 6
	_cover.offset_top = 6
	_cover.offset_right = -6
	_cover.offset_bottom = -6
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.visible = false
	cover_panel.add_child(_cover)
	_cover_placeholder = QBOTheme.muted("QBO", 22)
	_cover_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cover_panel.add_child(_cover_placeholder)

	var info := QBOTheme.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now.add_child(info)
	_title = QBOTheme.label("", 24, QBOTheme.TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 2
	info.add_child(_title)
	_artist = QBOTheme.label("", 16, QBOTheme.ACCENT)
	info.add_child(_artist)
	_status = QBOTheme.muted("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_status)
	_permission = QBOTheme.label("", 13, QBOTheme.GOLD)
	info.add_child(_permission)

	if AppConfig.is_mobile:
		var deep := QBOTheme.vbox(10)
		root.add_child(deep)
		root = deep

	var transport := QBOTheme.hbox(8)
	root.add_child(transport)
	var prev := QBOTheme.button("⏮")
	prev.custom_minimum_size = Vector2(64, 48)
	prev.pressed.connect(_prev)
	transport.add_child(prev)
	_play_button = QBOTheme.button("Phát", true)
	_play_button.custom_minimum_size = Vector2(120, 48)
	_play_button.pressed.connect(_toggle_play)
	transport.add_child(_play_button)
	var next := QBOTheme.button("⏭")
	next.custom_minimum_size = Vector2(64, 48)
	next.pressed.connect(_next)
	transport.add_child(next)
	var sync := QBOTheme.button("Đồng bộ lại")
	sync.pressed.connect(func():
		if App.world != null and App.world.dj != null:
			Net.send_dj("sync", App.world.dj.build_state())
			ui.call("toast", "Đã đồng bộ trạng thái DJ.", "success")
	)
	transport.add_child(sync)

	var vol_row := QBOTheme.hbox(8)
	root.add_child(vol_row)
	vol_row.add_child(QBOTheme.section("ÂM LƯỢNG"))
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.custom_minimum_size = Vector2(0, 26)
	_volume.value_changed.connect(func(value: float):
		if App.world != null and App.world.dj != null:
			App.world.dj.set_volume(value)
	)
	vol_row.add_child(_volume)

	var beat_row := QBOTheme.hbox(8)
	root.add_child(beat_row)
	beat_row.add_child(QBOTheme.section("BEAT"))
	_beat_bar = ProgressBar.new()
	_beat_bar.show_percentage = false
	_beat_bar.max_value = 1.0
	_beat_bar.custom_minimum_size = Vector2(0, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = QBOTheme.PURPLE
	fill.set_corner_radius_all(3)
	_beat_bar.add_theme_stylebox_override("background", bg)
	_beat_bar.add_theme_stylebox_override("fill", fill)
	_beat_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	beat_row.add_child(_beat_bar)

	var lib_head := QBOTheme.hbox(8)
	root.add_child(lib_head)
	lib_head.add_child(QBOTheme.section("THƯ VIỆN NHẠC"))
	_library_status = QBOTheme.muted("", 12)
	_library_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lib_head.add_child(_library_status)
	_search = QBOTheme.line_edit("Tìm bài hát / nghệ sĩ…", false, 80)
	_search.custom_minimum_size = Vector2(240, 36)
	_search.text_changed.connect(func(_t): _rebuild_playlist())
	lib_head.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 230)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_playlist_box = QBOTheme.vbox(4)
	_playlist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_playlist_box)

	var note := QBOTheme.muted("Nguồn: music.nguyenphuquyet.online  •  Chỉ phát MP3/OGG/WAV. Các bài M4A (AAC) được ẩn vì Godot không giải mã native.", 11)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)


func _refresh_permission() -> void:
	if _permission == null:
		return
	var can := Net.can_control("dj")
	_permission.text = "Bạn được cấp quyền DJ." if can else "Bạn chưa có quyền DJ — nhờ chủ phòng cấp trong danh sách người chơi."
	_permission.add_theme_color_override("font_color", QBOTheme.SUCCESS if can else QBOTheme.GOLD)
	if _play_button != null:
		_play_button.disabled = not can
	if _volume != null:
		_volume.editable = can


func _refresh() -> void:
	if _title == null or App.world == null or App.world.dj == null:
		return
	var dj: QBODJSystem = App.world.dj
	_title.text = dj.current_title
	_artist.text = dj.current_artist if dj.current_artist != "" else "—"
	_status.text = ("Đang phát" if dj.playing else "Đã tạm dừng") + "  •  " + ("đang tải bài…" if dj.is_loading_track() else "sẵn sàng")
	_play_button.text = "Tạm dừng" if dj.playing else "Phát"
	_volume.set_value_no_signal(dj.volume)
	_update_library_status(dj)
	_rebuild_playlist()
	_refresh_permission()
	_update_cover(dj)


func _update_library_status(dj: QBODJSystem) -> void:
	if dj.library_loading:
		_library_status.text = "Đang tải danh sách từ API…"
	elif dj.library_error != "":
		_library_status.text = "%d bài  •  %s" % [dj.track_count(), dj.library_error]
	else:
		_library_status.text = "%d bài phát được" % dj.track_count()


func _rebuild_playlist() -> void:
	if _playlist_box == null or App.world == null or App.world.dj == null:
		return
	var dj: QBODJSystem = App.world.dj
	var filter := _search.text.strip_edges().to_lower() if _search != null else ""
	var signature := "%s|%d|%s|%s" % [dj.current_track_id, dj.track_count(), dj.library_loading, filter]
	if signature == _playlist_signature:
		return
	_playlist_signature = signature
	for child in _playlist_box.get_children():
		child.queue_free()
	var shown := 0
	var tracks := dj.playlist()
	for i in tracks.size():
		var track: Dictionary = tracks[i]
		var haystack := (str(track.get("title", "")) + " " + str(track.get("artist", ""))).to_lower()
		if filter != "" and not haystack.contains(filter):
			continue
		shown += 1
		var row := QBOTheme.hbox(8)
		var active := str(track.get("id", "")) == dj.current_track_id
		var label := QBOTheme.label("%02d  %s  —  %s" % [i + 1, str(track.get("title", "?")), str(track.get("artist", ""))], 13, QBOTheme.ACCENT if active else QBOTheme.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)
		var duration := float(track.get("duration", 0.0))
		var dur_label := QBOTheme.muted(_format_time(duration), 12)
		row.add_child(dur_label)
		var play := QBOTheme.button("Phát" if not active else "Đang phát")
		play.custom_minimum_size = Vector2(86, 28)
		play.add_theme_font_size_override("font_size", 11)
		play.disabled = active or not Net.can_control("dj")
		var track_id := str(track.get("id", ""))
		play.pressed.connect(func():
			dj.play_track(track_id)
			_refresh()
		)
		row.add_child(play)
		_playlist_box.add_child(row)
	if shown == 0:
		_playlist_box.add_child(QBOTheme.muted("Không có bài nào khớp bộ lọc.", 13))


func _update_cover(dj: QBODJSystem) -> void:
	if dj.current_cover_url == _cover_url:
		return
	_cover_url = dj.current_cover_url
	if _cover_url == "":
		_cover.visible = false
		_cover_placeholder.visible = true
		return
	var texture: Texture2D = await dj.load_cover(_cover_url)
	if _cover_url != dj.current_cover_url or not is_inside_tree():
		return
	if texture == null:
		_cover.visible = false
		_cover_placeholder.visible = true
		return
	_cover.texture = texture
	_cover.visible = true
	_cover_placeholder.visible = false


func _toggle_play() -> void:
	if App.world != null and App.world.dj != null:
		App.world.dj.toggle_play()
		_refresh()


func _next() -> void:
	if App.world != null and App.world.dj != null:
		App.world.dj.next_track()
		_refresh()


func _prev() -> void:
	if App.world != null and App.world.dj != null:
		App.world.dj.prev_track()
		_refresh()


func _on_library_changed() -> void:
	_playlist_signature = ""
	_refresh()


func _process(delta: float) -> void:
	_time += delta
	_ui_timer -= delta
	if _beat_bar != null and App.world != null and App.world.lighting != null:
		var playing: bool = App.world.dj != null and App.world.dj.playing
		var beat: float = 0.5 + 0.5 * sin(_time * 8.0) if playing else 0.0
		_beat_bar.value = beat
		if App.world.dj != null:
			_play_button.text = "Tạm dừng" if App.world.dj.playing else "Phát"
	if _ui_timer <= 0.0:
		_ui_timer = 0.4
		if App.world != null and App.world.dj != null:
			var dj: QBODJSystem = App.world.dj
			_title.text = dj.current_title
			_artist.text = dj.current_artist if dj.current_artist != "" else "—"
			_status.text = ("Đang phát" if dj.playing else "Đã tạm dừng") + "  •  " + ("đang tải bài…" if dj.is_loading_track() else "sẵn sàng")
			_update_library_status(dj)
			_rebuild_playlist()
			_update_cover(dj)


func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "--:--"
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
