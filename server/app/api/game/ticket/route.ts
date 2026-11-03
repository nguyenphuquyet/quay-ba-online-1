import type { NextRequest } from "next/server";
import { requireUser } from "@/lib/auth";
import { jsonOk, parseJson, requireSameOrigin, withApi } from "@/lib/http";
import { createGameTicket } from "@/lib/tickets";
import { gameTicketSchema } from "@/lib/validation";

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
	return withApi(request, { name: "game:ticket", rateLimit: { limit: 20, windowMs: 60_000 } }, async () => {
		requireSameOrigin(request);
		const user = await requireUser(request);
		const input = await parseJson(request, gameTicketSchema);
		const ticket = await createGameTicket(user.id, input.roomCode);
		return jsonOk(ticket);
	});
}
