import type { NextRequest } from "next/server";
import { z } from "zod";
import { requireRole } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { moderationBanSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
	return withApi(request, { name: "moderation:ban", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const moderator = await requireRole(request, ["MODERATOR", "ADMIN"]);
		const { id } = await context.params;
		const parsed = z.string().uuid().safeParse(id);
		if (!parsed.success) throw new ApiError(400, "INVALID_ID", "ID người dùng không hợp lệ.");
		if (parsed.data === moderator.id) {
			throw new ApiError(400, "SELF_MODERATION", "Không thể tự khóa tài khoản của mình.");
		}
		const input = await parseJson(request, moderationBanSchema);
		const prisma = getPrisma();
		const target = await prisma.user.findUnique({ where: { id: parsed.data } });
		if (!target) throw new ApiError(404, "USER_NOT_FOUND", "Không tìm thấy người chơi.");
		if (target.role === "ADMIN" && moderator.role !== "ADMIN") {
			throw new ApiError(403, "FORBIDDEN", "Không thể khóa tài khoản admin.");
		}
		const updated = await prisma.user.update({
			where: { id: target.id },
			data: { bannedAt: input.banned ? new Date() : null },
		});
		if (input.banned) {
			await prisma.session.updateMany({
				where: { userId: target.id, revokedAt: null },
				data: { revokedAt: new Date() },
			});
		}
		return jsonOk({ user: { id: updated.id, banned: updated.bannedAt !== null } });
	});
}
