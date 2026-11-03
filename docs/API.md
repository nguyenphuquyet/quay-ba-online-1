# API — QUẨY BAR ONLINE (Next.js App Router)

Base URL dev: `http://127.0.0.1:3000`
Auth: `Authorization: Bearer <accessToken>` (Godot) **hoặc** cookie `qbo_access` (web).
Mọi response lỗi có dạng:

```json
{ "error": { "code": "VALIDATION_ERROR", "message": "Dữ liệu không hợp lệ.", "details": [...] } }
```

Header mọi response: `x-request-id`, `cache-control: no-store`.

## 1. Auth

### POST /api/auth/register

Rate limit: 8/phút/IP.

```json
{ "username": "neonfox", "email": "neon@example.com", "password": "matkhau123", "displayName": "Neon Fox" }
```

`201`:

```json
{
  "accessToken": "eyJ...",
  "refreshToken": "v7b...",
  "expiresIn": 900,
  "user": { "id": "uuid", "username": "neonfox", "displayName": "Neon Fox", "avatarUrl": null, "bio": null, "role": "USER", "createdAt": "..." }
}
```

Lỗi: `409 USERNAME_TAKEN`, `409 EMAIL_TAKEN`, `422 VALIDATION_ERROR`.
Cookie `qbo_access` / `qbo_refresh` được set httpOnly.

### POST /api/auth/login

Rate limit 12/phút/IP.

```json
{ "identifier": "neonfox", "password": "matkhau123" }
```

`200` cùng schema register. Lỗi: `401 INVALID_CREDENTIALS`, `403 ACCOUNT_BANNED`.

### POST /api/auth/refresh

Body (tùy chọn nếu dùng cookie): `{ "refreshToken": "..." }`

- Rotation: refresh token cũ bị thu hồi, trả cặp mới.
- Phát hiện reuse → thu hồi **toàn bộ** session của user, trả `401 REFRESH_REUSED`.
- Hết hạn: `401 REFRESH_EXPIRED`; thiếu: `401 REFRESH_REQUIRED`.

### POST /api/auth/logout

Thu hồi refresh token hiện tại, xóa cookie. Trả `{ "ok": true }`.

### GET /api/users/me

`200`:

```json
{
  "user": { ...publicUser },
  "stats": { "friends": 3, "openRooms": 1 },
  "equipped": [{ "itemKey": "outfit_obsidian", "itemType": "outfit" }]
}
```

`401 UNAUTHORIZED` nếu thiếu/sai token.

### PATCH /api/users/me

Body (ít nhất 1 trường): `displayName`, `bio`, `avatarUrl` (http/https, ≤500 ký tự).
Kiểm tra Origin cho mutation. Trả `{ "user": ... }`.

### GET /api/users/[id]

Hồ sơ công khai: `id, username, displayName, avatarUrl, bio, createdAt, online, banned, stats.roomsCreated`. Không trả email.

## 2. Rooms

### GET /api/rooms

Query: `search`, `visibility=all|public|private`, `limit` (1–50).

```json
{
  "rooms": [{
    "id": "uuid", "code": "LOTUS-2481", "name": "Đêm Champagne", "description": "...",
    "map": "the_chrome_lotus", "maxPlayers": 16, "playerCount": 4,
    "isPublic": true, "hasPassword": false, "status": "open",
    "lightingPreset": "party",
    "owner": { "id": "uuid", "username": "host", "displayName": "Host", "avatarUrl": null },
    "createdAt": "...", "updatedAt": "..."
  }]
}
```

Không bao giờ trả `passwordHash`.

### POST /api/rooms

Yêu cầu đăng nhập. Rate limit 6/phút. Tối đa 3 phòng mở/người.

```json
{
  "name": "Đêm Champagne",
  "description": "Dress code: đen",
  "maxPlayers": 16,
  "isPublic": false,
  "password": "1234",
  "map": "the_chrome_lotus",
  "lightingPreset": "party"
}
```

`201 { room }`. Mã phòng do server sinh (`LOTUS-XXXX`). Lỗi: `409 TOO_MANY_ROOMS`, `409 CAPACITY_TOO_LOW`, `503` khi DB lỗi.

### GET /api/rooms/[code]

Trả room + `members[]` (id, username, displayName, avatarUrl, role, joinedAt).

### PATCH /api/rooms/[code]

Chỉ chủ phòng. Đổi `name`, `description`, `maxPlayers`, `isPublic`, `password` (rỗng = bỏ mật khẩu), `lightingPreset`, `status=OPEN|CLOSED`. Không được giảm sức chứa dưới số member.

### DELETE /api/rooms/[code]

Chỉ chủ phòng. Xóa room + membership + ticket liên quan.

### POST /api/rooms/[code]/join

Rate limit 30/phút.

```json
{ "password": "1234" }
```

`200`:

