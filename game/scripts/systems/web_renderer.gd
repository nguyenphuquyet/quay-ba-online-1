class_name QBOWebRenderer
extends Node
## QBOWebRenderer — render web thật cho màn hình TV/LED mà không cần biên dịch
## plugin CEF/WebView2.
##
## Cách hoạt động (chỉ trên máy có Chromium/Chrome/Edge):
##   1. Khởi động trình duyệt headless với DevTools Protocol (CDP).
##   2. Kết nối WebSocket tới target "page".
##   3. Bật Page.startScreencast: Chromium gửi từng frame JPEG (base64) qua CDP.
##   4. Giải mã JPEG thành ImageTexture và đưa cho màn web ở sân khấu.
##
## Không đọc/ghi profile người dùng: mỗi phiên dùng thư mục tạm riêng, xoá khi đóng.
## Nếu máy không có trình duyệt, `available` = false và TV quay về trạng thái
## trung thực (hiển thị URL + lý do), không giả lập nội dung.

signal texture_ready(texture: Texture2D)
signal page_loaded(title: String, url: String)
signal failed(reason: String)
signal started()

const START_TIMEOUT_MS := 20000
const MAX_FRAME_WIDTH := 1600
const FRAME_QUALITY := 70
## Giải mã JPEG mỗi frame rất tốn CPU trên GPU yếu: gửi cách frame (~30 fps)
## là đủ mượt cho TV trong club.
const SCREENCAST_EVERY_NTH_FRAME := 2

## Shim chèn vào mọi trang trước khi script của trang chạy.
##
## 1. Fullscreen: YouTube gọi `requestFullscreen()`; trong Chromium headless lời
##    gọi này đổi kích thước cửa sổ và làm screencast vỡ hình. Ta thay bằng một
##    lớp CSS "cinema" cố định phần tử được yêu cầu fullscreen cho phủ kín
##    viewport 1920x1080, vẫn bắn fullscreenchange để player cập nhật nút bấm.
## 2. Âm thanh: trình duyệt headless thường coi như chưa có thao tác người dùng
##    nên một số player tự mute. Bỏ mute khi media bắt đầu phát để TV có tiếng.
const PAGE_SHIM := """
(() => {
  window.__qboTvShim = true;
  try {
  const STYLE_ID = '__qbo_tv_style';
  let fsEl = null;
  const ensureStyle = () => {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      html.qbo-tv-fs, html.qbo-tv-fs body { overflow: hidden !important; background: #000 !important; }
      .qbo-tv-fs-target {
        position: fixed !important; inset: 0 !important;
        width: 100vw !important; height: 100vh !important;
        max-width: none !important; max-height: none !important;
        margin: 0 !important; padding: 0 !important;
        z-index: 2147483647 !important; background: #000 !important;
      }
    `;
    (document.head || document.documentElement).appendChild(style);
  };
  const notify = () => {
    window.dispatchEvent(new Event('resize'));
    document.dispatchEvent(new Event('fullscreenchange'));
    document.dispatchEvent(new Event('webkitfullscreenchange'));
  };
  // Một số player (YouTube) gọi fullscreen trên <html>/<body>; khi đó phải đưa
  // đúng khối player vào toàn màn hình, nếu không video bên trong bị co về 0.
  const pick = (el) => {
    if (!el || el === document.documentElement || el === document.body) {
      return document.querySelector('#movie_player') ||
        document.querySelector('.html5-video-player') ||
        el || document.documentElement;
    }
    return el;
  };
  const enter = (raw) => {
    const el = pick(raw);
    ensureStyle();
    if (fsEl && fsEl !== el) fsEl.classList.remove('qbo-tv-fs-target');
    fsEl = el || document.documentElement;
    fsEl.classList.add('qbo-tv-fs-target');
    document.documentElement.classList.add('qbo-tv-fs');
    notify();
  };
  const exit = () => {
    if (fsEl) fsEl.classList.remove('qbo-tv-fs-target');
    fsEl = null;
    document.documentElement.classList.remove('qbo-tv-fs');
    notify();
  };
  const proto = Element.prototype;
  proto.requestFullscreen = function() { enter(this); return Promise.resolve(); };
  proto.webkitRequestFullscreen = proto.requestFullscreen;
  proto.mozRequestFullScreen = proto.requestFullscreen;
  proto.msRequestFullscreen = proto.requestFullscreen;
  HTMLVideoElement.prototype.webkitEnterFullscreen = function() { enter(this); };
  HTMLVideoElement.prototype.webkitExitFullscreen = function() { exit(); };
  document.exitFullscreen = function() { exit(); return Promise.resolve(); };
  document.webkitExitFullscreen = exit;
  document.webkitCancelFullScreen = exit;
  Object.defineProperty(document, 'fullscreenElement', { configurable: true, get: () => fsEl });
  Object.defineProperty(document, 'webkitFullscreenElement', { configurable: true, get: () => fsEl });
  Object.defineProperty(document, 'fullscreenEnabled', { configurable: true, get: () => true });
  Object.defineProperty(document, 'webkitFullscreenEnabled', { configurable: true, get: () => true });
  // TV của club luôn muốn nghe tiếng: bỏ trạng thái mute mặc định của player.
  document.addEventListener('play', (e) => {
    const el = e.target;
    if (el instanceof HTMLMediaElement && el.muted) el.muted = false;
  }, true);
  } catch (e) {
    window.__qboTvShimError = String(e && e.stack || e);
  }
})();
"""

