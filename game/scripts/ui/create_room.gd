extends Control
## Create Room — tạo phòng thật trên backend, sau đó xin game ticket và vào club.

var ui: CanvasLayer

var _name: LineEdit
var _description: TextEdit
var _max_players: HSlider
var _max_label: Label
var _public: CheckBox
var _password: LineEdit
var _password_field: VBoxContainer
var _preset: OptionButton
var _feedback: Label
var _submit: Button
var _busy := false


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
	var back := QBOTheme.button("← Danh sách phòng")
	back.pressed.connect(func(): ui.call("show_screen", "room_browser"))
	header.add_child(back)
	var titles := QBOTheme.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(QBOTheme.title("MỞ PHÒNG ĐÊM NAY", 34))
	titles.add_child(QBOTheme.muted("Đặt tên, chọn sức chứa và quyền riêng tư. Bạn sẽ là chủ phòng.", 13))
	header.add_child(titles)

	var body := QBOTheme.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)

	var form_panel := QBOTheme.panel(24)
	form_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(form_panel)
	var form := QBOTheme.vbox(14)
	form_panel.add_child(form)

	_name = QBOTheme.line_edit("Ví dụ: Đêm Champagne — Lotus", false, 60)
	form.add_child(QBOTheme.field("TÊN PHÒNG", _name))

	_description = TextEdit.new()
	_description.placeholder_text = "Mô tả ngắn: nhạc, dress code, dịp đặc biệt…"
	_description.custom_minimum_size = Vector2(0, 96)
	_description.add_theme_font_override("font", QBOTheme.font())
	form.add_child(QBOTheme.field("MÔ TẢ", _description))

	var slider_row := QBOTheme.vbox(6)
	var max_head := QBOTheme.hbox(8)
	max_head.add_child(QBOTheme.section("SỨC CHỨA"))
	max_head.add_child(QBOTheme.spacer())
	_max_label = QBOTheme.label("16 người", 14, QBOTheme.GOLD_BRIGHT)
	max_head.add_child(_max_label)
	slider_row.add_child(max_head)
	_max_players = HSlider.new()
	_max_players.min_value = 2
	_max_players.max_value = AppConfig.MAX_ROOM_PLAYERS
	_max_players.step = 1
	_max_players.value = 16
	_max_players.custom_minimum_size = Vector2(0, 26)
	_max_players.value_changed.connect(func(value: float):
		_max_label.text = "%d người" % int(value)
	)
	slider_row.add_child(_max_players)
	form.add_child(slider_row)

	var privacy := QBOTheme.hbox(12)
	form.add_child(privacy)
	_public = CheckBox.new()
	_public.text = "Phòng công khai (hiện trong danh sách)"
	_public.button_pressed = true
	_public.toggled.connect(func(value: bool):
		_password_field.visible = not value
	)
	privacy.add_child(_public)

	_password_field = QBOTheme.vbox(6)
	_password_field.visible = false
	_password = QBOTheme.line_edit("Mật khẩu phòng (tối thiểu 4 ký tự)", true, 64)
	_password_field.add_child(QBOTheme.field("MẬT KHẨU PHÒNG", _password))
	form.add_child(_password_field)

	var preset_row := QBOTheme.vbox(6)
	preset_row.add_child(QBOTheme.section("ÁNH SÁNG KHỞI ĐẦU"))
	_preset = OptionButton.new()
	for key in ["party", "chill", "lounge", "edm", "cyberpunk", "chinese_neon", "vip", "blackout"]:
		_preset.add_item(str(key))
	_preset.select(0)
	preset_row.add_child(_preset)
	form.add_child(preset_row)

	_feedback = QBOTheme.muted("", 13)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_feedback)

	_submit = QBOTheme.button("Tạo phòng & vào club", true)
	_submit.pressed.connect(_submit_room)
	form.add_child(_submit)

	var tips := QBOTheme.panel(22)
	tips.custom_minimum_size = Vector2(340, 0)
	tips.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(tips)
	var tip_box := QBOTheme.vbox(10)
	tips.add_child(tip_box)
	tip_box.add_child(QBOTheme.section("CHỦ PHÒNG CÓ THỂ"))
	for line in [
		"Khóa quyền điều khiển TV / màn hình LED",
		"Khóa quyền DJ và ánh sáng",
		"Cấp quyền DJ cho từng người chơi",
		"Mời người chơi ra khỏi phòng",
		"Đổi preset ánh sáng cho cả phòng",
	]:
		var label := QBOTheme.label("• " + line, 14, QBOTheme.MUTED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip_box.add_child(label)
	tip_box.add_child(QBOTheme.hsep(8))
	var server_note := QBOTheme.muted("Game server: %s\nGame ticket do backend cấp và được dedicated server xác minh." % AppConfig.endpoint(), 12)
	server_note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tip_box.add_child(server_note)


func _submit_room() -> void:
	if _busy:
		return
	var room_name := _name.text.strip_edges()
	if room_name.length() < 3:
		_feedback.text = "Tên phòng cần ít nhất 3 ký tự."
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	var is_public := _public.button_pressed
	var password := _password.text
	if not is_public and password.length() < 4:
		_feedback.text = "Phòng riêng cần mật khẩu tối thiểu 4 ký tự."
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	if not GameState.is_logged_in():
		_feedback.text = "Bạn cần đăng nhập để tạo phòng online."
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	_busy = true
	_submit.disabled = true
	_feedback.text = "Đang tạo phòng…"
	_feedback.add_theme_color_override("font_color", QBOTheme.MUTED)
	var payload := {
		"name": room_name,
		"description": _description.text.strip_edges().left(280),
		"maxPlayers": int(_max_players.value),
		"isPublic": is_public,
		"password": password if not is_public else "",
		"map": "the_chrome_lotus",
		"lightingPreset": str(_preset.get_item_text(_preset.selected)),
	}
	var res := await Api.create_room(payload)
	if not res["ok"]:
		_busy = false
		_submit.disabled = false
		_feedback.text = str(res["error"])
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	var data: Dictionary = res["data"] if res["data"] is Dictionary else {}
	var room: Dictionary = data.get("room", data)
	var code := str(room.get("code", ""))
	if code == "":
		_busy = false
		_submit.disabled = false
		_feedback.text = "Backend không trả về mã phòng."
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	_feedback.text = "Đã tạo phòng %s — đang xin game ticket…" % code
	var ticket_res := await Api.request_game_ticket(code)
	if not ticket_res["ok"]:
		_busy = false
		_submit.disabled = false
		_feedback.text = str(ticket_res["error"])
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	var ticket_data: Dictionary = ticket_res["data"] if ticket_res["data"] is Dictionary else {}
	var game: Dictionary = ticket_data.get("game", {})
	var ticket := str(ticket_data.get("ticket", ""))
	_busy = false
	_submit.disabled = false
	if ticket == "":
		_feedback.text = "Không nhận được game ticket."
		_feedback.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	ui.call("begin_room", room, ticket, str(game.get("host", AppConfig.game_host)), int(game.get("port", AppConfig.game_port)))
