# MULTIPLAYER — QUẨY BAR ONLINE

## 1. Mô hình

- **Dedicated server** Godot headless, mỗi phòng là một nightclub instance riêng.
- ENet UDP, mặc định cổng **7000**. Client không dùng HTTP để đồng bộ vị trí.
- Server authoritative: client chỉ gửi input/state; server kiểm tra và broadcast.

```
Client A ──ENet──► Dedicated server ◄──ENet── Client B
      │                   │
      └── HTTP ──► Next.js (auth, room, ticket) ◄── HTTP ──┘
```

## 2. Game ticket (bắt buộc)

1. Người chơi đăng nhập, join phòng qua Next.js.
2. `POST /api/rooms/[code]/join` tạo membership và trả `ticket` (raw) + `game { host, port }`.
3. Client gọi RPC `srv_join(ticket, displayName, avatar)`.
4. Server gọi `POST /api/game/ticket/verify` với header `X-Game-Server-Secret`.
5. Backend kiểm tra: hash tồn tại, chưa dùng, chưa hết hạn (5 phút), user không bị ban, phòng còn mở, user còn là member; đánh dấu `usedAt`.
6. Server nhận `userId`, `isOwner`, `room` và gán owner/chủ phòng.

Server yêu cầu `QBO_GAME_SECRET` khớp `GAME_SERVER_SECRET` của backend. Nếu thiếu secret, server **từ chối** mọi kết nối. Chỉ dùng `--allow-unverified-tickets` khi test cục bộ.

## 3. RPC

| RPC | Chiều | Kênh | Quyền | Mục đích |
| --- | --- | --- | --- | --- |
| `srv_join` | C→S | reliable | — | Xác minh ticket, lấy roster |
| `cli_welcome` | S→C | reliable | — | Roster, settings, đèn/DJ/TV, thông tin bản thân |
| `srv_player_state` | C→S | unreliable_ordered | member | Vị trí, yaw, animation, flags (seat) |
| `cli_player_state` | S→C | unreliable_ordered | — | Relay state cho người khác |
| `cli_correction` | S→C | reliable | — | Kéo về vị trí hợp lệ |
| `srv_chat` / `cli_chat` | C→S→C | reliable | member + rate limit 8/5s | Chat phòng |
| `srv_interact` / `cli_interaction` | C→S→C | reliable | phụ thuộc action | Tương tác nội thất, mở UI, đổi state |
| `srv_lighting` / `cli_lighting` | C→S→C | reliable | owner hoặc `lighting_allowed` | Preset, intensity, speed |
| `srv_dj` / `cli_dj` | C→S→C | reliable | owner hoặc `dj_allowed` | Playlist, play/pause, volume, URL |
| `srv_tv` / `cli_tv` | C→S→C | reliable | owner hoặc `tv_allowed` | URL, play/pause, position, volume |
| `srv_room_settings` / `cli_room_settings` | C→S→C | reliable | owner | Khóa quyền, cấp quyền |
| `cli_kicked` | S→C | reliable | owner | Mời ra |

## 4. Chống gian lận

- Vị trí: `max_distance = PLAYER_RUN_SPEED * dt * 1.6 + 0.75` (dt clamp 0.02–0.6s); vượt → correction.
- Độ cao: ngoài khoảng `[-20, 60]` → correction.
- Interaction: chỉ nhận action hợp lệ; action điều khiển (`dj*`, `light*`, `tv*`) phải qua `can_control`.
- Ghế/thang máy: server cập nhật vị trí chuẩn trước khi broadcast để không tự kéo người chơi về.
- Chat: rate limit 8 tin/5 giây, cắt 240 ký tự.
- Đèn: whitelist 8 preset; intensity 0–4.
- DJ: whitelist action; URL http/https.
- TV: server lưu state cuối, người vào sau nhận ngay.
- Roster/owner: server chọn owner đầu tiên; owner rời → chuyển cho peer còn lại.

## 5. Reconnect

- Mất kết nối server → client phát `connection_lost`, thử tối đa 3 lần, mỗi lần chờ 2s và xin **ticket mới** qua backend (`POST /api/game/ticket`), vì ticket cũ đã single-use.
- Thành công → vào lại phòng với roster mới; thất bại → về menu.
- Server xoá session ngay khi peer disconnect; player phải join lại.

## 6. Giới hạn phòng và quyền

- `maxPlayers` cấu hình 2–32, server cũng giới hạn peer tối đa 64.
- Owner: phòng đầu tiên join nếu chưa có owner; backend đánh dấu `isOwner` cho chủ phòng.
- Owner có thể:
  - khóa DJ / ánh sáng / TV (`*_locked`),
  - cấp/thu quyền DJ cho từng peer (`grant_permission`/`revoke_permission`),
  - kick (`kick_peer`).
- Chủ phòng rời phòng → server chọn owner mới.

## 7. Chạy và kiểm thử

```bash
# 1) Dedicated server (test không cần backend)
godot --headless --path game --fixed-fps 60 -- --server --port=7001 --allow-unverified-tickets

# 2) Client smoke test (process thứ hai)
godot --headless --path game --fixed-fps 60 -- --net-smoke=7001
```

Kết quả mong đợi:

```
[NET-SMOKE] players=1 roster=1 local=... owner=... connected=true
[NET-SMOKE] vị trí sau di chuyển: (...)
[NET-SMOKE] OK
```

Kiểm thử bằng máy thật khác:

1. Chạy server với `QBO_GAME_SECRET` + `QBO_API_URL`.
2. Mở 2 client, đăng nhập 2 tài khoản, tạo/join cùng phòng.
3. Kiểm tra: thấy nhau di chuyển, animation, ngồi ghế, đổi đèn, DJ play, TV URL.
4. Rút mạng client → xem reconnect (cần backend cấp ticket mới).

## 8. Triển khai

- Mở UDP `7000` (hoặc port cấu hình).
- Đặt `QBO_GAME_SECRET`, `QBO_API_URL`, `QBO_GAME_PORT`.
- Docker: `docker compose up -d game-server`; xem `multiplayer/README.md`.
- VPS: `docker compose -f multiplayer/docker-compose.vps.yml --env-file multiplayer/.env.vps up -d --build`; xem `docs/DEPLOY_VPS.md`.
- `GAME_SERVER_HOST` của heartbeat phải là IP công khai của VPS (không phải `game-server` nội bộ Docker).
- Heartbeat lên backend (`POST /api/game/servers/heartbeat`) để backend chọn server khi cấp ticket.
- Scale ngang: mỗi server instance một phòng (MVP). Registry hỗ trợ nhiều server; cần thêm logic chọn server theo tải cho production.

### Kiểm tra nhanh server từ xa

```bash
# handshake ENet (không cần game ticket) — dùng khi nghi firewall chặn UDP
godot --headless --path game --script res://tools/net_probe.gd -- <host> <port>
# [PROBE] status=2 (OK)

# vào phòng thật bằng ticket thật (host:port:ticket)
godot --headless --path game -- --net-smoke=<host>:<port>:<ticket>
# [NET-SMOKE] players=2 roster=2 ... OK

# muốn thử offline: dựng server ENet tối giản ở máy
godot --headless --path game --script res://tools/net_echo_server.gd -- 7101
```

## 9. Chưa làm

- Voice chat WebRTC/SFU (dự kiến SFU + signaling qua backend; xem PROGRESS).
- Server-side physics simulation đầy đủ (hiện kiểm tra displacement, không mô phỏng lại).
- Chat persistence/history, moderation realtime, matchmaking toàn cầu.