## Trang cầu nối chạy trên loopback HTTP để iframe YouTube có Referer/Origin hợp
## lệ. Mở thẳng youtube.com/embed/... ở tab top-level khiến YouTube báo lỗi 153.
const PLAYER_HTML := """<!doctype html><html lang="vi"><head><meta charset="utf-8">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
#frame{display:block;border:0;width:100vw;height:100vh}</style></head><body>
<iframe id="frame" allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
<script>
(() => {
  const id = new URLSearchParams(location.search).get('v') || '';
  const origin = encodeURIComponent(location.origin);
  const frame = document.getElementById('frame');
  frame.src = 'https://www.youtube.com/embed/' + encodeURIComponent(id) +
    '?autoplay=1&rel=0&modestbranding=1&playsinline=1&enablejsapi=1&origin=' + origin;
})();
</script></body></html>"""

var available := false
var executable := ""
var unavailable_reason := ""
var texture: ImageTexture
var current_url := ""
var current_title := ""
var loading := false
var running := false

var _viewport_size := Vector2i(1920, 340)
var _ws: WebSocketPeer
var _pid := -1
var _port := 0
var _http_server: TCPServer
var _http_port := 0
var _http_clients: Array = []
var _profile_dir := ""
var _msg_id := 0
var _pending: Array = []
var _screencast_active := false
var _ws_open_handled := false
var _closing_reported := false
var _start_timer := 0.0
var _frame_count := 0
var _eval_tags: Dictionary = {}
var _shot_paths: Dictionary = {}


func _ready() -> void:
	name = "WebRenderer"
	set_process(false)
	_probe_browser()


func _exit_tree() -> void:
	stop_browser()


# ------------------------------------------------------------------ discovery

func _probe_browser() -> void:
	if AppConfig.is_mobile:
		unavailable_reason = "Máy di động chưa build WebView native."
		available = false
		return
	var override := OS.get_environment("QBO_BROWSER_PATH")
	if override != "" and FileAccess.file_exists(override):
		executable = override
		available = true
		return
	var candidates: Array[String] = []
	match OS.get_name():
		"Windows":
			var pf := OS.get_environment("ProgramFiles")
			var pf86 := OS.get_environment("ProgramFiles(x86)")
			var local := OS.get_environment("LOCALAPPDATA")
			candidates = [
				pf.path_join("Google/Chrome/Application/chrome.exe"),
				pf86.path_join("Google/Chrome/Application/chrome.exe"),
				local.path_join("Google/Chrome/Application/chrome.exe"),
				pf86.path_join("Microsoft/Edge/Application/msedge.exe"),
				pf.path_join("Microsoft/Edge/Application/msedge.exe"),
			]
			# Chromium đầy đủ (Playwright) trước, WebView2 runtime sau: runtime của
			# WebView2 thường không mở được DevTools/headless.
			candidates.append_array(_newest_in(local.path_join("ms-playwright"), "chrome.exe"))
			candidates.append_array(_newest_in(pf86.path_join("Microsoft/EdgeWebView/Application"), "msedge.exe"))
		"macOS":
			candidates = [
				"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
				"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
				"/Applications/Chromium.app/Contents/MacOS/Chromium",
			]
		_:
			for name in ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge"]:
				var found := _which(name)
				if found != "":
					candidates.append(found)
	for path in candidates:
		if path != "" and FileAccess.file_exists(path):
			executable = path
			available = true
			return
	unavailable_reason = "Không tìm thấy Chrome/Edge/Chromium trên máy để render web."


