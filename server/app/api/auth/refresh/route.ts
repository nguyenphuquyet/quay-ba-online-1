import type { NextRequest } from "next/server";
import { applyAuthCookies, REFRESH_COOKIE, rotateRefreshToken } from "@/lib/auth";
import { ApiError, jsonOk, parseJson, withApi } from "@/lib/http";
import { refreshSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "auth:refresh", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		const input = await parseJson(request, refreshSchema).catch(() => ({ refreshToken: undefined }));
		const token = input.refreshToken ?? request.cookies.get(REFRESH_COOKIE)?.value;
		if (!token) {
			throw new ApiError(401, "REFRESH_REQUIRED", "Thiếu refresh token.");
		}
		const tokens = await rotateRefreshToken(token, {
			userAgent: request.headers.get("user-agent"),
			ip: request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
		});
		const response = jsonOk(tokens);
		applyAuthCookies(response, tokens);
		return response;
	});
}
