import type { NextRequest } from "next/server";
import { ApiError } from "./api-error";
import { log } from "./logger";

type Bucket = { hits: number[]; resetAt: number };

const memoryBuckets = new Map<string, Bucket>();
let redisClient: unknown = null;
let redisUnavailable = false;

async function getRedis(): Promise<{
	incr: (key: string) => Promise<number>;
	pexpire: (key: string, ms: number) => Promise<number>;
} | null> {
	if (redisUnavailable || !process.env.REDIS_URL) return null;
	if (redisClient) return redisClient as never;
	try {
		const mod = (await import("ioredis")) as unknown as { default: new (url: string, options: Record<string, unknown>) => unknown };
		const client = new mod.default(process.env.REDIS_URL, {
			maxRetriesPerRequest: 1,
			enableOfflineQueue: false,
			lazyConnect: false,
		});
		redisClient = client;
		return client as never;
	} catch (error) {
		redisUnavailable = true;
		log("warn", "redis_unavailable", { error: String(error) });
		return null;
	}
}

export function clientKey(request: NextRequest): string {
	const forwarded = request.headers.get("x-forwarded-for");
	if (forwarded) return forwarded.split(",")[0].trim();
	return request.headers.get("x-real-ip") ?? "local";
}

export async function enforceRateLimit(key: string, limit: number, windowMs: number): Promise<void> {
	const redis = await getRedis();
	if (redis) {
		try {
			const count = await redis.incr(key);
			if (count === 1) await redis.pexpire(key, windowMs);
			if (count > limit) {
				throw new ApiError(429, "RATE_LIMITED", "Bạn thao tác quá nhanh. Vui lòng thử lại sau.");
			}
			return;
		} catch (error) {
			if (error instanceof ApiError) throw error;
			log("warn", "redis_rate_limit_failed", { error: String(error) });
			redisUnavailable = true;
		}
	}
	const now = Date.now();
	const bucket = memoryBuckets.get(key);
	if (!bucket || bucket.resetAt <= now) {
		memoryBuckets.set(key, { hits: [now], resetAt: now + windowMs });
		cleanupMemory(now);
		return;
	}
	bucket.hits = bucket.hits.filter((stamp) => now - stamp < windowMs);
	bucket.hits.push(now);
	if (bucket.hits.length > limit) {
		throw new ApiError(429, "RATE_LIMITED", "Bạn thao tác quá nhanh. Vui lòng thử lại sau.");
	}
}

let lastCleanup = Date.now();

function cleanupMemory(now: number): void {
	if (now - lastCleanup < 60_000) return;
	lastCleanup = now;
	for (const [key, bucket] of memoryBuckets.entries()) {
		if (bucket.resetAt <= now) memoryBuckets.delete(key);
	}
}