func _newest_in(root: String, file_name: String) -> Array[String]:
	var result: Array[String] = []
	if not DirAccess.dir_exists_absolute(root):
		return result
	var dirs := DirAccess.get_directories_at(root)
	dirs.sort()
	dirs.reverse()
	for dir in dirs:
		# Playwright: <root>/chromium-xxx/chrome-win/chrome.exe
		var nested := root.path_join(dir).path_join("chrome-win").path_join(file_name)
		if FileAccess.file_exists(nested):
			result.append(nested)
		var direct := root.path_join(dir).path_join(file_name)
		if FileAccess.file_exists(direct):
			result.append(direct)
	return result


func _which(name: String) -> String:
	var out: Array = []
	var code := OS.execute("which", [name], out, true)
	if code == 0 and out.size() > 0:
		return str(out[0]).strip_edges()
	return ""


# ------------------------------------------------------------------ lifecycle

func is_supported() -> bool:
	return available


func status_text() -> String:
	if available:
		return "Chromium headless • " + executable.get_file()
	return unavailable_reason


func _start_http_server() -> void:
	if _http_server != null:
		return
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		return
	_http_server = server
	_http_port = server.get_local_port()


## URL trang cầu nối (loopback) để nhúng video YouTube cho đúng origin.
func player_page_url(video_id: String) -> String:
	if _http_port <= 0:
		_start_http_server()
	if _http_port <= 0:
		return ""
	return "http://127.0.0.1:%d/player?v=%s" % [_http_port, video_id.uri_encode()]


func _poll_http() -> void:
	if _http_server == null:
		return
	while _http_server.is_connection_available():
		var peer := _http_server.take_connection()
		if peer == null:
			break
		_http_clients.append({"peer": peer, "buf": PackedByteArray(), "sent": false})
	for i in range(_http_clients.size() - 1, -1, -1):
		var client: Dictionary = _http_clients[i]
		var peer: StreamPeerTCP = client["peer"]
		if peer == null:
			_http_clients.remove_at(i)
			continue
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			_http_clients.remove_at(i)
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var chunk = peer.get_data(available)
			if int(chunk[0]) == OK:
				var buffer: PackedByteArray = client["buf"]
				buffer.append_array(chunk[1])
				client["buf"] = buffer
		var text := (client["buf"] as PackedByteArray).get_string_from_utf8()
		if not bool(client["sent"]) and (text.contains("\r\n\r\n") or text.length() > 2048):
			var body := PLAYER_HTML.to_utf8_buffer()
			var header := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % body.size()
			peer.put_data(header.to_utf8_buffer())
			peer.put_data(body)
			client["sent"] = true
		if bool(client["sent"]):
			peer.disconnect_from_host()
			_http_clients.remove_at(i)


