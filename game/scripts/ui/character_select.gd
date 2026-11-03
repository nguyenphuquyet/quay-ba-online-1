extends Control
## Character Select — chọn tên hiển thị, outfit/màu nhân vật và chế độ camera.

const STYLES := [
	{"name": "Obsidian", "color": Color(0.13, 0.05, 0.09), "desc": "Áo da đen, dây chuyền vàng"},
	{"name": "Midnight", "color": Color(0.06, 0.09, 0.16), "desc": "Xanh navy, phong cách lounge"},
	{"name": "Smoke", "color": Color(0.1, 0.1, 0.11), "desc": "Xám khói tối giản"},
	{"name": "Rosé", "color": Color(0.24, 0.06, 0.16), "desc": "Đỏ rượu vang, nổi bật"},
	{"name": "Jade", "color": Color(0.09, 0.14, 0.12), "desc": "Xanh ngọc, cyberpunk nhẹ"},
]

var ui: CanvasLayer

var _style := 0
var _camera_third := true
var _name_edit: LineEdit
var _style_buttons: Array = []
var _preview_name: Label
var _preview_desc: Label
var _camera_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style = SettingsManager.character_style
	_camera_third = SettingsManager.camera_mode != "first"
	_build()
	_refresh()


func _build() -> void:
	var margin := QBOTheme.margins(48 if not AppConfig.is_mobile else 16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var columns := QBOTheme.hbox(32)
	margin.add_child(columns)

	var left := QBOTheme.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(left)
	left.add_child(QBOTheme.section("BƯỚC CUỐI"))
	left.add_child(QBOTheme.title("DIỆN MẠO CỦA BẠN", 42))
	var room_label := QBOTheme.muted("Phòng: %s" % str(ui.pending_room.get("name", ui.pending_room.get("code", ""))) if ui else "", 14)
	room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(room_label)

	_name_edit = QBOTheme.line_edit("Tên hiển thị", false, 24)
	if GameState.is_logged_in():
		_name_edit.text = GameState.display_name()
	else:
		_name_edit.text = GameState.guest_name
	left.add_child(QBOTheme.field("TÊN HIỂN THỊ TRONG CLUB", _name_edit))

	var styles_box := QBOTheme.vbox(8)
	styles_box.add_child(QBOTheme.section("TRANG PHỤC"))
	var row := QBOTheme.hbox(10)
	styles_box.add_child(row)
	for i in STYLES.size():
		var style: Dictionary = STYLES[i]
		var button := Button.new()
		button.text = str(style["name"])
		button.custom_minimum_size = Vector2(0, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_override("font", QBOTheme.font())
		button.add_theme_color_override("font_color", QBOTheme.TEXT)
		var normal := QBOTheme.panel_style(style["color"], 10, Color(1, 1, 1, 0.15))
		normal.content_margin_top = 8
		normal.content_margin_bottom = 8
		button.add_theme_stylebox_override("normal", normal)
		var hover := QBOTheme.panel_style(style["color"].lightened(0.12), 10, QBOTheme.GOLD)
		hover.content_margin_top = 8
		hover.content_margin_bottom = 8
		button.add_theme_stylebox_override("hover", hover)
		button.pressed.connect(func(): _select_style(i))
		row.add_child(button)
		_style_buttons.append(button)
	left.add_child(styles_box)
	_preview_name = QBOTheme.label("", 18, QBOTheme.GOLD_BRIGHT)
	left.add_child(_preview_name)
	_preview_desc = QBOTheme.muted("", 13)
	left.add_child(_preview_desc)

	_camera_btn = QBOTheme.button("")
	_camera_btn.pressed.connect(func():
		_camera_third = not _camera_third
		SettingsManager.camera_mode = "third" if _camera_third else "first"
		SettingsManager.save_settings()
		_refresh()
	)
	left.add_child(_camera_btn)

	var actions := QBOTheme.hbox(10)
	left.add_child(actions)
	var enter := QBOTheme.button("Bước vào The Chrome Lotus", true)
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(_enter_room)
	actions.add_child(enter)
	var cancel := QBOTheme.button("Hủy")
	cancel.pressed.connect(func(): ui.call("show_screen", "room_browser"))
	actions.add_child(cancel)

	var card := QBOTheme.panel(26)
	card.custom_minimum_size = Vector2(420, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(card)
	var info := QBOTheme.vbox(12)
	card.add_child(info)
	info.add_child(QBOTheme.section("THÔNG TIN PHÒNG"))
	info.add_child(QBOTheme.title(str(ui.pending_room.get("name", "The Chrome Lotus")) if ui else "The Chrome Lotus", 28))
	var code := str(ui.pending_room.get("code", "")) if ui else ""
	info.add_child(QBOTheme.label("Mã phòng: %s" % code, 15, QBOTheme.CYAN))
	var owner := "—"
	if ui and ui.pending_room.get("owner") is Dictionary:
		owner = str(ui.pending_room["owner"].get("displayName", "—"))
	info.add_child(QBOTheme.muted("Chủ phòng: %s" % owner, 13))
	info.add_child(QBOTheme.muted("Bản đồ: The Chrome Lotus", 13))
	info.add_child(QBOTheme.hsep(6))
	var tips := QBOTheme.muted(
		"Trong club:\nWASD di chuyển • Chuột xoay • Shift chạy • Space nhảy\nE tương tác • V đổi camera • Enter chat • Esc menu\nR khiêu vũ • F emote",
		13
	)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(tips)
	info.add_child(QBOTheme.hsep(6))
	var sync := QBOTheme.muted("Vị trí, animation, ánh sáng và các màn hình sân khấu được đồng bộ bởi dedicated server.", 12)
	sync.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sync)


func _select_style(index: int) -> void:
	_style = index
	_refresh()


func _refresh() -> void:
	if _preview_name == null:
		return
	var style: Dictionary = STYLES[_style % STYLES.size()]
	_preview_name.text = "%s — %s" % [_name_edit.text if _name_edit.text != "" else "Người chơi", style["name"]]
	_preview_desc.text = str(style["desc"])
	for i in _style_buttons.size():
		var button: Button = _style_buttons[i]
		button.modulate = Color(1, 1, 1, 1) if i == _style else Color(0.72, 0.7, 0.76, 1)
	_camera_btn.text = "Camera: Góc nhìn thứ ba (V để đổi)" if _camera_third else "Camera: Góc nhìn thứ nhất (V để đổi)"


func _enter_room() -> void:
	var display := _name_edit.text.strip_edges()
	if display.length() < 2:
		ui.call("toast", "Tên hiển thị cần ít nhất 2 ký tự.", "error")
		return
	SettingsManager.character_style = _style
	SettingsManager.save_settings()
	if GameState.is_logged_in():
		GameState.user["displayName"] = display
		GameState.save_session()
	else:
		GameState.guest_name = display
	ui.call("enter_pending_room")
