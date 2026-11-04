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

		// Phòng là tạm thời: chủ phòng rời đi thì đóng phòng, không chuyển quyền.
		if (room.ownerId === user.id) {
			await prisma.$transaction([
				prisma.room.update({ where: { id: room.id }, data: { status: "CLOSED" } }),
				prisma.roomMember.deleteMany({ where: { roomId: room.id } }),
			]);
			return jsonOk({ ok: true, remaining: 0, closed: true });
		}

		await prisma.roomMember.delete({ where: { id: membership.id } });
		const remaining = await prisma.roomMember.count({ where: { roomId: room.id } });
		if (remaining === 0) {
			await prisma.room.update({ where: { id: room.id }, data: { status: "CLOSED" } });
		}
		return jsonOk({ ok: true, remaining, closed: remaining === 0 });
	});
}
