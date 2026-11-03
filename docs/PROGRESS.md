# PROGRESS — QUẨY BAR ONLINE

Cập nhật: 2026-11-03
Phiên bản: 0.1.0 (nền tảng MVP)

> Tài liệu này ghi đúng trạng thái đã kiểm chứng, không đánh dấu hoàn thành cho phần chưa test.

## 1. Đã hoàn thành (có kiểm chứng)

### Phase 1 — Foundation
- [x] Cấu trúc repo `game/ server/ multiplayer/ tools/ docs/`.
- [x] Godot 4.7 project import sạch, chạy headless smoke test.
- [x] Nightclub The Chrome Lotus dựng procedural: sảnh, sàn nhảy LED, sân khấu DJ với TV chính 20:9 (visualizer) + TV phụ 16:9 (màn web), bar, VIP lounge, ban công, hành lang, WC, phòng điều khiển ánh sáng, phòng VIP, khu máy tính; PBR material + texture procedural.
- [x] Player controller FP/TPP, joystick mobile, animation procedural (idle/walk/run/jump/sit/dance/dj/drink/computer).
- [x] Interaction component dùng chung (ghế, cửa, thang máy, bar, computer, TV, DJ booth, lighting console).
- [x] UI theme dark/glass/neon, splash, login/register, main menu, room browser, create room, character select, settings, friends, HUD, computer, DJ, lighting.

### Phase 2 — Multiplayer
- [x] Dedicated server Godot headless (`--server`).
- [x] ENet join bằng game ticket, server authority vị trí, correction, chat, interaction, roster.
- [x] Đồng bộ animation, seating, DJ state, lighting, TV state.
- [x] Reconnect 3 lần với ticket mới.
- [x] **Kiểm chứng 2 tiến trình**: server + client smoke test pass (xem mục 5).

### Phase 3 — Backend
- [x] Next.js App Router 16, TypeScript strict, Prisma 6.19, MySQL schema.
- [x] Auth: register/login/logout/refresh rotation + reuse detection, JWT jose, bcrypt 12, cookie httpOnly.
- [x] Users/me, public profile, PATCH profile.
- [x] Rooms: list/search/filter, create, detail, join (mật khẩu/sức chứa), leave (chuyển owner), update, delete.
- [x] Game ticket 5 phút, single-use, verify bằng `X-Game-Server-Secret`; registry server + heartbeat.
- [x] Friends, inventory, reports, moderation cơ bản.
- [x] Zod validation, rate limiting (Redis tùy chọn + in-memory), JSON logging, error envelope.
- [x] `prisma validate` + `prisma generate` + `tsc --noEmit` + `next build` **pass**.

### Phase 5 (một phần) — Nightclub systems
- [x] DJ playlist, play/pause/next/prev/volume/seek, beat detection bằng spectrum analyzer, nhạc demo tổng hợp gốc, tải MP3/OGG/WAV từ URL.
- [x] 8 preset ánh sáng + intensity/speed/beat sync, LED động, moving head, strobe, đồng bộ server.
- [x] TV state sync + phát `.ogv` native; máy tính có browser UI, history, URL guard, gửi lên TV.
- [x] TV phụ render **web thật** bằng Chromium/Chrome/Edge headless qua DevTools Protocol (JPEG screencast), không cần build plugin CEF/WebView2.
- [x] Click/cuộn chuột trực tiếp trên TV phụ trong club; input được relay qua server để mọi client thấy cùng trạng thái trang.
- [x] Máy tính trong bar phản chiếu đúng trang của TV phụ và bấm được trên bản sao đó.
- [x] TV chính giữa sân khấu chạy visualizer động (logo, vòng spectrum, EQ bars, now playing, đồng hồ).

### Phase 6 (một phần) — Computer & TV
- [x] Desktop UI, thanh địa chỉ, back/forward/reload/home, tab TV, info.
- [x] `QBOUrlGuard`: chỉ http/https, chặn localhost/private/metadata (SSRF), allowlist + xác nhận domain lạ, phân loại YouTube/audio/video/web.
- [x] BrowserProvider abstraction PC/Android/iOS, báo đúng năng lực, fallback mở ngoài.
- [x] `QBOWebRenderer`: dò Chrome/Edge/Chromium/Playwright, khởi động headless, kết nối CDP, nhận frame JPEG → `ImageTexture`, gửi chuột/bàn phím.
- [x] URL mặc định của TV phụ là YouTube; bỏ thanh địa chỉ trên màn hình TV (trang phủ kín 16:9).

## 2. Đang thực hiện / đã có khung nhưng chưa kiểm chứng

