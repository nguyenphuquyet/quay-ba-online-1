import type { Room, RoomMember, User } from "@prisma/client";

export type RoomWithRelations = Room & {
	owner: Pick<User, "id" | "username" | "displayName" | "avatarUrl">;
	members?: Array<RoomMember & { user?: Pick<User, "id" | "username" | "displayName" | "avatarUrl"> }>;
	_count?: { members: number };
};

export function serializeRoom(room: RoomWithRelations): Record<string, unknown> {
	return {
		id: room.id,
		code: room.code,
		name: room.name,
		description: room.description,
		map: room.map,
		maxPlayers: room.maxPlayers,
		playerCount: room._count?.members ?? room.members?.length ?? 0,
		isPublic: room.isPublic,
		hasPassword: Boolean(room.passwordHash),
		status: room.status === "OPEN" ? "open" : "closed",
		lightingPreset: room.lightingPreset,
		owner: {
			id: room.owner.id,
			username: room.owner.username,
			displayName: room.owner.displayName,
			avatarUrl: room.owner.avatarUrl,
		},
		createdAt: room.createdAt.toISOString(),
		updatedAt: room.updatedAt.toISOString(),
	};
}

export function roomInclude() {
	return {
		owner: { select: { id: true, username: true, displayName: true, avatarUrl: true } },
		_count: { select: { members: true } },
	} as const;
}
