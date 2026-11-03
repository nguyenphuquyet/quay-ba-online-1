@tool
extends EditorPlugin
## Đóng gói AAR WebView native vào bản export Android.
##
## AAR được CI build từ `android-plugin/` rồi copy vào
## `addons/qbo_webview_android/bin/`. Nếu thiếu AAR, Godot vẫn export được
## nhưng game sẽ báo "plugin chưa cài" (không giả lập WebView).

var export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree() -> void:
	if export_plugin != null:
		remove_export_plugin(export_plugin)
		export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name := "QBOWebViewAndroid"

	func _supports_platform(platform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform, debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["qbo_webview_android/bin/QBOWebViewAndroid-debug.aar"])
		return PackedStringArray(["qbo_webview_android/bin/QBOWebViewAndroid-release.aar"])

	func _get_name() -> String:
		return _plugin_name