- [ ] **Visual QA**: đã có chế độ `--screenshot` render ảnh thật; đã tinh chỉnh sân khấu 2 TV, tiếp tục đánh giá ánh sáng/vật liệu.
- [x] Export preset Windows/Android/iOS trong `game/export_presets.cfg`; workflow GitHub Actions build Windows `.exe`, Android **APK release** và iOS IPA không ký.
- [ ] Android export: đã có workflow CI; chưa chạy thử trên thiết bị/kiểm tra hiệu năng.
- [ ] iOS export: đã có workflow CI tạo IPA không ký; chưa cài trên thiết bị thật (cần ký lại).
- [ ] Native WebView plugin cho mobile: adapter có, plugin chưa build (PC đã dùng CDP nên không cần).
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
game/scripts/systems/{lighting_controller,dj_system,tv_system,web_renderer,demo_track,url_guard}.gd
game/scripts/browser/{browser_provider,pc_browser_provider,android_browser_provider,ios_browser_provider,browser_factory}.gd
game/scripts/ui/{ui_theme,ui_root,splash_screen,login_screen,main_menu,room_browser,create_room,character_select,settings_screen,friends_panel,hud,virtual_joystick,computer_screen,dj_panel,lighting_panel}.gd
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

Tài liệu: README, ARCHITECTURE, API, MULTIPLAYER, BUILD, BROWSER, ASSET_LICENSES, PROGRESS.

## 4. Lỗi còn tồn tại / rủi ro

1. **Web trên mobile** chưa render (PC đã render thật bằng Chromium headless qua CDP). Android/iOS cần native WebView plugin.
2. **Âm thanh trang web** bị tắt (`--mute-audio`); nhạc club do DJ system phát.
3. **DRM** (Netflix/Spotify/một số video YouTube) không phát được trong Chromium headless — giới hạn kỹ thuật, không vượt.
4. **Voice chat** chưa có; UI chưa có nút voice để tránh nút chết.
5. **Mobile build** chưa export; UI mobile mới test logic, chưa test cảm ứng thật.
6. **Backend runtime** chưa test với MySQL thật; chỉ typecheck/build/validate. Health API sẽ báo `database: down` nếu chưa có MySQL.
7. **Reconnect** cần backend cấp ticket mới; chưa test đứt mạng thật.
8. **Anti-cheat** mới ở mức displacement; chưa simulate physics server-side.
9. **Animation** là procedural, chưa dùng animation clip/Mixamo; chất lượng thấp hơn asset authored.
10. **Nhạc DJ** phụ thuộc codec: Godot hỗ trợ MP3/OGG/WAV; YouTube không phải URL audio hợp lệ.
11. **CDP renderer** chưa tự khởi động lại Chromium nếu WebSocket đóng giữa chừng; hiện báo lỗi và dừng renderer.

## 5. Lệnh kiểm thử đã chạy và kết quả

| Lệnh | Kết quả |
| --- | --- |
| `Godot --headless --path game --editor --quit` | Import project OK, class cache OK |
| `Godot --headless --path game --fixed-fps 60 -- --smoke` | **PASS** — interactables=27, players=1, 6 moving heads, demo track 12s/32kHz, TV kind=youtube embedded=false, di chuyển OK, ngồi/đứng OK |
| `Godot --headless --path game -- --server --port=7001 --allow-unverified-tickets` + `--net-smoke=7001` | **PASS** — players=1, roster=1, connected=true, di chuyển OK, interaction server broadcast OK |
| `prisma validate` | **PASS** |
| `prisma generate` | **PASS** (Prisma 6.19.3) |
| `tsc --noEmit` | **PASS** |
| `next build` | Xem cập nhật bên dưới |
| `--screenshot` | Xem mục 6 |

## 6. Ảnh render kiểm tra

Chạy:

```bash
Godot --path game -- --screenshot
```

Ảnh lưu tại `game/export/screenshots/` (01_entrance, 02_dancefloor, 03_stage, 04_bar, 05_vip, 06_balcony). Đây là render thật từ Godot, không phải mockup.

## 7. Công việc tiếp theo (ưu tiên)

1. Đánh giá/tinh chỉnh ảnh render: độ sáng, màu, bố cục, vật liệu.
2. Cài MySQL/Docker, chạy migration + test end-to-end register → create room → join → verify ticket.
3. Build native WebView/CEF cho Windows + Android, kiểm thử YouTube embed trên thiết bị thật.
4. Voice chat WebRTC (signaling qua Next.js route + SFU).
5. Export Android thử trên thiết bị; tinh chỉnh mobile UI/perf.
6. ~~Bổ sung animation clip cho nhân vật hoặc asset nhân vật có license phù hợp.~~ Đã xong: model GLB "Low Poly Girl" (CC-BY 4.0, 89 xương, 35 animation) + pipeline tự nạp/chuẩn hóa.
7. Test 2 máy thật qua Internet với dedicated server + domain/TLS.

## 8. Ghi chú phát triển

- Không dùng Express/NestJS; mọi API trong Next.js App Router.
- Không dùng HTTP cho đồng bộ vị trí.
- Không có secret trong repo; `server/.env.example` chỉ chứa placeholder.
- Asset Internet duy nhất: model nhân vật "Low Poly Girl" (CC-BY 4.0) — bắt buộc giữ dòng ghi công trong `game/assets/models/characters/README.md` và màn hình credits khi phát hành; phần còn lại là procedural gốc (xem ASSET_LICENSES.md).
