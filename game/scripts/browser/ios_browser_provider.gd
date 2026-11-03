class_name QBOIOSBrowserProvider
extends QBOBrowserProvider
## iOS backend: WKWebView nhúng, đóng gói dạng GDExtension (`ios-plugin/`).
##
## GDExtension không đăng ký được engine singleton nên lớp native
## `QBOWebViewIOS` được tạo bằng `ClassDB.instantiate()`. Nếu bản build không
## kèm thư viện native, provider báo "chưa hỗ trợ" và nơi gọi sẽ mở bằng ứng
## dụng hệ thống (`OS.shell_open`).

const SINGLETON_NAME := "QBOWebViewIOS"
const NATIVE_CLASS := "QBOWebViewIOS"

var _open := false
var _native: Object = null


func _native_view() -> Object:
	if _native != null and is_instance_valid(_native):
		return _native
	if Engine.has_singleton(SINGLETON_NAME):
		_native = Engine.get_singleton(SINGLETON_NAME)
		return _native
	if ClassDB.class_exists(NATIVE_CLASS):
		_native = ClassDB.instantiate(NATIVE_CLASS)
	return _native


func provider_name() -> String:
	return "WKWebView" if is_embedded_supported() else "WKWebView (chưa cài)"


func platform() -> String:
	return "ios"


func capability() -> Dictionary:
	if Engine.has_singleton(SINGLETON_NAME) or ClassDB.class_exists(NATIVE_CLASS):
		return {"embedded": true, "reason": ""}
	return {
		"embedded": false,
		"reason": "Bản build iOS này không kèm GDExtension WKWebView (xem docs/IOS_WEBVIEW.md).",
	}


func open(url: String) -> bool:
	var native := _native_view()
	if native == null or not native.has_method("open"):
		return false
	var result: Variant = native.call("open", url)
	_open = true
	if result is bool:
		return bool(result)
	return true


func close() -> void:
	var native := _native_view()
	if native != null and native.has_method("close"):
		native.call("close")
	_open = false


func is_open() -> bool:
	var native := _native_view()
	if native != null and native.has_method("is_open"):
		return bool(native.call("is_open"))
	return _open


func documentation() -> String:
	return "docs/IOS_WEBVIEW.md"
