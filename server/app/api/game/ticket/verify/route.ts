import type { NextRequest } from "next/server";
import { jsonOk, parseJson, withApi } from "@/lib/http";
import { verifyGameTicket } from "@/lib/tickets";
import { gameTicketVerifySchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "game:ticket:verify", rateLimit: { limit: 60, windowMs: 60_000 } }, async () => {
		const input = await parseJson(request, gameTicketVerifySchema);
		const secret = request.headers.get("x-game-server-secret");
		const result = await verifyGameTicket(input.ticket, secret);
		return jsonOk(result);
	});
}
