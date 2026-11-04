class_name QBOUrlGuard
extends RefCounted
## Kiểm tra URL media trước khi tải về máy.
##
## TV lớn chỉ nhận video trực tiếp (MP4/MOV/M4V/Ogg Theora), booth DJ chỉ nhận
## audio trực tiếp (MP3/OGG/WAV). Không còn luồng nhúng website/YouTube.

const ALLOWED_SCHEMES := ["http", "https"]
const AUDIO_EXTENSIONS := [".mp3", ".ogg", ".oga", ".wav"]
const VIDEO_EXTENSIONS := [".mp4", ".mov", ".m4v", ".ogv"]
## API nhạc của quán; vẫn cho phép host khác nếu URL là media trực tiếp.
const TRUSTED_HOSTS := [
	"music.nguyenphuquyet.online",
	"archive.org",
	"commons.wikimedia.org",
]


static func validate(raw_url: String) -> Dictionary:
	var url := raw_url.strip_edges()
	if url == "":
		return _fail("URL trống.")
	if url.length() > 1000:
		return _fail("URL quá dài (tối đa 1000 ký tự).")
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
	var kind := "other"
	for ext in AUDIO_EXTENSIONS:
		if lower.contains(ext):
			kind = "audio"
			break
	if kind == "other":
		for ext in VIDEO_EXTENSIONS:
			if lower.contains(ext):
				kind = "video"
				break
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


static func is_supported_audio(url: String) -> bool:
	return validate(url).get("kind", "") == "audio"


static func is_supported_video(url: String) -> bool:
	return validate(url).get("kind", "") == "video"


## Ghép URL tương đối từ API với host gốc. API trả `/media/audio/...`.
static func absolute_url(raw_url: String, base_url: String) -> String:
	var value := raw_url.strip_edges()
	if value == "":
		return ""
	if value.begins_with("http://") or value.begins_with("https://"):
		return value
	var base := base_url.strip_edges().rstrip("/")
	if value.begins_with("//"):
		return "https:" + value
	if value.begins_with("/"):
		return base + value
	return base + "/" + value


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
