extends Control
## HUD trong club: chat, danh sách người chơi, quyền chủ phòng, mobile controls.

var ui: CanvasLayer

var _room_label: Label
var _count_label: Label
var _fps_label: Label
var _camera_label: Label
var _prompt_panel: PanelContainer
var _prompt_label: Label
var _chat_panel: PanelContainer
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _player_panel: PanelContainer
var _player_list: VBoxContainer
var _menu_panel: PanelContainer
var _menu_open := false
var _quick_menu: PanelContainer
var _quick_blocker: Control
var _player_panel_open := false
var _chat_open := false
var _mobile: Control
var _joystick: QBOVirtualJoystick
var _run_button: Button
var _look_touch := -1
var _look_last := Vector2.ZERO
var _connected := false
var _refresh_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect_signals()


func _connect_signals() -> void:
	if _connected:
		return
	_connected = true
	Net.chat_received.connect(_on_chat)
	Net.system_message.connect(_on_system_message)
	Net.roster_changed.connect(_on_roster_changed)
	Net.room_settings_received.connect(func(_s): _refresh_player_list())
	Net.join_succeeded.connect(func(_r): _update_room_info())
	Net.player_joined.connect(func(_id, _info): _refresh_player_list())
	Net.player_left.connect(func(_id): _refresh_player_list())


func on_show() -> void:
	_connect_signals()
	_update_room_info()
	_refresh_player_list()
	_set_chat_visible(false)
	_player_panel.visible = false
	_menu_panel.visible = false
	_menu_open = false
	_close_quick_menu()
	_look_touch = -1
	if _joystick != null:
		_joystick.visible = true
	ui.call("set_hud_blocked", false) if ui.has_method("set_hud_blocked") else null
	if not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_append_chat("Hệ thống", "Chào mừng tới The Chrome Lotus. Nhấn Enter để chat, E để tương tác.", QBOTheme.GOLD)


func _build() -> void:
	_build_top_bar()
	_build_crosshair()
	_build_prompt()
	_build_chat()
	_build_player_panel()
	_build_menu()
	_build_mobile_controls()
	_build_hints()


func _build_top_bar() -> void:
	# Không dùng dải ngang full-width nữa: chỉ 2 cụm nhỏ nổi ở hai góc.
	var club := QBOTheme.vbox(0)
	club.add_child(QBOTheme.label("THE CHROME LOTUS", 15, QBOTheme.GOLD_BRIGHT))
	_room_label = QBOTheme.muted("", 11)
	club.add_child(_room_label)
	var left := _hud_pill(club)
	_anchor_pill(left, true)
	add_child(left)

	var row := QBOTheme.hbox(10)
	_count_label = QBOTheme.label("", 12, QBOTheme.MUTED)
	row.add_child(_count_label)
	_camera_label = QBOTheme.muted("Góc nhìn 3", 11)
	row.add_child(_camera_label)
	_fps_label = QBOTheme.label("", 11, QBOTheme.SUCCESS)
	row.add_child(_fps_label)

	# Gom các nút phụ vào một icon menu ☰ để góc phải thật gọn.
	var quick := QBOTheme.button("☰")
	quick.tooltip_text = "Menu nhanh: người chơi, DJ, ánh sáng, menu"
	quick.custom_minimum_size = Vector2(40, 32)
	quick.add_theme_font_size_override("font_size", 18)
	quick.pressed.connect(_toggle_quick_menu)
	row.add_child(quick)
	var right := _hud_pill(row)
	_anchor_pill(right, false)
	add_child(right)
	_build_quick_menu()


func _hud_pill(content: Control) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := QBOTheme.panel_style(Color(0.03, 0.02, 0.04, 0.55), 18, Color(1, 1, 1, 0.06))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	pill.add_theme_stylebox_override("panel", style)
	pill.add_child(content)
	return pill


func _anchor_pill(pill: PanelContainer, align_left: bool) -> void:
	if align_left:
		pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
		pill.grow_horizontal = Control.GROW_DIRECTION_END
		pill.offset_left = 16
		pill.offset_top = 14
		pill.offset_right = 16
		pill.offset_bottom = 14
	else:
		pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		pill.offset_left = -16
		pill.offset_top = 14
		pill.offset_right = -16
		pill.offset_bottom = 14
	pill.reset_size()


