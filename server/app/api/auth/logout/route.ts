import type { NextRequest } from "next/server";
import { clearAuthCookies, REFRESH_COOKIE, revokeRefreshToken } from "@/lib/auth";
import { jsonOk, parseJson, withApi } from "@/lib/http";
import { refreshSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "auth:logout", rateLimit: { limit: 30, windowMs: 60_000 } }, async () => {
		const input = await parseJson(request, refreshSchema).catch(() => ({ refreshToken: undefined }));
		const token = input.refreshToken ?? request.cookies.get(REFRESH_COOKIE)?.value;
		if (token) {
			await revokeRefreshToken(token);
		}
		const response = jsonOk({ ok: true });
		clearAuthCookies(response);
		return response;
	});
}
