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
| `srv_dj` / `cli_dj` | C→S→C | reliable | owner hoặc `dj_allowed` | Track trong thư viện API, play/pause, position, volume |
| `srv_tv` / `cli_tv` | C→S→C | reliable | owner hoặc `tv_allowed` | URL, play/pause, position, volume |
| `srv_room_settings` / `cli_room_settings` | C→S→C | reliable | owner | Khóa quyền, cấp quyền |
| `srv_ping` / `cli_pong` | C→S→C | unreliable_ordered | member | Watchdog 3s, phát hiện mạng lag sau 12s |
| `srv_owner_leaving` | C→S | reliable | owner | Chủ phòng chủ động rời → đóng phòng ngay |
| `cli_room_closed` | S→C | reliable | — | Phòng đã đóng (chủ rời / hết thời gian chờ) |
| `cli_kicked` | S→C | reliable | owner | Mời ra |

## 4. Chống gian lận

- Vị trí: `max_distance = PLAYER_RUN_SPEED * dt * 1.6 + 0.75` (dt clamp 0.02–0.6s); vượt → correction.
- Độ cao: ngoài khoảng `[-20, 60]` → correction.
- Interaction: chỉ nhận action hợp lệ; action điều khiển (`dj*`, `light*`, `tv*`) phải qua `can_control`.
- Ghế/thang máy: server cập nhật vị trí chuẩn trước khi broadcast để không tự kéo người chơi về.
- Chat: rate limit 8 tin/5 giây, cắt 240 ký tự.
- Đèn: whitelist 8 preset; intensity 0–4.
- DJ: whitelist action; `track_id` phải có trong thư viện API đã tải.
- TV: chỉ nhận video trực tiếp (mp4/mov/m4v/ogv); server lưu state cuối, người vào sau nhận ngay.
- Roster/owner: server chọn owner đầu tiên; quyền owner **không** chuyển cho người khác. Chủ phòng rời → phòng đóng.

### 4.1 Đồng bộ nhạc trong phòng

- Chủ phòng/DJ tải bài trước. Trong lúc tải, state gửi đi có `loading=true`, `playing=false`, nên máy khác **không phát từ 0**.
- Máy khác nhận state `loading` sẽ tải trước vào cache nhưng nằm chờ; tải xong cũng chưa phát.
- Khi chủ phòng tải xong, state `play` có `position` + `updated_at`. Máy nào tải xong sẽ nhảy đúng vị trí đã trôi qua (giới hạn 15 giây để tránh lệch đồng hồ), không lặp lại đoạn đầu.
- Máy vào giữa bài tải xong sẽ seek đến vị trí hiện tại của phòng.
- Godot cần toàn bộ file MP3/OGG/WAV để giải mã native nên không stream theo chunk; thay vào đó tải nền + chờ/jump theo timeline.

## 5. Reconnect

- Client gửi `srv_ping` mỗi 3 giây; quá **12 giây** không có `cli_pong` → coi như mất mạng và bắt đầu reconnect (không cần chờ ENet timeout).
- `server_disconnected` cũng kích hoạt reconnect ngay.
- Tối đa **5 lần**, backoff tăng dần (2s, 3.5s, 5s, 6.5s, 8s). Mỗi lần xin **ticket mới** qua `POST /api/game/ticket` vì ticket cũ đã single-use.
- Thành công → vào lại phòng, server khôi phục vị trí/trạng thái theo `user_id` (kể cả ghế đang ngồi) và broadcast “đã kết nối lại”. Thất bại → phát `connection_lost`, client về menu.
- Server giữ trạng thái người chơi đã rớt trong **30 giây** (`_away`). Chủ phòng rớt cũng có 30 giây để quay lại trước khi phòng đóng.
- UI hiện toast “Đang kết nối lại phòng (lần n/5)…” và “Đã kết nối lại phòng.”.

## 6. Phòng tạm thời (ephemeral)

- Phòng chỉ tồn tại khi còn người dùng: chủ phòng rời (chủ động hoặc quá 30 giây) → dedicated server đóng phòng, báo `cli_room_closed` cho mọi client và gọi `POST /api/game/rooms/[code]/close`.
- Backend `POST /api/rooms/[code]/leave` đóng phòng ngay khi chủ rời; người cuối cùng rời cũng đóng phòng.
- Client gửi `POST /api/rooms/[code]/heartbeat` mỗi 30 giây. `GET /api/rooms` tự đóng phòng OPEN quá **120 giây** không có nhịp hoặc không còn member, nên không còn phòng “ma” sau restart/crash.
- Một tiến trình dedicated server phục vụ **một phòng tại một thời điểm**; đóng phòng xong mới nhận ticket của phòng khác.

## 7. Giới hạn phòng và quyền

- `maxPlayers` cấu hình 2–32, server cũng giới hạn peer tối đa 64.
- Owner: phòng đầu tiên join nếu chưa có owner; backend đánh dấu `isOwner` cho chủ phòng.
- Owner có thể:
  - khóa DJ / ánh sáng / TV (`*_locked`),
  - cấp/thu quyền DJ cho từng peer (`grant_permission`/`revoke_permission`),
  - kick (`kick_peer`).
- Chủ phòng rời phòng → phòng đóng, **không** chuyển owner.

## 8. Chạy và kiểm thử

```bash
# 1) Dedicated server (test không cần backend)
godot --headless --path game --fixed-fps 60 -- --server --port=7001 --allow-unverified-tickets

# 2) Client smoke test (process thứ hai)
godot --headless --path game --fixed-fps 60 -- --net-smoke=7001

# 3) Kiểm tra reconnect: giả lập mất mạng rồi tự nối lại
godot --headless --path game -- --net-smoke=7001 --reconnect-test

# 4) Kiểm tra chủ phòng rời → phòng đóng ngay (nhận cli_room_closed)
godot --headless --path game -- --net-smoke=7001 --owner-leave
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

## 9. Triển khai

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

## 10. Chưa làm

- Voice chat WebRTC/SFU (dự kiến SFU + signaling qua backend; xem PROGRESS).
- Server-side physics simulation đầy đủ (hiện kiểm tra displacement, không mô phỏng lại).
- Chat persistence/history, moderation realtime, matchmaking toàn cầu.
