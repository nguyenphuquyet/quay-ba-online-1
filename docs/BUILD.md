# BUILD & DEPLOY — QUẨY BAR ONLINE

## 0. Phiên bản đã kiểm tra

| Thành phần | Phiên bản | Trạng thái trong môi trường này |
| --- | --- | --- |
| Godot | 4.7.2 stable | Đã import project, parse/compile, smoke test headless |
| Node.js | 24.22.0 | Đã cài dependency, chạy Prisma/Next build |
| Next.js | 16.4.4 | Xem PROGRESS cho kết quả build |
| MySQL 8 | — | Không có trong môi trường, chưa chạy migration thật |
| Android SDK / Xcode | — | Android SDK không có; iOS build chạy trên GitHub Actions macOS runner, chưa chạy thử trên thiết bị |

## 1. Godot client (PC)

Yêu cầu: Godot 4.7.x, export templates tương ứng (Editor → Manage Export Templates).

```bash
# Mở editor
godot --path game --editor

# Chạy thử
godot --path game

# Headless smoke test (không cần UI)
godot --headless --path game --fixed-fps 60 -- --smoke
```

### Cấu hình môi trường runtime

| Biến | Mặc định | Ý nghĩa |
| --- | --- | --- |
| `QBO_API_URL` | `http://127.0.0.1:3000` | Backend Next.js |
| `QBO_GAME_HOST` | `127.0.0.1` | Địa chỉ dedicated server |
| `QBO_GAME_PORT` | `7000` | Cổng ENet |
| `QBO_GAME_SECRET` | — | Secret xác minh ticket (dedicated server) |
| `QBO_ALLOW_UNVERIFIED_TICKETS` | `0` | Chỉ dùng khi test |

Có thể truyền bằng CLI: `--api=…`, `--host=…`, `--port=…`.

### Export Windows

1. Project → Export → Add… → Windows Desktop.
2. Export path: `game/export/builds/windows/QuayBarOnline.exe`.
3. Embed PCK, chọn architecture x86_64.
4. Export Project.

Workflow tự động: `.github/workflows/windows.yml` (Windows runner) tạo artifact `QuayBarOnline-windows-x86_64.zip`, bên trong là một file `.exe` duy nhất đã nhúng PCK.

### Export Android

1. Cài Android SDK + JDK 17; cấu hình Editor Settings → Export → Android.
2. Project → Install Android Build Template (chỉ cần khi bật Gradle build).
3. Export preset Android:
   - Renderer: **GL Compatibility** (`renderer/rendering_method.mobile="gl_compatibility"` đã cấu hình).
   - Texture compression: ETC2/ASTC.
   - Architectures: arm64-v8a (+ armeabi-v7a nếu cần).
   - Permissions: INTERNET bắt buộc.
4. Export APK/AAB.

Workflow tự động: `.github/workflows/android.yml` (Ubuntu + JDK 17 + Android SDK 36) export **APK release**:

- Nếu có secret `ANDROID_KEYSTORE_BASE64` (+ `ANDROID_KEYSTORE_USER`, `ANDROID_KEYSTORE_PASSWORD`), workflow dùng keystore cố định của bạn.
- Nếu không, workflow tạo keystore release tạm và ký APK bằng key đó (cài được, nhưng không thể cập nhật đè lên bản build bằng key khác).
- Artifact: `QuayBarOnline-android-release-apk` chứa `QuayBarOnline-release.apk`.

Keystore không được commit. Muốn phát hành cập nhật lâu dài, tạo keystore và lưu base64 vào GitHub Secrets:

```bash
keytool -genkeypair -v -keystore release.keystore -storepass '...' \
  -alias quaybar -keypass '...' -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Quay Bar Online,O=Nguyen Phu Quyet,C=VN"
base64 -w0 release.keystore   # dán vào secret ANDROID_KEYSTORE_BASE64
```

**Chưa kiểm chứng**: môi trường hiện tại không có Android SDK/thiết bị, nên chưa thể xác nhận build và hiệu năng thực tế.

### Export iOS

Preset đã có sẵn trong `game/export_presets.cfg` (tên `iOS`):

- Bundle id: `com.nguyenphuquyet.quaybaronline`
- Min iOS: 15.0, arm64, iPhone + iPad
- `application/export_project_only=true` — chỉ xuất Xcode project để CI tự build
- Team id trong preset chỉ là placeholder (`ABCDE12345`); build không dùng signing
- `application/code_sign_identity_*="-"` để Godot ad-hoc ký các `.dylib` nhúng, tránh lỗi `codesign` khi không có chứng chỉ Apple. IPA cuối vẫn **không được ký**.

#### Build tự động trên GitHub Actions (IPA không ký)

Workflow `.github/workflows/ios-unsigned.yml`:

1. Tải Godot `4.7.2-stable` bản macOS + export templates.
2. `godot --headless --path game --import` để import asset (kể cả GLB nhân vật).
3. `godot --headless --path game --export-release "iOS" build/ios/QuayBarOnline.xcodeproj`.
4. `xcodebuild` với `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, `CODE_SIGN_IDENTITY=""`, `DEVELOPMENT_TEAM=""`.
5. Đóng gói `Payload/QuayBarOnline.app` thành `QuayBarOnline-unsigned.ipa` và upload artifact.

Chạy: **Actions → Build unsigned iOS IPA → Run workflow** (hoặc push lên `main` khi có thay đổi trong `game/`).

Tải artifact `QuayBarOnline-unsigned-ipa`, giải nén được file IPA.

**Giới hạn quan trọng:** IPA không có chữ ký Apple nên iOS từ chối cài trên máy thường. Muốn cài, phải ký lại bằng:

- Sideloadly / AltStore / SideStore với Apple ID cá nhân, hoặc
- Chứng chỉ Apple Developer + provisioning profile, hoặc
- Thiết bị jailbreak / TrollStore.

Ngoài ra phần TV/YouTube dùng Chromium + CDP chỉ chạy trên desktop; trên iOS màn hình TV sẽ báo thiếu backend browser thay vì phát video.

#### Build thủ công trên macOS

```bash
# Cần Godot 4.7.2 + export templates
godot --headless --path game --import
godot --headless --path game --export-release "iOS" build/ios/QuayBarOnline.xcodeproj

