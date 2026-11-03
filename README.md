# QUẨY BAR ONLINE

Game nightclub xã hội 3D multiplayer, đa nền tảng (Windows / Android / iOS). Người chơi tạo phòng, gặp bạn bè trong câu lạc bộ **The Chrome Lotus**, khiêu vũ, chat, lên booth DJ, điều khiển ánh sáng, dùng máy tính trong bar và chia sẻ nội dung lên màn hình LED sân khấu.

> Trạng thái: **nền tảng MVP đang chạy được** — client Godot 4.7, dedicated server ENet authoritative, backend Next.js + Prisma/MySQL. Build iOS **không ký** được tạo tự động bằng GitHub Actions (macOS runner); phần browser nhúng native và voice chat WebRTC chưa được kiểm chứng trên thiết bị thật. Xem [PROGRESS.md](PROGRESS.md) để biết chính xác đã làm và chưa làm.

## Thành phần

| Thành phần | Công nghệ | Thư mục |
| --- | --- | --- |
| Game client | Godot 4.7, GDScript, Forward+ / GL Compatibility | [`game/`](game) |
| Dedicated game server | Cùng code Godot, chạy headless `--server` | [`game/`](game) + [`multiplayer/`](multiplayer) |
| Backend web/API | Next.js 16 App Router, TypeScript, Prisma, MySQL 8, Redis (tùy chọn) | [`server/`](server) |
| Tài liệu | Kiến trúc, API, multiplayer, build, browser, license | [`docs/`](docs) |

Backend production đang chạy tại **https://quay-bar-online-server.vercel.app** (health: `/api/health`). Hướng dẫn deploy/DB: [docs/DEPLOY_VERCEL.md](docs/DEPLOY_VERCEL.md).

Không dùng Express/NestJS. Không có server Node riêng cho gameplay: đồng bộ vị trí/animation/interaction đi qua ENet, backend Next.js chỉ cấp tài khoản, phòng và game ticket.

## Chạy nhanh

### 1. Game client (PC)

Yêu cầu Godot **4.7.x**. Binary không được commit vào repo.

```bash
# Mở bằng Godot editor:
godot --path game --editor

# Hoặc chạy trực tiếp:
godot --path game
```

Trong menu chọn **Chơi solo / offline** để vào club ngay mà không cần backend, hoặc đăng nhập để tạo/tham gia phòng online.

### 2. Backend

```bash
cd server
cp .env.example .env        # điền DATABASE_URL, AUTH_SECRET, GAME_SERVER_SECRET
npm install
npx prisma migrate deploy   # áp migration có sẵn trong prisma/migrations
npm run dev                 # http://127.0.0.1:3000
```

MySQL 8 có thể chạy bằng Docker:

```bash
docker compose up -d mysql redis
```

Muốn đưa backend lên Internet: xem [docs/DEPLOY_VERCEL.md](docs/DEPLOY_VERCEL.md) (Next.js API chạy được trên Vercel; dedicated server Godot ENet/UDP thì không).

### 3. Dedicated game server

```bash
# Server headless, lắng nghe UDP 7000
godot --headless --path game -- --server --port=7000

# Cần secret khớp backend để xác minh game ticket
QBO_GAME_SECRET="..." QBO_API_URL="http://127.0.0.1:3000" godot --headless --path game -- --server
```

Hoặc dùng `docker compose up game-server`. Chi tiết: [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md).

### 4. Build tự động (Windows / Android / iOS)

Ba workflow GitHub Actions dùng chung `game/export_presets.cfg`:

| Nền tảng | Workflow | Artifact |
| --- | --- | --- |
| Windows x86_64 | [`.github/workflows/windows.yml`](.github/workflows/windows.yml) | `QuayBarOnline-windows-x86_64.zip` (1 file `.exe` đã nhúng PCK) |
| Android (arm64, release) | [`.github/workflows/android.yml`](.github/workflows/android.yml) | `QuayBarOnline-android-release-apk` (APK release, ký bằng keystore tạo trong CI hoặc secret) |
| iOS (IPA không ký) | [`.github/workflows/ios-unsigned.yml`](.github/workflows/ios-unsigned.yml) | `QuayBarOnline-unsigned-ipa` |

Chạy thủ công: **Actions → chọn workflow → Run workflow**. Các workflow cũng tự chạy khi push lên `main` nếu có thay đổi trong `game/`.