func _build_quick_menu() -> void:
	_quick_blocker = Control.new()
	_quick_blocker.name = "QuickMenuBlocker"
	_quick_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quick_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_quick_blocker.visible = false
	_quick_blocker.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_close_quick_menu()
	)
	add_child(_quick_blocker)

	_quick_menu = PanelContainer.new()
	_quick_menu.name = "QuickMenu"
	_quick_menu.visible = false
	_quick_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quick_menu.offset_left = -248
	_quick_menu.offset_right = -16
	_quick_menu.offset_top = 74
	_quick_menu.offset_bottom = 286
	_quick_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := QBOTheme.panel_style(Color(0.035, 0.026, 0.045, 0.98), 12, Color(0.96, 0.82, 0.53, 0.4))
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_quick_menu.add_theme_stylebox_override("panel", style)
	add_child(_quick_menu)

	var box := QBOTheme.vbox(6)
	_quick_menu.add_child(box)
	var title := QBOTheme.section("MENU NHANH")
	box.add_child(title)
	for entry in [
		{"text": "Người chơi", "callable": _toggle_player_panel},
		{"text": "TV sân khấu", "callable": _open_stage_tv},
		{"text": "DJ", "callable": func(): App.open_dj_panel()},
		{"text": "Ánh sáng", "callable": func(): App.open_lighting_panel()},
		{"text": "Menu", "callable": _toggle_menu},
	]:
		var action: Callable = entry["callable"]
		var button := QBOTheme.button(str(entry["text"]))
		button.custom_minimum_size = Vector2(0, 36)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func():
			_close_quick_menu()
			action.call()
		)
		box.add_child(button)


func _open_stage_tv() -> void:
	## Mobile: mở WebView native đúng video cả phòng đang xem. Desktop: mở bảng
	## điều khiển TV (màn web đã render sẵn trong club).
	var tv = App.world.tv if App.world != null else null
	if tv != null and tv.native_player_available() and tv.open_native_player():
		return
	App.open_computer("tv")


func _toggle_quick_menu() -> void:
	if _quick_menu == null:
		return
	if _quick_menu.visible:
		_close_quick_menu()
	else:
		_menu_open = false
		_menu_panel.visible = false
		_quick_menu.visible = true
		_quick_blocker.visible = true
		_sync_hud_block()
		if not AppConfig.is_mobile:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_quick_menu() -> void:
	if _quick_menu == null:
		return
	_quick_menu.visible = false
	if _quick_blocker != null:
		_quick_blocker.visible = false
	_sync_hud_block()


func _sync_hud_block() -> void:
	if ui != null and ui.has_method("set_hud_blocked"):
		var quick_open := _quick_menu != null and _quick_menu.visible
		ui.call("set_hud_blocked", _menu_open or quick_open)


func _build_crosshair() -> void:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(4, 4)
	dot.size = Vector2(4, 4)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -2
	dot.offset_top = -2
	dot.offset_right = 2
	dot.offset_bottom = 2
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.65)
	style.set_corner_radius_all(2)
	dot.add_theme_stylebox_override("panel", style)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_panel.offset_left = -240
	_prompt_panel.offset_right = 240
	_prompt_panel.offset_top = -150
	_prompt_panel.offset_bottom = -104
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := QBOTheme.panel_style(Color(0.04, 0.025, 0.05, 0.82), 12, Color(0.96, 0.82, 0.53, 0.35))
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_prompt_panel.add_theme_stylebox_override("panel", style)
	add_child(_prompt_panel)
	_prompt_label = QBOTheme.label("", 15, QBOTheme.TEXT)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.visible = false


