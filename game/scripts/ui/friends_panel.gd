extends Control
## Friends — danh sách bạn bè, lời mời đến/đi, thêm bạn bằng username.
## Toàn bộ dữ liệu lấy từ Next.js API; lỗi backend hiển thị rõ ràng.

var ui: CanvasLayer

var _list: VBoxContainer
var _incoming: VBoxContainer
var _username: LineEdit
var _feedback: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func on_show() -> void:
	_load()


func _build() -> void:
	var margin := QBOTheme.margins(48 if not AppConfig.is_mobile else 16)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var layout := QBOTheme.vbox(16)
	margin.add_child(layout)

	var header := QBOTheme.hbox(16)
	layout.add_child(header)
	var back := QBOTheme.button("← Menu")
	back.pressed.connect(func():
		if App.world != null:
			ui.call("enter_game")
		else:
			ui.call("show_screen", "main_menu")
	)
	header.add_child(back)
	var titles := QBOTheme.vbox(2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(QBOTheme.title("BẠN BÈ", 34))
	titles.add_child(QBOTheme.muted("Kết bạn để mời vào phòng riêng của bạn.", 13))
	header.add_child(titles)
	var refresh := QBOTheme.button("Tải lại")
	refresh.pressed.connect(_load)
	header.add_child(refresh)

	var columns := QBOTheme.hbox(18)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)

	var friends_panel := QBOTheme.panel(20)
	friends_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(friends_panel)
	var fbox := QBOTheme.vbox(10)
	friends_panel.add_child(fbox)
	fbox.add_child(QBOTheme.section("DANH SÁCH BẠN BÈ"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fbox.add_child(scroll)
	_list = QBOTheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var side := QBOTheme.panel(20)
	side.custom_minimum_size = Vector2(340, 0)
	columns.add_child(side)
	var sbox := QBOTheme.vbox(12)
	side.add_child(sbox)
	sbox.add_child(QBOTheme.section("THÊM BẠN"))
	_username = QBOTheme.line_edit("Username của bạn bè")
	_username.text_submitted.connect(func(_t): _add_friend())
	sbox.add_child(_username)
	var add := QBOTheme.button("Gửi lời mời", true)
	add.pressed.connect(_add_friend)
	sbox.add_child(add)
	_feedback = QBOTheme.muted("", 13)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(_feedback)
	sbox.add_child(QBOTheme.hsep(10))
	sbox.add_child(QBOTheme.section("LỜI MỜI ĐẾN"))
	_incoming = QBOTheme.vbox(8)
	sbox.add_child(_incoming)
	sbox.add_child(QBOTheme.hsep(10))
	var note := QBOTheme.muted("Mời bạn bè vào phòng: chia sẻ mã phòng (hiển thị trong HUD) và họ dùng Tham gia bằng mã.", 12)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(note)


func _load() -> void:
	if not GameState.is_logged_in():
		_show_feedback("Đăng nhập để dùng danh bạ bạn bè.", true)
		return
	var res := await Api.list_friends()
	if not res["ok"]:
		_show_feedback(str(res["error"]), true)
		return
	var data: Dictionary = res["data"] if res["data"] is Dictionary else {}
	for child in _list.get_children():
		child.queue_free()
	for child in _incoming.get_children():
		child.queue_free()
	var friends: Array = data.get("friends", [])
	if friends.is_empty():
		_list.add_child(QBOTheme.muted("Chưa có bạn bè. Gửi lời mời bằng username.", 14))
	for friend in friends:
		_list.add_child(_friend_row(friend))
	var incoming: Array = data.get("incoming", [])
	if incoming.is_empty():
		_incoming.add_child(QBOTheme.muted("Không có lời mời.", 13))
	for request in incoming:
		_incoming.add_child(_request_row(request))
	_show_feedback("Đã tải %d bạn bè." % friends.size(), false)


func _friend_row(friend: Dictionary) -> PanelContainer:
	var panel := QBOTheme.panel(12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := QBOTheme.hbox(10)
	panel.add_child(row)
	var user: Dictionary = friend.get("user", {})
	var name := str(user.get("displayName", user.get("username", "Người chơi")))
	var online := bool(friend.get("online", false))
	var box := QBOTheme.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(QBOTheme.label(name, 15, QBOTheme.TEXT))
	box.add_child(QBOTheme.muted(("● Đang online" if online else "○ Offline") + "  •  @" + str(user.get("username", "")), 12))
	row.add_child(box)
	var remove := QBOTheme.button("Xóa")
	remove.pressed.connect(func():
		var res := await Api.friend_remove(str(friend.get("id", "")))
		if res["ok"]:
			_load()
		else:
			_show_feedback(str(res["error"]), true)
	)
	row.add_child(remove)
	return panel


func _request_row(request: Dictionary) -> PanelContainer:
	var panel := QBOTheme.panel(10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := QBOTheme.hbox(8)
	panel.add_child(row)
	var user: Dictionary = request.get("user", request.get("from", {}))
	var label := QBOTheme.label(str(user.get("displayName", user.get("username", "?"))), 14, QBOTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var accept := QBOTheme.button("Chấp nhận")
	accept.pressed.connect(func():
		var res := await Api.friend_accept(str(request.get("id", "")))
		if res["ok"]:
			_load()
		else:
			_show_feedback(str(res["error"]), true)
	)
	row.add_child(accept)
	return panel


func _add_friend() -> void:
	var username := _username.text.strip_edges()
	if username == "":
		return
	var res := await Api.friend_request(username)
	if res["ok"]:
		_username.text = ""
		_show_feedback("Đã gửi lời mời tới @" + username, false)
	else:
		_show_feedback(str(res["error"]), true)


func _show_feedback(text: String, error: bool) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", QBOTheme.DANGER if error else QBOTheme.MUTED)
