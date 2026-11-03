class_name QBOIOSBrowserProvider
extends QBOBrowserProvider
## iOS backend: WKWebView qua Godot iOS plugin (singleton "QBOWebViewIOS").
## Thiếu plugin -> báo chưa hỗ trợ; fallback mở Safari bằng OS.shell_open.

const SINGLETON_NAME := "QBOWebViewIOS"

var _open := false


func provider_name() -> String:
	return "WKWebView" if is_embedded_supported() else "WKWebView (plugin chưa cài)"


func platform() -> String:
	return "ios"


func capability() -> Dictionary:
	if not Engine.has_singleton(SINGLETON_NAME):
		return {
			"embedded": false,
			"reason": "Cần thêm plugin WKWebView vào iOS export (xem docs/BROWSER.md).",
		}
	return {"embedded": true, "reason": ""}


func open(url: String) -> bool:
	if not Engine.has_singleton(SINGLETON_NAME):
		return false
	var singleton := Engine.get_singleton(SINGLETON_NAME)
	if not singleton.has_method("open"):
		return false
	singleton.call("open", url)
	_open = true
	return true


func close() -> void:
	if Engine.has_singleton(SINGLETON_NAME):
		var singleton := Engine.get_singleton(SINGLETON_NAME)
		if singleton.has_method("close"):
			singleton.call("close")
	_open = false


func is_open() -> bool:
	return _open


func documentation() -> String:
	return "docs/BROWSER.md#ios--wkwebview"
