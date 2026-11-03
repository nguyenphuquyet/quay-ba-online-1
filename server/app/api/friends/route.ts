import type { NextRequest } from "next/server";
import type { User } from "@prisma/client";
import { requireUser } from "@/lib/auth";
import { jsonOk, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

type FriendUser = Pick<User, "id" | "username" | "displayName" | "avatarUrl" | "lastSeenAt">;

function isOnline(user: FriendUser): boolean {
	return user.lastSeenAt !== null && Date.now() - user.lastSeenAt.getTime() < 2 * 60_000;
}

function serializeUser(user: FriendUser) {
	return {
		id: user.id,
		username: user.username,
		displayName: user.displayName,
		avatarUrl: user.avatarUrl,
		online: isOnline(user),
	};
}

export async function GET(request: NextRequest) {
	return withApi(request, { name: "friends:list", rateLimit: { limit: 90, windowMs: 60_000 } }, async () => {
		const user = await requireUser(request);
		const rows = await getPrisma().friendship.findMany({
			where: { OR: [{ requesterId: user.id }, { addresseeId: user.id }] },
			include: {
				requester: { select: { id: true, username: true, displayName: true, avatarUrl: true, lastSeenAt: true } },
				addressee: { select: { id: true, username: true, displayName: true, avatarUrl: true, lastSeenAt: true } },
			},
			orderBy: { updatedAt: "desc" },
		});

		const friends: unknown[] = [];
		const incoming: unknown[] = [];
		const outgoing: unknown[] = [];

		for (const row of rows) {
			const isRequester = row.requesterId === user.id;
			const other = isRequester ? row.addressee : row.requester;
			const payload = {
				id: row.id,
				status: row.status.toLowerCase(),
				user: serializeUser(other),
				createdAt: row.createdAt.toISOString(),
			};
			if (row.status === "ACCEPTED") {
				friends.push(payload);
			} else if (row.status === "PENDING" && !isRequester) {
				incoming.push(payload);
			} else if (row.status === "PENDING" && isRequester) {
				outgoing.push(payload);
			}
		}

		return jsonOk({ friends, incoming, outgoing });
	});
}
