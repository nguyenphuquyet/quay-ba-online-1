import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { equipSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "inventory:equip", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, equipSchema);
		const prisma = getPrisma();
		const item = await prisma.inventoryItem.findFirst({ where: { id: input.itemId, userId: user.id } });
		if (!item) throw new ApiError(404, "ITEM_NOT_FOUND", "Bạn không sở hữu vật phẩm này.");
		if (item.itemType === "emote") {
			return jsonOk({ ok: true, equipped: item.itemKey, note: "Emote luôn khả dụng khi đã sở hữu." });
		}
		await prisma.$transaction([
			prisma.inventoryItem.updateMany({
				where: { userId: user.id, itemType: item.itemType, equipped: true },
				data: { equipped: false },
			}),
			prisma.inventoryItem.update({ where: { id: item.id }, data: { equipped: true } }),
		]);
		return jsonOk({ ok: true, equipped: item.itemKey, itemType: item.itemType });
	});
}
