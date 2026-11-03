import { randomBytes, timingSafeEqual } from "node:crypto";
import { env } from "./env";
import { ApiError } from "./http";
import { hashToken } from "./auth";
import { getPrisma } from "./prisma";
import { roomInclude, serializeRoom } from "./serialize";

const TICKET_TTL_MS = 5 * 60 * 1000;

export async function createGameTicket(userId: string, code: string) {
	const prisma = getPrisma();
	const room = await prisma.room.findUnique({
		where: { code },
		include: roomInclude(),
	});
	if (!room || room.status !== "OPEN") {
		throw new ApiError(404, "ROOM_NOT_FOUND", "Phòng không tồn tại hoặc đã đóng.");
	}
	const membership = await prisma.roomMember.findUnique({
		where: { roomId_userId: { roomId: room.id, userId } },
	});
	if (!membership) {
		throw new ApiError(403, "NOT_A_MEMBER", "Bạn chưa tham gia phòng này.");
	}
	if (room._count.members > room.maxPlayers) {
		throw new ApiError(409, "ROOM_FULL", "Phòng đã đầy.");
	}
	const ticket = randomBytes(32).toString("base64url");
	const expiresAt = new Date(Date.now() + TICKET_TTL_MS);
	await prisma.gameTicket.create({
		data: {
			ticketHash: hashToken(ticket),
			userId,
			roomId: room.id,
			expiresAt,
		},
	});
	const game = await selectGameServer();
	return {
		ticket,
		expiresAt: expiresAt.toISOString(),
		room: serializeRoom(room),
		game,
		isOwner: room.ownerId === userId,
	};
}

async function selectGameServer(): Promise<{ host: string; port: number; serverId: string | null; name: string }> {
	const prisma = getPrisma();
	const cutoff = new Date(Date.now() - 60_000);
	try {
		const server = await prisma.gameServer.findFirst({
			where: { status: "ONLINE", lastHeartbeatAt: { gte: cutoff } },
			orderBy: { lastHeartbeatAt: "desc" },
		});
		if (server) {
			return { host: server.host, port: server.port, serverId: server.id, name: server.name };
		}
	} catch {
		// Registry chưa migrate — rơi về cấu hình env.
	}
	return {
		host: env().GAME_SERVER_HOST,
		port: env().GAME_SERVER_PORT,
		serverId: null,
		name: "default",
	};
}

function assertGameServerSecret(provided: string | null): void {
	const expected = process.env.GAME_SERVER_SECRET;
	if (!expected) {
		throw new ApiError(503, "GAME_SECRET_MISSING", "Backend chưa cấu hình GAME_SERVER_SECRET.");
	}
	if (!provided) {
		throw new ApiError(401, "GAME_SECRET_REQUIRED", "Thiếu X-Game-Server-Secret.");
	}
	const a = Buffer.from(provided);
	const b = Buffer.from(expected);
	if (a.length !== b.length || !timingSafeEqual(a, b)) {
		throw new ApiError(403, "GAME_SECRET_INVALID", "X-Game-Server-Secret không hợp lệ.");
	}
}

export async function verifyGameTicket(ticket: string, secret: string | null) {
	assertGameServerSecret(secret);
	const prisma = getPrisma();
	const record = await prisma.gameTicket.findUnique({
		where: { ticketHash: hashToken(ticket) },
		include: {
			user: true,
			room: { include: { owner: { select: { id: true } } } },
		},
	});
	if (!record) {
		throw new ApiError(401, "TICKET_INVALID", "Game ticket không hợp lệ.");
	}
	if (record.usedAt) {
		throw new ApiError(409, "TICKET_USED", "Game ticket đã được sử dụng.");
	}
	if (record.expiresAt.getTime() <= Date.now()) {
		throw new ApiError(401, "TICKET_EXPIRED", "Game ticket đã hết hạn.");
	}
	if (record.user.bannedAt) {
		throw new ApiError(403, "ACCOUNT_BANNED", "Tài khoản đã bị khóa.");
	}
	if (record.room.status !== "OPEN") {
		throw new ApiError(409, "ROOM_CLOSED", "Phòng đã đóng.");
	}
	const membership = await prisma.roomMember.findUnique({
		where: { roomId_userId: { roomId: record.roomId, userId: record.userId } },
	});
	if (!membership) {
		throw new ApiError(403, "NOT_A_MEMBER", "Người chơi không còn trong phòng.");
	}
	await prisma.$transaction([
		prisma.gameTicket.update({ where: { id: record.id }, data: { usedAt: new Date() } }),
		prisma.user.update({ where: { id: record.userId }, data: { lastSeenAt: new Date() } }),
	]);
	return {
		userId: record.userId,
		username: record.user.username,
		displayName: record.user.displayName,
		isOwner: record.room.ownerId === record.userId,
		room: {
			id: record.room.id,
			code: record.room.code,
			name: record.room.name,
			map: record.room.map,
			maxPlayers: record.room.maxPlayers,
			lightingPreset: record.room.lightingPreset,
		},
	};
}
