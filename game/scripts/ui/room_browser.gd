extends Control
## Room Browser — danh sách phòng đang mở từ backend, tìm kiếm, lọc, vào bằng mật khẩu.

var ui: CanvasLayer

var _list: VBoxContainer
var _search: LineEdit
var _filter: OptionButton
var _status: Label
var _password: LineEdit
var _password_row: Control
var _pending_password_room := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func on_show() -> void:
	_load_rooms()


func _build() -> void:
	var margin := QBOTheme.margins(48 if not AppConfig.is_mobile else 16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var layout := QBOTheme.vbox(16)
	margin.add_child(layout)

	var header := QBOTheme.hbox(16)
	layout.add_child(header)
	var back := QBOTheme.button("← Menu")
	back.pressed.connect(func(): ui.call("show_screen", "main_menu"))
	header.add_child(back)
	var titles := QBOTheme.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(QBOTheme.title("PHÒNG ĐANG MỞ", 34))
	titles.add_child(QBOTheme.muted("Mỗi phòng là một nightclub riêng với chủ phòng và bộ quyền riêng.", 13))
	header.add_child(titles)
	var create := QBOTheme.button("+ Tạo phòng", true)
	create.pressed.connect(func(): ui.call("show_screen", "create_room"))
	header.add_child(create)

	var toolbar := QBOTheme.hbox(10)
	layout.add_child(toolbar)
	_search = QBOTheme.line_edit("Tìm theo tên, mã phòng hoặc chủ phòng…")
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _load_rooms())
	toolbar.add_child(_search)
	_filter = OptionButton.new()
	_filter.add_item("Tất cả", 0)
	_filter.add_item("Công khai", 1)
	_filter.add_item("Riêng tư", 2)
	_filter.item_selected.connect(func(_i): _load_rooms())
	toolbar.add_child(_filter)
	var refresh := QBOTheme.button("Tải lại")
	refresh.pressed.connect(_load_rooms)
	toolbar.add_child(refresh)

	var columns := QBOTheme.hbox(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)

	var list_panel := QBOTheme.panel(16)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)
	_list = QBOTheme.vbox(10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var side := QBOTheme.panel(20)
	side.custom_minimum_size = Vector2(330, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(side)
	var side_box := QBOTheme.vbox(12)
	side.add_child(side_box)
	side_box.add_child(QBOTheme.section("THAM GIA NHANH"))
	_password_row = QBOTheme.vbox(6)
	_password = QBOTheme.line_edit("Mật khẩu phòng (nếu có)", true, 64)
	_password_row.add_child(QBOTheme.field("MẬT KHẨU", _password))
	_password_row.visible = false
	side_box.add_child(_password_row)
	side_box.add_child(QBOTheme.hsep(6))
	side_box.add_child(QBOTheme.section("CHƠI MỘT MÌNH"))
	var solo_hint := QBOTheme.muted("Không cần backend. Bạn vẫn có thể tham quan club, thử DJ, ánh sáng, máy tính và TV.", 13)
	solo_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(solo_hint)
	var solo := QBOTheme.button("Chơi solo / offline")
	solo.pressed.connect(func():
		GameState.guest_name = "Khách"
		App.start_solo()
	)
	side_box.add_child(solo)
	side_box.add_child(QBOTheme.hsep(6))
	side_box.add_child(QBOTheme.section("LƯU Ý"))
	var note := QBOTheme.muted("Phòng online cần Next.js + MySQL chạy. Danh sách tự cập nhật khi bấm Tải lại.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(note)

	_status = QBOTheme.muted("", 13)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_status)


func _load_rooms() -> void:
	_status.text = "Đang tải danh sách phòng…"
	_status.add_theme_color_override("font_color", QBOTheme.MUTED)
	for child in _list.get_children():
		child.queue_free()
	if not GameState.is_logged_in():
		_show_message("Đăng nhập để xem và tham gia phòng online.", true)
		return
	var visibility: String = ["all", "public", "private"][_filter.selected if _filter.selected >= 0 else 0]
	var res := await Api.list_rooms(_search.text.strip_edges(), visibility)
	if not res["ok"]:
		_status.text = "Không tải được phòng: %s" % res["error"]
		_status.add_theme_color_override("font_color", QBOTheme.DANGER)
		return
	var data: Dictionary = res["data"] if res["data"] is Dictionary else {}
	var rooms: Array = data.get("rooms", [])
	_status.text = "%d phòng đang hoạt động." % rooms.size()
	_status.add_theme_color_override("font_color", QBOTheme.MUTED)
	if rooms.is_empty():
		_show_message("Chưa có phòng nào. Hãy tạo phòng đầu tiên của đêm nay.", false)
		return
	for room in rooms:
		_list.add_child(_room_card(room))


func _show_message(text: String, error: bool) -> void:
	var panel := QBOTheme.panel(18)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := QBOTheme.label(text, 15, QBOTheme.DANGER if error else QBOTheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	_list.add_child(panel)


func _room_card(room: Dictionary) -> PanelContainer:
	var card := QBOTheme.panel(16)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := QBOTheme.hbox(16)
	card.add_child(row)
	var info := QBOTheme.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_row := QBOTheme.hbox(8)
	name_row.add_child(QBOTheme.label(str(room.get("name", "Phòng")), 20, QBOTheme.TEXT))
	var badge_text := "CÔNG KHAI" if bool(room.get("isPublic", true)) else "RIÊNG TƯ"
	var badge := QBOTheme.label(badge_text, 11, QBOTheme.GOLD if bool(room.get("isPublic", true)) else QBOTheme.PURPLE)
	name_row.add_child(badge)
	info.add_child(name_row)
	var owner_name := "—"
	if room.get("owner") is Dictionary:
		owner_name = str(room["owner"].get("displayName", room["owner"].get("username", "—")))
	var meta := "%s  •  chủ phòng %s  •  %d/%d người" % [
		str(room.get("code", "-----")), owner_name,
		int(room.get("playerCount", 0)), int(room.get("maxPlayers", 16)),
	]
	info.add_child(QBOTheme.muted(meta, 13))
	var desc := str(room.get("description", ""))
	if desc != "":
		var desc_label := QBOTheme.muted(desc, 13)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc_label)
	var status_text := "Đang mở" if str(room.get("status", "open")) == "open" else str(room.get("status", ""))
	info.add_child(QBOTheme.label(status_text, 12, QBOTheme.SUCCESS if status_text == "Đang mở" else QBOTheme.MUTED))

	var join := QBOTheme.button("Tham gia")
	join.custom_minimum_size = Vector2(120, 44)
	join.pressed.connect(func(): _join(room))
	row.add_child(join)
	return card


func _join(room: Dictionary) -> void:
	var code := str(room.get("code", ""))
	if code == "":
		return
	var password := _password.text
	if bool(room.get("hasPassword", false)) and password == "":
		_pending_password_room = code
		_password_row.visible = true
		_password.grab_focus()
		ui.call("toast", "Phòng này cần mật khẩu — nhập ở khung bên phải rồi bấm Tham gia lại.", "warn")
		return
	ui.call("toast", "Đang vào phòng %s…" % code)
	var res := await Api.join_room(code, password)
	if not res["ok"]:
		ui.call("toast", str(res["error"]), "error")
		return
	var data: Dictionary = res["data"]
	var joined_room: Dictionary = data.get("room", room)
	var ticket := str(data.get("ticket", ""))
	var game: Dictionary = data.get("game", {})
	if ticket == "":
		ui.call("toast", "Không nhận được game ticket.", "error")
		return
	var host := str(game.get("host", AppConfig.game_host))
	var port := int(game.get("port", AppConfig.game_port))
	ui.call("begin_room", joined_room, ticket, host, port)