cd game/build/ios
xcodebuild -project QuayBarOnline.xcodeproj -scheme QuayBarOnline \
  -configuration Release -sdk iphoneos -destination "generic/platform=iOS" \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" build

mkdir -p package/Payload
cp -R DerivedData/Build/Products/Release-iphoneos/QuayBarOnline.app package/Payload/
cd package && zip -qry QuayBarOnline-unsigned.ipa Payload
```

### Dedicated server build

Cách 1 — chạy trực tiếp bằng Godot headless (khuyến nghị cho dev):

```bash
godot --headless --path game -- --server --port=7000
```

Cách 2 — export Linux headless:

1. Export preset Linux/X11, tắt cửa sổ (dùng `--headless` khi chạy).
2. Trên server: `./QuayBarOnlineServer --headless -- --server --port=7000`.
3. Docker: dùng `multiplayer/Dockerfile`.

### Cấu hình chất lượng

Preset nằm trong `SettingsManager.PRESETS` (low/medium/high/ultra): scale 3D, MSAA, shadow atlas, glow/SSAO/SSR/fog. Người chơi đổi trong Cài đặt. Mobile mặc định medium/low theo số core.

## 2. Backend Next.js

```bash
cd server
cp .env.example .env
npm install
npx prisma generate
npx prisma migrate dev --name init     # cần MySQL 8
npm run dev                            # port 3000
```

Production:

```bash
npm run build
npm run start
# hoặc
docker compose up -d server
```

### Biến môi trường

Xem `server/.env.example`. Bắt buộc:

- `DATABASE_URL` — MySQL 8, ví dụ `mysql://qbo:...@mysql:3306/quaybaronline`.
- `AUTH_SECRET` — ≥ 32 ký tự ngẫu nhiên.
- `GAME_SERVER_SECRET` — khớp `QBO_GAME_SECRET` của game server.
- `GAME_SERVER_HOST` / `GAME_SERVER_PORT` — fallback khi registry trống.
- `REDIS_URL` — tùy chọn.
- `ACCESS_TOKEN_TTL`, `REFRESH_TOKEN_TTL_DAYS`.

Không commit `.env`; không đưa secret vào Godot client.

### MySQL bằng Docker

```bash
docker compose up -d mysql redis
```

Database mặc định: `quaybaronline`, user `qbo`, password lấy từ `MYSQL_PASSWORD` trong compose (đổi trước khi deploy).

### Migration & seed

```bash
cd server
npx prisma migrate deploy              # production
SEED_MODERATOR_PASSWORD='...' npx prisma db seed
```

### Healthcheck

`GET /api/health` → `{ status: "ok", database: "up|down", version, time }`.

## 3. Docker Compose

```bash
cp .env.example .env   # nếu có; đặt MYSQL_PASSWORD, GAME_SERVER_SECRET, AUTH_SECRET
docker compose up -d mysql redis server game-server heartbeat
```

- `mysql` — MySQL 8.4, volume `mysql-data`.
- `redis` — Redis 7, volume `redis-data`.
- `server` — Next.js production image, migrate khi start.
- `game-server` — Godot headless Linux, UDP 7000.
- `heartbeat` — đăng ký server với backend mỗi 30s.

Chưa chạy thử Docker trong môi trường hiện tại (không có Docker); cấu hình cần được kiểm chứng trên máy có Docker.

## 4. Quy trình phát hành (gợi ý)

1. `tools/development/verify.sh` — import/smoke Godot + Prisma + typecheck + build.
2. Migration production + backup DB.
3. Deploy backend, kiểm tra `/api/health` và đăng nhập.
4. Deploy dedicated server với secret; kiểm tra heartbeat.
5. Export PC/mobile, kiểm tra đăng nhập, tạo phòng, 2 client, TV/DJ.
6. Theo dõi log JSON của backend; rate limit; lỗi ticket.

## 5. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| `Không kết nối được backend` | Next.js chưa chạy / sai `QBO_API_URL` | Chạy server, kiểm tra `/api/health` |
| `Game server chưa cấu hình QBO_GAME_SECRET` | Server thiếu secret | Đặt secret khớp backend, hoặc test với `--allow-unverified-tickets` |
| `Game ticket không hợp lệ hoặc đã hết hạn` | Ticket hết 5 phút/đã dùng | Xin ticket mới bằng cách join lại |
| `Phòng đã đầy` | membership >= maxPlayers | Tăng `maxPlayers` hoặc rời phòng khác |
| Lỗi đăng nhập 401 | access token hết hạn và refresh lỗi | Đăng nhập lại (refresh rotation đã thu hồi phiên) |
| Godot không thấy class `QBO…` | Chưa import project | `godot --headless --path game --editor --quit` |

## 6. Không được làm khi deploy

- Không đặt `GAME_SERVER_SECRET` trong client hoặc repo.
- Không dùng `--allow-unverified-tickets` trên production.
- Không mở MySQL ra Internet.
- Không tự tải/đóng gói asset hoặc nhạc không có giấy phép.
