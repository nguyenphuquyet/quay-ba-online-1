extends Node
## Net — lớp multiplayer ENet với dedicated server có thẩm quyền.
##
## Mô hình:
##  - SOLO: chơi một mình, không mở cổng mạng (dùng cho offline/demo).
##  - DEDICATED_SERVER: tiến trình Godot headless (game -- --server).
##  - CLIENT: kết nối tới dedicated server bằng game ticket do Next.js cấp.
##
## Server KHÔNG tin dữ liệu client: kiểm tra tốc độ/vị trí, quyền DJ/đèn/TV,
## khoảng cách tương tác và giới hạn người chơi. Client gửi trạng thái ~15Hz.

signal server_started(port: int)
signal join_succeeded(room: Dictionary)
signal join_failed(reason: String)
signal connection_lost(reason: String)
signal reconnecting(attempt: int)
signal reconnect_failed(reason: String)
signal roster_changed(roster: Array)
signal player_joined(id: int, info: Dictionary)
signal player_left(id: int)
signal player_state_received(id: int, state: Dictionary)
signal correction_received(position: Vector3)
signal chat_received(id: int, name: String, text: String)
signal system_message(text: String)
signal interaction_received(id: int, target: String, action: String, payload: Dictionary)
signal lighting_received(state: Dictionary)
signal dj_received(action: String, payload: Dictionary)
signal tv_received(state: Dictionary)
signal room_settings_received(settings: Dictionary)
signal kicked(reason: String)
signal room_closed(reason: String)
signal local_player_ready(spawn: Dictionary)

var mode: int = AppConfig.Mode.SOLO
var peer: ENetMultiplayerPeer = null
var players: Dictionary = {}
var roster: Array = []
var room: Dictionary = {}
var room_settings: Dictionary = {
	"dj_locked": false,
	"lighting_locked": false,
	"tv_locked": false,
	"dj_allowed": [],
	"lighting_allowed": [],
	"tv_allowed": [],
}
var lighting_state: Dictionary = {}
var dj_state: Dictionary = {}
var tv_state: Dictionary = {}
var local_peer_id := 1
var owner_id := -1
var max_players := 32
var server_port := 7000
var server_world: Node3D = null

var _last_states: Dictionary = {}
var _last_state_at: Dictionary = {}
var _chat_buckets: Dictionary = {}
var _ticket := ""
var _endpoint_host := ""
var _endpoint_port := 0
var _reconnecting := false
var _reconnect_attempts := 0
var _joined := false
var _shutting_down := false

## Chờ chủ phòng kết nối lại trước khi đóng phòng (mạng lag / rớt tạm thời).
const OWNER_GRACE_MS := 30_000
const MAX_RECONNECT_ATTEMPTS := 5
const PING_INTERVAL := 3.0
const PING_TIMEOUT := 12.0

## user_id -> { info, expires } để khôi phục người chơi khi họ kết nối lại.
var _away: Dictionary = {}
var _owner_user_id := ""
var _owner_deadline_ms := 0
var _closing := false
var _ping_timer := 0.0
var _last_pong_ms := 0
## Đã bị kick / phòng đóng -> không tự reconnect.
var _room_ended := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if mode == AppConfig.Mode.DEDICATED_SERVER:
		if _owner_deadline_ms > 0 and Time.get_ticks_msec() >= _owner_deadline_ms:
			_owner_deadline_ms = 0
			_close_room("Chủ phòng đã rời phòng. Phòng đã đóng.")
		return
	if mode != AppConfig.Mode.CLIENT or not _joined or _reconnecting:
		return
	_ping_timer -= delta
	if _ping_timer <= 0.0:
		_ping_timer = PING_INTERVAL
		rpc_id(1, "srv_ping", Time.get_ticks_msec())
	if _last_pong_ms > 0 and Time.get_ticks_msec() - _last_pong_ms > int(PING_TIMEOUT * 1000.0):
		_last_pong_ms = 0
		_handle_connection_lost("Mạng không phản hồi — đang kết nối lại.")


