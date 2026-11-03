import type { NextRequest } from "next/server";
import { ApiError, jsonOk, parseJson, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { heartbeatSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "game:heartbeat", rateLimit: { limit: 120, windowMs: 60_000 } }, async () => {
		const expected = process.env.GAME_SERVER_SECRET;
		const secret = request.headers.get("x-game-server-secret");
		if (!expected) {
			throw new ApiError(503, "GAME_SECRET_MISSING", "Backend chưa cấu hình GAME_SERVER_SECRET.");
		}
		if (!secret || secret !== expected) {
			throw new ApiError(403, "GAME_SECRET_INVALID", "X-Game-Server-Secret không hợp lệ.");
		}
		const input = await parseJson(request, heartbeatSchema);
		const prisma = getPrisma();
		const server = await prisma.gameServer.upsert({
			where: { host_port: { host: input.host, port: input.port } },
			create: {
				name: input.name,
				host: input.host,
				port: input.port,
				region: input.region,
				capacity: input.capacity,
				status: "ONLINE",
				lastHeartbeatAt: new Date(),
			},
			update: {
				name: input.name,
				region: input.region,
				capacity: input.capacity,
				status: "ONLINE",
				lastHeartbeatAt: new Date(),
			},
		});
		return jsonOk({
			server: {
				id: server.id,
				name: server.name,
				host: server.host,
				port: server.port,
				lastHeartbeatAt: server.lastHeartbeatAt.toISOString(),
			},
		});
	});
}