## Khởi động trình duyệt + kết nối CDP. Trả false nếu không khởi động được.
func start(viewport_size: Vector2i) -> bool:
	if running:
		return true
	if not available:
		failed.emit(unavailable_reason)
		return false
	_viewport_size = Vector2i(
		clampi(viewport_size.x, 320, MAX_FRAME_WIDTH),
		clampi(viewport_size.y, 160, 1080)
	)
	_port = _pick_port()
	if _port == 0:
		_fail("Không tìm được cổng trống cho trình duyệt.")
		return false
	_start_http_server()
	_profile_dir = OS.get_user_data_dir().path_join("web_profile_%d_%d" % [OS.get_process_id(), Time.get_ticks_msec()])
	DirAccess.make_dir_recursive_absolute(_profile_dir)
	var args := [
		"--headless=new",
		"--remote-debugging-port=%d" % _port,
		"--remote-allow-origins=*",
		"--user-data-dir=" + _profile_dir,
		"--no-first-run",
		"--no-default-browser-check",
		"--disable-background-timer-throttling",
		"--disable-backgrounding-occluded-windows",
		"--disable-renderer-backgrounding",
		"--disable-dev-shm-usage",
		"--hide-scrollbars",
		# TV phụ phải phát được tiếng của trang (YouTube, SoundCloud…). Không dùng
		# --mute-audio; cho phép autoplay để nhạc tự chạy khi mở trang.
		"--autoplay-policy=no-user-gesture-required",
		"--force-device-scale-factor=1",
		# Headless "new" vẫn giữ thanh công cụ ~140px; cộng bù để vùng nội dung
		# đúng bằng viewport cần render.
		"--window-size=%d,%d" % [_viewport_size.x, _viewport_size.y + 140],
		"about:blank",
	]
	_pid = OS.create_process(executable, args)
	if _pid <= 0:
		_fail("Không chạy được trình duyệt (%s)." % executable)
		return false
	running = true
	_start_timer = 0.0
	_frame_count = 0
	set_process(true)
	_poll_debug_endpoint()
	return true


func stop_browser() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_screencast_active = false
	_ws_open_handled = false
	_closing_reported = false
	if _pid > 0:
		if OS.get_name() == "Windows":
			OS.execute("taskkill", ["/PID", str(_pid), "/T", "/F"], [], true)
		else:
			OS.kill(_pid)
		_pid = -1
	running = false
	set_process(false)
	_pending.clear()
	if _http_server != null:
		_http_server.stop()
		_http_server = null
	_http_port = 0
	for client in _http_clients:
		var peer = client.get("peer")
		if peer is StreamPeerTCP:
			peer.disconnect_from_host()
	_http_clients.clear()
	if _profile_dir != "" and DirAccess.dir_exists_absolute(_profile_dir):
		_remove_dir_recursive(_profile_dir)
		_profile_dir = ""


func _remove_dir_recursive(path: String) -> void:
	for dir in DirAccess.get_directories_at(path):
		_remove_dir_recursive(path.path_join(dir))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _pick_port() -> int:
	for i in 24:
		var candidate := 9300 + (int(Time.get_ticks_usec() % 400) + i * 7) % 500
		var server := TCPServer.new()
		var ok := server.listen(candidate, "127.0.0.1") == OK
		server.stop()
		if ok:
			return candidate
	return 0


func _fail(reason: String) -> void:
	unavailable_reason = reason
	loading = false
	printerr("[WEB] " + reason)
	failed.emit(reason)


# ------------------------------------------------------------------ CDP

func _poll_debug_endpoint() -> void:
	if not running:
		return
	print("[WEB] Trình duyệt: %s (pid=%d, cổng=%d)" % [executable, _pid, _port])
	var ws_url := ""
	var attempts := int(START_TIMEOUT_MS / 500)
	for attempt in attempts:
		if not running:
			return
		var http := HTTPRequest.new()
		http.timeout = 2.0
		add_child(http)
		var err := http.request("http://127.0.0.1:%d/json/list" % _port)
		if err != OK:
			http.queue_free()
			_fail("Không gọi được DevTools của trình duyệt.")
			return
		var res: Array = await http.request_completed
		http.queue_free()
		await get_tree().create_timer(0.25).timeout
		if not running:
			return
		if int(res[1]) != 200:
			continue
		var parsed = JSON.parse_string(str(res[3].get_string_from_utf8()))
		if parsed is Array:
			for target in parsed:
				if str(target.get("type", "")) == "page":
					ws_url = str(target.get("webSocketDebuggerUrl", ""))
					break
		if ws_url != "":
			break
		await get_tree().create_timer(0.5).timeout
	if ws_url == "":
		_fail("Trình duyệt không mở được DevTools sau %ds." % int(START_TIMEOUT_MS / 1000))
		return
	print("[WEB] Kết nối CDP: " + ws_url)
	_ws = WebSocketPeer.new()
	# Mặc định Godot chỉ nhận frame tối đa 64 KB, trong khi một khung hình
	# 1920x1080 JPEG thường lớn hơn nhiều — vượt ngưỡng là WebSocket bị đóng
	# ngay sau frame đầu. Nâng buffer lên 16 MB để nhận frame thoải mái.
	_ws.inbound_buffer_size = 16 * 1024 * 1024
	_ws.outbound_buffer_size = 4 * 1024 * 1024
	var connect_err := _ws.connect_to_url(ws_url)
	if connect_err != OK:
		_fail("Không kết nối được WebSocket CDP (%s)." % error_string(connect_err))
		return
	_ws_open_handled = false


