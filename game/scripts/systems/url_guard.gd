class_name QBOUrlGuard
extends RefCounted
## Kiểm tra URL trước khi mở trên TV/Browser: chặn SSRF, javascript:, file:…
## Trả về { ok, url, host, kind, trusted, reason }.

const ALLOWED_SCHEMES := ["http", "https"]
const TRUSTED_HOSTS := [
	"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com",
	"vimeo.com", "player.vimeo.com", "soundcloud.com", "twitch.tv", "www.twitch.tv",
	"bilibili.com", "www.bilibili.com", "spotify.com", "open.spotify.com",
	"archive.org", "commons.wikimedia.org",
]
const AUDIO_EXTENSIONS := [".mp3", ".ogg", ".oga", ".wav"]
const VIDEO_EXTENSIONS := [".ogv"]


static func validate(raw_url: String) -> Dictionary:
	var url := raw_url.strip_edges()
	if url == "":
		return _fail("URL trống.")
	if url.length() > 500:
		return _fail("URL quá dài (tối đa 500 ký tự).")
	if not (url.begins_with("http://") or url.begins_with("https://")):
		url = "https://" + url
	var scheme_end := url.find("://")
	if scheme_end <= 0:
		return _fail("URL không hợp lệ.")
	var scheme := url.substr(0, scheme_end).to_lower()
	if not ALLOWED_SCHEMES.has(scheme):
		return _fail("Chỉ hỗ trợ http/https.")
	var rest := url.substr(scheme_end + 3)
	var host_end := rest.length()
	for separator in ["/", "?", "#"]:
		var idx := rest.find(separator)
		if idx >= 0 and idx < host_end:
			host_end = idx
	var host_port := rest.substr(0, host_end).to_lower()
	var host := host_port
	if host_port.contains(":"):
		host = host_port.split(":")[0]
	if host == "":
		return _fail("URL thiếu tên miền.")
	if _is_private_host(host):
		return _fail("Không cho phép truy cập địa chỉ nội bộ/localhost (chống SSRF).")
	var lower := url.to_lower()
	var kind := "web"
	for ext in AUDIO_EXTENSIONS:
		if lower.contains(ext):
			kind = "audio"
			break
	if kind == "web":
		for ext in VIDEO_EXTENSIONS:
			if lower.contains(ext):
				kind = "video"
				break
	if _is_youtube(host):
		kind = "youtube"
	var trusted := false
	for allowed in TRUSTED_HOSTS:
		if host == allowed or host.ends_with("." + allowed):
			trusted = true
			break
	return {
		"ok": true,
		"url": url,
		"host": host,
		"kind": kind,
		"trusted": trusted,
		"reason": "",
	}


static func youtube_video_id(url: String) -> String:
	var raw := url.strip_edges()
	# Cho phép dán thẳng mã video 11 ký tự.
	if raw.length() == 11 and not raw.contains("/") and not raw.contains(".") and not raw.contains(" "):
		return raw
	var parsed := validate(raw)
	if not parsed["ok"]:
		return ""
	var host := str(parsed["host"])
	var path := raw.split("?")[0].split("#")[0]
	if host == "youtu.be":
		var tail := path.split("youtu.be/")
		if tail.size() > 1:
			return _clean_youtube_id(tail[1].split("/")[0])
	for marker in ["/embed/", "/shorts/", "/live/", "/v/"]:
		if marker in path:
			return _clean_youtube_id(path.split(marker)[1].split("/")[0])
	if raw.contains("v="):
		return _clean_youtube_id(raw.split("v=")[1].split("&")[0])
	return ""


static func _clean_youtube_id(value: String) -> String:
	var id := value.strip_edges()
	# ID YouTube gồm 11 ký tự [A-Za-z0-9_-].
	var result := ""
	for i in id.length():
		var ch := id[i]
		if ch.is_valid_int() or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "-" or ch == "_":
			result += ch
			if result.length() == 11:
				break
		else:
			break
	return result


static func _is_youtube(host: String) -> bool:
	return host == "youtu.be" or host.ends_with("youtube.com")


static func _is_private_host(host: String) -> bool:
	if host == "localhost" or host.ends_with(".localhost") or host.ends_with(".local"):
		return true
	if host == "metadata.google.internal" or host == "metadata":
		return true
	if host == "0.0.0.0" or host == "::1" or host == "[::1]":
		return true
	var parts := host.split(".")
	if parts.size() == 4:
		for part in parts:
			if not part.is_valid_int():
				return false
		var a := int(parts[0])
		var b := int(parts[1])
		if a == 127 or a == 10 or a == 0:
			return true
		if a == 192 and b == 168:
			return true
		if a == 172 and b >= 16 and b <= 31:
			return true
		if a == 169 and b == 254:
			return true
		if a == 100 and b >= 64 and b <= 127:
			return true
	return false


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "url": "", "host": "", "kind": "", "trusted": false, "reason": reason}
