import type { NextRequest } from "next/server";
import { requireUser, verifyPassword } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { roomInclude, serializeRoom } from "@/lib/serialize";
import { createGameTicket } from "@/lib/tickets";
import { joinRoomSchema, roomCodeParam } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:join", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { code: rawCode } = await context.params;
		const code = roomCodeParam.parse(rawCode);
		const input = await parseJson(request, joinRoomSchema);
		const prisma = getPrisma();

		const room = await prisma.room.findUnique({ where: { code }, include: roomInclude() });
		if (!room) throw new ApiError(404, "ROOM_NOT_FOUND", "Phòng không tồn tại.");
		if (room.status !== "OPEN") throw new ApiError(409, "ROOM_CLOSED", "Phòng đã đóng.");

		const existing = await prisma.roomMember.findUnique({
			where: { roomId_userId: { roomId: room.id, userId: user.id } },
		});
		if (!existing) {
			if (room._count.members >= room.maxPlayers) {
				throw new ApiError(409, "ROOM_FULL", "Phòng đã đầy.");
			}
			if (room.passwordHash) {
				const valid = await verifyPassword(input.password, room.passwordHash);
				if (!valid) throw new ApiError(403, "WRONG_PASSWORD", "Mật khẩu phòng không đúng.");
			}
			await prisma.roomMember.create({
				data: { roomId: room.id, userId: user.id, role: "MEMBER" },
			});
		}

		const ticketData = await createGameTicket(user.id, code);
		const refreshed = await prisma.room.findUnique({ where: { id: room.id }, include: roomInclude() });
		if (!refreshed) throw new ApiError(404, "ROOM_NOT_FOUND", "Phòng không tồn tại.");
		return jsonOk({
			...ticketData,
			room: serializeRoom(refreshed),
			role: existing?.role ?? "MEMBER",
			isOwner: room.ownerId === user.id,
		});
	});
}