func _on_ws_open() -> void:
	_ws_open_handled = true
	print("[WEB] CDP đã kết nối, bật screencast %dx%d" % [_viewport_size.x, _viewport_size.y])
	_send("Page.enable", {})
	_send("Runtime.enable", {})
	# Trang web chạy trong cửa sổ headless nhưng vẫn cần được coi là đang focus
	# để YouTube nhận phím và phát media ổn định.
	_send("Emulation.setFocusEmulationEnabled", {"enabled": true})
	# Chèn shim trước khi trang tải: fullscreen của YouTube/HTML5 sẽ biến thành
	# chế độ "cinema" phủ kín khung 1920x1080 thay vì gọi fullscreen thật của
	# Chromium (làm đổi viewport và vỡ hình trên TV).
	_send("Page.addScriptToEvaluateOnNewDocument", {"source": PAGE_SHIM})
	_send("Emulation.setDeviceMetricsOverride", {
		"width": _viewport_size.x,
		"height": _viewport_size.y,
		"deviceScaleFactor": 1,
		"mobile": false,
	})
	_send("Page.startScreencast", {
		"format": "jpeg",
		"quality": FRAME_QUALITY,
		"maxWidth": _viewport_size.x,
		"maxHeight": _viewport_size.y,
		"everyNthFrame": SCREENCAST_EVERY_NTH_FRAME,
	})
	_screencast_active = true
	started.emit()
	var queued := _pending.duplicate()
	_pending.clear()
	for item in queued:
		_send(str(item["method"]), item["params"])


func _send(method: String, params: Dictionary, require_ws := true) -> int:
	_msg_id += 1
	var payload := {"id": _msg_id, "method": method}
	if not params.is_empty():
		payload["params"] = params
	var text := JSON.stringify(payload)
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		if require_ws:
			_pending.append({"method": method, "params": params})
		return _msg_id
	_ws.send_text(text)
	return _msg_id


func navigate(url: String) -> void:
	current_url = url
	loading = true
	_send("Page.navigate", {"url": url})
	_send("Page.bringToFront", {})


func reload() -> void:
	if current_url != "":
		loading = true
		_send("Page.reload", {"ignoreCache": false})


func back() -> void:
	_evaluate_history("history.back()")


func forward() -> void:
	_evaluate_history("history.forward()")


func _evaluate_history(expression: String) -> void:
	_send("Runtime.evaluate", {"expression": expression})


## Chạy JS trong trang và in kết quả ra console Godot. Dùng cho test/kiểm tra
## trạng thái DOM (kích thước viewport, phần tử fullscreen, video…).
func evaluate(expression: String, tag := "") -> void:
	if not _is_open():
		return
	var id := _send("Runtime.evaluate", {
		"expression": expression,
		"returnByValue": true,
		"awaitPromise": true,
	})
	_eval_tags[id] = tag if tag != "" else expression.substr(0, 48)


## Chụp ảnh bitmap thật của trang qua CDP (không phụ thuộc screencast).
func capture_screenshot(path: String) -> void:
	if not _is_open():
		return
	var id := _send("Page.captureScreenshot", {"format": "png", "fromSurface": true})
	_shot_paths[id] = path


# ------------------------------------------------------------------ input

