import { PrismaClient } from "@prisma/client";

// Singleton để tránh mở quá nhiều connection khi Next hot-reload.
const globalForPrisma = globalThis as unknown as { qboPrisma?: PrismaClient };

export function getPrisma(): PrismaClient {
	if (!globalForPrisma.qboPrisma) {
		globalForPrisma.qboPrisma = new PrismaClient({
			log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
		});
	}
	return globalForPrisma.qboPrisma;
}
