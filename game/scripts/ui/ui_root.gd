extends CanvasLayer
## UIRoot — quản lý màn hình, overlay, toast và trạng thái input của UI.

const SCREEN_PATHS := {
	"splash": "res://scripts/ui/splash_screen.gd",
	"login": "res://scripts/ui/login_screen.gd",
	"main_menu": "res://scripts/ui/main_menu.gd",
	"room_browser": "res://scripts/ui/room_browser.gd",
	"create_room": "res://scripts/ui/create_room.gd",
	"character_select": "res://scripts/ui/character_select.gd",
	"settings": "res://scripts/ui/settings_screen.gd",
	"friends": "res://scripts/ui/friends_panel.gd",
	"hud": "res://scripts/ui/hud.gd",
}
const OVERLAY_PATHS := {
	"computer": "res://scripts/ui/computer_screen.gd",
	"dj": "res://scripts/ui/dj_panel.gd",
	"lighting": "res://scripts/ui/lighting_panel.gd",
}

var root: Control
var safe_root: Control
var screens: Dictionary = {}
var overlays: Dictionary = {}
var current_screen := ""
var hud: Control

var pending_room: Dictionary = {}
var pending_ticket := ""
var pending_host := ""
var pending_port := 0

var _overlay_open := false
var _chat_focused := false
var _hud_blocked := false
var _web_typing := false
var _toast_box: VBoxContainer
var _menu_background: Control


func boot() -> void:
	layer = 10
	root = Control.new()
	root.name = "UI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = QBOTheme.theme()
	add_child(root)

	_build_background()

	# Mọi màn hình/overlay nằm trong safe_root để chừa vùng tai thỏ và bo góc
	# trên điện thoại. Nền vẫn phủ kín màn hình (không bị viền đen hai bên).
	safe_root = Control.new()
	safe_root.name = "SafeArea"
	safe_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(safe_root)

	_build_toast_layer()
	GameState.toast_requested.connect(toast)
	Net.join_failed.connect(_on_join_failed)
	Net.kicked.connect(_on_kicked)
	Net.connection_lost.connect(_on_connection_lost)

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	show_screen("splash")
	await get_tree().create_timer(1.4).timeout
	if GameState.is_logged_in():
		var res := await Api.me()
		if res["ok"]:
			show_screen("main_menu")
		else:
			GameState.clear_session()
			show_screen("login")
	else:
		show_screen("login")


func _build_background() -> void:
	_menu_background = Control.new()
	_menu_background.name = "MenuBackground"
	_menu_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_menu_background)

	# Nền synthwave của Game Menu Kit Lite, dùng chung cho mọi màn hình menu.
	if MenuKit.style != null:
		var kit_bg := MenuKit.style.create_background()
		kit_bg.name = "KitBackground"
		kit_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		kit_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_background.add_child(kit_bg)
		var overlay := MenuKit.style.create_overlay()
		if overlay != null:
			overlay.name = "KitOverlay"
			overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_menu_background.add_child(overlay)
	else:
		var bg := ColorRect.new()
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.color = QBOTheme.BG
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_menu_background.add_child(bg)

	var footer := QBOTheme.label("QUẨY BAR ONLINE  •  THE CHROME LOTUS  •  v" + AppConfig.APP_VERSION, 12, QBOTheme.MUTED)
	footer.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer.position = Vector2(0, 0)
	footer.offset_left = -460
	footer.offset_top = -34
	footer.offset_right = -24
	footer.offset_bottom = -12
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_menu_background.add_child(footer)


func _build_toast_layer() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toasts"
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.offset_left = -320
	_toast_box.offset_right = 320
	_toast_box.offset_top = 26
	_toast_box.add_theme_constant_override("separation", 8)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe_root.add_child(_toast_box)


# ------------------------------------------------------------------ screens

func show_screen(name: String) -> void:
	if not SCREEN_PATHS.has(name):
		push_error("Màn hình không tồn tại: " + name)
		return
	if _overlay_open:
		close_overlay()
	current_screen = name
	if not screens.has(name):
		var created := _instantiate(SCREEN_PATHS[name], name)
		screens[name] = created
	for key in screens.keys():
		var node: Control = screens[key]
		node.visible = key == name
	var active: Control = screens[name]
	if active.has_method("on_show"):
		active.call("on_show")
	_update_background_visibility()
	if not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _instantiate(path: String, node_name: String) -> Control:
	var script := load(path)
	var node: Control = script.new()
	node.name = node_name.capitalize().replace(" ", "")
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.visible = false
	node.ui = self
	(safe_root if safe_root != null else root).add_child(node)
	return node


