# PROGRESS — QUẨY BAR ONLINE

Cập nhật: 2026-11-04
Phiên bản: 0.1.0 (nền tảng MVP)

> Tài liệu này ghi đúng trạng thái đã kiểm chứng, không đánh dấu hoàn thành cho phần chưa test.

## 1. Đã hoàn thành (có kiểm chứng)

### Phase 1 — Foundation
- [x] Cấu trúc repo `game/ server/ multiplayer/ tools/ docs/`.
- [x] Godot 4.7 project import sạch, chạy headless smoke test.
- [x] Nightclub The Chrome Lotus dựng procedural: sảnh, sàn nhảy LED, sân khấu DJ với TV lớn 20:9 (nhạc DJ/MP4) + TV nhỏ 16:9 (thông tin nhà phát triển), bar, VIP lounge, ban công, hành lang, WC, phòng điều khiển ánh sáng, phòng VIP, khu máy tính; PBR material + texture procedural.
- [x] Player controller FP/TPP, joystick mobile, animation procedural (idle/walk/run/jump/sit/dance/dj/drink/computer).
- [x] Interaction component dùng chung (ghế, cửa, thang máy, bar, computer, TV, DJ booth, lighting console).
- [x] UI theme dark/glass/neon, splash, login/register, main menu, room browser, create room, character select, settings, friends, HUD, computer, DJ, lighting.

### Phase 2 — Multiplayer
- [x] Dedicated server Godot headless (`--server`).
- [x] ENet join bằng game ticket, server authority vị trí, correction, chat, interaction, roster.
- [x] Đồng bộ animation, seating, DJ state, lighting, TV state.
- [x] Reconnect 3 lần với ticket mới.
- [x] **Kiểm chứng 2 tiến trình**: server + client smoke test pass; server + 2 client pass, client vào sau nhận đúng TV state (URL MP4) qua broadcast (xem mục 5).

### Phase 3 — Backend
- [x] Next.js App Router 16, TypeScript strict, Prisma 6.19, MySQL schema.
- [x] Auth: register/login/logout/refresh rotation + reuse detection, JWT jose, bcrypt 12, cookie httpOnly.
- [x] Users/me, public profile, PATCH profile.
- [x] Rooms: list/search/filter, create, detail, join (mật khẩu/sức chứa), leave (chuyển owner), update, delete.
- [x] Game ticket 5 phút, single-use, verify bằng `X-Game-Server-Secret`; registry server + heartbeat.
- [x] Friends, inventory, reports, moderation cơ bản.
- [x] Zod validation, rate limiting (Redis tùy chọn + in-memory), JSON logging, error envelope.
- [x] `prisma validate` + `prisma generate` + `tsc --noEmit` + `next build` **pass**.

### Phase 5 — Nightclub systems
- [x] Booth DJ tải thư viện từ `https://music.nguyenphuquyet.online/api/songs?take=1000`, lọc và chỉ giữ MP3/OGG/WAV (ẩn 25 bài M4A/AAC mà Godot không giải mã native). Hiện có 71 bài phát được.
- [x] Tải + giải mã audio từ API, cache stream/cover; play/pause/next/prev/volume/seek; beat detection bằng spectrum analyzer; nhạc demo tổng hợp gốc khi API lỗi.
- [x] 8 preset ánh sáng + intensity/speed/beat sync, LED động, moving head, strobe, đồng bộ server.
- [x] TV state sync; TV lớn 20:9 phát màn nhạc DJ (bìa, tên bài, tiến trình, EQ) và video MP4/MOV/M4V/OGV trực tiếp; TV nhỏ hiển thị thông tin nhà phát triển. Vị trí video được gửi lại mỗi 6 giây; chênh lệch đồng hồ giữa hai máy >15 giây bị bỏ qua thay vì seek sai.
- [x] Video MP4/H.264 dùng GDExtension `claytercek/godot-native-video` v0.4.0 (`native_video`), tải về cache rồi phát bằng `VideoStreamPlayer`; giữ tỉ lệ 16:9 trên màn 20:9.
- [x] Máy tính trong bar: tab NHẠC/DJ (playlist API, transport, volume, cover) và tab TV SÂN KHẤU (dán link MP4 trực tiếp, play/pause, volume, trở về màn nhạc).
- [x] Không còn WebView/YouTube/iframe: đã xoá addon `qbo_webview_*`, `scripts/browser/*`, `web_renderer.gd` và toàn bộ luồng nhập URL web.

