# Deploy backend lên Vercel

## 1. Deploy được gì, không deploy được gì

| Thành phần | Vercel | Ghi chú |
| --- | --- | --- |
| Backend Next.js (`server/`) — auth, phòng, bạn bè, inventory, report, game ticket | ✅ | App Router API routes chạy tốt trên Vercel Functions |
| Dedicated game server Godot (`game/ --server`, ENet **UDP** 7000) | ❌ | Vercel là serverless HTTP, không giữ được socket UDP lâu dài. Cần VPS / Railway / Fly.io / máy tự host |
| MySQL 8 | ❌ (không cấp sẵn) | Phải dùng dịch vụ ngoài (Aiven, TiDB Cloud, Railway, VPS…) |
| Redis | ⚠️ tùy chọn | Không bắt buộc; nếu trống thì rate limit chạy in-memory theo từng instance |

Workflow build game (`windows.yml`, `android.yml`, `ios-unsigned.yml`) **không liên quan** đến Vercel; chúng chỉ tạo file cài game.

## 2. Chuẩn bị database MySQL

Vercel không có MySQL. Chọn một nơi chạy MySQL 8 và lấy connection string dạng:

```text
mysql://USER:PASSWORD@HOST:PORT/DATABASE
```

Một số lựa chọn:

| Nhà cung cấp | Ghi chú |
| --- | --- |
| **Aiven for MySQL** | Có gói free nhỏ, bật SSL, phù hợp demo |
| **TiDB Cloud Serverless** | Tương thích MySQL, free tier, có connection pooler |
| **Railway MySQL** | Nhanh, có trial |
| **VPS riêng** | Toàn quyền, nhưng phải tự sao lưu/bảo mật |

Khi dùng Prisma trên serverless, thêm tham số giới hạn connection:

```text
mysql://USER:PASSWORD@HOST:PORT/DATABASE?ssl={"rejectUnauthorized":true}&connection_limit=1
```

> Mật khẩu có ký tự đặc biệt phải URL-encode (`@` → `%40`, `#` → `%23`, …).
> Nếu nhà cung cấp đưa connection string không có SSL mà serverless báo lỗi, thêm `?sslaccept=strict` hoặc bỏ phần `ssl`.

Tạo schema lần đầu (chạy ở máy bạn, trỏ vào DB hosted):

```bash
cd server
DATABASE_URL="mysql://..." npx prisma migrate deploy
# tùy chọn: dữ liệu mẫu
DATABASE_URL="mysql://..." npm run db:seed
```

Migration đã được commit sẵn tại `server/prisma/migrations/` (`20261103120000_init`), nên **không cần** `migrate dev` trên CI.

## 3. Biến môi trường trên Vercel

Vào **Project → Settings → Environment Variables** và thêm cho cả `Production` (và `Preview` nếu muốn):

| Biến | Bắt buộc | Giá trị |
| --- | --- | --- |
| `DATABASE_URL` | ✅ | Connection string MySQL ở mục 2 |
| `AUTH_SECRET` | ✅ | Chuỗi ngẫu nhiên ≥ 32 ký tự |
| `GAME_SERVER_SECRET` | ✅ (nếu dùng ticket) | Phải **trùng** `QBO_GAME_SECRET` của Godot dedicated server |
| `GAME_SERVER_HOST` | ⬜ | IP/hostname của dedicated server (mặc định `127.0.0.1`) |
| `GAME_SERVER_PORT` | ⬜ | Mặc định `7000` |
| `REDIS_URL` | ⬜ | Chỉ cần khi muốn rate limit phân tán |
| `ACCESS_TOKEN_TTL` | ⬜ | Mặc định `900` giây |
| `REFRESH_TOKEN_TTL_DAYS` | ⬜ | Mặc định `30` |

Sinh secret:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

> `GAME_SERVER_HOST` là địa chỉ **UDP** mà client sẽ kết nối. Nếu dedicated server chạy sau NAT, phải mở/forward cổng UDP tương ứng; Vercel không làm hộ việc này.

## 4. Cách A — import bằng Vercel Dashboard (khuyến nghị)

