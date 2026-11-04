import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonOk, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { roomCodeParam } from "@/lib/validation";

export const dynamic = "force-dynamic";

/**
 * Heartbeat giữ phòng "còn sống" khi client đang ở trong phòng.
 * Client gọi mỗi 30 giây; danh sách phòng sẽ đóng phòng quá 2 phút không có nhịp.
 */
export async function POST(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:heartbeat", rateLimit: { limit: 12, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { code: rawCode } = await context.params;
		const code = roomCodeParam.parse(rawCode);
		const prisma = getPrisma();

		const room = await prisma.room.findUnique({ where: { code }, select: { id: true, status: true } });
		if (!room) throw new ApiError(404, "ROOM_NOT_FOUND", "Phòng không tồn tại.");
		if (room.status !== "OPEN") throw new ApiError(409, "ROOM_CLOSED", "Phòng đã đóng.");

		const membership = await prisma.roomMember.findUnique({
			where: { roomId_userId: { roomId: room.id, userId: user.id } },
			select: { id: true },
		});
		if (!membership) throw new ApiError(403, "NOT_A_MEMBER", "Bạn không còn trong phòng này.");

		// `updatedAt` được dùng làm mốc hoạt động gần nhất của phòng.
		await prisma.room.update({ where: { id: room.id }, data: { updatedAt: new Date() } });
		return jsonOk({ ok: true });
	});
}
