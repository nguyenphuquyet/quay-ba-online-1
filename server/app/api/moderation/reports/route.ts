import type { NextRequest } from "next/server";
import { requireRole } from "@/lib/auth";
import { jsonOk, withApi } from "@/lib/http";
import { getPrisma } from "@/lib/prisma";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
	return withApi(request, { name: "moderation:reports", rateLimit: { limit: 60, windowMs: 60_000 } }, async () => {
		await requireRole(request, ["MODERATOR", "ADMIN"]);
		const reports = await getPrisma().report.findMany({
			where: { status: "OPEN" },
			include: {
				reporter: { select: { id: true, username: true, displayName: true } },
				target: { select: { id: true, username: true, displayName: true } },
			},
			orderBy: { createdAt: "asc" },
			take: 100,
		});
		return jsonOk({
			reports: reports.map((report) => ({
				id: report.id,
				reason: report.reason,
				detail: report.detail,
				status: report.status.toLowerCase(),
				createdAt: report.createdAt.toISOString(),
				reporter: report.reporter,
				target: report.target,
			})),
		});
	});
}