1. Push code lên GitHub.
2. Vào [vercel.com/new](https://vercel.com/new) → **Import Git Repository** → chọn repo.
3. Cấu hình project:
   - **Root Directory**: `server`
   - **Framework Preset**: Next.js (tự nhận)
   - **Build Command**: đã cấu hình trong `server/vercel.json` (`prisma generate && next build`)
   - **Install Command**: `npm ci`
   - **Output Directory**: để trống
4. Thêm các biến môi trường ở mục 3.
5. **Deploy**. Mỗi lần push lên `main` (thay đổi trong `server/`) Vercel sẽ tự build lại.
6. Kiểm tra: `https://<project>.vercel.app/api/health` phải trả `{"status":"ok","database":"up"}`.

`server/vercel.json` đã ghim region `sin1` (Singapore) cho gần Việt Nam. Nếu DB ở region khác, sửa `regions` cho khớp để giảm độ trễ.

## 5. Cách B — deploy bằng CLI

```bash
npm install -g vercel
cd server
vercel login
vercel link                 # tạo .vercel/project.json (không commit)
vercel env add DATABASE_URL production
vercel env add AUTH_SECRET production
vercel env add GAME_SERVER_SECRET production
vercel --prod
```

Sau khi `vercel link`, file `server/.vercel/project.json` chứa `orgId` và `projectId` — dùng cho workflow CI bên dưới (không phải secret nhạy cảm, nhưng repo đang public nên cứ để trong GitHub Secrets).

## 6. Cách C — deploy bằng GitHub Actions

Workflow [`.github/workflows/deploy-vercel.yml`](../.github/workflows/deploy-vercel.yml) chạy thủ công (**Actions → Deploy backend to Vercel → Run workflow**).

Thêm repository secrets:

| Secret | Lấy ở đâu |
| --- | --- |
| `VERCEL_TOKEN` | [vercel.com/account/tokens](https://vercel.com/account/tokens) |
| `VERCEL_ORG_ID` | `server/.vercel/project.json` sau `vercel link` |
| `VERCEL_PROJECT_ID` | `server/.vercel/project.json` sau `vercel link` |
| `DATABASE_URL` | Tùy chọn — nếu có, workflow chạy `prisma migrate deploy` trước khi deploy |

Workflow sẽ pull env từ Vercel, build prebuilt, deploy production và gọi thử `/api/health`.

## 7. Trỏ game client vào backend đã deploy

Client Godot đọc theo thứ tự: biến môi trường → tham số dòng lệnh → mặc định `http://127.0.0.1:3000`.

```bash
# Windows (PowerShell)
$env:QBO_API_URL="https://<project>.vercel.app"
.\QuayBarOnline.exe

# hoặc tham số dòng lệnh
QuayBarOnline.exe --api=https://<project>.vercel.app
```

Với bản build phát hành, nên sửa `DEFAULT_API_URL` trong `game/scripts/autoload/app_config.gd` thành domain Vercel (hoặc truyền `--api=` trong shortcut/launcher).

## 8. Lưu ý khi chạy Prisma + MySQL trên Vercel

- **Connection limit**: mỗi function instance mở pool riêng. Luôn đặt `connection_limit=1` và ưu tiên nhà cung cấp có pooler (TiDB, PlanetScale…). Aiven không có pooler mặc định → giới hạn `max_connections` thấp khi demo.
- **Cold start**: request đầu tiên có thể chậm 1–3 giây.
- **Migration**: chạy `prisma migrate deploy` từ máy local hoặc CI, **không** chạy trong build Vercel (build có thể chạy song song nhiều lần).
- **Log**: xem **Project → Logs / Functions**; lỗi cấu hình env sẽ hiện `Cấu hình môi trường không hợp lệ`.
- **Hobby plan** của Vercel chỉ dành cho mục đích phi thương mại; nếu game có thu phí/quảng cáo thì cần Pro.
- **Không commit** `.env`, keystore hay `server/.vercel/`.

## 9. Checklist sau deploy

- [ ] `GET /api/health` → `status: ok`, `database: up`
- [ ] Đăng ký + đăng nhập được từ client
- [ ] Tạo phòng, vào phòng, nhận game ticket
- [ ] Dedicated server Godot chạy ở nơi khác (VPS) với `QBO_API_URL` trỏ về domain Vercel và `QBO_GAME_SECRET` khớp `GAME_SERVER_SECRET`
- [ ] `GAME_SERVER_HOST`/`GAME_SERVER_PORT` trỏ đúng địa chỉ UDP công khai
