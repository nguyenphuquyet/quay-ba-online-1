extends Control
## Computer Desktop — máy tính trong bar: Lotus Browser, TV/LED và thông tin.
## Đây là URL dispatcher thật + bridge tới BrowserProvider; không giả lập render web.

var ui: CanvasLayer
var params: Dictionary = {}

var provider: QBOBrowserProvider
var _window: PanelContainer
var _tabbar: Control
var _tabs: Dictionary = {}
var _content: Dictionary = {}
var _address: LineEdit
var _browser_status: Label
var _page: VBoxContainer
var _page_scroll: ScrollContainer
var _history: Array = []
var _history_index := -1
var _web_surface_enabled := false
var _webview_texture: TextureRect
var _current_url := "qbo://home"
var _fullscreen := false

var _tv_url: LineEdit
var _tv_state: Label
var _tv_volume: HSlider
var _tv_publish: Button
var _tv_play: Button
var _tv_provider: Label
var _tv_permission: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	provider = QBOBrowserFactory.create()
	_build()
	var tab := str(params.get("tab", "browser"))
	_switch_tab(tab if _tabs.has(tab) else "browser")
	if tab == "tv":
		_refresh_tv_state()
	Net.tv_received.connect(func(_s): _refresh_tv_state())
	Net.room_settings_received.connect(func(_s): _refresh_tv_permissions())


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	# Cửa sổ lớn hơn hẳn để trang web đọc được; nút ⛶ còn phóng to gần kín màn hình.
	_window.offset_left = -720
	_window.offset_right = 720
	_window.offset_top = -430
	_window.offset_bottom = 430
	_window.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.04, 0.032, 0.05, 0.98), 16, Color(0.85, 0.7, 0.43, 0.35)))
	add_child(_window)
	var root := QBOTheme.vbox(0)
	_window.add_child(root)

	var titlebar := PanelContainer.new()
	titlebar.name = "TitleBar"
	var tb_style := QBOTheme.panel_style(Color(0.07, 0.05, 0.08, 1.0), 10)
	# Thanh tiêu đề mỏng: mặc định panel_style đệm 24/22px làm nó cao gần 100px.
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
	trow.add_child(QBOTheme.label("LOTUS NET  —  máy tính trong bar", 14, QBOTheme.GOLD_BRIGHT))
	trow.add_child(QBOTheme.spacer())
	trow.add_child(QBOTheme.muted(str(provider.provider_name()), 12))
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
		{"key": "browser", "label": "YOUTUBE"},
		{"key": "tv", "label": "TV / MÀN HÌNH LED"},
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
	content_host.custom_minimum_size = Vector2(0, 560)
	root.add_child(content_host)
	_build_browser(content_host)
	_build_tv(content_host)
	_build_info(content_host)
	_switch_tab("browser")
	_render_home()


