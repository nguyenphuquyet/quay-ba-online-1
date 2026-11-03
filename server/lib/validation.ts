import { z } from "zod";

const username = z
	.string()
	.trim()
	.toLowerCase()
	.min(3, "Username tối thiểu 3 ký tự")
	.max(24, "Username tối đa 24 ký tự")
	.regex(/^[a-z0-9_]+$/, "Username chỉ gồm chữ thường, số và dấu gạch dưới");

const password = z.string().min(8, "Mật khẩu tối thiểu 8 ký tự").max(128, "Mật khẩu tối đa 128 ký tự");

export const registerSchema = z.object({
	username,
	email: z.string().trim().toLowerCase().email("Email không hợp lệ").max(191),
	password,
	displayName: z.string().trim().min(2, "Tên hiển thị tối thiểu 2 ký tự").max(32, "Tên hiển thị tối đa 32 ký tự"),
});

export const loginSchema = z.object({
	identifier: z.string().trim().min(3, "Nhập username hoặc email").max(191),
	password: z.string().min(1, "Nhập mật khẩu").max(128),
});

export const refreshSchema = z.object({
	refreshToken: z.string().min(10).optional(),
});

export const updateProfileSchema = z
	.object({
		displayName: z.string().trim().min(2).max(32).optional(),
		bio: z.string().trim().max(280).nullable().optional(),
		avatarUrl: z
			.string()
			.trim()
			.max(500)
			.refine((value) => value === "" || /^https?:\/\//i.test(value), "Avatar phải là URL http/https")
			.nullable()
			.optional(),
	})
	.refine((value) => Object.keys(value).length > 0, "Không có trường nào để cập nhật");

const roomCodePattern = /^[A-Z0-9-]{4,16}$/;

export const roomCodeParam = z.string().trim().toUpperCase().regex(roomCodePattern, "Mã phòng không hợp lệ");

export const createRoomSchema = z.object({
	name: z.string().trim().min(3, "Tên phòng tối thiểu 3 ký tự").max(60),
	description: z.string().trim().max(280).default(""),
	maxPlayers: z.coerce.number().int().min(2).max(32).default(16),
	isPublic: z.boolean().default(true),
	password: z.string().max(64).default(""),
	map: z.string().trim().max(48).default("the_chrome_lotus"),
	lightingPreset: z
		.enum(["chill", "lounge", "party", "edm", "cyberpunk", "chinese_neon", "vip", "blackout"])
		.default("party"),
});

export const updateRoomSchema = z
	.object({
		name: z.string().trim().min(3).max(60).optional(),
		description: z.string().trim().max(280).optional(),
		maxPlayers: z.coerce.number().int().min(2).max(32).optional(),
		isPublic: z.boolean().optional(),
		password: z.string().max(64).optional(),
		lightingPreset: z
			.enum(["chill", "lounge", "party", "edm", "cyberpunk", "chinese_neon", "vip", "blackout"])
			.optional(),
		status: z.enum(["OPEN", "CLOSED"]).optional(),
	})
	.refine((value) => Object.keys(value).length > 0, "Không có trường nào để cập nhật");

export const joinRoomSchema = z.object({
	password: z.string().max(64).default(""),
});

export const roomListQuerySchema = z.object({
	search: z.string().trim().max(60).default(""),
	visibility: z.enum(["all", "public", "private"]).default("all"),
	limit: z.coerce.number().int().min(1).max(50).default(30),
});

export const friendRequestSchema = z.object({ username });
export const friendAcceptSchema = z.object({ id: z.string().uuid() });
export const friendIdParam = z.string().uuid("ID bạn bè không hợp lệ");

export const reportSchema = z.object({
	targetId: z.string().uuid(),
	reason: z.enum(["harassment", "spam", "hate", "sexual", "violence", "cheating", "other"]),
	detail: z.string().trim().max(500).default(""),
});

export const equipSchema = z.object({ itemId: z.string().uuid() });

export const gameTicketSchema = z.object({ roomCode: roomCodeParam });

export const gameTicketVerifySchema = z.object({ ticket: z.string().min(20, "Ticket không hợp lệ").max(200) });

export const heartbeatSchema = z.object({
	name: z.string().trim().min(1).max(60),
	host: z.string().trim().min(1).max(191),
	port: z.coerce.number().int().positive().max(65535),
	region: z.string().trim().max(32).default("local"),
	capacity: z.coerce.number().int().min(1).max(64).default(32),
});

export const moderationBanSchema = z.object({
	banned: z.boolean(),
	reason: z.string().trim().max(280).optional(),
});
