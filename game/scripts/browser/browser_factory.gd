class_name QBOBrowserFactory
extends RefCounted
## Chọn BrowserProvider theo nền tảng — không giả định một plugin chạy mọi nơi.

static func create() -> QBOBrowserProvider:
	match OS.get_name():
		"Android":
			return QBOAndroidBrowserProvider.new()
		"iOS":
			return QBOIOSBrowserProvider.new()
		_:
			return QBOPCBrowserProvider.new()