## Gửi click chuột tới trang web. Toạ độ tính bằng pixel CSS của khung hình
## (khớp với viewport truyền vào start()).
func mouse_click(x: float, y: float, button := "left") -> void:
	if not _is_open():
		return
	var point := {
		"x": clampf(x, 0.0, float(_viewport_size.x - 1)),
		"y": clampf(y, 0.0, float(_viewport_size.y - 1)),
		"button": button,
		"buttons": 1,
	}
	_send("Input.dispatchMouseEvent", {
		"type": "mouseMoved", "x": point["x"], "y": point["y"],
		"button": "none", "buttons": 0,
	})
	_send("Input.dispatchMouseEvent", {
		"type": "mousePressed", "x": point["x"], "y": point["y"],
		"button": button, "buttons": 1, "clickCount": 1,
	})
	_send("Input.dispatchMouseEvent", {
		"type": "mouseReleased", "x": point["x"], "y": point["y"],
		"button": button, "buttons": 0, "clickCount": 1,
	})


## Di chuyển con trỏ trong trang (hover, hiện thanh điều khiển YouTube).
func mouse_move(x: float, y: float) -> void:
	if not _is_open():
		return
	_send("Input.dispatchMouseEvent", {
		"type": "mouseMoved",
		"x": clampf(x, 0.0, float(_viewport_size.x - 1)),
		"y": clampf(y, 0.0, float(_viewport_size.y - 1)),
		"button": "none",
		"buttons": 0,
	})


func mouse_wheel(x: float, y: float, delta: float) -> void:
	if not _is_open():
		return
	_send("Input.dispatchMouseEvent", {
		"type": "mouseWheel",
		"x": clampf(x, 0.0, float(_viewport_size.x - 1)),
		"y": clampf(y, 0.0, float(_viewport_size.y - 1)),
		"deltaX": 0.0,
		"deltaY": delta,
	})


func insert_text(text: String) -> void:
	if not _is_open():
		return
	_send("Input.insertText", {"text": text})


# ------------------------------------------------------------------ keyboard
# Modifier bits theo CDP: Alt=1, Ctrl=2, Meta=4, Shift=8.
const MOD_ALT := 1
const MOD_CTRL := 2
const MOD_META := 4
const MOD_SHIFT := 8


## Chuyển InputEventKey của Godot thành payload gửi được qua Net và CDP.
static func key_payload(event: InputEventKey, pressed: bool) -> Dictionary:
	var keycode := int(event.keycode)
	var unicode := int(event.unicode)
	var info := _key_info(keycode, unicode)
	var mods := 0
	if event.alt_pressed:
		mods |= MOD_ALT
	if event.ctrl_pressed:
		mods |= MOD_CTRL
	if event.meta_pressed:
		mods |= MOD_META
	if event.shift_pressed:
		mods |= MOD_SHIFT
	var text := ""
	if pressed and unicode >= 32 and mods & (MOD_CTRL | MOD_ALT | MOD_META) == 0:
		text = String.chr(unicode)
	if pressed and (keycode == KEY_ENTER or keycode == KEY_KP_ENTER):
		text = "\r"
	return {
		"type": "key",
		"key": str(info[0]),
		"code": str(info[1]),
		"vk": int(info[2]),
		"text": text,
		"mods": mods,
		"down": pressed,
		"repeat": bool(event.echo),
	}


static func _key_info(keycode: int, unicode: int) -> Array:
	if keycode >= 65 and keycode <= 90:
		var ch := String.chr(unicode) if unicode >= 32 else String.chr(keycode).to_lower()
		return [ch, "Key" + String.chr(keycode), keycode]
	if keycode >= 48 and keycode <= 57:
		return [String.chr(unicode) if unicode >= 32 else String.chr(keycode), "Digit" + String.chr(keycode), keycode]
	match keycode:
		KEY_SPACE:
			return [" ", "Space", 32]
		KEY_ENTER:
			return ["Enter", "Enter", 13]
		KEY_KP_ENTER:
			return ["Enter", "NumpadEnter", 13]
		KEY_TAB:
			return ["Tab", "Tab", 9]
		KEY_BACKSPACE:
			return ["Backspace", "Backspace", 8]
		KEY_DELETE:
			return ["Delete", "Delete", 46]
		KEY_ESCAPE:
			return ["Escape", "Escape", 27]
		KEY_LEFT:
			return ["ArrowLeft", "ArrowLeft", 37]
		KEY_RIGHT:
			return ["ArrowRight", "ArrowRight", 39]
		KEY_UP:
			return ["ArrowUp", "ArrowUp", 38]
		KEY_DOWN:
			return ["ArrowDown", "ArrowDown", 40]
		KEY_HOME:
			return ["Home", "Home", 36]
		KEY_END:
			return ["End", "End", 35]
		KEY_PAGEUP:
			return ["PageUp", "PageUp", 33]
		KEY_PAGEDOWN:
			return ["PageDown", "PageDown", 34]
		KEY_INSERT:
			return ["Insert", "Insert", 45]
		KEY_SHIFT:
			return ["Shift", "ShiftLeft", 16]
		KEY_CTRL:
			return ["Control", "ControlLeft", 17]
		KEY_ALT:
			return ["Alt", "AltLeft", 18]
	if unicode >= 32:
		return [String.chr(unicode), "", 0]
	return [OS.get_keycode_string(keycode).to_lower(), "", 0]


