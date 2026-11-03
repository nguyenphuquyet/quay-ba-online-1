import type { NextRequest } from "next/server";
import { z } from "zod";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonOk, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
	return withApi(request, { name: "friends:delete", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { id } = await context.params;
		const parsed = z.string().uuid().safeParse(id);
		if (!parsed.success) {
			throw new ApiError(400, "INVALID_ID", "ID bạn bè không hợp lệ.");
		}
		const result = await getPrisma().friendship.deleteMany({
			where: {
				id: parsed.data,
				OR: [{ requesterId: user.id }, { addresseeId: user.id }],
			},
		});
		if (result.count === 0) {
			throw new ApiError(404, "FRIENDSHIP_NOT_FOUND", "Không tìm thấy quan hệ bạn bè.");
		}
		return jsonOk({ ok: true });
	});
}
