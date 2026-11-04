extends MenuKitMainMenu
## Main Menu — điểm vào của club, dựng trên Game Menu Kit Lite.
##
## Phần khung (nền synthwave, tiêu đề phát sáng, hiệu ứng intro, xác nhận thoát,
## điều hướng bàn phím/gamepad) do kit lo. Phần nghiệp vụ của QUẨY BAR ONLINE
## (phòng, bạn bè, đăng nhập, vào nhanh bằng mã phòng) nằm trong poster bên phải.

var ui: CanvasLayer

var _poster: PanelContainer
var _status: Label
var _profile: Label
var _room_code_input: LineEdit
var _account_button: MenuKitMenuButton


func _init() -> void:
	kicker = "THE CHROME LOTUS // NIGHTCLUB ONLINE"
	title_lines = PackedStringArray(["QUẨY BAR", "ONLINE"])
	footer_text = "WASD DI CHUYỂN  ·  E TƯƠNG TÁC  ·  ESC MENU  ·  v" + AppConfig.APP_VERSION
	confirm_quit = true


func _ready() -> void:
	super()
	_build_poster()
	resized.connect(_layout_poster)


## Dùng nền synthwave chung của UIRoot để không tạo hai shader cùng lúc.
func _create_background() -> Control:
	var clear := Control.new()
	clear.name = "TransparentBackground"
	clear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return clear


func on_show() -> void:
	_refresh_profile()
	_check_backend()
	_sync_account_button()
	focus_first_button()


# ------------------------------------------------------------------ menu buttons

func _add_buttons() -> void:
	_make_button("Vào phòng đang mở", &"browse")
	_make_button("Tạo phòng của bạn", &"create")
	_make_button("Chơi solo / offline", &"solo")
	_make_button("Bạn bè", &"friends")
	_make_button("Cài đặt", &"settings")
	_account_button = _make_button("Đăng nhập / Đăng ký", &"account")
	if not OS.has_feature("web"):
		_make_button("Thoát game", &"quit")


func _on_button_pressed(id: StringName) -> void:
	super(id)
	match id:
		&"browse":
			ui.call("show_screen", "room_browser")
		&"create":
			ui.call("show_screen", "create_room")
		&"solo":
			if not GameState.is_logged_in():
				GameState.guest_name = "Khách"
			App.start_solo()
		&"friends":
			ui.call("show_screen", "friends")
		&"settings":
			ui.call("show_screen", "settings")
		&"account":
			if GameState.is_logged_in():
				_logout()
			else:
				ui.call("show_screen", "login")
		&"quit":
			ask_quit()


func _sync_account_button() -> void:
	if _account_button == null:
		return
	_account_button.text = "Đăng xuất" if GameState.is_logged_in() else "Đăng nhập / Đăng ký"


## Xác nhận trước khi thoát, sau đó dùng màn hình goodbye của kit.
func ask_quit() -> void:
	var choice: int = await ask(
		"Rời câu lạc bộ?",
		"Bạn sẽ thoát khỏi Quẩy Bar Online. Hẹn gặp lại ở The Chrome Lotus.",
		["Ở lại", "Thoát"]
	)
	if choice != 1:
		return
	if quit_requested.get_connections().is_empty():
		MenuKit.quit_game()
	else:
		quit_requested.emit()


# ------------------------------------------------------------------ poster

