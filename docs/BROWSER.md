# BROWSER & TV — QUẨY BAR ONLINE

## 1. Mục tiêu và giới hạn

Sân khấu có **hai màn hình**:

| Màn hình | Vị trí | Nội dung |
| --- | --- | --- |
| TV chính | Giữa sân khấu, 20:9 (14.4 × 6.48 m) | Visualizer/branding động (logo, vòng spectrum, EQ bars, now playing) |
| TV phụ | Bên phải sân khấu, 16:9 (5.4 × 3.04 m), nghiêng 16° | **Trang web thật**, click/cuộn chuột trực tiếp trên màn hình |

Máy tính trong bar mở **Lotus Browser** và phản chiếu đúng trang web đang chạy trên TV phụ.

### Backend render web

| Nền tảng | Backend | Trạng thái trong repo |
| --- | --- | --- |
| Windows PC | Chromium/Chrome/Edge headless qua **DevTools Protocol (CDP)** | **Đã chạy** — không cần build plugin |
| macOS | Chromium/Chrome/Edge headless qua CDP | Cùng code, chưa test máy thật |
| Linux | Chrome/Chromium headless qua CDP | Cùng code, chưa test máy thật |
| Android / iOS | WebView native qua Godot plugin | Adapter sẵn sàng, **chưa build plugin** |

`QBOWebRenderer` tự dò trình duyệt theo thứ tự:

1. Biến môi trường `QBO_BROWSER_PATH`
2. Google Chrome (Program Files / Program Files (x86) / LocalAppData)
3. Microsoft Edge
4. Chromium trong cache Playwright (`%LOCALAPPDATA%\ms-playwright\chromium-*`)
5. WebView2 runtime (`EdgeWebView`) — thường **không** mở được DevTools/headless

Không tìm thấy trình duyệt → `available = false`, TV phụ hiển thị thẻ trạng thái trung thực (URL + lý do), không giả lập nội dung.

Video `.ogv` (Theora) phát native bằng `VideoStreamPlayer`. YouTube phát qua trang web thật trong Chromium (chính sách nhúng chính thức của YouTube); không tải luồng, không vượt DRM, không chặn quảng cáo.

## 2. Kiến trúc

```
Lotus Browser UI (computer_screen.gd)
        │
        ├── QBOUrlGuard.validate(url)  (SSRF, scheme, allowlist)
        │
        ├── QBOBrowserFactory.create() ─► PC / Android / iOS provider (fallback)
        │
        └── QBO TVSystem.show_shared(url)
                 │
                 ├── Net.send_tv ─► server ─► mọi client
                 │
                 └── QBOWebRenderer.navigate(url)
                          │
                          ├── Chromium headless (--remote-debugging-port)
                          ├── WebSocket CDP tới target "page"
                          ├── Page.startScreencast (JPEG base64)
                          └── ImageTexture ─► TV phụ + màn hình máy tính
```

- `QBOBrowserProvider` (base): `provider_name`, `platform`, `capability`, `open`, `close`, `get_texture`, `is_open`, `external_open`.
- Provider không được báo `embedded=true` khi chưa thực sự render.
- TV state gồm: `url, title, playing, position, volume, kind, status, provider, by, updated_at`.
- Server kiểm tra quyền `tv` trước khi broadcast state **và** trước khi relay input.

### Click/cuộn đồng bộ

1. Người chơi ngắm TV phụ (ray từ camera, kể cả khi khoá chuột) → `QBOTVSystem.screen_pixel_at()` đưa tia vào không gian local của TV (TV nghiêng 16°) và trả pixel 1920×1080.
2. `click_page()` gửi `Input.dispatchMouseEvent` qua CDP và `Net.send_tv_input({type:"click", x, y})`.
3. `srv_tv_input` kiểm tra quyền rồi relay `cli_tv_input` cho các client khác (trừ người gửi).
4. Mỗi client áp cùng input lên renderer của mình → cả phòng thấy cùng trạng thái trang.

Máy tính trong bar bấm trên trang phản chiếu cũng đi qua đúng đường này.

## 3. Chi tiết CDP

- Khởi động: `--headless=new --remote-debugging-port=<port> --user-data-dir=<temp> --window-size=W,(H+140)`.
  Cộng 140 px vì headless "new" vẫn giữ thanh công cụ; nhờ vậy vùng nội dung đúng 1920×1080.