> iOS IPA **không có chữ ký Apple**, nên không cài trực tiếp được trên iPhone thường. Dùng để lưu trữ, kiểm tra cấu trúc app, hoặc ký lại bằng Sideloadly / AltStore / tài khoản developer của bạn. Chi tiết: [docs/BUILD.md](docs/BUILD.md#export-ios).

## Điều khiển

| Hành động | PC | Mobile |
| --- | --- | --- |
| Di chuyển | WASD / phím mũi tên | Joystick ảo trái |
| Xoay camera | Chuột | Vuốt nửa phải màn hình |
| Chạy | Shift (toggle) | Nút Chạy |
| Nhảy | Space | Nút Nhảy |
| Tương tác | E | Nút Tương tác |
| Đổi camera FPS/TPP | V | Nút Camera |
| Chat | Enter | Nút Chat |
| Menu | Esc | Nút Menu trên HUD |
| Khiêu vũ / emote | R / F | Nút Khiêu vũ |

## Tính năng đã có trong code

- Nightclub **The Chrome Lotus** dựng procedural: sảnh, sàn nhảy LED, sân khấu DJ + màn LED 26m, bar champagne, VIP lounge, ban công, nhà vệ sinh, hành lang, phòng điều khiển ánh sáng, phòng VIP riêng, khu máy tính.
- Nhân vật 3D GLB có **89 xương, 35 animation** (idle/walk/run/jump/sit/emote…), tự chuẩn hóa chiều cao và khớp clip theo tên; chuyển first/third person kiểu GTA V. Model "Low Poly Girl" (CC-BY 4.0) — xem [game/assets/models/characters/README.md](game/assets/models/characters/README.md).
- Interaction component tái sử dụng: ghế, cửa, thang máy, bar, DJ booth, lighting console, máy tính, TV.
- Multiplayer ENet dedicated server: server authority cho di chuyển (kiểm tra tốc độ), quyền DJ/đèn/TV, chat, interaction, reconnect.
- DJ: playlist, play/pause/next/prev, volume, beat detection từ spectrum analyzer, nhạc demo **tổng hợp gốc** (124 BPM) + tải MP3/OGG/WAV từ URL hợp lệ.
- Ánh sáng: 8 preset (Chill, Lounge, Party, EDM, Cyberpunk, Chinese Neon, VIP, Blackout), cường độ/tốc độ/beat sync, đồng bộ qua server.
- TV/LED: đồng bộ URL, play/pause, thời gian, âm lượng; phát native video `.ogv`; hiển thị trạng thái trung thực khi thiếu WebView nhúng.
- Máy tính trong bar: desktop UI, thanh địa chỉ, back/forward/reload/home, history, allowlist/denylist, chặn SSRF, chuyển URL lên TV.
- Ứng dụng backend: đăng ký/đăng nhập JWT + refresh rotation, hồ sơ, phòng, bạn bè, inventory, report, game ticket, registry server, moderation cơ bản, rate limit, validation zod, logging JSON.
- UI PC/mobile riêng, theme dark/glass/neon, joystick và nút cảm ứng.

## Cấu trúc repository

```
game/          Godot client + dedicated server mode
server/        Next.js App Router API + Prisma/MySQL
multiplayer/   Dockerfile & công cụ chạy dedicated server
tools/         Script kiểm tra/asset import nội bộ
docs/          ARCHITECTURE, API, MULTIPLAYER, BUILD, BROWSER, ASSET_LICENSES
```

## Kiểm thử đã chạy

```bash
# Godot: parse/import project và smoke test offline (world, player, DJ, TV, seat)
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game --fixed-fps 60 -- --smoke

# Godot: 2 tiến trình — dedicated server + client, kiểm tra authority, spawn, interaction
godot --headless --path game -- --server --port=7001 --allow-unverified-tickets
godot --headless --path game --fixed-fps 60 -- --net-smoke=7001

# Backend
cd server && npx prisma validate && npx prisma generate && npm run typecheck && npm run build
```

Kết quả và giới hạn: xem [PROGRESS.md](PROGRESS.md).

## Tài liệu

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/API.md](docs/API.md)
- [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md)
- [docs/BUILD.md](docs/BUILD.md)
- [docs/BROWSER.md](docs/BROWSER.md)
- [docs/ASSET_LICENSES.md](docs/ASSET_LICENSES.md)

## Giấy phép tài nguyên

Hầu hết mô hình, vật liệu, texture và nhạc demo là **tài sản gốc được tạo procedural trong dự án**. Ngoại lệ: model nhân vật **"Low Poly Girl"** của `manoeldarochadeoliveira` trên Sketchfab, giấy phép **CC-BY 4.0** — bắt buộc giữ dòng ghi công. Chi tiết và quy tắc khi thêm asset bên thứ ba: [docs/ASSET_LICENSES.md](docs/ASSET_LICENSES.md).