func _build_chat() -> void:
	_chat_panel = PanelContainer.new()
	_chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	# Cao theo nội dung: 1 dòng thì bé xíu, nhiều tin thì tự nới lên.
	_chat_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_panel.offset_left = 16
	_chat_panel.offset_top = -24
	_chat_panel.offset_right = 460
	_chat_panel.offset_bottom = -24
	_chat_panel.custom_minimum_size = Vector2(444, 0)
	_chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := QBOTheme.panel_style(Color(0.03, 0.02, 0.04, 0.45), 14, Color(1, 1, 1, 0.05))
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_chat_panel.add_theme_stylebox_override("panel", style)
	add_child(_chat_panel)
	var box := QBOTheme.vbox(4)
	_chat_panel.add_child(box)
	_chat_log = QBOTheme.vbox(2)
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_chat_log)
	_chat_input = QBOTheme.line_edit("Nhập tin nhắn rồi Enter…", false, 240)
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_submit_chat)
	_chat_input.focus_entered.connect(func(): ui.call("set_chat_focused", true))
	_chat_input.focus_exited.connect(func(): ui.call("set_chat_focused", false))
	box.add_child(_chat_input)
	_chat_panel.visible = false


func _build_player_panel() -> void:
	_player_panel = PanelContainer.new()
	_player_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_player_panel.offset_left = -380
	_player_panel.offset_right = -20
	_player_panel.offset_top = 92
	_player_panel.offset_bottom = 640
	_player_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_player_panel.add_theme_stylebox_override("panel", QBOTheme.panel_style(QBOTheme.PANEL, 16))
	add_child(_player_panel)
	var box := QBOTheme.vbox(8)
	_player_panel.add_child(box)
	var head := QBOTheme.hbox(8)
	head.add_child(QBOTheme.section("TRONG PHÒNG"))
	head.add_child(QBOTheme.spacer())
	var close := QBOTheme.button("×")
	close.custom_minimum_size = Vector2(36, 30)
	close.pressed.connect(_toggle_player_panel)
	head.add_child(close)
	box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_player_list = QBOTheme.vbox(6)
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_player_list)
	var manage := QBOTheme.button("Quản lý phòng")
	manage.pressed.connect(_toggle_menu)
	box.add_child(manage)
	_player_panel.visible = false


func _build_menu() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_menu_panel.offset_left = -230
	_menu_panel.offset_right = 230
	_menu_panel.offset_top = -280
	_menu_panel.offset_bottom = 280
	_menu_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_panel.add_theme_stylebox_override("panel", QBOTheme.panel_style(QBOTheme.PANEL_ALT, 20, QBOTheme.GOLD))
	add_child(_menu_panel)
	var box := QBOTheme.vbox(10)
	_menu_panel.add_child(box)
	box.add_child(QBOTheme.title("TẠM DỪNG", 28))
	var name_label := QBOTheme.muted("%s  •  %s" % [GameState.display_name(), str(GameState.room.get("code", ""))], 13)
	box.add_child(name_label)
	box.add_child(QBOTheme.hsep(6))

	var resume := QBOTheme.button("Tiếp tục", true)
	resume.pressed.connect(_toggle_menu)
	box.add_child(resume)
	var settings := QBOTheme.button("Cài đặt")
	settings.pressed.connect(func():
		_toggle_menu()
		ui.call("show_screen", "settings")
	)
	box.add_child(settings)
	var friends := QBOTheme.button("Bạn bè")
	friends.pressed.connect(func():
		_toggle_menu()
		ui.call("show_screen", "friends")
	)
	box.add_child(friends)
	var copy := QBOTheme.button("Sao chép mã phòng")
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(str(GameState.room.get("code", "")))
		ui.call("toast", "Đã sao chép mã phòng.", "success")
	)
	box.add_child(copy)
	box.add_child(QBOTheme.hsep(6))
	box.add_child(QBOTheme.section("QUYỀN CHỦ PHÒNG"))
	var owner_note := QBOTheme.muted("Chỉ chủ phòng thay đổi được các khóa dưới đây.", 12)
	owner_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(owner_note)
	_add_lock_toggle(box, "Khóa quyền DJ", "dj_locked")
	_add_lock_toggle(box, "Khóa quyền ánh sáng", "lighting_locked")
	_add_lock_toggle(box, "Khóa quyền TV", "tv_locked")
	box.add_child(QBOTheme.hsep(6))
	var leave := QBOTheme.button("Rời phòng")
	leave.pressed.connect(func():
		_toggle_menu()
		App.leave_room()
	)
	box.add_child(leave)
	_menu_panel.visible = false