func is_server() -> bool:
	return mode == AppConfig.Mode.DEDICATED_SERVER


func is_client() -> bool:
	return mode == AppConfig.Mode.CLIENT


func is_online() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ------------------------------------------------------------------ solo

func start_solo(room_info: Dictionary) -> void:
	_teardown_peer()
	mode = AppConfig.Mode.SOLO
	room = room_info.duplicate(true)
	owner_id = 1
	local_peer_id = 1
	_joined = true
	players.clear()
	players[1] = _make_player_info(1, GameState.display_name(), GameState.avatar_url())
	players[1]["is_owner"] = true
	_rebuild_roster()
	local_player_ready.emit(players[1])


# ------------------------------------------------------------------ dedicated server

func start_server(port: int, capacity := 32) -> bool:
	_teardown_peer()
	server_port = port
	max_players = clampi(capacity, 1, 64)
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(server_port, max_players)
	if err != OK:
		AppConfig.is_dedicated = false
		mode = AppConfig.Mode.SOLO
		push_error("Không mở được cổng %d: %s" % [server_port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	mode = AppConfig.Mode.DEDICATED_SERVER
	owner_id = -1
	_joined = true
	server_started.emit(server_port)
	print("[QBO] Dedicated server lắng nghe cổng %d (tối đa %d người)" % [server_port, max_players])
	return true


# ------------------------------------------------------------------ client

func connect_to_room(host: String, port: int, ticket: String) -> bool:
	_teardown_peer()
	mode = AppConfig.Mode.CLIENT
	_endpoint_host = host
	_endpoint_port = port
	_ticket = ticket
	if not _reconnecting:
		_reconnect_attempts = 0
		if not GameState.room.is_empty():
			room = GameState.room.duplicate(true)
	_room_ended = false
	_joined = false
	_last_pong_ms = 0
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		join_failed.emit("Không tạo được kết nối tới %s:%d (%s)." % [host, port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	return true


func _on_connected_to_server() -> void:
	_joined = false
	local_peer_id = multiplayer.get_unique_id()
	rpc_id(1, "srv_join", _ticket, GameState.display_name(), GameState.avatar_url())


func _on_connection_failed() -> void:
	if _reconnecting:
		return
	join_failed.emit("Không kết nối được game server %s:%d." % [_endpoint_host, _endpoint_port])
	_teardown_peer()


func _on_server_disconnected() -> void:
	_handle_connection_lost("Mất kết nối tới game server.")


func _handle_connection_lost(reason: String) -> void:
	if _shutting_down or _room_ended or mode != AppConfig.Mode.CLIENT or _reconnecting:
		return
	_joined = false
	_last_pong_ms = 0
	connection_lost.emit(reason)
	_attempt_reconnect()


func _attempt_reconnect() -> void:
	if _reconnecting or mode != AppConfig.Mode.CLIENT or _endpoint_host == "":
		return
	_reconnecting = true
	var ticket := _ticket
	var code := str(room.get("code", ""))
	if code == "":
		code = str(GameState.room.get("code", ""))
	var last_error := ""
	for attempt in range(1, MAX_RECONNECT_ATTEMPTS + 1):
		_reconnect_attempts = attempt
		reconnecting.emit(attempt)
		await get_tree().create_timer(2.0 + float(attempt - 1) * 1.5).timeout
		if mode != AppConfig.Mode.CLIENT:
			break
		if code != "":
			var res := await Api.request_game_ticket(code)
			if res["ok"] and res["data"] is Dictionary and res["data"].has("ticket"):
				ticket = str(res["data"]["ticket"])
			else:
				last_error = str(res.get("error", ""))
		if ticket == "":
			continue
		connect_to_room(_endpoint_host, _endpoint_port, ticket)
		if await _wait_for_welcome(8.0):
			_reconnecting = false
			_reconnect_attempts = 0
			_last_pong_ms = Time.get_ticks_msec()
			system_message.emit("Đã kết nối lại phòng.")
			return
	_reconnecting = false
	_reconnect_attempts = 0
	if last_error != "":
		reconnect_failed.emit("Không thể kết nối lại (%s). Vui lòng vào lại phòng." % last_error)
	else:
		reconnect_failed.emit("Không thể kết nối lại. Vui lòng vào lại phòng.")


func _wait_for_welcome(timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _joined:
			return true
		await get_tree().process_frame
	return false


# ------------------------------------------------------------------ server handshake

@rpc("any_peer", "call_remote", "reliable")
func srv_join(ticket: String, display_name: String, avatar := "") -> void:
	if not is_server() or _closing:
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		return
	if players.size() >= max_players:
		rpc_id(sender, "cli_kicked", "Phòng đã đầy.")
		return
	var verified := await _verify_ticket(ticket)
	if not verified["ok"]:
		rpc_id(sender, "cli_kicked", verified.get("error", "Vé vào game không hợp lệ."))
		return
	var ticket_room: Dictionary = verified.get("room", {}) if verified.get("room") is Dictionary else {}
	var code := str(ticket_room.get("code", ""))
	# Một tiến trình server chỉ phục vụ một phòng tại một thời điểm.
	if not room.is_empty() and code != "" and str(room.get("code", "")) != "" and code != str(room.get("code", "")):
		rpc_id(sender, "cli_kicked", "Server đang phục vụ phòng khác. Vui lòng thử lại sau.")
		return
	if room.is_empty() and not ticket_room.is_empty():
		room = ticket_room
	var user_id := str(verified.get("user_id", ""))
	var info := _make_player_info(sender, display_name, avatar)
	info["user_id"] = user_id
	# Khôi phục vị trí/trạng thái nếu người chơi quay lại trong thời gian chờ.
	var restored: Dictionary = _away.get(user_id, {})
	var resumed := false
	if user_id != "" and not restored.is_empty() and int(restored.get("expires", 0)) > Time.get_ticks_msec():
		var old_info: Dictionary = restored.get("info", {})
		for key in ["position", "yaw", "animation", "flags", "style"]:
			if old_info.has(key):
				info[key] = old_info[key]
		resumed = true
	_away.erase(user_id)
	info["is_owner"] = bool(verified.get("is_owner", false))
	if info["is_owner"]:
		owner_id = sender
		_owner_user_id = user_id
		_owner_deadline_ms = 0
	elif owner_id == -1 and _owner_user_id == "":
		# Fallback cho server test không xác minh ticket.
		owner_id = sender
		_owner_user_id = user_id
		info["is_owner"] = true
	players[sender] = info
	_last_states[sender] = info.get("position", Vector3.ZERO)
	_last_state_at[sender] = Time.get_ticks_msec()
	_rebuild_roster()
	rpc_id(sender, "cli_welcome", players, room_settings, owner_id, lighting_state, dj_state, tv_state, info)
	for id in players.keys():
		if int(id) != sender:
			rpc_id(int(id), "cli_player_joined", sender, info)
	if resumed:
		_broadcast_all("cli_system_message", ["%s đã kết nối lại." % str(info.get("name", "Người chơi"))])
	print("[QBO] %s (#%d) vào phòng %s" % [display_name, sender, room.get("code", "?")])
	_broadcast_except(sender, "cli_roster", [roster])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_ping(stamp: int) -> void:
	if not is_server():
		return
	rpc_id(multiplayer.get_remote_sender_id(), "cli_pong", stamp)


@rpc("authority", "call_remote", "unreliable_ordered")
func cli_pong(_stamp: int) -> void:
	_last_pong_ms = Time.get_ticks_msec()


@rpc("any_peer", "call_remote", "reliable")
func srv_owner_leaving() -> void:
	if not is_server():
		return
	if multiplayer.get_remote_sender_id() != owner_id:
		return
	_close_room("Chủ phòng đã đóng phòng.")


func _verify_ticket(ticket: String) -> Dictionary:
	if ticket == "":
		return {"ok": false, "error": "Thiếu game ticket."}
	if AppConfig.game_secret == "":
		if AppConfig.allow_unverified_tickets:
			return {"ok": true, "user_id": "dev", "is_owner": owner_id == -1}
		return {"ok": false, "error": "Game server chưa cấu hình QBO_GAME_SECRET để xác minh ticket."}
	var res := await Api.verify_game_ticket(ticket)
	if not res["ok"] or not (res["data"] is Dictionary):
		return {"ok": false, "error": "Game ticket không hợp lệ hoặc đã hết hạn."}
	var data: Dictionary = res["data"]
	return {
		"ok": true,
		"user_id": str(data.get("userId", "")),
		"is_owner": bool(data.get("isOwner", false)),
		"room": data.get("room", {}),
	}


@rpc("authority", "call_remote", "reliable")
func cli_welcome(roster_in: Dictionary, settings_in: Dictionary, owner: int, lighting: Dictionary, dj: Dictionary, tv: Dictionary, me: Dictionary) -> void:
	players = roster_in.duplicate(true)
	room_settings = settings_in.duplicate(true)
	owner_id = owner
	lighting_state = lighting.duplicate(true)
	dj_state = dj.duplicate(true)
	tv_state = tv.duplicate(true)
	_joined = true
	_rebuild_roster()
	_last_pong_ms = Time.get_ticks_msec()
	_ping_timer = 0.0
	join_succeeded.emit(room)
	local_player_ready.emit(me)
	if not lighting_state.is_empty():
		lighting_received.emit(lighting_state)
	if not tv_state.is_empty():
		tv_received.emit(tv_state)
	if not dj_state.is_empty():
		dj_received.emit("sync", dj_state)
	room_settings_received.emit(room_settings)


@rpc("authority", "call_remote", "reliable")
func cli_kicked(reason: String) -> void:
	_room_ended = true
	kicked.emit(reason)
	_teardown_peer()


@rpc("authority", "call_remote", "reliable")
func cli_room_closed(reason: String) -> void:
	_room_ended = true
	room_closed.emit(reason)
	_teardown_peer()


@rpc("authority", "call_remote", "reliable")
func cli_player_joined(id: int, info: Dictionary) -> void:
	players[id] = info
	_rebuild_roster()
	player_joined.emit(id, info)


@rpc("authority", "call_remote", "reliable")
func cli_player_left(id: int) -> void:
	players.erase(id)
	_rebuild_roster()
	player_left.emit(id)


@rpc("authority", "call_remote", "reliable")
func cli_roster(value: Array) -> void:
	roster = value
	roster_changed.emit(roster)


# ------------------------------------------------------------------ player state

func send_player_state(position: Vector3, yaw: float, animation: String, flags := 0) -> void:
	if not is_online() or (mode != AppConfig.Mode.CLIENT and mode != AppConfig.Mode.DEDICATED_SERVER):
		return
	rpc_id(1, "srv_player_state", position, yaw, animation, flags)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func srv_player_state(position: Vector3, yaw: float, animation: String, flags: int) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var now := Time.get_ticks_msec()
	var last_at := int(_last_state_at.get(sender, now))
	var dt := clampf(float(now - last_at) / 1000.0, 0.02, 0.6)
	_last_state_at[sender] = now
	var last_pos: Vector3 = _last_states.get(sender, position)
	var max_distance := AppConfig.PLAYER_RUN_SPEED * dt * AppConfig.SERVER_SPEED_MULTIPLIER + AppConfig.SERVER_POSITION_TOLERANCE
	if last_pos.distance_to(position) > max_distance:
		rpc_id(sender, "cli_correction", last_pos)
		return
	if position.y < -20.0 or position.y > 60.0:
		rpc_id(sender, "cli_correction", last_pos)
		return
	_last_states[sender] = position
	var info: Dictionary = players[sender]
	info["position"] = position
	info["yaw"] = yaw
	info["animation"] = animation
	info["flags"] = flags
	players[sender] = info
	_broadcast_except(sender, "cli_player_state", [sender, position, yaw, animation, flags])


@rpc("authority", "call_remote", "unreliable_ordered")
func cli_player_state(id: int, position: Vector3, yaw: float, animation: String, flags: int) -> void:
	player_state_received.emit(id, {"position": position, "yaw": yaw, "animation": animation, "flags": flags})


@rpc("authority", "call_remote", "reliable")
func cli_correction(position: Vector3) -> void:
	correction_received.emit(position)


# ------------------------------------------------------------------ chat

func send_chat(text: String) -> void:
	if text.strip_edges() == "":
		return
	if mode == AppConfig.Mode.SOLO:
		chat_received.emit(1, GameState.display_name(), text.strip_edges().left(240))
		return
	if not is_online():
		return
	rpc_id(1, "srv_chat", text.strip_edges().left(240))


@rpc("any_peer", "call_remote", "reliable")
func srv_chat(text: String) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	if not _allow_chat(sender):
		rpc_id(sender, "cli_system_message", "Bạn gửi tin nhắn quá nhanh, thử lại sau.")
		return
	var clean := text.strip_edges().left(240)
	if clean == "":
		return
	_broadcast_all("cli_chat", [sender, str(players[sender].get("name", "?")), clean])


func _allow_chat(peer_id: int) -> bool:
	var now := Time.get_ticks_msec()
	var bucket: Array = _chat_buckets.get(peer_id, [])
	var kept: Array = []
	for stamp in bucket:
		if now - int(stamp) < 5000:
			kept.append(stamp)
	kept.append(now)
	_chat_buckets[peer_id] = kept
	return kept.size() <= 8


@rpc("authority", "call_remote", "reliable")
func cli_chat(id: int, display: String, text: String) -> void:
	chat_received.emit(id, display, text)


@rpc("authority", "call_remote", "reliable")
func cli_system_message(text: String) -> void:
	system_message.emit(text)


# ------------------------------------------------------------------ permissions

func is_owner(peer_id := -1) -> bool:
	var id := local_peer_id if peer_id == -1 else peer_id
	if mode == AppConfig.Mode.SOLO:
		return true
	return id == owner_id


func can_control(permission: String, peer_id := -1) -> bool:
	var id := local_peer_id if peer_id == -1 else peer_id
	if mode == AppConfig.Mode.SOLO:
		return true
	if is_owner(id):
		return true
	if bool(room_settings.get(permission + "_locked", false)):
		return false
	var list: Array = room_settings.get(permission + "_allowed", [])
	return list.has(id)


func grant_permission(permission: String, peer_id: int) -> void:
	if not is_server() or not is_owner(peer_id_of_self()):
		return
	var list: Array = room_settings.get(permission + "_allowed", [])
	if not list.has(peer_id):
		list.append(peer_id)
	room_settings[permission + "_allowed"] = list
	_apply_room_settings()


func peer_id_of_self() -> int:
	if is_server():
		return owner_id
	return local_peer_id


func revoke_permission(permission: String, peer_id: int) -> void:
	if not is_server() or not is_owner(peer_id_of_self()):
		return
	var list: Array = room_settings.get(permission + "_allowed", [])
	list.erase(peer_id)
	room_settings[permission + "_allowed"] = list
	_apply_room_settings()


# ------------------------------------------------------------------ interactions

func request_interaction(target: String, action: String, payload := {}) -> void:
	if mode == AppConfig.Mode.SOLO:
		interaction_received.emit(1, target, action, payload)
		return
	if not is_online():
		return
	rpc_id(1, "srv_interact", target, action, payload)


@rpc("any_peer", "call_remote", "reliable")
func srv_interact(target: String, action: String, payload: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	var allowed_actions := ["seat", "stand", "door", "elevator", "bar", "computer_open", "tv_control", "speaker", "use"]
	if not allowed_actions.has(action):
		if not can_control(_permission_for(action), sender):
			rpc_id(sender, "cli_system_message", "Bạn không có quyền điều khiển thiết bị này. Chủ phòng có thể cấp quyền.")
			return
	# Dịch chuyển do server cho phép (ghế/thang máy) phải cập nhật vị trí chuẩn,
	# nếu không anti-cheat sẽ kéo người chơi về chỗ cũ.
	if action in ["seat", "elevator"] and payload is Dictionary:
		var destination = payload.get("destination", payload.get("seat", null))
		if destination is Vector3:
			_last_states[sender] = destination
	_broadcast_all("cli_interaction", [sender, target, action, payload])
	# Giữ trạng thái TV/DJ/đèn để người vào sau đồng bộ đúng.
	if action == "tv_state" and payload is Dictionary:
		tv_state = payload.duplicate(true)
	elif action == "dj_state" and payload is Dictionary:
		dj_state = payload.duplicate(true)


func _permission_for(action: String) -> String:
	if action.begins_with("dj"):
		return "dj"
	if action.begins_with("light"):
		return "lighting"
	if action.begins_with("tv"):
		return "tv"
	return "none"


@rpc("authority", "call_remote", "reliable")
func cli_interaction(id: int, target: String, action: String, payload: Dictionary) -> void:
	interaction_received.emit(id, target, action, payload)


# ------------------------------------------------------------------ lighting / dj / tv

func send_lighting(state: Dictionary) -> void:
	if mode == AppConfig.Mode.SOLO:
		lighting_received.emit(state)
		lighting_state = state.duplicate(true)
		return
	if not is_online():
		return
	rpc_id(1, "srv_lighting", state)


@rpc("any_peer", "call_remote", "reliable")
func srv_lighting(state: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender) or not can_control("lighting", sender):
		rpc_id(sender, "cli_system_message", "Bạn không có quyền điều khiển ánh sáng.")
		return
	if not _sanitize_lighting(state):
		return
	lighting_state = state.duplicate(true)
	_broadcast_all("cli_lighting", [state])


func _sanitize_lighting(state: Dictionary) -> bool:
	var preset := str(state.get("preset", ""))
	if preset == "":
		return false
	var allowed := ["chill", "lounge", "party", "edm", "cyberpunk", "chinese_neon", "vip", "blackout"]
	if not allowed.has(preset):
		return false
	if state.has("intensity") and (float(state["intensity"]) < 0.0 or float(state["intensity"]) > 4.0):
		return false
	return true


@rpc("authority", "call_remote", "reliable")
func cli_lighting(state: Dictionary) -> void:
	lighting_state = state.duplicate(true)
	lighting_received.emit(state)


func send_dj(action: String, payload: Dictionary) -> void:
	if mode == AppConfig.Mode.SOLO:
		dj_received.emit(action, payload)
		return
	if not is_online():
		return
	rpc_id(1, "srv_dj", action, payload)


@rpc("any_peer", "call_remote", "reliable")
func srv_dj(action: String, payload: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	if not can_control("dj", sender):
		rpc_id(sender, "cli_system_message", "Bạn chưa được cấp quyền DJ.")
		return
	var allowed := ["play", "pause", "resume", "next", "prev", "volume", "seek", "load", "sync"]
	if not allowed.has(action):
		return
	if action == "load":
		var url := str(payload.get("url", ""))
		if not _valid_media_url(url):
			rpc_id(sender, "cli_system_message", "URL nhạc không hợp lệ (chỉ http/https).")
			return
	dj_state = payload.duplicate(true)
	dj_state["action"] = action
	_broadcast_all("cli_dj", [action, payload])


func _valid_media_url(url: String) -> bool:
	if url == "" or url.length() > 500:
		return false
	return url.begins_with("http://") or url.begins_with("https://")


@rpc("authority", "call_remote", "reliable")
func cli_dj(action: String, payload: Dictionary) -> void:
	dj_received.emit(action, payload)


func send_tv(state: Dictionary) -> void:
	if mode == AppConfig.Mode.SOLO:
		tv_state = state.duplicate(true)
		tv_received.emit(state)
		return
	if not is_online():
		return
	rpc_id(1, "srv_tv", state)


@rpc("any_peer", "call_remote", "reliable")
func srv_tv(state: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender) or not can_control("tv", sender):
		rpc_id(sender, "cli_system_message", "Bạn không có quyền điều khiển màn hình TV.")
		return
	tv_state = state.duplicate(true)
	_broadcast_all("cli_tv", [state])


@rpc("authority", "call_remote", "reliable")
func cli_tv(state: Dictionary) -> void:
	tv_state = state.duplicate(true)
	tv_received.emit(state)


# ------------------------------------------------------------------ room settings

func set_room_setting(key: String, value: Variant) -> void:
	if mode == AppConfig.Mode.SOLO:
		room_settings[key] = value
		room_settings_received.emit(room_settings)
		return
	if not is_online():
		return
	rpc_id(1, "srv_room_settings", {key: value})


@rpc("any_peer", "call_remote", "reliable")
func srv_room_settings(patch: Dictionary) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not is_owner(sender):
		rpc_id(sender, "cli_system_message", "Chỉ chủ phòng mới có thể đổi cài đặt phòng.")
		return
	for key in patch.keys():
		if key in ["dj_locked", "lighting_locked", "tv_locked"]:
			room_settings[key] = bool(patch[key])
		elif key == "dj_allowed" or key == "lighting_allowed" or key == "tv_allowed":
			if patch[key] is Array:
				room_settings[key] = patch[key]
	_apply_room_settings()


func _apply_room_settings() -> void:
	_broadcast_all("cli_room_settings", [room_settings])
	room_settings_received.emit(room_settings)


@rpc("authority", "call_remote", "reliable")
func cli_room_settings(settings_in: Dictionary) -> void:
	room_settings = settings_in.duplicate(true)
	room_settings_received.emit(room_settings)


func kick_peer(peer_id: int) -> void:
	if not is_server() or not is_owner(peer_id_of_self()) or not players.has(peer_id):
		return
	rpc_id(peer_id, "cli_kicked", "Bạn đã bị chủ phòng mời ra khỏi phòng.")
	if peer != null:
		peer.disconnect_peer(peer_id)


## Client báo server biết chủ phòng chủ động rời (đóng phòng ngay, không chờ grace).
func notify_owner_leaving() -> void:
	if mode == AppConfig.Mode.CLIENT and is_owner() and multiplayer.has_multiplayer_peer():
		rpc_id(1, "srv_owner_leaving")


# ------------------------------------------------------------------ peer lifecycle

func _on_peer_connected(id: int) -> void:
	if not is_server():
		return
	print("[QBO] Peer %d đã kết nối, chờ xác minh ticket." % id)


func _on_peer_disconnected(id: int) -> void:
	if not is_server() or not players.has(id):
		return
	var info: Dictionary = players[id]
	var user_id := str(info.get("user_id", ""))
	players.erase(id)
	_last_states.erase(id)
	_last_state_at.erase(id)
	_chat_buckets.erase(id)
	# Giữ trạng thái để khôi phục nếu người chơi kết nối lại trong thời gian chờ.
	if user_id != "":
		_away[user_id] = {
			"info": info.duplicate(true),
			"expires": Time.get_ticks_msec() + OWNER_GRACE_MS,
		}
	var was_owner := id == owner_id
	if was_owner:
		owner_id = -1
		_owner_deadline_ms = Time.get_ticks_msec() + OWNER_GRACE_MS
		_broadcast_all("cli_system_message", ["Chủ phòng mất kết nối — đang chờ kết nối lại..."])
	_rebuild_roster()
	_broadcast_all("cli_player_left", [id])
	print("[QBO] %s rời phòng." % str(info.get("name", "?")))
	if players.is_empty() and not was_owner:
		_close_room("Phòng không còn người chơi.")


## Đóng phòng: báo client, báo backend, ngắt kết nối và reset để nhận phòng mới.
func _close_room(reason: String) -> void:
	if _closing:
		return
	_closing = true
	_owner_deadline_ms = 0
	var code := str(room.get("code", ""))
	if code != "" and AppConfig.game_secret != "":
		Api.close_game_room(code)
	_broadcast_all("cli_room_closed", [reason])
	await get_tree().create_timer(0.5).timeout
	if peer != null:
		for id in multiplayer.get_peers():
			peer.disconnect_peer(int(id))
	_reset_room_state()


func _reset_room_state() -> void:
	players.clear()
	roster.clear()
	_last_states.clear()
	_last_state_at.clear()
	_chat_buckets.clear()
	_away.clear()
	room.clear()
	owner_id = -1
	_owner_user_id = ""
	_owner_deadline_ms = 0
	lighting_state.clear()
	dj_state.clear()
	tv_state.clear()
	_closing = false
	roster_changed.emit(roster)
	print("[QBO] Phòng đã đóng, server sẵn sàng nhận phòng mới.")


func _make_player_info(id: int, display_name: String, avatar: String) -> Dictionary:
	return {
		"id": id,
		"name": display_name.strip_edges().left(32) if display_name != "" else "Người chơi",
		"avatar": avatar,
		"position": Vector3(0, 1.2, 22),
		"yaw": 0.0,
		"animation": "idle",
		"flags": 0,
		"style": SettingsManager.character_style,
		"is_owner": false,
	}


func _rebuild_roster() -> void:
	roster = []
	for id in players.keys():
		roster.append(players[id])
	roster.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	if mode != AppConfig.Mode.SOLO:
		roster_changed.emit(roster)


func _broadcast_all(method: String, args: Array) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	for id in multiplayer.get_peers():
		_rpc_peer(int(id), method, args)


func _rpc_peer(id: int, method: String, args: Array) -> void:
	match method:
		"cli_chat":
			rpc_id(id, "cli_chat", args[0], args[1], args[2])
		"cli_interaction":
			rpc_id(id, "cli_interaction", args[0], args[1], args[2], args[3])
		"cli_lighting":
			rpc_id(id, "cli_lighting", args[0])
		"cli_dj":
			rpc_id(id, "cli_dj", args[0], args[1])
		"cli_tv":
			rpc_id(id, "cli_tv", args[0])
		"cli_roster":
			rpc_id(id, "cli_roster", args[0])
		"cli_system_message":
			rpc_id(id, "cli_system_message", args[0])
		"cli_player_joined":
			rpc_id(id, "cli_player_joined", args[0], args[1])
		"cli_player_left":
			rpc_id(id, "cli_player_left", args[0])
		"cli_kicked":
			rpc_id(id, "cli_kicked", args[0])
		"cli_room_closed":
			rpc_id(id, "cli_room_closed", args[0])
		"cli_room_settings":
			rpc_id(id, "cli_room_settings", args[0])
		"cli_player_state":
			rpc_id(id, "cli_player_state", args[0], args[1], args[2], args[3], args[4])
		_:
			pass


func _broadcast_except(except_id: int, method: String, args: Array) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	for id in multiplayer.get_peers():
		if int(id) == except_id:
			continue
		_rpc_peer(int(id), method, args)


func send_system(text: String) -> void:
	if mode == AppConfig.Mode.SOLO:
		system_message.emit(text)
		return
	if is_server():
		_broadcast_all("cli_system_message", [text])


func _teardown_peer() -> void:
	_shutting_down = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	peer = null
	_shutting_down = false
	_joined = false


func stop() -> void:
	_teardown_peer()
	mode = AppConfig.Mode.SOLO
	players.clear()
	roster.clear()
	room.clear()
	owner_id = -1
	lighting_state.clear()
	dj_state.clear()
	tv_state.clear()
	_last_states.clear()
	_last_state_at.clear()
	_chat_buckets.clear()
	_away.clear()
	_owner_user_id = ""
	_owner_deadline_ms = 0
	_closing = false
	_reconnecting = false
	_reconnect_attempts = 0
	_room_ended = false
	_ping_timer = 0.0
	_last_pong_ms = 0
	_endpoint_host = ""
	_endpoint_port = 0
	_ticket = ""
