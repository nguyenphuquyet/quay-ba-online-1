import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonCreated, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { friendRequestSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "friends:request", rateLimit: { limit: 20, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, friendRequestSchema);
		if (input.username === user.username) {
			throw new ApiError(400, "SELF_REQUEST", "Không thể kết bạn với chính mình.");
		}
		const prisma = getPrisma();
		const target = await prisma.user.findUnique({ where: { username: input.username } });
		if (!target) throw new ApiError(404, "USER_NOT_FOUND", "Không tìm thấy người chơi này.");

		const existing = await prisma.friendship.findFirst({
			where: {
				OR: [
					{ requesterId: user.id, addresseeId: target.id },
					{ requesterId: target.id, addresseeId: user.id },
				],
			},
		});
		if (existing) {
			if (existing.status === "ACCEPTED") {
				throw new ApiError(409, "ALREADY_FRIENDS", "Hai người đã là bạn bè.");
			}
			if (existing.status === "BLOCKED") {
				throw new ApiError(403, "BLOCKED", "Không thể gửi lời mời tới người chơi này.");
			}
			if (existing.status === "PENDING" && existing.addresseeId === user.id) {
				const accepted = await prisma.friendship.update({
					where: { id: existing.id },
					data: { status: "ACCEPTED" },
				});
				return jsonCreated({
					accepted: true,
					friendship: { id: accepted.id, status: "accepted" },
					message: "Hai người đã trở thành bạn bè.",
				});
			}
			throw new ApiError(409, "REQUEST_PENDING", "Lời mời kết bạn đã được gửi trước đó.");
		}

		const friendship = await prisma.friendship.create({
			data: { requesterId: user.id, addresseeId: target.id, status: "PENDING" },
		});
		return jsonCreated({
			accepted: false,
			friendship: { id: friendship.id, status: "pending" },
		});
	});
}
