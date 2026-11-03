import { z } from "zod";

const envSchema = z.object({
	DATABASE_URL: z.string().min(1, "DATABASE_URL là bắt buộc"),
	AUTH_SECRET: z.string().min(32, "AUTH_SECRET phải dài tối thiểu 32 ký tự"),
	GAME_SERVER_SECRET: z.string().min(8).optional(),
	GAME_SERVER_HOST: z.string().default("127.0.0.1"),
	GAME_SERVER_PORT: z.coerce.number().int().positive().default(7000),
	REDIS_URL: z.string().optional(),
	ACCESS_TOKEN_TTL: z.coerce.number().int().positive().default(900),
	REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
	NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
});

export type AppEnv = z.infer<typeof envSchema>;

let cached: AppEnv | null = null;

export function env(): AppEnv {
	if (cached) return cached;
	const parsed = envSchema.safeParse(process.env);
	if (!parsed.success) {
		const details = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ");
		throw new Error(`Cấu hình môi trường không hợp lệ — ${details}`);
	}
	cached = parsed.data;
	return cached;
}

export function isProduction(): boolean {
	return process.env.NODE_ENV === "production";
}
