import type { NextRequest } from "next/server";
import { publicUser, requireUser } from "@/lib/auth";
import { jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { updateProfileSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
	return withApi(request, { name: "users:me:get", rateLimit: { limit: 120, windowMs: 60_000 } }, async () => {
		const user = await requireUser(request);
		const prisma = getPrisma();
		const [friendsCount, roomsCount, inventory] = await Promise.all([
			prisma.friendship.count({
				where: {
					status: "ACCEPTED",
					OR: [{ requesterId: user.id }, { addresseeId: user.id }],
				},
			}),
			prisma.room.count({ where: { ownerId: user.id, status: "OPEN" } }),
			prisma.inventoryItem.findMany({ where: { userId: user.id, equipped: true } }),
		]);
		return jsonOk({
			user: publicUser(user),
			stats: { friends: friendsCount, openRooms: roomsCount },
			equipped: inventory.map((item) => ({ itemKey: item.itemKey, itemType: item.itemType })),
		});
	});
}

export async function PATCH(request: NextRequest) {
	return withApi(request, { name: "users:me:patch", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, updateProfileSchema);
		const data: Record<string, unknown> = {};
		if (input.displayName !== undefined) data.displayName = input.displayName;
		if (input.bio !== undefined) data.bio = input.bio === "" ? null : input.bio;
		if (input.avatarUrl !== undefined) data.avatarUrl = input.avatarUrl === "" ? null : input.avatarUrl;
		const updated = await getPrisma().user.update({ where: { id: user.id }, data });
		return jsonOk({ user: publicUser(updated) });
	});
}