func _apply_safe_area() -> void:
	## Trên điện thoại có tai thỏ/bo góc, đẩy toàn bộ UI vào vùng an toàn để
	## không bị cắt mất hai mép. Nền vẫn phủ kín nên không lộ viền đen.
	if safe_root == null:
		return
	safe_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not AppConfig.is_mobile:
		return
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return
	var view := get_viewport().get_visible_rect().size
	var left := clampf(float(safe.position.x) / float(screen.x), 0.0, 0.2)
	var top := clampf(float(safe.position.y) / float(screen.y), 0.0, 0.2)
	var right := clampf(float(screen.x - safe.position.x - safe.size.x) / float(screen.x), 0.0, 0.2)
	var bottom := clampf(float(screen.y - safe.position.y - safe.size.y) / float(screen.y), 0.0, 0.2)
	safe_root.offset_left = round(view.x * left)
	safe_root.offset_top = round(view.y * top)
	safe_root.offset_right = -round(view.x * right)
	safe_root.offset_bottom = -round(view.y * bottom)


func _update_background_visibility() -> void:
	var in_game := current_screen == "hud"
	if _menu_background != null:
		_menu_background.visible = not in_game and not _overlay_open


func enter_game() -> void:
	_overlay_open = false
	show_screen("hud")
	hud = screens.get("hud")
	_update_background_visibility()


func exit_game() -> void:
	close_overlay()
	show_screen("main_menu")
	if screens.has("main_menu") and screens["main_menu"].has_method("on_show"):
		screens["main_menu"].call("on_show")


func set_interaction_prompt(text: String) -> void:
	if hud != null and is_instance_valid(hud) and hud.has_method("set_prompt"):
		hud.call("set_prompt", text)


func set_camera_mode(third_person: bool) -> void:
	if hud != null and hud.has_method("set_camera_label"):
		hud.call("set_camera_label", third_person)


func set_chat_focused(value: bool) -> void:
	_chat_focused = value


func is_input_blocked() -> bool:
	# Màn hình Settings/Friends mở từ HUD: không còn là "hud" nên player phải
	# ngừng khoá chuột, nếu không con trỏ sẽ biến mất và không bấm được.
	var screen_open := current_screen != "" and current_screen != "hud"
	return _overlay_open or _chat_focused or _hud_blocked or screen_open


func set_hud_blocked(value: bool) -> void:
	_hud_blocked = value


## Đang gõ bàn phím vào trang web trên TV: chặn di chuyển/nhảy nhưng vẫn giữ
## chuột ở chế độ captured để ngắm màn hình.
func set_web_typing(value: bool) -> void:
	_web_typing = value


func is_web_typing() -> bool:
	return _web_typing


func is_overlay_open() -> bool:
	return _overlay_open


func open_overlay(kind: String, params: Dictionary = {}) -> void:
	if not OVERLAY_PATHS.has(kind):
		return
	if overlays.has(kind):
		var existing: Control = overlays[kind]
		if is_instance_valid(existing):
			existing.queue_free()
		overlays.erase(kind)
	var script := load(OVERLAY_PATHS[kind])
	var node: Control = script.new()
	node.name = "Overlay_" + kind
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.ui = self
	node.params = params
	(safe_root if safe_root != null else root).add_child(node)
	overlays[kind] = node
	_overlay_open = true
	_menu_background.visible = false
	if not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_overlay() -> void:
	for key in overlays.keys():
		var node = overlays[key]
		if is_instance_valid(node):
			node.queue_free()
	overlays.clear()
	_overlay_open = false
	_update_background_visibility()
	if current_screen == "hud" and not AppConfig.is_mobile:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if hud != null and hud.has_method("set_prompt"):
		hud.call("set_prompt", "")


func toast(message: String, level := "info") -> void:
	if _toast_box == null:
		return
	var color := QBOTheme.TEXT
	if level == "error":
		color = QBOTheme.DANGER
	elif level == "success":
		color = QBOTheme.SUCCESS
	elif level == "warn":
		color = QBOTheme.GOLD
	var panel := PanelContainer.new()
	var style := QBOTheme.panel_style(QBOTheme.PANEL_ALT, 12, Color(1, 1, 1, 0.1))
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var label := QBOTheme.label(message, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_toast_box.add_child(panel)
	panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(3.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)


func begin_room(room: Dictionary, ticket: String, host: String, port: int) -> void:
	pending_room = room
	pending_ticket = ticket
	pending_host = host
	pending_port = port
	show_screen("character_select")


func enter_pending_room() -> void:
	App.start_room(pending_room, pending_ticket, pending_host, pending_port)


func _on_join_failed(reason: String) -> void:
	toast(reason, "error")
	App.leave_room()


func _on_kicked(reason: String) -> void:
	toast(reason, "error")
	App.leave_room()


func _on_connection_lost(reason: String) -> void:
	toast(reason, "error")