```json
{
  "ticket": "random-256-bit",
  "expiresAt": "2026-11-03T...",
  "room": { ...room },
  "game": { "host": "127.0.0.1", "port": 7000, "serverId": null, "name": "default" },
  "isOwner": false,
  "role": "MEMBER"
}
```

Idempotent nếu đã là member. Lỗi: `404 ROOM_NOT_FOUND`, `409 ROOM_CLOSED`, `409 ROOM_FULL`, `403 WRONG_PASSWORD`.

### POST /api/rooms/[code]/leave

Xóa membership. Owner rời → chuyển quyền cho member sớm nhất; hết member → room `CLOSED`.
Trả `{ "ok": true, "remaining": n }`.

## 3. Game tickets

### POST /api/game/ticket

Body `{ "roomCode": "LOTUS-2481" }`. Yêu cầu là member. Ticket TTL **5 phút**, single-use.

```json
{ "ticket": "...", "expiresAt": "...", "room": {...}, "game": {"host":"...","port":7000}, "isOwner": true }
```

### POST /api/game/ticket/verify

**Chỉ game server.** Header `X-Game-Server-Secret` khớp `GAME_SERVER_SECRET`.
Body `{ "ticket": "..." }`. Đánh dấu đã dùng, trả:

```json
{
  "userId": "uuid", "username": "neonfox", "displayName": "Neon Fox", "isOwner": false,
  "room": { "id": "...", "code": "LOTUS-2481", "name": "...", "map": "...", "maxPlayers": 16, "lightingPreset": "party" }
}
```

Lỗi: `401 TICKET_INVALID`, `409 TICKET_USED`, `401 TICKET_EXPIRED`, `403 ACCOUNT_BANNED`, `409 ROOM_CLOSED`, `403 NOT_A_MEMBER`, `403 GAME_SECRET_INVALID`.

### POST /api/game/servers/heartbeat

Header secret. Body `{ name, host, port, region, capacity }`. Upsert registry, trả server id.

## 4. Friends

### GET /api/friends

```json
{
  "friends": [{ "id": "friendshipId", "status": "accepted", "user": {"id":"...","username":"...","displayName":"...","online":true}, "createdAt": "..." }],
  "incoming": [ ... ],
  "outgoing": [ ... ]
}
```

### POST /api/friends/request

`{ "username": "neonfox" }`. Nếu người kia đã gửi lời mời trước đó → tự động chấp nhận (`accepted: true`). Lỗi: `404 USER_NOT_FOUND`, `400 SELF_REQUEST`, `409 ALREADY_FRIENDS`, `403 BLOCKED`.

### POST /api/friends/accept

`{ "id": "friendshipId" }` — chỉ người nhận. `404 REQUEST_NOT_FOUND` nếu không hợp lệ.

### DELETE /api/friends/[id]

Xóa quan hệ nếu là một trong hai bên.

## 5. Inventory

### GET /api/inventory

Tự cấp starter items (idempotent). Trả `{ items: [{ id, itemKey, itemType, equipped, name, description, color, acquiredAt }] }`.

### POST /api/inventory/equip

`{ "itemId": "uuid" }`. Trang bị 1 item / loại; emote luôn dùng được khi sở hữu. Lỗi `404 ITEM_NOT_FOUND`.

## 6. Reports & moderation

### POST /api/reports

`{ "targetId": "uuid", "reason": "harassment|spam|hate|sexual|violence|cheating|other", "detail": "..." }`
Rate limit 5/10 phút. Không tự báo cáo mình. `201 { report }`.

### GET /api/moderation/reports

Role `MODERATOR`/`ADMIN`. Danh sách report `OPEN`.

### PATCH /api/moderation/users/[id]

Role `MODERATOR`/`ADMIN`. `{ "banned": true, "reason": "..." }`. Ban → thu hồi mọi session. Không thể tự khóa mình; moderator không khóa admin.

## 7. Health

`GET /api/health` → `200 { status: "ok", service, version, database: "up"|"down", time }`.

## 8. Rate limit mặc định

| Endpoint | Giới hạn |
| --- | --- |
| register | 8 / phút / IP |
| login | 12 / phút / IP |
| refresh / logout | 30 / phút / IP |
| rooms list/detail | 90–120 / phút / IP |
| room create | 6 / phút / IP |
| join | 30 / phút / IP |
| game ticket | 20 / phút / IP |
| ticket verify | 60 / phút / IP |
| reports | 5 / 10 phút / IP |

Vượt giới hạn → `429 RATE_LIMITED`. Dùng Redis nếu có `REDIS_URL`, nếu không in-memory (single instance).

## 9. Bảo mật triển khai

- `AUTH_SECRET` ≥ 32 ký tự, không commit.
- `GAME_SERVER_SECRET` chỉ chia sẻ backend ↔ game server.
- Access token 15 phút; refresh 30 ngày, rotate mỗi lần.
- Cookie httpOnly, secure khi production, sameSite=lax.
- Validate Origin với mutation dùng cookie.
- Không log token/mật khẩu; log JSON chỉ metadata request.
