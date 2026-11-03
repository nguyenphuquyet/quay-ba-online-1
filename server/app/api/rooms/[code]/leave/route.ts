import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonOk, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { roomCodeParam } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:leave", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { code: rawCode } = await context.params;
		const code = roomCodeParam.parse(rawCode);
		const prisma = getPrisma();

		const room = await prisma.room.findUnique({ where: { code } });
		if (!room) throw new ApiError(404, "ROOM_NOT_FOUND", "Phòng không tồn tại.");

		const membership = await prisma.roomMember.findUnique({
			where: { roomId_userId: { roomId: room.id, userId: user.id } },
		});
		if (!membership) {
			return jsonOk({ ok: true, alreadyLeft: true });
		}

		await prisma.roomMember.delete({ where: { id: membership.id } });

		if (room.ownerId === user.id) {
			const nextOwner = await prisma.roomMember.findFirst({
				where: { roomId: room.id },
				orderBy: { joinedAt: "asc" },
			});
			if (nextOwner) {
				await prisma.$transaction([
					prisma.roomMember.update({ where: { id: nextOwner.id }, data: { role: "OWNER" } }),
					prisma.room.update({ where: { id: room.id }, data: { ownerId: nextOwner.userId } }),
				]);
			} else {
				await prisma.room.update({ where: { id: room.id }, data: { status: "CLOSED" } });
			}
		}

		const remaining = await prisma.roomMember.count({ where: { roomId: room.id } });
		return jsonOk({ ok: true, remaining });
	});
}
