import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { friendAcceptSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "friends:accept", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, friendAcceptSchema);
		const result = await getPrisma().friendship.updateMany({
			where: { id: input.id, addresseeId: user.id, status: "PENDING" },
			data: { status: "ACCEPTED" },
		});
		if (result.count === 0) {
			throw new ApiError(404, "REQUEST_NOT_FOUND", "Không tìm thấy lời mời kết bạn.");
		}
		return jsonOk({ ok: true });
	});
}
