# WebView native trên Android (TV sân khấu)

TV phụ trong club cần một trình duyệt thật để phát YouTube. Trên desktop, game
dùng Chromium headless + CDP để lấy texture. Trên Android, cách đó không chạy,
nên game dùng **WebView native** qua Godot Android plugin (v2).

## Kiến trúc

```
computer_screen.gd  ──▶ tv_system.play_youtube(url)
                              │
                              ├─ Net.send_tv(state)  ──▶ cả phòng nhận cùng trạng thái
                              │
                              └─ provider.open(embed_url)  (chỉ trên thiết bị có WebView)
                                        │
                                        ▼
                         QBOWebViewAndroid (Java, lớp phủ toàn màn hình)
                         WebView thật + nút "✕ Đóng TV"
```

- Trạng thái TV (`url`, `kind`, `video_id`, `updated_at`, …) là **dữ liệu chung
  của phòng**, luôn được gửi lên server kể cả khi máy đang thao tác không nhúng
  được trình duyệt. Nhờ vậy điện thoại vẫn điều khiển được TV cho cả phòng.
- Thiết bị không render được vào texture 3D sẽ hiện thẻ trạng thái trên màn sân
  khấu và mở player bằng **menu nhanh → TV sân khấu**.
- Video YouTube được nạp bằng `loadDataWithBaseURL("https://www.youtube.com", …)`
  để Origin/Referer khớp với iframe nhúng chính thức (tránh lỗi phát 153).

## Thành phần trong repo

| Đường dẫn | Vai trò |
| --- | --- |
| `android-plugin/` | Project Gradle build AAR (`org.godotengine:godot:4.7.2.stable`). |
| `android-plugin/plugin/src/main/java/com/quaybar/webview/QBOWebViewAndroid.java` | Lớp plugin: `onMainCreate` trả về lớp phủ WebView, các hàm `open`, `close`, `isOpen`, `setInsets`. |
| `game/addons/qbo_webview_android/export_plugin.gd` | `EditorExportPlugin` đưa AAR vào bản export Android. |
| `game/scripts/browser/android_browser_provider.gd` | Gọi singleton `QBOWebViewAndroid` từ GDScript. |
| `.github/workflows/android.yml` | Build AAR → cài Android build template → export APK. |

AAR không commit vào git (xem `.gitignore`); CI build từ `android-plugin/` rồi
copy sang `game/addons/qbo_webview_android/bin/`.

## Build local

```bash
cd android-plugin
gradle wrapper --gradle-version 8.11.1 --distribution-type bin
./gradlew :plugin:assembleRelease
mkdir -p ../game/addons/qbo_webview_android/bin
cp plugin/build/outputs/aar/plugin-release.aar \
   ../game/addons/qbo_webview_android/bin/QBOWebViewAndroid-release.aar
```

Sau đó export Android với `gradle_build/use_gradle_build=true` (đã bật trong
`game/export_presets.cfg`).

## Kiểm tra trên máy

1. Mở app → vào phòng → menu nhanh `☰` → **TV sân khấu**.
2. Nếu chưa có nội dung, mở máy tính trong bar → tab TV → dán link YouTube →
   **▶ Phát trên TV**. Trên Android, video mở ngay toàn màn hình.
3. Nút **✕ Đóng TV** (hoặc phím Back) quay lại club mà không rời phòng.
4. Người chơi khác trong phòng thấy thẻ trạng thái trên TV và mở cùng video
   bằng menu → TV sân khấu (mốc thời gian gần khớp theo `updated_at`).

## iOS

iOS cần WKWebView trong một static library và `ios/plugins/*.gdip`, phải build
bằng Xcode trên runner macOS. Hiện chưa có; trên iOS nút TV mở link bằng trình
duyệt hệ thống (`OS.shell_open`).