func _add_lock_toggle(parent: VBoxContainer, text: String, key: String) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = bool(Net.room_settings.get(key, false))
	check.disabled = not Net.is_owner()
	check.toggled.connect(func(value: bool): Net.set_room_setting(key, value))
	parent.add_child(check)


func _build_mobile_controls() -> void:
	if not AppConfig.is_mobile:
		return
	_mobile = Control.new()
	_mobile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mobile)

	_look_touch = -1

	# Nửa trái màn hình là vùng di chuyển: chạm đâu joystick mọc ra đó.
	# Vùng joystick chỉ chiếm góc dưới-trái (ngón cái). Trước đây vùng này
	# rộng 56% × 85% màn hình nên phần lớn chỗ vuốt đều bị joystick nuốt mất,
	# khiến người chơi tưởng "xoay camera không ăn".
	_joystick = QBOVirtualJoystick.new()
	_joystick.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_joystick.anchor_left = 0.0
	_joystick.anchor_top = 0.52
	_joystick.anchor_right = 0.38
	_joystick.anchor_bottom = 1.0
	_joystick.offset_left = 0
	_joystick.offset_top = 0
	_joystick.offset_right = 0
	_joystick.offset_bottom = 0
	_joystick.moved.connect(_on_joystick)
	_mobile.add_child(_joystick)

	var pad := GridContainer.new()
	pad.columns = 2
	pad.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pad.offset_left = -300
	pad.offset_top = -300
	pad.offset_right = -28
	pad.offset_bottom = -28
	pad.add_theme_constant_override("h_separation", 10)
	pad.add_theme_constant_override("v_separation", 10)
	_mobile.add_child(pad)

	var jump := _mobile_button("Nhảy", 86)
	jump.pressed.connect(func(): _with_player("jump"))
	pad.add_child(jump)
	var interact := _mobile_button("Tương tác", 86)
	interact.pressed.connect(func(): _with_player("interact"))
	pad.add_child(interact)
	_run_button = _mobile_button("Chạy", 86)
	_run_button.toggle_mode = true
	_run_button.toggled.connect(func(value: bool):
		if _run_button != null:
			_run_button.text = "Chạy" if value else "Đi bộ"
		var player = App.local_player()
		if player != null:
			player.set_sprint_toggle(value)
	)
	pad.add_child(_run_button)
	var camera_btn := _mobile_button("Camera", 86)
	camera_btn.pressed.connect(func(): _with_player("camera"))
	pad.add_child(camera_btn)
	var chat_btn := _mobile_button("Chat", 86)
	chat_btn.pressed.connect(_open_chat)
	pad.add_child(chat_btn)
	var dance := _mobile_button("Khiêu vũ", 86)
	dance.pressed.connect(func(): _with_player("dance"))
	pad.add_child(dance)


func _mobile_button(text: String, min_size: int) -> Button:
	var button := QBOTheme.button(text)
	button.custom_minimum_size = Vector2(min_size, 68)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _build_hints() -> void:
	if AppConfig.is_mobile:
		return
	var hint := QBOTheme.label("WASD di chuyển  •  Shift chạy  •  Space nhảy  •  E tương tác  •  V camera  •  Tab menu nhanh  •  Enter chat  •  Esc menu", 12, Color(0.72, 0.68, 0.78, 0.8))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -360
	hint.offset_right = 360
	hint.offset_top = -46
	hint.offset_bottom = -22
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


# ------------------------------------------------------------------ input

func _with_player(action: String) -> void:
	var player = App.local_player()
	if player == null:
		return
	match action:
		"jump":
			player.call("_jump")
		"interact":
			player.call("_try_interact")
		"camera":
			player.call("toggle_camera")
		"dance":
			player.call("play_emote", "dance")
		"drink":
			player.call("play_emote", "drink")


func _on_joystick(value: Vector2) -> void:
	var player = App.local_player()
	if player != null:
		player.set_touch_move(value)


