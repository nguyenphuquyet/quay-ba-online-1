#!/usr/bin/env node
/**
 * Probe backend không cần MySQL:
 * - health trả 200 (database có thể down)
 * - route bảo vệ trả 401
 * - validation trả 422
 * - verify ticket thiếu/sai secret trả 401/403
 * - landing page trả 200
 *
 * Chạy: BASE_URL=http://127.0.0.1:3100 node tools/development/api_probe.mjs
 */
const base = (process.env.BASE_URL || "http://127.0.0.1:3000").replace(/\/$/, "");
let failures = 0;

async function call(path, options = {}) {
	const response = await fetch(`${base}${path}`, options);
	const text = await response.text();
	let json = null;
	try {
		json = JSON.parse(text);
	} catch {
		/* HTML hoặc rỗng */
	}
	return { status: response.status, json, text };
}

function expect(label, condition, detail) {
	if (condition) {
		console.log(`PASS  ${label}`);
	} else {
		failures += 1;
		console.log(`FAIL  ${label} — ${detail}`);
	}
}

const jsonPost = (body, headers = {}) => ({
	method: "POST",
	headers: { "content-type": "application/json", ...headers },
	body: JSON.stringify(body),
});

const health = await call("/api/health");
expect("health 200", health.status === 200, `status=${health.status}`);
expect("health có database field", health.json?.database === "up" || health.json?.database === "down", JSON.stringify(health.json));

const me = await call("/api/users/me");
expect("me không auth → 401", me.status === 401, `status=${me.status}`);

const register = await call("/api/auth/register", jsonPost({ username: "x", email: "bad", password: "1", displayName: "" }));
expect("register invalid → 422", register.status === 422, `status=${register.status} body=${register.text.slice(0, 120)}`);
expect("register lỗi có code VALIDATION_ERROR", register.json?.error?.code === "VALIDATION_ERROR", JSON.stringify(register.json));

const login = await call("/api/auth/login", jsonPost({ identifier: "a" }));
expect("login thiếu password → 422", login.status === 422, `status=${login.status}`);

const verifyNoSecret = await call("/api/game/ticket/verify", jsonPost({ ticket: "x".repeat(30) }));
expect("verify thiếu secret → 401", verifyNoSecret.status === 401, `status=${verifyNoSecret.status} ${verifyNoSecret.text.slice(0, 120)}`);

const verifyBadSecret = await call(
	"/api/game/ticket/verify",
	jsonPost({ ticket: "x".repeat(30) }, { "x-game-server-secret": "wrong-secret" }),
);
expect("verify sai secret → 403", verifyBadSecret.status === 403, `status=${verifyBadSecret.status} ${verifyBadSecret.text.slice(0, 120)}`);

const rooms = await call("/api/rooms");
expect(
	"rooms list DB-down → 200 hoặc 500 (không crash process)",
	rooms.status === 200 || rooms.status === 500,
	`status=${rooms.status}`,
);

const home = await call("/");
expect("landing 200", home.status === 200, `status=${home.status}`);
expect("landing có tiêu đề", home.text.includes("QUẨY BAR ONLINE"), "missing title");

console.log(failures === 0 ? "\nAPI PROBE: PASS" : `\nAPI PROBE: ${failures} FAIL`);
process.exit(failures === 0 ? 0 : 1);
