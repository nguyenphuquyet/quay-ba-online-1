extends Control
## Settings — preset đồ họa PC/mobile, âm lượng, sensitivity, fullscreen, FPS.

var ui: CanvasLayer

var _preset_note: Label
var _master_value: Label
var _music_value: Label
var _sfx_value: Label
var _sens_value: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var margin := QBOTheme.margins(48 if not AppConfig.is_mobile else 16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var layout := QBOTheme.vbox(16)
	margin.add_child(layout)

	var header := QBOTheme.hbox(16)
	layout.add_child(header)
	var back := QBOTheme.button("← Quay lại")
	back.pressed.connect(_go_back)
	header.add_child(back)
	var titles := QBOTheme.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(QBOTheme.title("CÀI ĐẶT", 34))
	titles.add_child(QBOTheme.muted("Tối ưu theo thiết bị: %s" % ("mobile" if AppConfig.is_mobile else "PC"), 13))
	header.add_child(titles)

	var columns := QBOTheme.hbox(18)
	layout.add_child(columns)

	var graphics := QBOTheme.panel(24)
	graphics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(graphics)
	var gbox := QBOTheme.vbox(12)
	graphics.add_child(gbox)
	gbox.add_child(QBOTheme.section("ĐỒ HỌA"))
	_preset_note = QBOTheme.muted("", 13)
	_preset_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gbox.add_child(_preset_note)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	gbox.add_child(grid)
	for preset in ["low", "medium", "high", "ultra"]:
		var button := QBOTheme.button(str(preset).to_upper())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			SettingsManager.set_preset(preset)
			_refresh()
			ui.call("toast", "Đã đổi đồ họa: %s" % preset.to_upper(), "success")
		)
		grid.add_child(button)
	gbox.add_child(QBOTheme.hsep(8))
	var fullscreen := CheckBox.new()
	fullscreen.text = "Toàn màn hình"
	fullscreen.button_pressed = SettingsManager.fullscreen
	fullscreen.toggled.connect(func(value: bool):
		SettingsManager.fullscreen = value
		SettingsManager.apply_window()
		SettingsManager.save_settings()
	)
	gbox.add_child(fullscreen)
	var show_fps := CheckBox.new()
	show_fps.text = "Hiển thị FPS"
	show_fps.button_pressed = SettingsManager.show_fps
	show_fps.toggled.connect(func(value: bool):
		SettingsManager.show_fps = value
		SettingsManager.save_settings()
	)
	gbox.add_child(show_fps)
	var invert_y := CheckBox.new()
	invert_y.text = "Đảo trục Y"
	invert_y.button_pressed = SettingsManager.invert_y
	invert_y.toggled.connect(func(value: bool):
		SettingsManager.invert_y = value
		SettingsManager.save_settings()
	)
	gbox.add_child(invert_y)
	gbox.add_child(QBOTheme.hsep(8))
	var perf := QBOTheme.muted("Preset mobile giảm scale 3D, tắt SSAO/SSR và hạ chất lượng bóng đổ để giữ nhiệt độ và pin.", 12)
	perf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gbox.add_child(perf)

	var right := QBOTheme.panel(24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var rbox := QBOTheme.vbox(10)
	right.add_child(rbox)
	rbox.add_child(QBOTheme.section("ÂM THANH"))
	_master_value = QBOTheme.label("", 13, QBOTheme.MUTED)
	rbox.add_child(_master_label("Âm lượng tổng", SettingsManager.master_volume, func(v): _set_audio("master", v)))
	rbox.add_child(_master_value)
	_music_value = QBOTheme.label("", 13, QBOTheme.MUTED)
	rbox.add_child(_master_label("Nhạc (DJMixer)", SettingsManager.music_volume, func(v): _set_audio("music", v)))
	rbox.add_child(_music_value)
	_sfx_value = QBOTheme.label("", 13, QBOTheme.MUTED)
	rbox.add_child(_master_label("Hiệu ứng", SettingsManager.sfx_volume, func(v): _set_audio("sfx", v)))
	rbox.add_child(_sfx_value)
	rbox.add_child(QBOTheme.hsep(10))
	rbox.add_child(QBOTheme.section("CHUỘT / CẢM ỨNG"))
	_sens_value = QBOTheme.label("", 13, QBOTheme.MUTED)
	rbox.add_child(_master_label("Độ nhạy nhìn", SettingsManager.mouse_sensitivity * 1000.0, func(v): _set_sensitivity(v), 0.8, 6.0, 0.1))
	rbox.add_child(_sens_value)
	rbox.add_child(QBOTheme.hsep(10))
	rbox.add_child(QBOTheme.section("TÀI KHOẢN"))
	if GameState.is_logged_in():
		rbox.add_child(QBOTheme.label(str(GameState.display_name()), 15, QBOTheme.TEXT))
		rbox.add_child(QBOTheme.muted("@" + str(GameState.user.get("username", "")), 13))
		var logout := QBOTheme.button("Đăng xuất")
		logout.pressed.connect(func():
			await Api.logout()
			ui.call("show_screen", "login")
		)
		rbox.add_child(logout)
	else:
		rbox.add_child(QBOTheme.muted("Chế độ khách", 13))
		var login := QBOTheme.button("Đăng nhập")
		login.pressed.connect(func(): ui.call("show_screen", "login"))
		rbox.add_child(login)

	_refresh()


func _master_label(text: String, value: float, callback: Callable, min_value := 0.0, max_value := 1.0, step := 0.05) -> VBoxContainer:
	var box := QBOTheme.vbox(4)
	box.add_child(QBOTheme.label(text, 14, QBOTheme.TEXT))
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 24)
	slider.value_changed.connect(callback)
	box.add_child(slider)
	return box


func _set_audio(kind: String, value: float) -> void:
	if kind == "master":
		SettingsManager.master_volume = value
	elif kind == "music":
		SettingsManager.music_volume = value
		if App.world != null and App.world.dj != null:
			App.world.dj.set_volume(value)
	else:
		SettingsManager.sfx_volume = value
	SettingsManager.apply_audio()
	SettingsManager.save_settings()
	_refresh()


func _set_sensitivity(value: float) -> void:
	SettingsManager.mouse_sensitivity = clampf(value / 1000.0, 0.0008, 0.008)
	SettingsManager.save_settings()
	_refresh()


func _refresh() -> void:
	if _preset_note == null:
		return
	_preset_note.text = "Preset hiện tại: %s (khuyến nghị cho máy này: %s)" % [
		SettingsManager.preset_name.to_upper(), AppConfig.suggested_graphics_preset().to_upper(),
	]
	_master_value.text = "%.0f%%" % (SettingsManager.master_volume * 100.0)
	_music_value.text = "%.0f%%" % (SettingsManager.music_volume * 100.0)
	_sfx_value.text = "%.0f%%" % (SettingsManager.sfx_volume * 100.0)
	_sens_value.text = "%.2f" % (SettingsManager.mouse_sensitivity * 1000.0)


func _go_back() -> void:
	if App.world != null:
		ui.call("enter_game")
	else:
		ui.call("show_screen", "main_menu")