func _unhandled_input(event: InputEvent) -> void:
	## Xoay camera bằng ngón tay ở mọi vùng trống trên màn hình (trừ vùng
	## joystick / nút bấm đã bị các Control đó nhận trước). Trước đây chỉ có
	## một dải 420px bên phải nên chạm ra ngoài là camera "không ăn".
	if not AppConfig.is_mobile or not visible:
		return
	if _chat_open or _menu_open:
		return
	if _quick_menu != null and _quick_menu.visible:
		return
	if ui != null and bool(ui.call("is_overlay_open")):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Luôn nhận ngón mới nhất. Nếu một lần nhấc tay trước đó bị UI
			# nuốt mất, trạng thái cũ không còn khoá camera nữa.
			_look_touch = touch.index
			_look_last = touch.position
		elif touch.index == _look_touch:
			_look_touch = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _look_touch:
			return
		var player = App.local_player()
		if player == null:
			return
		# Tính theo hiệu vị trí thực tế thay vì `relative` để ổn định trên
		# Android/iOS ở các mức DPI khác nhau.
		var move := drag.position - _look_last
		_look_last = drag.position
		if move.length_squared() > 0.0:
			player.add_touch_look(move)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if ui.call("is_overlay_open"):
		return
	# Bàn phím đang gửi vào trang web trên TV.
	if ui.has_method("is_web_typing") and bool(ui.call("is_web_typing")):
		return
	if event.is_action_pressed("chat") and not _chat_open:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu"):
		if _chat_open:
			_close_chat()
		elif _quick_menu != null and _quick_menu.visible:
			_close_quick_menu()
		else:
			_toggle_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_menu") and not _chat_open:
		_toggle_quick_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("emote") and not _chat_open:
		_with_player("drink")
	elif event.is_action_pressed("dance") and not _chat_open:
		_with_player("dance")


# ------------------------------------------------------------------ chat

func _open_chat() -> void:
	_set_chat_visible(true)
	_chat_open = true
	# Bàn phím ảo đang mở thì tắt joystick để không chặn ô nhập chat.
	if _joystick != null:
		_joystick.visible = false
		_on_joystick(Vector2.ZERO)
	_look_touch = -1
	_chat_input.grab_focus()
	ui.call("set_chat_focused", true)
	if AppConfig.is_mobile:
		DisplayServer.virtual_keyboard_show("")
	if not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close_chat() -> void:
	_chat_open = false
	if _joystick != null:
		_joystick.visible = true
	_look_touch = -1
	_chat_input.release_focus()
	_chat_input.text = ""
	_set_chat_visible(false)
	ui.call("set_chat_focused", false)
	if AppConfig.is_mobile:
		DisplayServer.virtual_keyboard_hide()
	elif App.world != null:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _set_chat_visible(value: bool) -> void:
	_chat_panel.visible = value
	_chat_input.visible = value
	_fit_chat_panel()


func _fit_chat_panel() -> void:
	if _chat_panel == null:
		return
	# Chờ container tính lại min size rồi mới co giãn theo nội dung.
	await get_tree().process_frame
	if is_instance_valid(_chat_panel):
		_chat_panel.reset_size()


func _submit_chat(text: String) -> void:
	var message := text.strip_edges()
	if message != "":
		Net.send_chat(message)
	_close_chat()


func _on_chat(_id: int, display: String, text: String) -> void:
	_append_chat(display, text, QBOTheme.TEXT)


func _on_system_message(text: String) -> void:
	_append_chat("Hệ thống", text, QBOTheme.GOLD)


