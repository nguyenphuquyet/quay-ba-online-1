import type { NextRequest } from "next/server";
import { hashPassword, requireUser } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { roomInclude, serializeRoom } from "@/lib/serialize";
import { roomCodeParam, updateRoomSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

async function loadRoom(rawCode: string) {
	const code = roomCodeParam.parse(rawCode);
	const room = await getPrisma().room.findUnique({
		where: { code },
		include: {
			...roomInclude(),
			members: {
				include: { user: { select: { id: true, username: true, displayName: true, avatarUrl: true } } },
				orderBy: { joinedAt: "asc" },
				take: 40,
			},
		},
	});
	if (!room) throw new ApiError(404, "ROOM_NOT_FOUND", "Không tìm thấy phòng.");
	return room;
}

export async function GET(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:detail", rateLimit: { limit: 120, windowMs: 60_000 } }, async () => {
		const { code } = await context.params;
		const room = await loadRoom(code);
		return jsonOk({
			room: {
				...serializeRoom(room),
				members: room.members.map((member) => ({
					id: member.user.id,
					username: member.user.username,
					displayName: member.user.displayName,
					avatarUrl: member.user.avatarUrl,
					role: member.role,
					joinedAt: member.joinedAt.toISOString(),
				})),
			},
		});
	});
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:update", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { code } = await context.params;
		const room = await loadRoom(code);
		if (room.ownerId !== user.id) {
			throw new ApiError(403, "NOT_OWNER", "Chỉ chủ phòng mới được đổi cài đặt.");
		}
		const input = await parseJson(request, updateRoomSchema);
		if (input.maxPlayers !== undefined && input.maxPlayers < room.members.length) {
			throw new ApiError(409, "CAPACITY_TOO_LOW", `Phòng đang có ${room.members.length} người.`);
		}
		const data: Record<string, unknown> = {};
		if (input.name !== undefined) data.name = input.name;
		if (input.description !== undefined) data.description = input.description;
		if (input.maxPlayers !== undefined) data.maxPlayers = input.maxPlayers;
		if (input.isPublic !== undefined) data.isPublic = input.isPublic;
		if (input.lightingPreset !== undefined) data.lightingPreset = input.lightingPreset;
		if (input.status !== undefined) data.status = input.status;
		if (input.password !== undefined) {
			data.passwordHash = input.password === "" ? null : await hashPassword(input.password);
		}
		const updated = await getPrisma().room.update({
			where: { id: room.id },
			data,
			include: roomInclude(),
		});
		return jsonOk({ room: serializeRoom(updated) });
	});
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "rooms:delete", rateLimit: { limit: 12, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const { code } = await context.params;
		const room = await loadRoom(code);
		if (room.ownerId !== user.id) {
			throw new ApiError(403, "NOT_OWNER", "Chỉ chủ phòng mới được xóa phòng.");
		}
		await getPrisma().room.delete({ where: { id: room.id } });
		return jsonOk({ ok: true });
	});
}
