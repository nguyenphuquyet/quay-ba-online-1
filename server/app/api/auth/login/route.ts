import type { NextRequest } from "next/server";
import { applyAuthCookies, issueTokens, verifyPassword } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { loginSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "auth:login", rateLimit: { limit: 12, windowMs: 60_000 } }, async () => {
		const input = await parseJson(request, loginSchema);
		const identifier = input.identifier.toLowerCase();
		const user = await getPrisma().user.findFirst({
			where: { OR: [{ username: identifier }, { email: identifier }] },
		});
		if (!user) {
			throw new ApiError(401, "INVALID_CREDENTIALS", "Tài khoản hoặc mật khẩu không đúng.");
		}
		const valid = await verifyPassword(input.password, user.passwordHash);
		if (!valid) {
			throw new ApiError(401, "INVALID_CREDENTIALS", "Tài khoản hoặc mật khẩu không đúng.");
		}
		if (user.bannedAt) {
			throw new ApiError(403, "ACCOUNT_BANNED", "Tài khoản đã bị khóa. Liên hệ ban quản trị.");
		}
		const tokens = await issueTokens(user, {
			userAgent: request.headers.get("user-agent"),
			ip: request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
		});
		const response = jsonOk(tokens);
		applyAuthCookies(response, tokens);
		return response;
	});
}