## Gửi một payload bàn phím (đã chuẩn hoá) tới trang web.
func dispatch_key(payload: Dictionary) -> void:
	if not _is_open():
		return
	var down := bool(payload.get("down", true))
	var text := str(payload.get("text", ""))
	var params := {
		"type": "keyDown" if down else "keyUp",
		"key": str(payload.get("key", "")),
		"code": str(payload.get("code", "")),
		"windowsVirtualKeyCode": int(payload.get("vk", 0)),
		"nativeVirtualKeyCode": int(payload.get("vk", 0)),
		"modifiers": int(payload.get("mods", 0)),
		"autoRepeat": bool(payload.get("repeat", false)),
	}
	if down and text != "":
		params["text"] = text
		params["unmodifiedText"] = text
	_send("Input.dispatchKeyEvent", params)


func _is_open() -> bool:
	return _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(delta: float) -> void:
	_poll_http()
	if _ws == null:
		return
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _ws_open_handled:
			_on_ws_open()
		while _ws.get_available_packet_count() > 0:
			_handle_packet(_ws.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if running and not _closing_reported:
			_closing_reported = true
			_fail("Kết nối DevTools bị đóng.")


func _handle_packet(text: String) -> void:
	var message = JSON.parse_string(text)
	if message is not Dictionary:
		return
	var method := str(message.get("method", ""))
	if method == "Page.screencastFrame":
		_push_frame(message.get("params", {}))
	elif method == "Page.frameNavigated":
		var frame: Dictionary = message.get("params", {}).get("frame", {})
		if str(frame.get("parentId", "")) == "":
			current_url = str(frame.get("url", current_url))
			current_title = str(frame.get("name", ""))
			loading = false
			page_loaded.emit(current_title, current_url)
	elif method == "Inspector.targetCrashed":
		_fail("Tab web bị treo.")
	var response_id := int(message.get("id", 0))
	if response_id > 0 and _eval_tags.has(response_id):
		var tag := str(_eval_tags[response_id])
		_eval_tags.erase(response_id)
		var result: Dictionary = message.get("result", {})
		var value = result.get("result", {}).get("value", null)
		if value == null:
			value = result.get("exceptionDetails", result)
		print("[WEB-EVAL] %s = %s" % [tag, str(value)])
	if response_id > 0 and _shot_paths.has(response_id):
		var shot_path := str(_shot_paths[response_id])
		_shot_paths.erase(response_id)
		var data := str(message.get("result", {}).get("data", ""))
		if data != "":
			var img := Image.new()
			var err := img.load_png_from_buffer(Marshalls.base64_to_raw(data))
			if err == OK:
				err = img.save_png(shot_path)
			print("[WEB-SHOT] %s size=%s (%s)" % [shot_path, img.get_size(), error_string(err)])


func _push_frame(params: Dictionary) -> void:
	var session_id := int(params.get("sessionId", 0))
	_send("Page.screencastFrameAck", {"sessionId": session_id})
	var data := str(params.get("data", ""))
	if data == "":
		return
	var bytes := Marshalls.base64_to_raw(data)
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK:
		return
	if texture == null or texture.get_width() != image.get_width() or texture.get_height() != image.get_height():
		texture = ImageTexture.create_from_image(image)
		texture_ready.emit(texture)
	else:
		texture.update(image)
	_frame_count += 1
	if _frame_count == 1:
		print("[WEB] Nhận frame đầu tiên %dx%d" % [image.get_width(), image.get_height()])
	loading = false
