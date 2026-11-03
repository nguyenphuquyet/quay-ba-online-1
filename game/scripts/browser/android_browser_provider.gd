class_name QBOAndroidBrowserProvider
extends QBOBrowserProvider
## Android backend: native Android WebView qua Godot Android plugin.
## Singleton do plugin đăng ký tên "QBOWebViewAndroid".
## Vì môi trường phát triển hiện tại không có Android SDK, provider báo
## "chưa cài plugin" nếu singleton vắng mặt — không giả lập WebView.

const SINGLETON_NAME := "QBOWebViewAndroid"

var _open := false


func provider_name() -> String:
	return "Android WebView" if is_embedded_supported() else "Android WebView (plugin chưa cài)"


func platform() -> String:
	return "android"


func capability() -> Dictionary:
	if not Engine.has_singleton(SINGLETON_NAME):
		return {
			"embedded": false,
			"reason": "Cần build addons/qbo_webview_android trong Android export template (xem docs/BROWSER.md).",
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
	return "docs/BROWSER.md#android--webview"
