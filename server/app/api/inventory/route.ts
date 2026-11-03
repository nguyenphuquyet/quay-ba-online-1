import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { jsonOk, withApi } from "@/lib/http";
import { definitionFor, STARTER_ITEMS } from "@/lib/inventory";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
	return withApi(request, { name: "inventory:list", rateLimit: { limit: 60, windowMs: 60_000 } }, async () => {
		const user = await requireUser(request);
		const prisma = getPrisma();
		await prisma.inventoryItem.createMany({
			data: STARTER_ITEMS.map((itemKey) => ({
				userId: user.id,
				itemKey,
				itemType: definitionFor(itemKey)?.type ?? "outfit",
				equipped: false,
			})),
			skipDuplicates: true,
		});
		const items = await prisma.inventoryItem.findMany({
			where: { userId: user.id },
			orderBy: [{ itemType: "asc" }, { acquiredAt: "asc" }],
		});
		return jsonOk({
			items: items.map((item) => {
				const definition = definitionFor(item.itemKey);
				return {
					id: item.id,
					itemKey: item.itemKey,
					itemType: item.itemType,
					equipped: item.equipped,
					name: definition?.name ?? item.itemKey,
					description: definition?.description ?? "",
					color: definition?.color ?? null,
					acquiredAt: item.acquiredAt.toISOString(),
				};
			}),
		});
	});
}