func _build_poster() -> void:
	_poster = QBOTheme.panel(20)
	_poster.name = "ClubPoster"
	_poster.anchor_left = 1.0
	_poster.anchor_right = 1.0
	_poster.anchor_top = 0.5
	_poster.anchor_bottom = 0.5
	_poster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_poster.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_poster)

	var box := QBOTheme.vbox(10)
	_poster.add_child(box)
	box.add_child(QBOTheme.section("HÔM NAY TẠI CLB"))
	box.add_child(QBOTheme.title("THE CHROME LOTUS", 28))

	var desc := QBOTheme.muted(
		"Nightclub Chinese Modern · Cyberpunk nhẹ\n" +
		"TV nhạc DJ 20:9 · TV thông tin nhà phát triển · DJ booth · 2 quầy bar · VIP lounge",
		13
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	box.add_child(QBOTheme.hsep(4))
	for line in [
		{"k": "Bản đồ", "v": "The Chrome Lotus"},
		{"k": "Sức chứa", "v": "tối đa 32 người / phòng"},
		{"k": "Ánh sáng", "v": "8 preset + beat sync"},
		{"k": "Màn hình", "v": "TV nhạc DJ + TV nhà phát triển + PC"},
	]:
		var row := QBOTheme.hbox(8)
		var key := QBOTheme.muted(str(line["k"]), 12)
		key.custom_minimum_size = Vector2(86, 0)
		row.add_child(key)
		row.add_child(QBOTheme.label(str(line["v"]), 13, QBOTheme.TEXT))
		box.add_child(row)

	box.add_child(QBOTheme.hsep(4))
	_profile = QBOTheme.label("", 12, Color(0.72, 0.8, 0.9))
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_profile)

	box.add_child(QBOTheme.hsep(2))
	box.add_child(QBOTheme.section("VÀO NHANH BẰNG MÃ PHÒNG"))
	var join_row := QBOTheme.hbox(8)
	_room_code_input = QBOTheme.line_edit("Mã phòng, ví dụ LOTUS-2481", false, 24)
	join_row.add_child(_room_code_input)
	var join_btn := QBOTheme.button("Vào", true)
	join_btn.pressed.connect(_join_by_code)
	join_row.add_child(join_btn)
	box.add_child(join_row)
	var hint := QBOTheme.muted("Mã phòng do chủ phòng chia sẻ. Phòng riêng cần mật khẩu.", 11)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	_status = QBOTheme.muted("", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_layout_poster()


func _layout_poster() -> void:
	if _poster == null:
		return
	var wide := size.x >= 1180.0
	_poster.visible = wide
	if not wide:
		return
	var width := 440.0
	var margin := 64.0
	_poster.offset_left = -width - margin
	_poster.offset_right = -margin
	_poster.offset_top = -300
	_poster.offset_bottom = 300


func _refresh_profile() -> void:
	if _profile == null:
		return
	if GameState.is_logged_in():
		_profile.text = "Đã đăng nhập: %s  •  @%s" % [
			GameState.display_name(), str(GameState.user.get("username", "")),
		]
		_profile.add_theme_color_override("font_color", QBOTheme.SUCCESS)
	else:
		_profile.text = "Chế độ khách — đăng nhập để tạo phòng và kết bạn."
		_profile.add_theme_color_override("font_color", QBOTheme.MUTED)


func _check_backend() -> void:
	if _status == null:
		return
	_status.text = "Đang kiểm tra backend %s…" % AppConfig.api_url
	var res := await Api.request("GET", "/api/health", null, false, 6.0)
	if res["ok"] and res["data"] is Dictionary:
		var data: Dictionary = res["data"]
		var db := str(data.get("database", "unknown"))
		_status.text = "Backend online  •  MySQL: %s  •  Game server: %s" % [db, AppConfig.endpoint()]
		_status.add_theme_color_override("font_color", QBOTheme.SUCCESS)
	else:
		_status.text = "Backend offline — vẫn chơi solo được; phòng online cần Next.js + MySQL."
		_status.add_theme_color_override("font_color", QBOTheme.GOLD)


# ------------------------------------------------------------------ quick join

func _join_by_code() -> void:
	var code := _room_code_input.text.strip_edges().to_upper()
	if code == "":
		return
	if not GameState.is_logged_in():
		ui.call("toast", "Đăng nhập để tham gia phòng online.", "warn")
		ui.call("show_screen", "login")
		return
	var password := ""
	var detail := await Api.room_detail(code)
	if detail["ok"] and detail["data"] is Dictionary:
		var room: Dictionary = detail["data"].get("room", detail["data"])
		if bool(room.get("isPrivate", false)):
			ui.call("toast", "Phòng này yêu cầu mật khẩu — hãy vào từ danh sách phòng.", "warn")
			return
	var res := await Api.join_room(code, password)
	if not res["ok"]:
		ui.call("toast", str(res["error"]), "error")
		return
	_handle_join_response(res["data"])


func _handle_join_response(data: Dictionary) -> void:
	var room: Dictionary = data.get("room", {})
	var ticket := str(data.get("ticket", ""))
	var game: Dictionary = data.get("game", {})
	if ticket == "":
		ui.call("toast", "Backend không cấp game ticket.", "error")
		return
	var host := str(game.get("host", AppConfig.game_host))
	var port := int(game.get("port", AppConfig.game_port))
	ui.call("begin_room", room, ticket, host, port)


func _logout() -> void:
	await Api.logout()
	ui.call("toast", "Đã đăng xuất.", "success")
	_sync_account_button()
	_refresh_profile()
	ui.call("show_screen", "login")
