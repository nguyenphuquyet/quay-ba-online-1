extends Node
## AppConfig — hằng số toàn cục, biến môi trường và đăng ký input action.
## Autoload chạy trước scene chính nên input/mobile detection luôn sẵn sàng.

const APP_NAME := "QUẨY BAR ONLINE"
const APP_VERSION := "0.1.0"
const DEFAULT_API_URL := "https://quay-bar-online-server.vercel.app"
const DEFAULT_GAME_HOST := "127.0.0.1"
const DEFAULT_GAME_PORT := 7000
const MAX_ROOM_PLAYERS := 32
const NETWORK_TICK_RATE := 15
const SERVER_PORT_ENV := "QBO_GAME_PORT"

const PLAYER_WALK_SPEED := 3.4
const PLAYER_RUN_SPEED := 6.2
const PLAYER_JUMP_VELOCITY := 4.4
const PLAYER_HEIGHT := 1.78

## Giới hạn an toàn phía server cho anti-cheat di chuyển.
const SERVER_POSITION_TOLERANCE := 0.75
const SERVER_SPEED_MULTIPLIER := 1.6

enum Mode { SOLO, DEDICATED_SERVER, CLIENT }

var api_url := DEFAULT_API_URL
var game_host := DEFAULT_GAME_HOST
var game_port := DEFAULT_GAME_PORT
var game_secret := ""
var allow_unverified_tickets := false
var is_mobile := false
var is_dedicated := false
var launch_args: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.get_name() in ["Android", "iOS"]
	launch_args = OS.get_cmdline_user_args()
	_read_environment()
	_parse_args()
	_register_input_actions()


func _read_environment() -> void:
	var env_api := OS.get_environment("QBO_API_URL")
	if env_api != "":
		api_url = env_api.rstrip("/")
	var env_host := OS.get_environment("QBO_GAME_HOST")
	if env_host != "":
		game_host = env_host
	var env_port := OS.get_environment(SERVER_PORT_ENV)
	if env_port != "" and env_port.is_valid_int():
		game_port = int(env_port)
	game_secret = OS.get_environment("QBO_GAME_SECRET")
	allow_unverified_tickets = OS.get_environment("QBO_ALLOW_UNVERIFIED_TICKETS") == "1"


func _parse_args() -> void:
	for arg in launch_args:
		if arg == "--server":
			is_dedicated = true
		elif arg.begins_with("--port="):
			var value := arg.split("=")[1]
			if value.is_valid_int():
				game_port = int(value)
		elif arg.begins_with("--host="):
			game_host = arg.split("=")[1]
		elif arg.begins_with("--api="):
			api_url = arg.split("=")[1].rstrip("/")
		elif arg == "--allow-unverified-tickets":
			allow_unverified_tickets = true


func _register_input_actions() -> void:
	_add_key_action("move_forward", [KEY_W, KEY_UP])
	_add_key_action("move_back", [KEY_S, KEY_DOWN])
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("sprint", [KEY_SHIFT])
	_add_key_action("jump", [KEY_SPACE])
	_add_key_action("interact", [KEY_E])
	_add_key_action("toggle_camera", [KEY_V])
	_add_key_action("chat", [KEY_ENTER])
	_add_key_action("menu", [KEY_ESCAPE])
	_add_key_action("quick_menu", [KEY_TAB])
	_add_key_action("emote", [KEY_F])
	_add_key_action("dance", [KEY_R])
	_add_key_action("toggle_lighting_hint", [KEY_L])


func _add_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func endpoint() -> String:
	return "http://%s:%d" % [game_host, game_port]


func suggested_graphics_preset() -> String:
	if not is_mobile:
		return "high"
	var cores := OS.get_processor_count()
	var model := OS.get_model_name().to_lower()
	if cores <= 4 or "low" in model:
		return "low"
	return "medium"