func _append_chat(from: String, text: String, color: Color) -> void:
	if _chat_log == null:
		return
	if not _chat_open:
		_set_chat_visible(true)
	var label := QBOTheme.label("%s: %s" % [from, text], 13, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_log.add_child(label)
	while _chat_log.get_child_count() > 7:
		var oldest := _chat_log.get_child(0)
		_chat_log.remove_child(oldest)
		oldest.queue_free()
	_fit_chat_panel()
	# Tự ẩn chat khi không mở sau 12s.
	var timer := get_tree().create_timer(12.0)
	timer.timeout.connect(func():
		if not _chat_open and is_instance_valid(label) and _chat_log.get_child_count() > 0:
			_set_chat_visible(false)
	)


# ------------------------------------------------------------------ panels

func _toggle_player_panel() -> void:
	_player_panel_open = not _player_panel_open
	_player_panel.visible = _player_panel_open
	if _player_panel_open:
		_refresh_player_list()


func _toggle_menu() -> void:
	_close_quick_menu()
	_menu_open = not _menu_open
	_menu_panel.visible = _menu_open
	if ui.has_method("set_hud_blocked"):
		ui.call("set_hud_blocked", _menu_open)
	if not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _menu_open else Input.MOUSE_MODE_CAPTURED)
	if _menu_open:
		_refresh_player_list()


func set_prompt(text: String) -> void:
	if _prompt_panel == null:
		return
	_prompt_panel.visible = text != ""
	if text != "":
		_prompt_label.text = ("Nhấn nút Tương tác — " if AppConfig.is_mobile else "E  —  ") + text


func set_camera_label(third_person: bool) -> void:
	if _camera_label != null:
		_camera_label.text = "Góc nhìn 3" if third_person else "Góc nhìn 1"


func _update_room_info() -> void:
	if _room_label == null:
		return
	var room_name := str(GameState.room.get("name", "The Chrome Lotus"))
	var code := str(GameState.room.get("code", "SOLO"))
	var solo := int(GameState.room.get("maxPlayers", 1)) <= 1 and code == "SOLO"
	# Giữ nhãn ngắn để cụm góc trái không kéo dài thành dải.
	_room_label.text = "Phòng offline • SOLO" if solo else "%s • %s" % [room_name, code]
	_count_label.visible = not solo
	_count_label.text = "%d/%d người" % [Net.players.size(), int(GameState.room.get("maxPlayers", AppConfig.MAX_ROOM_PLAYERS))]


func _on_roster_changed(_roster: Array) -> void:
	_update_room_info()
	if _player_panel_open or _menu_open:
		_refresh_player_list()


func _refresh_player_list() -> void:
	if _player_list == null:
		return
	for child in _player_list.get_children():
		child.queue_free()
	for entry in Net.roster:
		var row := QBOTheme.panel(10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := QBOTheme.vbox(2)
		row.add_child(line)
		var top := QBOTheme.hbox(6)
		line.add_child(top)
		var name_text := str(entry.get("name", "Người chơi"))
		if int(entry.get("id", -1)) == Net.local_peer_id:
			name_text += " (bạn)"
		top.add_child(QBOTheme.label(name_text, 14, QBOTheme.TEXT))
		if bool(entry.get("is_owner", false)):
			top.add_child(QBOTheme.label("CHỦ PHÒNG", 10, QBOTheme.GOLD))
		var dj_allowed: bool = Net.can_control("dj", int(entry.get("id", -1)))
		if dj_allowed and not bool(entry.get("is_owner", false)):
			top.add_child(QBOTheme.label("DJ", 10, QBOTheme.CYAN))
		if Net.is_owner() and int(entry.get("id", -1)) != Net.local_peer_id:
			var actions := QBOTheme.hbox(6)
			var grant := QBOTheme.button("Cấp DJ" if not dj_allowed else "Thu DJ")
			grant.custom_minimum_size = Vector2(0, 30)
			grant.add_theme_font_size_override("font_size", 11)
			var target_id := int(entry.get("id", -1))
			grant.pressed.connect(func():
				if Net.can_control("dj", target_id):
					Net.revoke_permission("dj", target_id)
				else:
					Net.grant_permission("dj", target_id)
				_refresh_player_list()
			)
			actions.add_child(grant)
			var kick := QBOTheme.button("Mời ra")
			kick.custom_minimum_size = Vector2(0, 30)
			kick.add_theme_font_size_override("font_size", 11)
			kick.pressed.connect(func(): Net.kick_peer(target_id))
			actions.add_child(kick)
			line.add_child(actions)
		_player_list.add_child(row)


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < 1.0:
		return
	_refresh_timer = 0.0
	_update_room_info()
	if _fps_label != null:
		if SettingsManager.show_fps:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
		else:
			_fps_label.text = ""
