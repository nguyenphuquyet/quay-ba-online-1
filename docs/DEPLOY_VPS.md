# DEPLOY GAME SERVER LÊN VPS

Mô hình đang dùng: **backend Next.js + MySQL ở nơi khác (Vercel/Aiven)**, còn
**Godot dedicated server chạy trên VPS** và mở **UDP 7000**. Client xin ticket
từ backend, ticket trả về `game.host` / `game.port`, rồi client kết nối ENet
thẳng tới VPS.

```
Client ──HTTP──▶ Vercel (auth/room/ticket) ──▶ Aiven MySQL
   │
   └──ENet UDP 7000──▶ VPS (Godot headless) ──HTTP verify ticket──▶ Vercel
```

## 0. Cần có

- VPS Ubuntu 22.04/24.04 (hoặc Debian), **IPv4 công khai**.
- Quyền SSH (`root` hoặc user có `sudo`).
- `GAME_SERVER_SECRET` đang dùng trên Vercel (Vercel → Project → Settings →
  Environment Variables). Phải **giống hệt** `GAME_SERVER_SECRET` bên dưới.
- Docker + Docker Compose trên VPS.

> VPS không cần mở TCP 3000 hay cài MySQL. Chỉ cần **UDP 7000**.

## 1. Cài Docker trên VPS

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# đăng xuất rồi đăng nhập lại để dùng docker không cần sudo
docker --version
docker compose version
```

## 2. Lấy source

```bash
git clone https://github.com/nguyenphuquyet/quay-ba-online-1.git
cd quay-ba-online-1
```

Nếu repo private, dùng deploy key hoặc `gh auth login` trên VPS.

## 3. Cấu hình

```bash
cp multiplayer/vps.env.example multiplayer/.env.vps
nano multiplayer/.env.vps
```

Điền:

| Biến | Giá trị |
| --- | --- |
| `QBO_API_URL` | `https://quay-bar-online-server.vercel.app` (hoặc domain backend của bạn) |
| `GAME_SERVER_SECRET` | đúng secret trên Vercel |
| `PUBLIC_GAME_HOST` | IP công khai của VPS, ví dụ `203.0.113.10`. Để trống nếu muốn tự lấy qua `api.ipify.org` |
| `GAME_SERVER_REGION` | `sin`, `hkg`, `sgp`… chỉ để hiển thị |

**Không** đặt `QBO_ALLOW_UNVERIFIED_TICKETS=1` trên production.

## 4. Mở firewall UDP

```bash
sudo ufw allow 7000/udp
sudo ufw status
```

Nếu VPS dùng firewall của nhà cung cấp (Security Group / Firewall rule), mở
thêm **UDP 7000** ở trang quản trị của họ.

## 5. Chạy

```bash
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps up -d --build
```

Xem log:

```bash
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps logs -f game-server
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps logs -f heartbeat
```

Log đúng:

```text
[qbo] dedicated server starting on UDP 7000
[heartbeat] ok server=... 203.0.113.10:7000
```

## 6. Kiểm tra backend đã nhận server

Heartbeat gọi `POST /api/game/servers/heartbeat` mỗi 30 giây. Backend chọn
server ONLINE có heartbeat trong 60 giây gần nhất khi cấp ticket.

Cách kiểm tra nhanh nhất: vào game, tạo phòng, xem log client hoặc gọi
`POST /api/game/ticket` (sau khi join phòng) và xem `game.host` / `game.port`.
Nếu vẫn là `127.0.0.1`:

- heartbeat chưa chạy hoặc sai `GAME_SERVER_SECRET`;
- `GAME_SERVER_HOST` đang là hostname nội bộ Docker (`game-server`) — phải là
  IP công khai;
- Vercel chưa có `GAME_SERVER_SECRET` trùng với VPS.

## 7. Biến môi trường trên Vercel

Bắt buộc:

```text
GAME_SERVER_SECRET = <giống hệt VPS>
```

Nên đặt thêm (fallback khi registry trống):

```text
GAME_SERVER_HOST = 203.0.113.10
GAME_SERVER_PORT = 7000
```

Sau khi đổi env, redeploy Vercel.

## 8. Cập nhật / khởi động lại

```bash
cd quay-bar-online-1
git pull
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps up -d --build
```

Dừng:

```bash
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps down
```

## 9. Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| Client kẹt ở "Đang vào phòng" | UDP 7000 bị chặn | Mở `ufw allow 7000/udp` + firewall của VPS |
| `Game ticket không hợp lệ` | Secret VPS khác Vercel | Đặt lại `GAME_SERVER_SECRET` cho khớp rồi restart |
| Ticket trả `127.0.0.1` | Heartbeat chết / host nội bộ Docker | Xem log heartbeat, đặt `PUBLIC_GAME_HOST=<IP VPS>` |
| Heartbeat `HTTP 403` | `x-game-server-secret` sai | Kiểm tra lại secret trên Vercel |
| Heartbeat `HTTP 503` | Vercel thiếu `GAME_SERVER_SECRET` | Thêm env trên Vercel rồi redeploy |
| Vào được nhưng không thấy ai | Mỗi instance chỉ là **một club** | MVP: 1 VPS = 1 club; nhiều phòng cần nhiều instance/port + định tuyến |

## 10. Giới hạn hiện tại

- Một tiến trình server chỉ giữ **một** world club. Nhiều phòng cùng lúc cần
  nhiều container/port và logic chọn server theo phòng (chưa làm).
- Chưa có auto-scale. VPS 1 vCPU/1 GB đủ cho club nhỏ (~10–20 người), nhưng
  nên theo dõi CPU/RAM và băng thông UDP.
- Không chạy `--allow-unverified-tickets` trên production.
