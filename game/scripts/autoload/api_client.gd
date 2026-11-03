extends Node
## ApiClient — cầu nối HTTP tới backend Next.js.
## Mọi hàm trả về Dictionary: { ok: bool, status: int, data: Variant, error: String }
## Token được refresh một lần khi gặp 401 (refresh token rotation).

var _refreshing := false


func _headers(auth: bool) -> PackedStringArray:
	var headers := PackedStringArray([
		"Accept: application/json",
		"Content-Type: application/json",
		"User-Agent: QuayBarOnline/%s (%s)" % [AppConfig.APP_VERSION, OS.get_name()],
	])
	if auth and GameState.access_token != "":
		headers.append("Authorization: Bearer " + GameState.access_token)
	return headers


func _send(method: String, path: String, body: Variant = null, auth := true, timeout := 15.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var payload := ""
	if body != null:
		payload = JSON.stringify(body)
	var err := http.request(AppConfig.api_url + path, _headers(auth), _http_method(method), payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": null, "error": "Không kết nối được backend (%s)." % error_string(err)}
	var response: Array = await http.request_completed
	http.queue_free()
	var result: int = response[0]
	var code: int = response[1]
	var raw: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": null, "error": "Lỗi mạng: %s." % _result_name(result)}
	var text := raw.get_string_from_utf8()
	var data: Variant = null
	if text.strip_edges() != "":
		data = JSON.parse_string(text)
	if code >= 200 and code < 300:
		return {"ok": true, "status": code, "data": data, "error": ""}
	var message := "Yêu cầu thất bại (%d)." % code
	if data is Dictionary:
		var body_dict: Dictionary = data
		if body_dict.get("error") is Dictionary:
			var inner: Dictionary = body_dict["error"]
			if inner.has("message"):
				message = str(inner["message"])
		elif body_dict.has("message"):
			message = str(body_dict["message"])
	return {"ok": false, "status": code, "data": data, "error": message}


func _http_method(method: String) -> HTTPClient.Method:
	match method.to_upper():
		"POST":
			return HTTPClient.METHOD_POST
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET


func _result_name(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return "không thể kết nối"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "không phân giải được tên miền"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "kết nối bị đóng"
		HTTPRequest.RESULT_TIMEOUT:
			return "quá thời gian chờ"
		_:
			return "mã %d" % result


func request(method: String, path: String, body: Variant = null, auth := true, timeout := 15.0) -> Dictionary:
	var res := await _send(method, path, body, auth, timeout)
	if res["status"] == 401 and auth and GameState.refresh_token != "":
		var refreshed := await refresh_session()
		if refreshed:
			res = await _send(method, path, body, auth, timeout)
	return res


# ---------------------------------------------------------------- auth

func register(username: String, email: String, password: String, display_name: String) -> Dictionary:
	var res := await request("POST", "/api/auth/register", {
		"username": username, "email": email, "password": password, "displayName": display_name,
	}, false)
	if res["ok"] and res["data"] is Dictionary:
		GameState.set_session(res["data"])
	return res


func login(identifier: String, password: String) -> Dictionary:
	var res := await request("POST", "/api/auth/login", {"identifier": identifier, "password": password}, false)
	if res["ok"] and res["data"] is Dictionary:
		GameState.set_session(res["data"])
	return res


func refresh_session() -> bool:
	if _refreshing:
		return false
	_refreshing = true
	var res := await _send("POST", "/api/auth/refresh", {"refreshToken": GameState.refresh_token}, false)
	_refreshing = false
	if res["ok"] and res["data"] is Dictionary:
		var data: Dictionary = res["data"]
		if data.has("accessToken"):
			GameState.set_session(data)
			return true
	GameState.clear_session()
	return false


func logout() -> Dictionary:
	var res := await request("POST", "/api/auth/logout", {}, true)
	GameState.clear_session()
	return res


func me() -> Dictionary:
	var res := await request("GET", "/api/users/me")
	if res["ok"] and res["data"] is Dictionary:
		var data: Dictionary = res["data"]
		if data.has("user") and data["user"] is Dictionary:
			GameState.set_user(data["user"])
		elif data.has("id"):
			GameState.set_user(data)
	return res


func update_profile(payload: Dictionary) -> Dictionary:
	var res := await request("PATCH", "/api/users/me", payload)
	if res["ok"] and res["data"] is Dictionary:
		var data: Dictionary = res["data"]
		if data.has("user") and data["user"] is Dictionary:
			GameState.set_user(data["user"])
	return res


func profile(id: String) -> Dictionary:
	return await request("GET", "/api/users/%s" % id)


# ---------------------------------------------------------------- rooms

func list_rooms(query := "", visibility := "all") -> Dictionary:
	var path := "/api/rooms?search=%s&visibility=%s" % [query.uri_encode(), visibility]
	return await request("GET", path)


func create_room(payload: Dictionary) -> Dictionary:
	return await request("POST", "/api/rooms", payload)


func join_room(code: String, password := "") -> Dictionary:
	return await request("POST", "/api/rooms/%s/join" % code, {"password": password})


func leave_room(code: String) -> Dictionary:
	return await request("POST", "/api/rooms/%s/leave" % code, {})


func room_detail(code: String) -> Dictionary:
	return await request("GET", "/api/rooms/%s" % code)


func request_game_ticket(room_code: String) -> Dictionary:
	return await request("POST", "/api/game/ticket", {"roomCode": room_code})


# ---------------------------------------------------------------- friends

func list_friends() -> Dictionary:
	var res := await request("GET", "/api/friends")
	if res["ok"] and res["data"] is Dictionary and res["data"].get("friends") is Array:
		GameState.friends = res["data"]["friends"]
	return res


func friend_request(username: String) -> Dictionary:
	return await request("POST", "/api/friends/request", {"username": username})


func friend_accept(id: String) -> Dictionary:
	return await request("POST", "/api/friends/accept", {"id": id})


func friend_remove(id: String) -> Dictionary:
	return await request("DELETE", "/api/friends/%s" % id)


# ---------------------------------------------------------------- inventory & moderation

func inventory() -> Dictionary:
	return await request("GET", "/api/inventory")


func equip(item_id: String) -> Dictionary:
	return await request("POST", "/api/inventory/equip", {"itemId": item_id})


func report(target_id: String, reason: String, detail := "") -> Dictionary:
	return await request("POST", "/api/reports", {"targetId": target_id, "reason": reason, "detail": detail})


# ---------------------------------------------------------------- game server (server-side calls)

func verify_game_ticket(game_ticket: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"X-Game-Server-Secret: " + AppConfig.game_secret,
	])
	var err := http.request(AppConfig.api_url + "/api/game/ticket/verify", headers, HTTPClient.METHOD_POST, JSON.stringify({"ticket": game_ticket}))
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "data": null, "error": "backend unreachable"}
	var response: Array = await http.request_completed
	http.queue_free()
	var code: int = response[1]
	var text := (response[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else null
	return {"ok": code >= 200 and code < 300, "status": code, "data": data, "error": "" if code < 300 else "invalid ticket"}
