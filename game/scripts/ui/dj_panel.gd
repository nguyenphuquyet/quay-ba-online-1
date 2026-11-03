extends Control
## DJ Panel — bảng điều khiển booth: transport, playlist, volume, URL nhạc.

var ui: CanvasLayer
var params: Dictionary = {}

var _title: Label
var _status: Label
var _permission: Label
var _play_button: Button
var _volume: HSlider
var _playlist_box: VBoxContainer
var _url: LineEdit
var _beat_bar: ProgressBar
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.dj_received.connect(func(_action, _payload): _refresh())
	Net.room_settings_received.connect(func(_s): _refresh_permission())
	_refresh()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -560
	window.offset_right = 560
	window.offset_top = -360
	window.offset_bottom = 360
	window.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.04, 0.03, 0.055, 0.98), 18, Color(0.62, 0.4, 0.95, 0.4)))
	add_child(window)
	var root := QBOTheme.vbox(12)
	window.add_child(root)

	var head := QBOTheme.hbox(10)
	root.add_child(head)
	head.add_child(QBOTheme.title("DJ BOOTH", 30))
	head.add_child(QBOTheme.spacer())
	var close := QBOTheme.button("Đóng")
	close.pressed.connect(func(): ui.call("close_overlay"))
	head.add_child(close)

	_title = QBOTheme.label("", 20, QBOTheme.TEXT)
	root.add_child(_title)
	_status = QBOTheme.muted("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	_permission = QBOTheme.label("", 13, QBOTheme.GOLD)
	root.add_child(_permission)

	if AppConfig.is_mobile:
		var deep := QBOTheme.vbox(10)
		root.add_child(deep)
		root = deep

	var transport := QBOTheme.hbox(8)
	root.add_child(transport)
	var prev := QBOTheme.button("⏮")
	prev.custom_minimum_size = Vector2(64, 52)
	prev.pressed.connect(_prev)
	transport.add_child(prev)
	_play_button = QBOTheme.button("Phát", true)
	_play_button.custom_minimum_size = Vector2(120, 52)
	_play_button.pressed.connect(_toggle_play)
	transport.add_child(_play_button)
	var next := QBOTheme.button("⏭")
	next.custom_minimum_size = Vector2(64, 52)
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

	root.add_child(QBOTheme.section("PLAYLIST"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 140)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_playlist_box = QBOTheme.vbox(6)
	_playlist_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_playlist_box)

	root.add_child(QBOTheme.section("PHÁT NHẠC TỪ URL"))
	var url_row := QBOTheme.hbox(8)
	root.add_child(url_row)
	_url = QBOTheme.line_edit("URL mp3 / ogg / wav trực tiếp (có giấy phép sử dụng)")
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	url_row.add_child(_url)
	var load_button := QBOTheme.button("Tải & phát", true)
	load_button.pressed.connect(_load_url)
	url_row.add_child(load_button)
	var note := QBOTheme.muted("Không đóng gói nhạc thương mại. Chỉ dùng bản nhạc bạn có quyền sử dụng; nhạc demo trong game là bản tổng hợp gốc của QBO.", 12)
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
	_status.text = ("Đang phát" if dj.playing else "Đã tạm dừng") + "  •  track: " + dj.current_track_id + ("\nURL: " + dj.current_url if dj.current_url != "" else "")
	_play_button.text = "Tạm dừng" if dj.playing else "Phát"
	_volume.set_value_no_signal(dj.volume * 100.0)
	_refresh_playlist(dj)
	_refresh_permission()


func _refresh_playlist(dj: QBODJSystem) -> void:
	if _playlist_box == null:
		return
	for child in _playlist_box.get_children():
		child.queue_free()
	for track in dj.playlist():
		var row := QBOTheme.hbox(8)
		var label := QBOTheme.label("%s  —  %s" % [str(track.get("title", "?")), str(track.get("artist", ""))], 13, QBOTheme.TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var play := QBOTheme.button("Phát")
		play.custom_minimum_size = Vector2(66, 30)
		play.add_theme_font_size_override("font_size", 11)
		var track_id := str(track.get("id", ""))
		play.pressed.connect(func():
			dj.play_track(track_id)
			_refresh()
		)
		row.add_child(play)
		_playlist_box.add_child(row)


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


func _load_url() -> void:
	var url := _url.text.strip_edges()
	if url == "":
		return
	if App.world != null and App.world.dj != null:
		App.world.dj.play_url(url)
		_url.text = ""
		_refresh()


func _process(delta: float) -> void:
	_time += delta
	if _beat_bar != null and App.world != null and App.world.lighting != null:
		var beat: float = 0.5 + 0.5 * sin(_time * 8.0) if App.world.dj != null and App.world.dj.playing else 0.0
		_beat_bar.value = beat
		_play_button.text = "Tạm dừng" if App.world.dj != null and App.world.dj.playing else "Phát"
