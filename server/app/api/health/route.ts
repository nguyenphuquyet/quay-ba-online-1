import type { NextRequest } from "next/server";
import { withApi, jsonOk } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
	return withApi(request, { name: "health" }, async () => {
		let database = "down";
		try {
			await getPrisma().$queryRaw`SELECT 1`;
			database = "up";
		} catch {
			database = "down";
		}
		return jsonOk({
			status: "ok",
			service: "quay-bar-online-server",
			version: "0.1.0",
			database,
			time: new Date().toISOString(),
		});
	});
}