- Kết nối: `GET http://127.0.0.1:<port>/json/list` → `webSocketDebuggerUrl` của target `page`.
- **Buffer WebSocket**: `inbound_buffer_size = 16 MB`. Mặc định Godot chỉ 64 KB; frame JPEG 1080p vượt ngưỡng này sẽ làm WebSocket đóng ngay sau frame đầu.
- Bật `Page.startScreencast` (JPEG quality 78, `everyNthFrame=1`), ack từng frame bằng `Page.screencastFrameAck`.
- Input: `Input.dispatchMouseEvent` (moved/pressed/released/wheel), `Input.insertText`.
- Mỗi phiên dùng profile tạm riêng, xoá khi đóng; `taskkill /T` dọn cả cây tiến trình.

### Giới hạn đã biết

- Không có âm thanh từ trang web (`--mute-audio`); nhạc của club do DJ system phát.
- DRM (Netflix, Spotify, một số video YouTube) không phát được trong Chromium headless.
- Screencast là JPEG nên chữ nhỏ có thể hơi mờ; xem gần vẫn đọc được.
- Mỗi client chạy một Chromium riêng → tốn RAM; tắt khi rời club.

## 4. Hợp đồng native plugin (dự phòng cho mobile)

### Android — WebView

Plugin Android (Java/Kotlin) đăng ký singleton `QBOWebViewAndroid`. Dùng `WebView` trong `FrameLayout` overlay hoặc `SurfaceTexture`; trả texture nếu render offscreen. Bật JavaScript, tắt file access, chặn `file://`/`content://`, giới hạn `shouldOverrideUrlLoading` theo allowlist.

### iOS — WKWebView

Plugin iOS đăng ký singleton `QBOWebViewIOS`. Dùng `WKWebView` + `WKWebViewConfiguration` (media playback inline), chặn navigation ngoài allowlist, không lưu cookie lâu dài.

## 5. URL Guard (đã triển khai)

`game/scripts/systems/url_guard.gd`:

- Chỉ `http` / `https`; tự thêm `https://` nếu thiếu scheme.
- Chặn:
  - `localhost`, `*.localhost`, `*.local`
  - `127.0.0.0/8`, `10.0.0.0/8`, `192.168.0.0/16`, `172.16.0.0/12`, `169.254.0.0/16`, `100.64.0.0/10`
  - `0.0.0.0`, `[::1]`, `metadata.google.internal`
- Phân loại: `audio` (.mp3/.ogg/.oga/.wav), `video` (.ogv), `youtube`, `web`.
- Allowlist domain tin cậy: YouTube, Vimeo, SoundCloud, Twitch, Bilibili, Spotify, Archive.org, Wikimedia Commons.
- Domain ngoài allowlist → trang **xác nhận** trước khi mở.
- Không lưu mật khẩu, không tự điền form, không tải file thực thi.

## 6. Chính sách nội dung

- Tuân thủ YouTube Terms; không tải luồng video, không chặn quảng cáo, không vượt DRM.
- Không giả User-Agent để vượt kiểm soát truy cập.
- Không dùng để phát nội dung người lớn, bản quyền trái phép, hoặc phát trực tiếp thể thao/PPV.
- Người chơi chịu trách nhiệm về URL họ chia sẻ; chủ phòng có quyền khoá TV.

## 7. Test đã chạy

- `--tv-test=<url>`: mở URL, chờ frame đầu, lưu `tv_web.png`, bấm thử (36, 40) → `tv_web_click.png`, chụp toàn cảnh `tv_web_scene.png`.
- Đã xác nhận: YouTube trang chủ render đúng, click hamburger đóng/mở sidebar (input CDP hoạt động), frame liên tục sau khi nâng buffer.
- `--smoke`: publish YouTube URL → `kind=youtube`, `embedded=true`; WASD di chuyển 4.68 m.
- `--screenshot`: 6 ảnh QA, TV chính chạy visualizer, TV phụ hiển thị trang web.

## 8. Việc cần làm

1. Build Android plugin (Gradle) + cấu hình export; iOS plugin (Xcode) nếu cần mobile.
2. Tự khởi động lại Chromium khi CDP đóng giữa chừng (hiện báo lỗi và dừng renderer).
3. Xác nhận âm lượng/seek đồng bộ khi phát video trên trang.
4. Đo RAM/CPU khi nhiều client cùng chạy Chromium; cân nhắc giảm `maxWidth` screencast.
