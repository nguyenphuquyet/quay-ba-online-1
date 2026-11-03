class_name QBOPCBrowserProvider
extends QBOBrowserProvider
## PC backend: tìm singleton CEF/WebView do plugin native cung cấp.
## Hợp đồng singleton (xem docs/BROWSER.md):
##   has_method("open"), "close", "navigate", "get_texture", "set_rect"
## Nếu không có plugin, chỉ hỗ trợ mở URL bằng trình duyệt hệ thống (fallback).

const SINGLETON_NAME := "QBOWebView"

var _open := false
var _current_url := ""


func provider_name() -> String:
	return "CEF / WebView2 (plugin chưa cài)" if not is_embedded_supported() else "CEF / WebView2"


func platform() -> String:
	return "pc"


func capability() -> Dictionary:
	var singleton := Engine.get_singleton(SINGLETON_NAME) if Engine.has_singleton(SINGLETON_NAME) else null
	if singleton == null:
		return {
			"embedded": false,
			"reason": "Chưa cài plugin CEF/WebView2. TV và máy tính chỉ hiển thị trạng thái URL; nút “Mở bằng trình duyệt” dùng trình duyệt hệ thống.",
		}
	return {"embedded": true, "reason": ""}


func open(url: String) -> bool:
	if not Engine.has_singleton(SINGLETON_NAME):
		return false
	var singleton := Engine.get_singleton(SINGLETON_NAME)
	if not singleton.has_method("open"):
		return false
	singleton.call("open", url)
	_current_url = url
	_open = true
	return true


func close() -> void:
	if not Engine.has_singleton(SINGLETON_NAME):
		return
	var singleton := Engine.get_singleton(SINGLETON_NAME)
	if singleton.has_method("close"):
		singleton.call("close")
	_open = false


func is_open() -> bool:
	return _open


func get_texture() -> Texture2D:
	if not Engine.has_singleton(SINGLETON_NAME):
		return null
	var singleton := Engine.get_singleton(SINGLETON_NAME)
	if singleton.has_method("get_texture"):
		return singleton.call("get_texture") as Texture2D
	return null


func documentation() -> String:
	return "docs/BROWSER.md#pc--cefwebview2"
