# Dedicated server

Thư mục này chứa cấu hình chạy **Godot dedicated server** cho QUẨY BAR ONLINE. Server dùng chung source với client (`game/`) nhưng chạy headless, không render, không UI.

## Chạy local

```bash
# Terminal 1 — backend (cần cho xác minh ticket)
cd server && npm run dev

# Terminal 2 — game server
QBO_API_URL="http://127.0.0.1:3000" \
QBO_GAME_SECRET="khớp GAME_SERVER_SECRET trong server/.env" \
godot --headless --path game -- --server --port=7000
```

Kiểm thử nhanh không cần backend:

```bash
godot --headless --path game --fixed-fps 60 -- --server --port=7001 --allow-unverified-tickets
# terminal khác:
godot --headless --path game --fixed-fps 60 -- --net-smoke=7001
```

## Docker

Từ thư mục gốc repo:

```bash
docker build -f multiplayer/Dockerfile -t qbo-game-server .
docker run --rm -p 7000:7000/udp \
  -e QBO_API_URL="http://host.docker.internal:3000" \
  -e QBO_GAME_SECRET="..." \
  -e QBO_GAME_PORT=7000 \
  qbo-game-server
```

Hoặc `docker compose up -d game-server heartbeat`.

### Chỉ game server trên VPS (backend vẫn ở Vercel)

```bash
cp multiplayer/vps.env.example multiplayer/.env.vps
# sửa PUBLIC_GAME_HOST + GAME_SERVER_SECRET
docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps up -d --build
sudo ufw allow 7000/udp
```

Xem hướng dẫn đầy đủ: [`docs/DEPLOY_VPS.md`](../docs/DEPLOY_VPS.md).

Image tải Godot Linux chính thức 4.7.2 và chạy project trực tiếp, không cần export template. Chưa được kiểm chứng trong môi trường phát triển hiện tại vì máy không có Docker.

## Biến môi trường

| Biến | Bắt buộc | Mô tả |
| --- | --- | --- |
| `QBO_API_URL` | Có | Backend Next.js để verify ticket |
| `QBO_GAME_SECRET` | Có | Khớp `GAME_SERVER_SECRET` backend |
| `QBO_GAME_PORT` | Không | UDP port, mặc định 7000 |
| `QBO_ALLOW_UNVERIFIED_TICKETS` | Không | Chỉ dùng test; production để `0` |
| `QBO_ROOM_CODE` | Không | Nhãn phòng hiển thị log |

Với heartbeat: `GAME_SERVER_HOST` phải là **IP công khai** mà client dùng để
kết nối UDP. Để trống thì `heartbeat.mjs` tự lấy IP qua `api.ipify.org`.

## Heartbeat

`heartbeat.mjs` gọi `POST /api/game/servers/heartbeat` mỗi 30s để backend biết server nào đang sống và cấp `game.host/port` tương ứng trong ticket. Chạy bằng `node multiplayer/heartbeat.mjs`.

Không đặt `GAME_SERVER_HOST=game-server` (hostname nội bộ Docker): máy client
ngoài Internet sẽ không phân giải được. Dùng IP công khai của VPS.

## Lưu ý production

- Mở **UDP** (không phải TCP) cho port game.
- Mỗi instance hiện phục vụ một phòng/club instance; muốn nhiều phòng cần nhiều instance + registry/port mapping.
- Không bật `--allow-unverified-tickets` trên production.
- Đặt server sau firewall, không công khai API backend nội bộ nếu không cần.
