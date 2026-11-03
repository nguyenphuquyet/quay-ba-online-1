extends Control
## Lighting Console — 8 preset, cường độ, tốc độ, beat sync; đồng bộ multiplayer.

var ui: CanvasLayer
var params: Dictionary = {}

var _preset_buttons: Dictionary = {}
var _intensity: HSlider
var _intensity_label: Label
var _speed: HSlider
var _speed_label: Label
var _beat_sync: CheckBox
var _permission: Label
var _preset_note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Net.lighting_received.connect(func(_state): _sync_from_world())
	Net.room_settings_received.connect(func(_s): _refresh_permission())
	_sync_from_world()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var window := PanelContainer.new()
	window.set_anchors_preset(Control.PRESET_CENTER)
	window.offset_left = -540
	window.offset_right = 540
	window.offset_top = -350
	window.offset_bottom = 350
	window.add_theme_stylebox_override("panel", QBOTheme.panel_style(Color(0.035, 0.03, 0.05, 0.98), 18, Color(0.3, 0.8, 0.92, 0.35)))
	add_child(window)
	var root := QBOTheme.vbox(12)
	window.add_child(root)

	var head := QBOTheme.hbox(10)
	root.add_child(head)
	head.add_child(QBOTheme.title("LIGHT CONSOLE", 30))
	head.add_child(QBOTheme.spacer())
	var close := QBOTheme.button("Đóng")
	close.pressed.connect(func(): ui.call("close_overlay"))
	head.add_child(close)

	_permission = QBOTheme.label("", 13, QBOTheme.GOLD)
	root.add_child(_permission)
	_preset_note = QBOTheme.muted("", 13)
	root.add_child(_preset_note)

	root.add_child(QBOTheme.section("PRESET"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)
	for key in ["chill", "lounge", "party", "edm", "cyberpunk", "chinese_neon", "vip", "blackout"]:
		var label := str(key).replace("_", " ").to_upper()
		var button := QBOTheme.button(label)
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func(): _apply(key))
		grid.add_child(button)
		_preset_buttons[key] = button

	root.add_child(QBOTheme.hsep(4))
	var intensity_row := QBOTheme.vbox(4)
	root.add_child(intensity_row)
	var intensity_head := QBOTheme.hbox(8)
	intensity_head.add_child(QBOTheme.section("CƯỜNG ĐỘ"))
	intensity_head.add_child(QBOTheme.spacer())
	_intensity_label = QBOTheme.label("", 13, QBOTheme.CYAN)
	intensity_head.add_child(_intensity_label)
	intensity_row.add_child(intensity_head)
	_intensity = HSlider.new()
	_intensity.min_value = 0.0
	_intensity.max_value = 2.0
	_intensity.step = 0.05
	_intensity.value = 1.0
	_intensity.custom_minimum_size = Vector2(0, 24)
	intensity_row.add_child(_intensity)

	var speed_row := QBOTheme.vbox(4)
	root.add_child(speed_row)
	var speed_head := QBOTheme.hbox(8)
	speed_head.add_child(QBOTheme.section("TỐC ĐỘ"))
	speed_head.add_child(QBOTheme.spacer())
	_speed_label = QBOTheme.label("", 13, QBOTheme.CYAN)
	speed_head.add_child(_speed_label)
	speed_row.add_child(speed_head)
	_speed = HSlider.new()
	_speed.min_value = 0.0
	_speed.max_value = 2.5
	_speed.step = 0.05
	_speed.value = 1.0
	_speed.custom_minimum_size = Vector2(0, 24)
	speed_row.add_child(_speed)

	_beat_sync = CheckBox.new()
	_beat_sync.text = "Đồng bộ beat với nhạc DJ"
	_beat_sync.button_pressed = true
	_beat_sync.toggled.connect(func(value: bool):
		if App.world != null and App.world.lighting != null:
			App.world.lighting.set_beat_sync(value)
			_push(true)
	)
	root.add_child(_beat_sync)

	var actions := QBOTheme.hbox(8)
	root.add_child(actions)
	var apply_button := QBOTheme.button("Áp dụng cho cả phòng", true)
	apply_button.pressed.connect(func(): _push(true))
	actions.add_child(apply_button)
	var preview := QBOTheme.button("Xem trước tại máy")
	preview.pressed.connect(func(): _push(false))
	actions.add_child(preview)
	var note := QBOTheme.muted("Người không có quyền vẫn xem được trạng thái; chỉ chủ phòng hoặc người được cấp quyền mới thay đổi được. Server kiểm tra quyền từng lần gửi.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)


func _apply(preset: String) -> void:
	if App.world == null or App.world.lighting == null:
		return
	App.world.lighting.apply_preset(preset, _intensity.value, _speed.value)
	_preset_note.text = "Preset: %s" % preset.replace("_", " ").to_upper()
	_highlight(preset)
	_push(true)


func _push(broadcast: bool) -> void:
	if App.world == null or App.world.lighting == null:
		return
	var lighting = App.world.lighting
	lighting.apply_preset(lighting.current_preset, _intensity.value, _speed.value)
	lighting.set_beat_sync(_beat_sync.button_pressed)
	_intensity_label.text = "%.2f×" % _intensity.value
	_speed_label.text = "%.2f×" % _speed.value
	if broadcast:
		Net.send_lighting(lighting.build_state())
	else:
		ui.call("toast", "Đã xem trước preset tại máy.", "info")


func _sync_from_world() -> void:
	if App.world == null or App.world.lighting == null:
		return
	var lighting = App.world.lighting
	_intensity.set_value_no_signal(lighting.intensity)
	_speed.set_value_no_signal(lighting.speed)
	_beat_sync.set_pressed_no_signal(lighting.beat_enabled)
	_intensity_label.text = "%.2f×" % lighting.intensity
	_speed_label.text = "%.2f×" % lighting.speed
	_preset_note.text = "Preset hiện tại: %s" % lighting.current_preset.replace("_", " ").to_upper()
	_highlight(lighting.current_preset)
	_refresh_permission()


func _highlight(active: String) -> void:
	for key in _preset_buttons.keys():
		var button: Button = _preset_buttons[key]
		button.modulate = Color(1, 1, 1, 1) if key == active else Color(0.68, 0.66, 0.74, 1)


func _refresh_permission() -> void:
	if _permission == null:
		return
	var can := Net.can_control("lighting")
	_permission.text = "Bạn có quyền điều khiển ánh sáng." if can else "Chưa có quyền điều khiển ánh sáng — liên hệ chủ phòng."
	_permission.add_theme_color_override("font_color", QBOTheme.SUCCESS if can else QBOTheme.GOLD)
	_intensity.editable = can
	_speed.editable = can
	_beat_sync.disabled = not can
	for key in _preset_buttons.keys():
		var button: Button = _preset_buttons[key]
		button.disabled = not can
