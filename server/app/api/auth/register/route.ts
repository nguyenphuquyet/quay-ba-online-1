import type { NextRequest } from "next/server";
import { Prisma } from "@prisma/client";
import { applyAuthCookies, hashPassword, issueTokens } from "@/lib/auth";
import { ApiError, jsonCreated, parseJson, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";
import { registerSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "auth:register", rateLimit: { limit: 8, windowMs: 60_000 } }, async () => {
		const input = await parseJson(request, registerSchema);
		const prisma = getPrisma();

		const existing = await prisma.user.findFirst({
			where: { OR: [{ username: input.username }, { email: input.email }] },
			select: { username: true, email: true },
		});
		if (existing) {
			if (existing.username === input.username) {
				throw new ApiError(409, "USERNAME_TAKEN", "Username này đã được sử dụng.");
			}
			throw new ApiError(409, "EMAIL_TAKEN", "Email này đã được đăng ký.");
		}

		const passwordHash = await hashPassword(input.password);
		let user;
		try {
			user = await prisma.user.create({
				data: {
					username: input.username,
					email: input.email,
					passwordHash,
					displayName: input.displayName,
					lastSeenAt: new Date(),
				},
			});
		} catch (error) {
			if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
				throw new ApiError(409, "ACCOUNT_EXISTS", "Username hoặc email đã tồn tại.");
			}
			throw error;
		}

		const tokens = await issueTokens(user, {
			userAgent: request.headers.get("user-agent"),
			ip: request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
		});
		const response = jsonCreated(tokens);
		applyAuthCookies(response, tokens);
		return response;
	});
}
