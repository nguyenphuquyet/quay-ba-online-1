# KIẾN TRÚC — QUẨY BAR ONLINE

## 1. Tổng quan

```
┌────────────────────┐        HTTPS/JSON        ┌──────────────────────────┐
│ Godot client       │ ───────────────────────► │ Next.js App Router       │
│ (PC / Android/iOS) │ ◄─────────────────────── │ + Prisma + MySQL 8       │
│                    │   auth, phòng, ticket    │ + Redis (rate limit)     │
│                    │                          └────────────┬─────────────┘
│                    │        ENet/UDP                       │ verify ticket
│                    │ ◄────────────────────────►            │ (secret)
└────────────────────┘   dedicated game server ◄─────────────┘
```

- **Client** không bao giờ tự cấp quyền owner/DJ/admin. Quyền do backend cấp trong ticket và server kiểm tra lại.
- **Dedicated server** là Godot headless, dựng cùng layout nightclub bằng cùng script builder, nên `interact_id` và vị trí khớp tuyệt đối giữa client/server.
- **Next.js** là backend web duy nhất: REST API, không Express/NestJS, không WebSocket gameplay.

## 2. Ranh giới trách nhiệm

| Lớp | Chịu trách nhiệm | Không chịu trách nhiệm |
| --- | --- | --- |
| Godot client | Render, input, UI, animation, đồng bộ state gửi lên server, dựng world | Quyết định quyền, vị trí cuối cùng, trạng thái phòng |
| Dedicated server | Xác minh ticket, giới hạn phòng, anti-cheat vị trí, phân quyền DJ/đèn/TV, broadcast state | Render, lưu DB, phát nhạc thực tế |
| Next.js | Auth, hồ sơ, phòng, thành viên, bạn bè, inventory, report, ticket, registry server | Đồng bộ frame, relay voice/video |
| MySQL | Dữ liệu bền vững | Trạng thái realtime |
| Redis | Rate limit phân tán (tùy chọn) | Dữ liệu gameplay |

## 3. Client Godot

### Autoload

| Node | Vai trò |
| --- | --- |
| `AppConfig` | Hằng số, env, input map, mobile detection |
| `SettingsManager` | Graphics preset, âm lượng, sensitivity, camera, style |
| `GameState` | Session, user, phòng hiện tại, toast |
| `Api` | HTTP client tới Next.js, refresh token tự động |
| `Net` | ENet, server authoritative RPC, roster, reconnect |
| `App` | Bootstrap UI/world, vào/ra phòng, overlay, smoke test |

### Cấu trúc scene

`scenes/bootstrap.tscn` chỉ là node rỗng; `App` dựng toàn bộ. World là `Nightclub` (Node3D) dựng procedural:

- `_build_environment()` — WorldEnvironment (glow, SSAO, SSR, fog theo preset).
- `_build_shell/lobby/main_hall/dance_floor/stage/bar/vip_lounge/balcony/corridor_and_backrooms/computer_desk/decor()` — hình học + PBR + collision.
- `_init_systems()` — `LightingController`, `DJSystem`, `TVSystem`.
- `_connect_net()` — nhận state từ `Net`, spawn/xoá player, dispatch interaction.

Component tái sử dụng:

- `QBOInteractable` (Area3D, layer 3): id, prompt, action, payload. Player raycast layer 4 (mask) để tìm.
- `QBOPlayer` (CharacterBody3D): FP/TP camera, mobile joystick, emote, seat, teleport, network state 15 Hz.
- `QBOCharacterRig`: mesh + rig procedural, animation theo state.
- `QBOMaterials` / `QBOTextures`: cache material & texture sinh procedural.

### Luồng vào phòng online

1. Client `POST /api/rooms/[code]/join` → backend kiểm tra mật khẩu/sức chứa, tạo membership, cấp **game ticket** (5 phút, single-use).
2. Client load world + `Net.connect_to_room(host, port, ticket)`.
3. Client gửi `srv_join(ticket, displayName, avatar)`.
4. Server gọi `POST /api/game/ticket/verify` với `X-Game-Server-Secret`; backend đánh dấu ticket đã dùng và trả `userId/isOwner/room`.
5. Server gán owner, gửi `cli_welcome` kèm roster, room settings, lighting/DJ/TV state.
6. Server broadcast roster; client spawn avatar theo `local_player_ready`/`player_joined`.

