import type { NextRequest } from "next/server";
import { jsonOk, withApi } from "@/lib/http";
import { closeGameRoom } from "@/lib/tickets";
import { roomCodeParam } from "@/lib/validation";

export const dynamic = "force-dynamic";

/** Dedicated server gọi khi chủ phòng rời/mất kết nối quá thời gian chờ. */
export async function POST(request: NextRequest, context: { params: Promise<{ code: string }> }) {
	return withApi(request, { name: "game:rooms:close", rateLimit: { limit: 60, windowMs: 60_000 } }, async () => {
		const { code: rawCode } = await context.params;
		const code = roomCodeParam.parse(rawCode);
		const secret = request.headers.get("x-game-server-secret");
		const result = await closeGameRoom(code, secret);
		return jsonOk(result);
	});
}