func _build_browser(host: Control) -> void:
	var tab := QBOTheme.vbox(10)
	tab.name = "BrowserTab"
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["browser"] = tab

	var nav := QBOTheme.hbox(6)
	nav.name = "NavBar"
	tab.add_child(nav)
	var home := QBOTheme.button("⌂")
	home.custom_minimum_size = Vector2(42, 40)
	home.tooltip_text = "Về trang chủ LOTUS NET"
	home.pressed.connect(func(): _navigate("qbo://home"))
	nav.add_child(home)
	_address = QBOTheme.line_edit("Dán link video YouTube: youtube.com/watch?v=… hoặc youtu.be/…")
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address.text = ""
	_address.text_submitted.connect(func(_t): _play_from_address())
	nav.add_child(_address)
	var go := QBOTheme.button("▶ Phát video", true)
	go.pressed.connect(_play_from_address)
	nav.add_child(go)

	_browser_status = QBOTheme.muted("", 12)
	_browser_status.name = "BrowserStatus"
	_browser_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(_browser_status)

	var content_panel := QBOTheme.panel(8)
	content_panel.name = "WebPanel"
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(content_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_panel.add_child(scroll)
	_page_scroll = scroll
	var holder := Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	_page = QBOTheme.vbox(10)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(_page)
	_webview_texture = TextureRect.new()
	_webview_texture.name = "WebView"
	_webview_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_webview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Giữ đúng tỉ lệ 16:9 của trang/video; phần thừa hai bên là nền tối, không
	# kéo méo hình. Chuột được ánh xạ theo vùng ảnh thật trong _page_pixel_from_local.
	_webview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_webview_texture.visible = false
	_webview_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_webview_texture.focus_mode = Control.FOCUS_ALL
	_webview_texture.gui_input.connect(_on_web_surface_input)
	content_panel.add_child(_webview_texture)


func _build_tv(host: Control) -> void:
	var tab := QBOTheme.vbox(12)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["tv"] = tab
	tab.add_child(QBOTheme.section("ĐIỀU KHIỂN MÀN HÌNH SÂN KHẤU"))
	var note := QBOTheme.muted("Nội dung bạn gửi sẽ hiện trên TV phụ ở sân khấu và đồng bộ cho cả phòng. Chỉ chủ phòng hoặc người được cấp quyền mới điều khiển được.", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(note)
	_tv_permission = QBOTheme.label("", 13, QBOTheme.GOLD)
	tab.add_child(_tv_permission)

	var row := QBOTheme.hbox(8)
	tab.add_child(row)
	_tv_url = QBOTheme.line_edit("Dán link video YouTube cần phát trên TV")
	_tv_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tv_url)
	_tv_publish = QBOTheme.button("▶ Phát trên TV", true)
	_tv_publish.pressed.connect(_publish_tv)
	row.add_child(_tv_publish)

	var state_panel := QBOTheme.panel(16)
	tab.add_child(state_panel)
	var state_box := QBOTheme.vbox(6)
	state_panel.add_child(state_box)
	state_box.add_child(QBOTheme.section("TRẠNG THÁI HIỆN TẠI"))
	_tv_state = QBOTheme.label("Chưa có nội dung.", 14, QBOTheme.TEXT)
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
	var stop := QBOTheme.button("Tắt màn hình")
	stop.pressed.connect(func():
		if App.world != null and App.world.tv != null:
			Net.send_tv({"url": "", "title": "The Chrome Lotus", "playing": false, "kind": "idle", "status": "Màn hình đã tắt.", "provider": "", "volume": 1.0, "position": 0.0})
	)
	controls.add_child(stop)
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

	var policy := QBOTheme.muted("TV phụ ở sân khấu phát video YouTube bằng iframe nhúng chính thức, đồng bộ với máy tính này cho cả phòng. Bạn chỉ cần dán link video; không phải thao tác trên cả trang web. TV lớn ở giữa vẫn chạy visualizer.", 12)
	policy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(policy)


func _build_info(host: Control) -> void:
	var tab := QBOTheme.vbox(12)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab.offset_top = 12
	host.add_child(tab)
	_content["info"] = tab
	tab.add_child(QBOTheme.section("LOTUS NET — THÔNG TIN"))
	tab.add_child(QBOTheme.label("Máy tính này là điểm điều khiển TV phụ (màn web) và truy cập web trong bar.", 15))
	var lines := [
		"BrowserProvider hiện tại: %s" % provider.provider_name(),
		"Nền tảng: %s" % provider.platform(),
		"Nhúng web: %s" % ("Có" if provider.is_embedded_supported() else "Chưa hỗ trợ trên máy này"),
		"Lý do: %s" % str(provider.capability().get("reason", "—")),
		"",
		"Bảo mật:",
		"• Chặn localhost, mạng nội bộ và địa chỉ metadata (chống SSRF).",
		"• Chỉ cho phép http/https; chặn javascript:, file:, data:.",
		"• Không lưu mật khẩu hay cookie website của người chơi.",
		"• Không vượt DRM hay giả lập trình duyệt để tải nội dung trái phép.",
		"• Trang ngoài allowlist cần xác nhận trước khi mở.",
		"",
		"Tài liệu tích hợp native WebView: docs/BROWSER.md",
	]
	for line in lines:
		var label := QBOTheme.label(str(line), 13, QBOTheme.MUTED if str(line).begins_with("•") or str(line) == "" else QBOTheme.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tab.add_child(label)
	tab.add_child(QBOTheme.hsep(8))
	var external := QBOTheme.button("Mở trang chủ YouTube bằng trình duyệt hệ thống")
	external.pressed.connect(func(): OS.shell_open("https://www.youtube.com"))
	tab.add_child(external)


func _switch_tab(key: String) -> void:
	for tab_key in _content.keys():
		var node: Control = _content[tab_key]
		node.visible = tab_key == key
	for tab_key in _tabs.keys():
		var button: Button = _tabs[tab_key]
		button.disabled = tab_key == key
	if key == "tv":
		_refresh_tv_state()


func _nav_action(symbol: String) -> void:
	match symbol:
		"←":
			_history_back()
		"→":
			_history_forward()
		"⟳":
			_navigate(_current_url)
		"⌂":
			_navigate("qbo://home")


func _play_from_address() -> void:
	var link := _address.text.strip_edges()
	if link == "":
		ui.call("toast", "Dán link video YouTube trước.", "warn")
		return
	if QBOUrlGuard.youtube_video_id(link) == "":
		ui.call("toast", "Link YouTube không hợp lệ.", "error")
		return
	_navigate(link)


func _navigate(input: String) -> void:
	var target := input.strip_edges()
	if target == "":
		return
	var video_id := QBOUrlGuard.youtube_video_id(target)
	if video_id != "":
		# Link YouTube: phát thẳng bằng iframe nhúng, không mở cả trang web.
		var watch_url := "https://www.youtube.com/watch?v=" + video_id
		_current_url = watch_url
		_address.text = watch_url
		_push_history(watch_url)
		_open_external(watch_url, QBOUrlGuard.validate(watch_url))
		return
	if target.begins_with("qbo://"):
		_address.text = target
		_current_url = target
		_push_history(target)
		if target == "qbo://home":
			_render_home()
		elif target == "qbo://rules":
			_render_rules()
		elif target == "qbo://help":
			_render_help()
		elif target == "qbo://room":
			_render_room()
		else:
			_render_home()
		return
	var check := QBOUrlGuard.validate(target)
	if not check["ok"]:
		_render_notice("Không mở được URL", str(check["reason"]), QBOTheme.DANGER)
		return
	var url := str(check["url"])
	_current_url = url
	_address.text = url
	_push_history(url)
	if not bool(check["trusted"]):
		_render_confirm_external(url)
		return
	_open_external(url, check)


func _open_external(url: String, check: Dictionary) -> void:
	var capability := provider.capability()
	var embedded := bool(capability.get("embedded", false))
	_browser_status.text = "Provider: %s" % provider.provider_name()
	# Ưu tiên màn web dùng chung: máy tính và TV phụ hiển thị cùng một trang.
	if App.world != null and App.world.tv != null and App.world.tv.web_available():
		var result: Dictionary = App.world.tv.show_shared(url, "")
		if bool(result.get("ok", false)):
			_render_notice(
				"Đang hiển thị trên TV phụ",
				"Trang này được render bởi %s và đồng bộ với TV phụ ở sân khấu. Bấm trực tiếp vào trang hoặc vào TV trong club để thao tác." % App.world.tv.web_backend_name(),
				QBOTheme.SUCCESS
			)
			_show_shared_page(url)
			return
	embedded = embedded or (App.world != null and App.world.tv != null and App.world.tv.web_available())
	if embedded and provider.open(url):
		_webview_texture.visible = true
		var texture := provider.get_texture()
		if texture != null:
			_webview_texture.texture = texture
		_render_notice("Đang hiển thị trong WebView", "Trang được render bởi %s. Tôn trọng chính sách nhúng của website." % provider.provider_name(), QBOTheme.SUCCESS)
		return
	_webview_texture.visible = false
	if str(check["kind"]) == "youtube":
		_render_notice(
			"YouTube chưa thể phát tại đây",
			"Thiết bị này chưa có trình duyệt nhúng. Bạn có thể mở bằng trình duyệt hệ thống hoặc gửi URL lên TV phụ để cả phòng cùng biết nội dung. Không tải video trực tiếp để tránh vi phạm chính sách YouTube.",
			QBOTheme.GOLD,
			url
		)
	elif str(check["kind"]) == "video":
		_render_notice(
			"Video .ogv có thể phát trên TV",
			"Godot hỗ trợ native Theora (.ogv). Gửi URL lên TV để phát đồng bộ cho cả phòng; MP4 cần WebView/plugin.",
			QBOTheme.GOLD,
			url
		)
	else:
		_render_notice(
			"Chưa nhúng được trang web",
			str(capability.get("reason", "Thiếu WebView/CEF provider.")),
			QBOTheme.GOLD,
			url
		)


func _show_shared_page(url: String) -> void:
	_web_surface_enabled = true
	_webview_texture.visible = true
	if _page_scroll != null:
		_page_scroll.visible = false
	if _webview_texture.texture == null and App.world != null and App.world.tv != null:
		_webview_texture.texture = App.world.tv.shared_texture()
	_address.text = url
	_browser_status.text = "Đồng bộ TV phụ  •  %s" % App.world.tv.web_backend_name()
	_apply_layout()


func _on_web_surface_input(event: InputEvent) -> void:
	if App.world == null or App.world.tv == null:
		return
	if event is InputEventKey:
		# Gõ trực tiếp vào trang đang phản chiếu từ TV.
		App.world.tv.key_page(event, event.pressed)
		_webview_texture.accept_event()
		return
	if event is InputEventMouseMotion:
		var pixel := _page_pixel_from_local(event.position)
		if pixel.x >= 0.0:
			App.world.tv.move_page(pixel)
		_webview_texture.accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		var pixel := _page_pixel_from_local(event.position)
		if pixel.x < 0.0:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			_webview_texture.grab_focus()
			App.world.tv.click_page(pixel)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			App.world.tv.wheel_page(pixel, -120.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			App.world.tv.wheel_page(pixel, 120.0)
		else:
			return
		_webview_texture.accept_event()


func _page_pixel_from_local(local: Vector2) -> Vector2:
	var box := _webview_texture.size
	if box.x <= 1.0 or box.y <= 1.0:
		return Vector2(-1, -1)
	# Ảnh 16:9 nằm giữa khung (STRETCH_KEEP_ASPECT_CENTERED): trừ viền hai bên
	# rồi chia theo tỉ lệ để ra pixel CSS 1280x720 của trang.
	var css_size := Vector2(QBOTVSystem.SCREEN_SIZE)
	var scale := minf(box.x / css_size.x, box.y / css_size.y)
	var content := css_size * scale
	var offset := (box - content) * 0.5
	var point := (local - offset) / scale
	if point.x < 0.0 or point.y < 0.0 or point.x > css_size.x or point.y > css_size.y:
		return Vector2(-1, -1)
	return point


func _process(_delta: float) -> void:
	if App.world == null or App.world.tv == null:
		return
	var tv = App.world.tv
	if not tv.is_web_active():
		return
	var texture: Texture2D = tv.shared_texture()
	if texture == null:
		return
	if not _web_surface_enabled:
		_show_shared_page(tv.shared_url())
	_webview_texture.texture = texture
	if not _address.has_focus():
		_address.text = tv.shared_url()


func _render_confirm_external(url: String) -> void:
	_clear_page()
	_page.add_child(QBOTheme.title("XÁC NHẬN MỞ TRANG NGOÀI", 24))
	var label := QBOTheme.muted("Trang này không nằm trong allowlist. Chỉ tiếp tục nếu bạn tin tưởng nguồn:\n%s" % url, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_page.add_child(label)
	var row := QBOTheme.hbox(10)
	var proceed := QBOTheme.button("Tiếp tục mở", true)
	proceed.pressed.connect(func():
		var check := QBOUrlGuard.validate(url)
		if check["ok"]:
			_open_external(str(check["url"]), check)
	)
	row.add_child(proceed)
	var cancel := QBOTheme.button("Hủy")
	cancel.pressed.connect(func(): _navigate("qbo://home"))
	row.add_child(cancel)
	_page.add_child(row)


func _render_home() -> void:
	_clear_page()
	_browser_status.text = "LOTUS TV  •  phát video YouTube bằng iframe nhúng"
	_page.add_child(QBOTheme.title("LOTUS NET", 30))
	_page.add_child(QBOTheme.muted("Dán link video YouTube vào thanh phía trên rồi bấm “▶ Phát video”. Video sẽ hiện trên màn web của máy tính và TV phụ ở sân khấu, đồng bộ cho cả phòng.", 14))
	_page.add_child(QBOTheme.hsep(6))
	_page.add_child(QBOTheme.section("VIDEO MẪU"))
	var samples := QBOTheme.hbox(8)
	_page.add_child(samples)
	for item in [
		{"label": "Big Buck Bunny", "url": "https://www.youtube.com/watch?v=aqz-KE-bpKQ"},
		{"label": "Blender Open Movie", "url": "https://www.youtube.com/watch?v=YE7VzlLtp-4"},
	]:
		var button := QBOTheme.button(str(item["label"]))
		button.pressed.connect(func(): _navigate(str(item["url"])))
		samples.add_child(button)
	_page.add_child(QBOTheme.hsep(6))
	_page.add_child(QBOTheme.section("TRANG NỘI BỘ"))
	var internal := QBOTheme.hbox(8)
	_page.add_child(internal)
	for item in [
		{"label": "Quy định club", "url": "qbo://rules"},
		{"label": "Hướng dẫn TV", "url": "qbo://help"},
		{"label": "Phòng hiện tại", "url": "qbo://room"},
	]:
		var button := QBOTheme.button(str(item["label"]))
		button.pressed.connect(func(): _navigate(str(item["url"])))
		internal.add_child(button)


func _render_rules() -> void:
	_clear_page()
	_page.add_child(QBOTheme.title("QUY ĐỊNH CLUB", 26))
	for line in [
		"1. Tôn trọng mọi người trong phòng; không quấy rối, phân biệt đối xử.",
		"2. Không phát nội dung vi phạm bản quyền hoặc DRM.",
		"3. Chủ phòng có quyền khóa DJ/TV/ánh sáng và mời người vi phạm ra ngoài.",
		"4. Không chia sẻ link độc hại, lừa đảo hoặc nội dung người lớn.",
		"5. Báo cáo hành vi xấu qua hồ sơ người chơi hoặc API /api/reports.",
	]:
		var label := QBOTheme.label(line, 14, QBOTheme.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_page.add_child(label)


func _render_help() -> void:
	_clear_page()
	_page.add_child(QBOTheme.title("HƯỚNG DẪN TV / MÀN HÌNH LED", 26))
	for line in [
		"Mở tab TV / MÀN HÌNH LED, nhập URL rồi bấm Gửi lên TV.",
		"Màn hình TV phụ ở sân khấu hiển thị trạng thái đồng bộ cho cả phòng.",
		"Video .ogv (Theora) phát native và đồng bộ thời gian.",
		"YouTube chỉ phát khi thiết bị có WebView nhúng; nếu không, hãy mở bằng trình duyệt hệ thống.",
		"Âm lượng TV được đồng bộ cùng trạng thái.",
	]:
		var label := QBOTheme.label("• " + line, 14, QBOTheme.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_page.add_child(label)


func _render_room() -> void:
	_clear_page()
	_page.add_child(QBOTheme.title("PHÒNG HIỆN TẠI", 26))
	var room: Dictionary = GameState.room
	_page.add_child(QBOTheme.label("Tên: %s" % str(room.get("name", "—")), 15))
	_page.add_child(QBOTheme.label("Mã: %s" % str(room.get("code", "—")), 15, QBOTheme.CYAN))
	_page.add_child(QBOTheme.label("Sức chứa: %d" % int(room.get("maxPlayers", 0)), 15))
	_page.add_child(QBOTheme.label("Số người: %d" % Net.players.size(), 15))
	var owner_name := "—"
	if room.get("owner") is Dictionary:
		owner_name = str(room["owner"].get("displayName", "—"))
	_page.add_child(QBOTheme.label("Chủ phòng: %s" % owner_name, 15))


func _render_notice(title: String, body: String, color: Color, url := "") -> void:
	_clear_page()
	var heading := QBOTheme.label(title, 24, color)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(heading)
	var label := QBOTheme.muted(body, 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page.add_child(label)
	if url != "":
		var url_label := QBOTheme.label(url, 12, QBOTheme.CYAN)
		url_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_page.add_child(url_label)
		var row := QBOTheme.hbox(8)
		_page.add_child(row)
		var open_external := QBOTheme.button("Mở bằng trình duyệt hệ thống")
		open_external.pressed.connect(func(): OS.shell_open(url))
		row.add_child(open_external)
		var send_tv := QBOTheme.button("Gửi lên TV sân khấu")
		send_tv.disabled = not (App.world != null and Net.can_control("tv"))
		send_tv.pressed.connect(func():
			if App.world != null and App.world.tv != null:
				var result: Dictionary = App.world.tv.publish(url, "", true)
				if bool(result.get("ok", false)):
					ui.call("toast", str(result.get("status", "Đã gửi lên TV.")), "success")
				else:
					ui.call("toast", str(result.get("reason", "Không gửi được.")), "error")
		)
		row.add_child(send_tv)


func _clear_page() -> void:
	if _page == null:
		return
	for child in _page.get_children():
		child.queue_free()
	_web_surface_enabled = false
	if _webview_texture != null:
		_webview_texture.visible = false
	if _page_scroll != null:
		_page_scroll.visible = true
	_apply_layout()


func _push_history(url: String) -> void:
	if _history_index >= 0 and _history_index < _history.size() and str(_history[_history_index]) == url:
		return
	_history = _history.slice(0, _history_index + 1)
	_history.append(url)
	_history_index = _history.size() - 1


func _history_back() -> void:
	if _history_index > 0:
		_history_index -= 1
		var url := str(_history[_history_index])
		_address.text = url
		_navigate(url)


func _history_forward() -> void:
	if _history_index >= 0 and _history_index < _history.size() - 1:
		_history_index += 1
		var url := str(_history[_history_index])
		_address.text = url
		_navigate(url)


func _publish_tv() -> void:
	if not Net.can_control("tv"):
		ui.call("toast", "Bạn không có quyền điều khiển TV. Chủ phòng có thể cấp quyền.", "error")
		return
	var url := _tv_url.text.strip_edges()
	if url == "":
		ui.call("toast", "Dán link video YouTube trước khi phát lên TV.", "warn")
		return
	if App.world == null or App.world.tv == null:
		ui.call("toast", "Chưa ở trong phòng.", "error")
		return
	if QBOUrlGuard.youtube_video_id(url) == "":
		ui.call("toast", "Link YouTube không hợp lệ.", "error")
		return
	var result: Dictionary = App.world.tv.play_youtube(url)
	if bool(result.get("ok", false)):
		ui.call("toast", str(result.get("status", "Đang phát video trên TV.")), "success")
	else:
		ui.call("toast", str(result.get("reason", "Không phát được video.")), "error")
	_refresh_tv_state()


func _refresh_tv_state() -> void:
	if _tv_state == null:
		return
	var state: Dictionary = Net.tv_state
	if state.is_empty():
		_tv_state.text = "Chưa có nội dung được chia sẻ."
		_tv_provider.text = "Provider: %s" % provider.provider_name()
	else:
		_tv_state.text = "%s\n%s\nNgười gửi: %s" % [
			str(state.get("title", "—")),
			str(state.get("status", "")),
			str(state.get("by", "—")),
		]
		_tv_provider.text = str(state.get("provider", ""))
	_refresh_tv_permissions()


func _refresh_tv_permissions() -> void:
	if _tv_permission == null:
		return
	var can := Net.can_control("tv")
	_tv_permission.text = "Bạn có quyền điều khiển TV." if can else "Bạn chưa có quyền điều khiển TV — chỉ chủ phòng hoặc người được cấp quyền."
	_tv_permission.add_theme_color_override("font_color", QBOTheme.SUCCESS if can else QBOTheme.GOLD)
	_tv_publish.disabled = not can


func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	_apply_layout()


func _apply_layout() -> void:
	# Khi đang xem web: giấu dòng trạng thái; chế độ ⛶ giấu thêm thanh tab để
	# nhường toàn bộ chiều cao cho trang.
	if _fullscreen:
		_window.offset_left = -790
		_window.offset_right = 790
		_window.offset_top = -445
		_window.offset_bottom = 445
	else:
		_window.offset_left = -720
		_window.offset_right = 720
		_window.offset_top = -430
		_window.offset_bottom = 430
	if _tabbar != null:
		_tabbar.visible = not _fullscreen
	if _browser_status != null:
		_browser_status.visible = not _web_surface_enabled and not _fullscreen


func _close() -> void:
	provider.close()
	ui.call("close_overlay")
