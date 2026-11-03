import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonCreated, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { reportSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "reports:create", rateLimit: { limit: 5, windowMs: 10 * 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, reportSchema);
		if (input.targetId === user.id) {
			throw new ApiError(400, "SELF_REPORT", "Không thể báo cáo chính mình.");
		}
		const prisma = getPrisma();
		const target = await prisma.user.findUnique({ where: { id: input.targetId }, select: { id: true } });
		if (!target) throw new ApiError(404, "USER_NOT_FOUND", "Không tìm thấy người chơi bị báo cáo.");
		const report = await prisma.report.create({
			data: {
				reporterId: user.id,
				targetId: input.targetId,
				reason: input.reason,
				detail: input.detail,
			},
		});
		return jsonCreated({
			report: {
				id: report.id,
				status: report.status.toLowerCase(),
				createdAt: report.createdAt.toISOString(),
			},
		});
	});
}
