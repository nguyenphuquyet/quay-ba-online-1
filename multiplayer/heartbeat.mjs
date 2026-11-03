#!/usr/bin/env node
/**
 * Đăng ký dedicated server với backend để /api/game/ticket chọn đúng server.
 * Chạy cùng game server, dùng chung GAME_SERVER_SECRET.
 */
const apiUrl = (process.env.QBO_API_URL || "http://127.0.0.1:3000").replace(/\/$/, "");
const secret = process.env.GAME_SERVER_SECRET || "";
const port = Number(process.env.GAME_SERVER_PORT || 7000);
const interval = Number(process.env.HEARTBEAT_INTERVAL_MS || 30000);
const name = process.env.GAME_SERVER_NAME || "The Chrome Lotus - dedicated";
const region = process.env.GAME_SERVER_REGION || "local";

/**
 * IP mà CLIENT dùng để kết nối UDP. Trên VPS phải là IP công khai, KHÔNG phải
 * hostname nội bộ Docker (`game-server`) — client ngoài Internet không phân
 * giải được tên đó.
 */
async function resolveHost() {
  const configured = (process.env.GAME_SERVER_HOST || "").trim();
  if (configured) return configured;
  try {
    const response = await fetch("https://api.ipify.org");
    if (response.ok) {
      const ip = (await response.text()).trim();
      if (ip) return ip;
    }
  } catch {
    // Không có Internet ra ngoài — để backend tự suy ra từ request.
  }
  return "";
}

const host = await resolveHost();

if (!secret) {
  console.error("[heartbeat] Thiếu GAME_SERVER_SECRET — dừng.");
  process.exit(1);
}

async function beat() {
  try {
    const response = await fetch(`${apiUrl}/api/game/servers/heartbeat`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Game-Server-Secret": secret,
      },
      body: JSON.stringify({ name, host, port, region, capacity: 32 }),
    });
    if (!response.ok) {
      const text = await response.text();
      console.warn(`[heartbeat] HTTP ${response.status}: ${text.slice(0, 200)}`);
      return;
    }
    const data = await response.json();
    console.log(`[heartbeat] ok server=${data.server?.id ?? "?"} ${host}:${port}`);
  } catch (error) {
    console.warn(`[heartbeat] lỗi mạng: ${error instanceof Error ? error.message : String(error)}`);
  }
}

console.log(`[heartbeat] ${apiUrl} ← ${name} (${host || "auto"}:${port}) mỗi ${interval}ms`);
await beat();
setInterval(beat, interval);
