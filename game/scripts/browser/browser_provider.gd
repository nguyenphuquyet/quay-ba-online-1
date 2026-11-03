class_name QBOBrowserProvider
extends RefCounted
## Hợp đồng BrowserProvider. Mỗi nền tảng có backend nhúng riêng; khi thiếu
## native plugin, provider BÁO CÁO không hỗ trợ thay vì giả vờ đã render web.

func provider_name() -> String:
	return "none"


func platform() -> String:
	return "unknown"


func capability() -> Dictionary:
	return {
		"embedded": false,
		"reason": "Chưa có native WebView/CEF plugin cho nền tảng này.",
	}


func is_embedded_supported() -> bool:
	return bool(capability().get("embedded", false))


func open(_url: String) -> bool:
	return false


func close() -> void:
	pass


func get_texture() -> Texture2D:
	return null


func is_open() -> bool:
	return false


func external_open(url: String) -> bool:
	if url.begins_with("https://") or url.begins_with("http://"):
		return OS.shell_open(url) == OK
	return false


func documentation() -> String:
	return "Xem docs/BROWSER.md để biết cách cài native plugin."