### Đồng bộ

- Vị trí/rotation/animation/flags gửi 15 Hz (`unreliable_ordered`).
- Server kiểm tra `distance <= run_speed * dt * 1.6 + 0.75`; sai → gửi correction, không relay.
- Interaction, chat, lighting, DJ, TV đi kênh reliable và được server lọc quyền.
- Late joiner nhận state đèn/TV/DJ trong `cli_welcome`.

## 4. Dedicated server

Cùng project Godot, chạy:

```bash
godot --headless --path game -- --server --port=7000
```

- `App._boot_dedicated_server()` dựng world `server_mode=true` (không player local, không UI) và `Net.start_server()`.
- ENet tối đa 64 peer; giới hạn phòng mặc định 32.
- Không render; vẫn dựng collision/mesh vì dùng chung builder.
- Docker image: `multiplayer/Dockerfile`, chạy trên Ubuntu + Godot Linux headless.

## 5. Backend Next.js

```
server/
  app/api/...        route handlers (Next App Router)
  lib/auth.ts        bcrypt, JWT jose, refresh rotation, cookies
  lib/http.ts        error envelope, validation, rate limit, request id
  lib/tickets.ts     game ticket tạo/verify, chọn game server
  lib/validation.ts  zod schemas
  lib/serialize.ts   public room payload (không lộ passwordHash)
  prisma/schema.prisma
```

- Password: bcrypt cost 12. Không lưu plaintext.
- Access token: JWT HS256, TTL 15 phút, issuer/audience cố định.
- Refresh: random 48 bytes, chỉ lưu SHA-256, xoay mỗi lần refresh, phát hiện reuse → thu hồi mọi session của user.
- Cookie httpOnly/sameSite=lax; Godot dùng Bearer token (không phụ thuộc cookie).
- Rate limit theo IP + route: register 8/phút, login 12/phút, report 5/10 phút, v.v. Redis nếu có `REDIS_URL`, fallback in-memory.
- Mọi response lỗi: `{ error: { code, message, details? } }`; request id trong header.

## 6. Bảo mật

| Rủi ro | Biện pháp |
| --- | --- |
| Giả mạo owner/DJ | Quyền do backend + server giữ; client không tự đặt |
| Teleport/speed hack | Server kiểm tra displacement, clamp y, correction |
| Gian lận ticket | Ticket random 256-bit, hash SHA-256, single-use, TTL 5 phút, secret server-server |
| Brute force login | bcrypt + rate limit + thông báo lỗi mơ hồ |
| Refresh token theft | Rotation + reuse detection + thu hồi toàn bộ |
| SSRF từ URL media | `QBOUrlGuard` chặn localhost/private/metadata (IPv4, IPv6, `user:pass@`); chỉ http/https và media trực tiếp |
| XSS trên landing | React escape, không render HTML thô từ user |
| CSRF | Cookie sameSite=lax + kiểm tra Origin cho mutation dùng cookie |
| Lộ password phòng | Chỉ trả `hasPassword`, hash bcrypt |

## 7. Hiệu năng

- Preset Low/Medium/High/Ultra: `scaling_3d_scale`, MSAA, shadow atlas, glow/SSAO/SSR/fog.
- Chỉ một số spotlight đổ shadow; LED dùng emission thay vì thêm realtime light.
- Texture procedural 256px (128px cho thảm/kim loại), cache material.
- Player update 15 Hz, không HTTP cho gameplay.
- Mobile dùng GL Compatibility renderer; UI riêng, joystick ảo.

## 8. Giới hạn đã biết

- Video MP4/MOV dùng GDExtension `native_video`, cần renderer Forward+ hoặc Mobile (RenderingDevice). Trên máy chỉ có OpenGL Compatibility, video vẫn giải mã nhưng không hiển thị khung hình; OGV/Theora chạy được trên mọi renderer.
- `native_video` chỉ có binary Windows/macOS/Linux, không hỗ trợ Android/iOS; TV trên mobile chỉ phát OGV.
- Voice chat WebRTC/SFU chưa triển khai.
- Chưa có build Android/iOS do thiếu SDK/Xcode.
- Chưa kiểm thử backend với MySQL thật trong môi trường này (không có MySQL/Docker); schema/Prisma/build đã được kiểm tra tĩnh.
