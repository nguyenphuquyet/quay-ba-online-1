import type { NextRequest } from "next/server";
import { randomInt } from "node:crypto";
import { publicUser, requireUser } from "@/lib/auth";
import { ApiError, jsonCreated, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { roomInclude, serializeRoom } from "@/lib/serialize";
import { createRoomSchema, roomListQuerySchema } from "@/lib/validation";
import { hashPassword } from "@/lib/auth";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
	return withApi(request, { name: "rooms:list", rateLimit: { limit: 90, windowMs: 60_000 } }, async () => {
		const params = request.nextUrl.searchParams;
		const query = roomListQuerySchema.parse({
			search: params.get("search") ?? undefined,
			visibility: params.get("visibility") ?? undefined,
			limit: params.get("limit") ?? undefined,
		});
		const where: Record<string, unknown> = { status: "OPEN" };
		if (query.visibility === "public") where.isPublic = true;
		if (query.visibility === "private") where.isPublic = false;
		if (query.search !== "") {
			where.OR = [
				{ name: { contains: query.search } },
				{ code: { contains: query.search.toUpperCase() } },
				{ owner: { displayName: { contains: query.search } } },
				{ owner: { username: { contains: query.search.toLowerCase() } } },
			];
		}
		const rooms = await getPrisma().room.findMany({
			where,
			include: roomInclude(),
			orderBy: { createdAt: "desc" },
			take: query.limit,
		});
		return jsonOk({ rooms: rooms.map(serializeRoom) });
	});
}

async function generateRoomCode(): Promise<string> {
	const prisma = getPrisma();
	for (let attempt = 0; attempt < 20; attempt += 1) {
		const code = `LOTUS-${randomInt(1000, 9999)}`;
		const existing = await prisma.room.findUnique({ where: { code }, select: { id: true } });
		if (!existing) return code;
	}
	throw new ApiError(500, "ROOM_CODE_EXHAUSTED", "Không sinh được mã phòng mới, thử lại sau.");
}

export async function POST(request: NextRequest) {
	return withApi(request, { name: "rooms:create", rateLimit: { limit: 6, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, createRoomSchema);
		const prisma = getPrisma();

		const openRooms = await prisma.room.count({ where: { ownerId: user.id, status: "OPEN" } });
		if (openRooms >= 3) {
			throw new ApiError(409, "TOO_MANY_ROOMS", "Bạn đã có 3 phòng đang mở. Hãy đóng phòng cũ trước.");
		}

		const passwordHash = input.isPublic || input.password === "" ? null : await hashPassword(input.password);
		const code = await generateRoomCode();
		const room = await prisma.room.create({
			data: {
				code,
				name: input.name,
				description: input.description,
				map: input.map,
				maxPlayers: input.maxPlayers,
				isPublic: input.isPublic,
				passwordHash,
				lightingPreset: input.lightingPreset,
				ownerId: user.id,
			},
		});
		await prisma.roomMember.create({
			data: { roomId: room.id, userId: user.id, role: "OWNER" },
		});
		const full = await prisma.room.findUnique({ where: { id: room.id }, include: roomInclude() });
		if (!full) {
			throw new ApiError(500, "ROOM_CREATE_FAILED", "Không tạo được phòng.");
		}
		return jsonCreated({
			room: serializeRoom(full),
			owner: publicUser(user),
		});
	});
}
