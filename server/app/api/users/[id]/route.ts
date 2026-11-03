import type { NextRequest } from "next/server";
import { ApiError, jsonOk, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
	return withApi(request, { name: "users:public", rateLimit: { limit: 120, windowMs: 60_000 } }, async () => {
		const { id } = await context.params;
		if (!/^[0-9a-f-]{36}$/i.test(id)) {
			throw new ApiError(400, "INVALID_ID", "ID người dùng không hợp lệ.");
		}
		const prisma = getPrisma();
		const user = await prisma.user.findUnique({
			where: { id },
			select: {
				id: true,
				username: true,
				displayName: true,
				avatarUrl: true,
				bio: true,
				createdAt: true,
				lastSeenAt: true,
				bannedAt: true,
				_count: { select: { ownedRooms: true, friendRequestsSent: true } },
			},
		});
		if (!user) {
			throw new ApiError(404, "USER_NOT_FOUND", "Không tìm thấy người chơi.");
		}
		const online = user.lastSeenAt !== null && Date.now() - user.lastSeenAt.getTime() < 2 * 60_000;
		return jsonOk({
			user: {
				id: user.id,
				username: user.username,
				displayName: user.displayName,
				avatarUrl: user.avatarUrl,
				bio: user.bio,
				createdAt: user.createdAt.toISOString(),
				online,
				banned: user.bannedAt !== null,
				stats: {
					roomsCreated: user._count.ownedRooms,
				},
			},
		});
	});
}
