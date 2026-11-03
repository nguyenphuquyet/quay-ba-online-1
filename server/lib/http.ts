import { NextResponse, type NextRequest } from "next/server";
import { randomUUID } from "node:crypto";
import { ZodError, type ZodType } from "zod";
import { log } from "./logger";
import { clientKey, enforceRateLimit } from "./rate-limit";
import { ApiError } from "./api-error";

export { ApiError };

export function jsonOk(data: unknown, init?: ResponseInit): NextResponse {
	return NextResponse.json(data, init);
}

export function jsonCreated(data: unknown): NextResponse {
	return NextResponse.json(data, { status: 201 });
}

export function jsonError(status: number, code: string, message: string, details?: unknown): NextResponse {
	return NextResponse.json(
		{ error: { code, message, ...(details !== undefined ? { details } : {}) } },
		{ status },
	);
}

export async function parseJson<T>(request: NextRequest, schema: ZodType<T>): Promise<T> {
	let body: unknown;
	try {
		body = await request.json();
	} catch {
		throw new ApiError(400, "INVALID_JSON", "Nội dung gửi lên phải là JSON hợp lệ.");
	}
	return schema.parse(body);
}

export type ApiHandler = (context: { requestId: string }) => Promise<NextResponse>;

export async function withApi(
	request: NextRequest,
	options: { name: string; rateLimit?: { limit: number; windowMs: number } },
	handler: ApiHandler,
): Promise<NextResponse> {
	const requestId = request.headers.get("x-request-id") ?? randomUUID();
	const started = Date.now();

	try {
		if (options.rateLimit) {
			await enforceRateLimit(
				`qbo:${options.name}:${clientKey(request)}`,
				options.rateLimit.limit,
				options.rateLimit.windowMs,
			);
		}
		const response = await handler({ requestId });
		response.headers.set("x-request-id", requestId);
		response.headers.set("cache-control", "no-store");
		log("info", "api_request", {
			requestId,
			route: options.name,
			method: request.method,
			status: response.status,
			durationMs: Date.now() - started,
		});
		return response;
	} catch (error) {
		if (error instanceof ZodError) {
			const details = error.issues.map((issue) => ({
				path: issue.path.join("."),
				message: issue.message,
			}));
			log("warn", "validation_error", { requestId, route: options.name, details });
			const response = jsonError(422, "VALIDATION_ERROR", "Dữ liệu không hợp lệ.", details);
			response.headers.set("x-request-id", requestId);
			return response;
		}
		if (error instanceof ApiError) {
			log("warn", "api_error", { requestId, route: options.name, code: error.code, status: error.status });
			const response = jsonError(error.status, error.code, error.message, error.details);
			response.headers.set("x-request-id", requestId);
			return response;
		}
		log("error", "unhandled_error", {
			requestId,
			route: options.name,
			error: error instanceof Error ? error.message : String(error),
			stack: error instanceof Error ? error.stack : undefined,
		});
		const response = jsonError(500, "INTERNAL_ERROR", "Đã xảy ra lỗi phía máy chủ.");
		response.headers.set("x-request-id", requestId);
		return response;
	}
}

export function requireSameOrigin(request: NextRequest): void {
	const origin = request.headers.get("origin");
	if (!origin) return; // Godot client không gửi Origin.
	const host = request.headers.get("host");
	if (!host) return;
	try {
		const originHost = new URL(origin).host;
		if (originHost !== host) {
			throw new ApiError(403, "ORIGIN_NOT_ALLOWED", "Yêu cầu phải xuất phát từ chính ứng dụng.");
		}
	} catch {
		throw new ApiError(403, "ORIGIN_NOT_ALLOWED", "Origin không hợp lệ.");
	}
}
