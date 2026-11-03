import bcrypt from "bcryptjs";
import { SignJWT, jwtVerify } from "jose";
import { createHash, randomBytes } from "node:crypto";
import type { User } from "@prisma/client";
import type { NextRequest } from "next/server";
import type { NextResponse } from "next/server";
import { env, isProduction } from "./env";
import { ApiError } from "./http";
import { getPrisma } from "./prisma";

export const ACCESS_COOKIE = "qbo_access";
export const REFRESH_COOKIE = "qbo_refresh";
const ISSUER = "quaybaronline";
const AUDIENCE = "qbo-client";

export type PublicUser = {
	id: string;
	username: string;
	displayName: string;
	avatarUrl: string | null;
	bio: string | null;
	role: string;
	createdAt: string;
};

export type IssuedTokens = {
	accessToken: string;
	refreshToken: string;
	expiresIn: number;
	user: PublicUser;
};

const refreshLifetimeMs = () => env().REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000;

function signingKey(): Uint8Array {
	return new TextEncoder().encode(env().AUTH_SECRET);
}

export function publicUser(user: User): PublicUser {
	return {
		id: user.id,
		username: user.username,
		displayName: user.displayName,
		avatarUrl: user.avatarUrl,
		bio: user.bio,
		role: user.role,
		createdAt: user.createdAt.toISOString(),
	};
}

export async function hashPassword(password: string): Promise<string> {
	return bcrypt.hash(password, 12);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
	return bcrypt.compare(password, hash);
}

export function hashToken(token: string): string {
	return createHash("sha256").update(token).digest("hex");
}

async function signAccessToken(user: Pick<User, "id" | "username" | "role">): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	return new SignJWT({ username: user.username, role: user.role, type: "access" })
		.setProtectedHeader({ alg: "HS256" })
		.setIssuer(ISSUER)
		.setAudience(AUDIENCE)
		.setSubject(user.id)
		.setIssuedAt(now)
		.setExpirationTime(now + env().ACCESS_TOKEN_TTL)
		.sign(signingKey());
}

export async function verifyAccessToken(token: string): Promise<{ userId: string } | null> {
	try {
		const { payload } = await jwtVerify(token, signingKey(), { issuer: ISSUER, audience: AUDIENCE });
		if (payload.type !== "access" || typeof payload.sub !== "string") return null;
		return { userId: payload.sub };
	} catch {
		return null;
	}
}

export function bearerToken(request: NextRequest): string | null {
	const header = request.headers.get("authorization");
	if (!header) return null;
	const [scheme, value] = header.split(" ");
	if (!scheme || scheme.toLowerCase() !== "bearer" || !value) return null;
	return value.trim() || null;
}

export async function getAuthUser(request: NextRequest): Promise<User | null> {
	const token = bearerToken(request) ?? request.cookies.get(ACCESS_COOKIE)?.value ?? null;
	if (!token) return null;
	const payload = await verifyAccessToken(token);
	if (!payload) return null;
	const user = await getPrisma().user.findUnique({ where: { id: payload.userId } });
	if (!user || user.bannedAt) return null;
	return user;
}

export async function requireUser(request: NextRequest): Promise<User> {
	const user = await getAuthUser(request);
	if (!user) {
		throw new ApiError(401, "UNAUTHORIZED", "Bạn cần đăng nhập để thực hiện thao tác này.");
	}
	return user;
}

export async function requireRole(request: NextRequest, roles: string[]): Promise<User> {
	const user = await requireUser(request);
	if (!roles.includes(user.role)) {
		throw new ApiError(403, "FORBIDDEN", "Bạn không có quyền thực hiện thao tác này.");
	}
	return user;
}

type SessionMeta = { userAgent?: string | null; ip?: string | null };

export async function issueTokens(user: User, meta: SessionMeta): Promise<IssuedTokens> {
	const prisma = getPrisma();
	const refreshToken = randomBytes(48).toString("base64url");
	const expiresAt = new Date(Date.now() + refreshLifetimeMs());
	await prisma.session.create({
		data: {
			userId: user.id,
			refreshHash: hashToken(refreshToken),
			expiresAt,
			userAgent: meta.userAgent?.slice(0, 255) ?? null,
			ipAddress: meta.ip?.slice(0, 64) ?? null,
		},
	});
	const accessToken = await signAccessToken(user);
	await prisma.user.update({ where: { id: user.id }, data: { lastSeenAt: new Date() } });
	return {
		accessToken,
		refreshToken,
		expiresIn: env().ACCESS_TOKEN_TTL,
		user: publicUser(user),
	};
}

export async function rotateRefreshToken(refreshToken: string, meta: SessionMeta): Promise<IssuedTokens> {
	const prisma = getPrisma();
	const session = await prisma.session.findUnique({
		where: { refreshHash: hashToken(refreshToken) },
		include: { user: true },
	});
	if (!session) {
		throw new ApiError(401, "INVALID_REFRESH", "Refresh token không hợp lệ.");
	}
	if (session.revokedAt) {
		// Phát hiện dùng lại refresh token đã xoay vòng: thu hồi toàn bộ phiên của user.
		await prisma.session.updateMany({
			where: { userId: session.userId, revokedAt: null },
			data: { revokedAt: new Date() },
		});
		throw new ApiError(401, "REFRESH_REUSED", "Refresh token đã bị thu hồi. Vui lòng đăng nhập lại.");
	}
	if (session.expiresAt.getTime() <= Date.now()) {
		throw new ApiError(401, "REFRESH_EXPIRED", "Phiên đăng nhập đã hết hạn.");
	}
	if (session.user.bannedAt) {
		throw new ApiError(403, "ACCOUNT_BANNED", "Tài khoản đã bị khóa.");
	}
	const nextToken = randomBytes(48).toString("base64url");
	const nextExpiry = new Date(Date.now() + refreshLifetimeMs());
	await prisma.$transaction([
		prisma.session.update({
			where: { id: session.id },
			data: { revokedAt: new Date(), replacedByHash: hashToken(nextToken) },
		}),
		prisma.session.create({
			data: {
				userId: session.userId,
				refreshHash: hashToken(nextToken),
				expiresAt: nextExpiry,
				userAgent: meta.userAgent?.slice(0, 255) ?? session.userAgent,
				ipAddress: meta.ip?.slice(0, 64) ?? session.ipAddress,
			},
		}),
	]);
	const accessToken = await signAccessToken(session.user);
	return {
		accessToken,
		refreshToken: nextToken,
		expiresIn: env().ACCESS_TOKEN_TTL,
		user: publicUser(session.user),
	};
}

export async function revokeRefreshToken(refreshToken: string): Promise<void> {
	await getPrisma().session.updateMany({
		where: { refreshHash: hashToken(refreshToken), revokedAt: null },
		data: { revokedAt: new Date() },
	});
}

export function applyAuthCookies(response: NextResponse, tokens: IssuedTokens): void {
	const secure = isProduction();
	response.cookies.set(ACCESS_COOKIE, tokens.accessToken, {
		httpOnly: true,
		secure,
		sameSite: "lax",
		path: "/",
		maxAge: tokens.expiresIn,
	});
	response.cookies.set(REFRESH_COOKIE, tokens.refreshToken, {
		httpOnly: true,
		secure,
		sameSite: "lax",
		path: "/",
		maxAge: env().REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60,
	});
}

export function clearAuthCookies(response: NextResponse): void {
	const secure = isProduction();
	response.cookies.set(ACCESS_COOKIE, "", { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 0 });
	response.cookies.set(REFRESH_COOKIE, "", { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 0 });
}
