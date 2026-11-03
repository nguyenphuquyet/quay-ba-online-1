extends Control
## Đăng nhập / Đăng ký — gọi backend Next.js thật; có chế độ chơi offline.

var ui: CanvasLayer

var _mode := "login"
var _busy := false
var _feedback: Label
var _login_box: VBoxContainer
var _register_box: VBoxContainer
var _tab_login: Button
var _tab_register: Button

var _login_identifier: LineEdit
var _login_password: LineEdit
var _reg_display: LineEdit
var _reg_username: LineEdit
var _reg_email: LineEdit
var _reg_password: LineEdit
var _reg_confirm: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var margin := QBOTheme.margins(56 if not AppConfig.is_mobile else 20)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	var columns := QBOTheme.hbox(48)
	margin.add_child(columns)

	# Cột thương hiệu.
	var brand := QBOTheme.vbox(16)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(brand)
	brand.add_child(QBOTheme.section("NIGHTCLUB XÃ HỘI 3D"))
	var title := QBOTheme.title("QUẨY BAR\nONLINE", 66)
	title.add_theme_constant_override("line_spacing", -8)
	brand.add_child(title)
	var tagline := QBOTheme.label("Bước vào The Chrome Lotus — sân khấu LED, quầy bar champagne và những bữa tiệc do chính bạn điều khiển.", 17, QBOTheme.MUTED)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(360, 0)
	brand.add_child(tagline)
	brand.add_child(QBOTheme.hsep(18))
	for feature in [
		"● Phòng riêng, DJ booth và hệ thống ánh sáng 8 preset",
		"● Màn hình LED + máy tính trong bar",
		"● Voice/text chat, bạn bè, emote và khiêu vũ",
	]:
		brand.add_child(QBOTheme.label(feature, 15, Color(0.8, 0.74, 0.85)))

	var panel := QBOTheme.panel(30)
	panel.custom_minimum_size = Vector2(480, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(panel)
	var form := QBOTheme.vbox(14)
	panel.add_child(form)

	var tabs := QBOTheme.hbox(8)
	form.add_child(tabs)
	_tab_login = QBOTheme.button("ĐĂNG NHẬP", true)
	_tab_login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_login.pressed.connect(func(): _switch_mode("login"))
	tabs.add_child(_tab_login)
	_tab_register = QBOTheme.button("ĐĂNG KÝ")
	_tab_register.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_register.pressed.connect(func(): _switch_mode("register"))
	tabs.add_child(_tab_register)

	_feedback = QBOTheme.muted("", 14)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 22)

	_login_box = QBOTheme.vbox(12)
	form.add_child(_login_box)
	_login_identifier = QBOTheme.line_edit("Tên đăng nhập hoặc email")
	_login_box.add_child(QBOTheme.field("TÀI KHOẢN", _login_identifier))
	_login_password = QBOTheme.line_edit("Mật khẩu", true)
	_login_password.text_submitted.connect(func(_t): _submit_login())
	_login_box.add_child(QBOTheme.field("MẬT KHẨU", _login_password))
	var login_btn := QBOTheme.button("Vào club", true)
	login_btn.pressed.connect(_submit_login)
	_login_box.add_child(login_btn)

	_register_box = QBOTheme.vbox(12)
	_register_box.visible = false
	form.add_child(_register_box)
	_reg_display = QBOTheme.line_edit("Tên hiển thị trong club", false, 32)
	_register_box.add_child(QBOTheme.field("TÊN HIỂN THỊ", _reg_display))
	_reg_username = QBOTheme.line_edit("username (3-24 ký tự)", false, 24)
	_register_box.add_child(QBOTheme.field("TÊN ĐĂNG NHẬP", _reg_username))
	_reg_email = QBOTheme.line_edit("email@example.com", false, 120)
	_register_box.add_child(QBOTheme.field("EMAIL", _reg_email))
	_reg_password = QBOTheme.line_edit("Ít nhất 8 ký tự", true)
	_register_box.add_child(QBOTheme.field("MẬT KHẨU", _reg_password))
	_reg_confirm = QBOTheme.line_edit("Nhập lại mật khẩu", true)
	_reg_confirm.text_submitted.connect(func(_t): _submit_register())
	_register_box.add_child(QBOTheme.field("XÁC NHẬN", _reg_confirm))
	var register_btn := QBOTheme.button("Tạo tài khoản", true)
	register_btn.pressed.connect(_submit_register)
	_register_box.add_child(register_btn)

	form.add_child(_feedback)
	form.add_child(QBOTheme.hsep(2))
	var divider := QBOTheme.muted("— hoặc —", 13)
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	form.add_child(divider)
	var offline := QBOTheme.button("Chơi offline (không cần tài khoản)")
	offline.pressed.connect(func():
		GameState.guest_name = "Khách"
		App.start_solo()
	)
	form.add_child(offline)
	var settings := QBOTheme.button("Cài đặt")
	settings.pressed.connect(func(): ui.call("show_screen", "settings"))
	form.add_child(settings)
	var note := QBOTheme.muted("Backend: %s\nServer game mặc định: %s" % [AppConfig.api_url, AppConfig.endpoint()], 12)
	note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	form.add_child(note)


func _switch_mode(mode: String) -> void:
	_mode = mode
	_login_box.visible = mode == "login"
	_register_box.visible = mode == "register"
	_tab_login.disabled = mode == "login"
	_tab_register.disabled = mode == "register"
	_feedback.text = ""


func _set_feedback(text: String, error := false) -> void:
	_feedback.text = text
	_feedback.add_theme_color_override("font_color", QBOTheme.DANGER if error else QBOTheme.MUTED)


func _submit_login() -> void:
	if _busy:
		return
	var identifier := _login_identifier.text.strip_edges()
	var password := _login_password.text
	if identifier == "" or password == "":
		_set_feedback("Nhập tài khoản và mật khẩu.", true)
		return
	_busy = true
	_set_feedback("Đang đăng nhập…")
	var res := await Api.login(identifier, password)
	_busy = false
	if res["ok"]:
		_set_feedback("")
		ui.call("show_screen", "main_menu")
	else:
		_set_feedback(str(res["error"]), true)


func _submit_register() -> void:
	if _busy:
		return
	var display := _reg_display.text.strip_edges()
	var username := _reg_username.text.strip_edges().to_lower()
	var email := _reg_email.text.strip_edges()
	var password := _reg_password.text
	if display == "" or username == "" or email == "" or password == "":
		_set_feedback("Điền đủ các trường.", true)
		return
	if password != _reg_confirm.text:
		_set_feedback("Mật khẩu xác nhận không khớp.", true)
		return
	_busy = true
	_set_feedback("Đang tạo tài khoản…")
	var res := await Api.register(username, email, password, display)
	_busy = false
	if res["ok"]:
		_set_feedback("Tài khoản đã sẵn sàng!", false)
		ui.call("show_screen", "main_menu")
	else:
		_set_feedback(str(res["error"]), true)
