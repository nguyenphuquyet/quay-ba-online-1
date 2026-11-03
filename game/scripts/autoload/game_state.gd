extends Node
## GameState — phiên đăng nhập, hồ sơ, phòng hiện tại và tiện ích thông báo.
## Không bao giờ lưu mật khẩu; chỉ lưu access/refresh token do backend cấp.

signal session_changed()
signal room_changed()
signal toast_requested(message: String, level: String)

const SESSION_PATH := "user://session.cfg"

var access_token := ""
var refresh_token := ""
var user: Dictionary = {}
var room: Dictionary = {}
var ticket := ""
var server_endpoint := ""
var guest_name := ""
var friends: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_session()


func is_logged_in() -> bool:
	return access_token != "" and not user.is_empty()


func user_id() -> String:
	return str(user.get("id", ""))


func display_name() -> String:
	if not user.is_empty():
		return str(user.get("displayName", user.get("username", "Người chơi")))
	if guest_name != "":
		return guest_name
	return "Khách"


func avatar_url() -> String:
	return str(user.get("avatarUrl", ""))


func set_session(data: Dictionary) -> void:
	access_token = str(data.get("accessToken", ""))
	refresh_token = str(data.get("refreshToken", ""))
	if data.has("user") and data["user"] is Dictionary:
		user = data["user"]
	save_session()
	session_changed.emit()


func set_user(value: Dictionary) -> void:
	user = value
	save_session()
	session_changed.emit()


func clear_session() -> void:
	access_token = ""
	refresh_token = ""
	user = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	session_changed.emit()


func set_room(value: Dictionary) -> void:
	room = value
	room_changed.emit()


func clear_room() -> void:
	room = {}
	room_changed.emit()


func save_session() -> void:
	if access_token == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "access", access_token)
	cfg.set_value("auth", "refresh", refresh_token)
	cfg.set_value("auth", "user", user)
	cfg.save(SESSION_PATH)


func load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	access_token = str(cfg.get_value("auth", "access", ""))
	refresh_token = str(cfg.get_value("auth", "refresh", ""))
	var saved_user = cfg.get_value("auth", "user", {})
	if saved_user is Dictionary:
		user = saved_user


func toast(message: String, level := "info") -> void:
	toast_requested.emit(message, level)