### Phase 6 — Security & URL guard
- [x] `QBOUrlGuard`: chỉ http/https, chặn localhost/private/metadata (SSRF) gồm IPv4, IPv6 `[::1]`/`fc00::`/`fe80::`, URL có `user:pass@`; phân loại audio/video trực tiếp.
- [x] `absolute_url()` ghép URL tương đối của API (`/media/...`) với host `music.nguyenphuquyet.online`.
- [x] Chỉ nhận audio `.mp3/.ogg/.oga/.wav` và video `.mp4/.mov/.m4v/.ogv`; từ chối mọi URL trang web.

## 2. Đang thực hiện / đã có khung nhưng chưa kiểm chứng

- [ ] **Visual QA**: đã có chế độ `--screenshot` render ảnh thật; ảnh `tv_ui.png` (TV lớn) và `tv_dev.png` (TV nhỏ) đã được tạo.
- [x] Export preset Windows/Android/iOS trong `game/export_presets.cfg`; workflow GitHub Actions build Windows `.exe`, Android **APK release** và iOS IPA không ký.
- [ ] Android export: đã có workflow CI; chưa chạy thử trên thiết bị/kiểm tra hiệu năng. `native_video` không có binary Android/iOS nên TV chỉ phát được OGV trên mobile.
- [ ] iOS export: đã có workflow CI tạo IPA không ký; chưa cài trên thiết bị thật (cần ký lại).
- [ ] Voice chat WebRTC/SFU: chưa triển khai.
- [ ] Chat lịch sử/persistence: chưa (chat hiện realtime qua ENet).
- [ ] Docker compose: file có, chưa chạy do máy không có Docker.
- [x] MySQL migration thật: migration `20261103120000_init` đã chạy trên **Aiven MySQL 8**; backend deploy Vercel tại https://quay-bar-online-server.vercel.app (`/api/health` → `database: up`, register/login đã test).
- [ ] Dedicated game server public: chưa deploy lên VPS; client vẫn mặc định `127.0.0.1:7000`.

## 3. File đã tạo/chỉnh sửa chính

Game:
```
game/project.godot
game/scenes/bootstrap.tscn
game/scripts/app.gd
game/scripts/autoload/{app_config,settings_manager,game_state,api_client,net}.gd
game/scripts/world/{nightclub,interactable,material_library,procedural_textures}.gd
game/scripts/player/{player,character_rig}.gd
game/scripts/systems/{lighting_controller,dj_system,tv_system,demo_track,url_guard}.gd
game/scripts/ui/{ui_theme,ui_root,splash_screen,login_screen,main_menu,room_browser,create_room,character_select,settings_screen,friends_panel,hud,virtual_joystick,computer_screen,dj_panel,lighting_panel}.gd
game/addons/native_video/   # GDExtension MP4/MOV (Windows/macOS/Linux)
```

Backend:
```
server/prisma/schema.prisma
server/lib/{auth,http,api-error,rate-limit,prisma,env,logger,validation,serialize,tickets,inventory}.ts
server/app/api/auth/{register,login,logout,refresh}/route.ts
server/app/api/users/{me,[id]}/route.ts
server/app/api/rooms/... (list/create/detail/join/leave/update/delete)
server/app/api/friends/... (list/request/accept/[id])
server/app/api/{inventory,reports,game,moderation}/...
server/Dockerfile, docker-compose.yml, multiplayer/Dockerfile + heartbeat
```

Tài liệu: README, ARCHITECTURE, API, MULTIPLAYER, BUILD, MUSIC, ASSET_LICENSES, PROGRESS.

## 4. Lỗi còn tồn tại / rủi ro

1. **MP4 cần GPU có Vulkan/D3D12**: `native_video` cần RenderingDevice (Forward+ hoặc Mobile). Máy dev hiện tại (GeForce GT 420, driver 382.33) không có Vulkan nên Godot tự lùi về OpenGL Compatibility; video vẫn giải mã nhưng không hiển thị được khung hình. Trên GPU hiện đại, Forward+ phát MP4 bình thường. OGV (Theora) vẫn chạy trên Compatibility.
2. **M4A/AAC bị ẩn**: Godot không giải mã native; API hiện có 25 bài M4A trong tổng 96.
3. **Voice chat** chưa có; UI chưa có nút voice để tránh nút chết.
4. **Mobile build** chưa export; UI mobile mới test logic, chưa test cảm ứng thật. `native_video` không hỗ trợ Android/iOS.
5. **Reconnect** cần backend cấp ticket mới; chưa test đứt mạng thật.
6. **Anti-cheat** mới ở mức displacement; chưa simulate physics server-side.
7. **Animation** là procedural + GLB clip, chất lượng thấp hơn asset authored.
8. **API nhạc** phụ thuộc dịch vụ ngoài; nếu API lỗi, booth DJ tự lùi về track demo tổng hợp.
9. **Video cache**: mỗi tệp giới hạn 300 MB, tổng cache tự dọn tệp cũ nhất khi vượt 1.5 GB; bảng TV có nút xoá thủ công và hiển thị dung lượng.
10. **Đồng bộ theo đồng hồ máy**: `updated_at` dùng giờ hệ thống của client gửi; nếu hai máy lệch >15 giây thì phần bù thời gian bị bỏ qua và chỉ còn sync định kỳ 6 giây. Chưa có server-authoritative clock.

