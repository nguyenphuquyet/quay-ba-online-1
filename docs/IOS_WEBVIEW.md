# WKWebView native trên iOS (TV sân khấu)

Trên Android, WebView là một **Godot Android plugin (v2)**. Trên iOS không có cơ
chế đó: Godot chỉ nhận thư viện tĩnh `.a` + file `.gdip`, hoặc **GDExtension**.
Repo này dùng GDExtension vì nó không cần header của engine.

```
computer_screen.gd ─▶ tv_system.play_youtube(url)
                            │
                            ├─ Net.send_tv(state)   ─▶ cả phòng cùng trạng thái
                            └─ QBOIOSBrowserProvider.open(embed_url)
                                      │
                                      ▼
                     ClassDB.instantiate("QBOWebViewIOS")
                                      │
                                      ▼
              WKWebView phủ toàn màn hình + nút "✕ Đóng TV"
```

## Vì sao là GDExtension mà không phải `.gdip`

`.gdip` yêu cầu thư viện phải `#include` header của engine (`Engine`,
`ClassDB`, …) — phải tải source Godot rồi chạy SCons để sinh header, rất nặng
cho CI. GDExtension chỉ cần **một** file header C (`gdextension_interface.h`),
mà repo đã rút gọn thành `ios-plugin/src/qbo_gdextension.h`.

Godot 4.7 hỗ trợ GDExtension dạng thư viện tĩnh trên iOS: exporter tự thêm
`-Wl,-U,_<entry_symbol>` và gọi entry point qua
`add_apple_embedded_platform_init_callback`.

## Thành phần

| Đường dẫn | Vai trò |
| --- | --- |
| `ios-plugin/src/qbo_gdextension.h` | Tập con ABI của GDExtension 4.7 (struct/typedef). |
| `ios-plugin/src/qbo_webview_ios.mm` | Đăng ký lớp `QBOWebViewIOS` + lớp phủ WKWebView. |
| `game/addons/qbo_webview_ios/qbo_webview_ios.gdextension` | Khai báo `entry_symbol` và đường dẫn `.a` cho `ios.release.arm64`. |
| `game/scripts/browser/ios_browser_provider.gd` | Gọi native qua `ClassDB`. |
| `.github/workflows/ios-unsigned.yml` | Build `.a` bằng `xcrun` trước khi export. |

Thư viện `.a` **không** commit vào git (`game/addons/qbo_webview_ios/bin/*.a`);
CI build rồi đặt vào đúng chỗ trước bước export.

## API của lớp native

```gdscript
var view := ClassDB.instantiate("QBOWebViewIOS")
view.open("https://www.youtube.com/embed/<id>?autoplay=1")  # -> bool
view.is_open()                                              # -> bool
view.set_insets(top, bottom)                                # float, float
view.reload()
view.close()
```

- `open()` nhận URL. Nếu là link nhúng YouTube, native dựng một trang HTML nhỏ
  với `baseURL = https://www.youtube.com` để Origin/Referer khớp iframe chính
  thức (tránh lỗi phát 153), rồi nạp iframe full-screen.
- URL khác được nạp thẳng bằng `loadRequest:`.
- Lớp phủ nằm trên `rootViewController.view`, tự co giãn theo xoay máy, nút đóng
  nằm dưới tai thỏ (safe area).

## Build local (cần macOS + Xcode)

```bash
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p game/addons/qbo_webview_ios/bin
xcrun --sdk iphoneos clang++ -arch arm64 -miphoneos-version-min=13.0 \
  -isysroot "$SDK" -std=c++17 -fobjc-arc -fmodules -fcxx-modules -O2 \
  -I ios-plugin/src -c ios-plugin/src/qbo_webview_ios.mm -o /tmp/qbo.o
xcrun --sdk iphoneos libtool -static \
  -o game/addons/qbo_webview_ios/bin/libqbo_webview_ios.ios.template_release.arm64.a /tmp/qbo.o
```

Sau đó export iOS như bình thường (`--export-release "iOS" ...`).

## Kiểm tra trên máy

1. Vào phòng → menu nhanh `☰` → **TV sân khấu**.
2. Nếu chưa có nội dung: mở máy tính trong bar → tab TV → dán link YouTube →
   **▶ Phát trên TV**. Trên iOS video mở toàn màn hình ngay.
3. **✕ Đóng TV** để quay lại club (không rời phòng).
4. Người chơi khác thấy thẻ trạng thái trên TV và mở cùng nội dung.

Nếu bản build **không** kèm extension (ví dụ bản cũ), provider báo chưa hỗ trợ và
game mở link bằng ứng dụng hệ thống — trạng thái TV vẫn được đồng bộ cho cả
phòng.

## Ghi chú kỹ thuật

- WebKit được **autolink** nhờ `@import WebKit` + `-fmodules`, nên không phải
  sửa `project.pbxproj` do Godot sinh ra.
- Không dùng `std::string`/exception để tránh kéo thêm phụ thuộc runtime.
- Entry point `qbo_webview_ios_init` chạy ở mức `SCENE`; lớp được đăng ký bằng
  `classdb_register_extension_class6` (API 4.7) + `classdb_construct_object3`.