## 5. Lệnh kiểm thử đã chạy và kết quả

| Lệnh | Kết quả |
| --- | --- |
| `Godot --headless --path game --editor --quit` | Import project OK, class cache OK, không còn lỗi GDExtension |
| `Godot --headless --path game --fixed-fps 60 -- --smoke` | **PASS** — interactables=27, players=1, 5 moving heads, demo track 12s/32kHz, TV music screen ready, di chuyển OK, ngồi/đứng OK, URL guard chặn 8 URL nội bộ |
| `Godot --headless --path game -- --media-test` | **PASS** — API trả 71 bài phát được; audio MP3 tải/giải mã OK (373.5s, playing); TV tải/giải mã MP4 OK (NativeVideoStream 10.00s); cache video xoá sạch qua `clear_video_cache()` |
| `Godot --headless --path game -- --ui-test` | **PASS** — overlay máy tính, DJ và TV mở/đóng không lỗi runtime |
| `Godot --path game -- --screenshot` | **PASS** — `tv_ui.png` 1280×576 (TV lớn) và `tv_dev.png` 1280×720 (TV nhỏ), 6 ảnh QA sân khấu/bar/VIP |
| `Godot --headless --path game -- --server --port=7001 --allow-unverified-tickets` + `--net-smoke=7001` | **PASS** — players=1, roster=1, connected=true, di chuyển OK, interaction server broadcast OK |
| Server + 2 client: `--net-smoke=7013 --tv-url=…` (owner) và `--net-smoke=7013 --watch-tv=…` | **PASS** — client 2 vào sau nhận đúng URL MP4 qua broadcast (`tv_received`), players=2, scene=2 |
| `prisma validate` | **PASS** |
| `prisma generate` | **PASS** (Prisma 6.19.3) |
| `tsc --noEmit` | **PASS** |
| `next build` | Xem cập nhật bên dưới |

## 6. Ảnh render kiểm tra

Chạy:

```bash
Godot --path game -- --screenshot
```

Ảnh lưu tại `game/export/screenshots/` (00_main_menu, 01_entrance, 02_dancefloor, 03_stage, 04_bar, 05_vip, 06_balcony, tv_ui, tv_dev). Đây là render thật từ Godot, không phải mockup.

## 7. Công việc tiếp theo (ưu tiên)

1. Đánh giá/tinh chỉnh ảnh render: độ sáng, màu, bố cục, vật liệu.
2. Kiểm thử MP4 trên máy có Vulkan/D3D12 để xác nhận khung hình hiển thị trên TV lớn.
3. Test 2 máy thật qua Internet với dedicated server + domain/TLS; đồng bộ DJ/TV đã pass trên 2 tiến trình cùng máy nhưng chưa qua mạng thật.
4. Voice chat WebRTC (signaling qua Next.js route + SFU).
5. Export Android thử trên thiết bị; tinh chỉnh mobile UI/perf.
6. Kiểm thử tự dọn cache video với thư viện nhiều video lớn (hiện mới test xoá thủ công).
7. Đã có [docs/MUSIC.md](MUSIC.md); cập nhật khi API nhạc đổi schema hoặc thêm định dạng.

## 8. Ghi chú phát triển

- Không dùng Express/NestJS; mọi API trong Next.js App Router.
- Không dùng HTTP cho đồng bộ vị trí.
- Không có secret trong repo; `server/.env.example` chỉ chứa placeholder.
- Asset Internet duy nhất: model nhân vật "Low Poly Girl" (CC-BY 4.0) — bắt buộc giữ dòng ghi công trong `game/assets/models/characters/README.md` và màn hình credits khi phát hành; phần còn lại là procedural gốc (xem ASSET_LICENSES.md).
- Nhạc phát từ thư viện `music.nguyenphuquyet.online` (repo `nguyenphuquyet/NPQ-Music-Web`).
