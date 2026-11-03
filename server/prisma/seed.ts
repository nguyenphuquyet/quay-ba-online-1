/**
 * Seed tối thiểu: tạo tài khoản MODERATOR nếu có SEED_MODERATOR_PASSWORD.
 * Không hardcode mật khẩu; không chạy tự động khi deploy.
 *
 *   SEED_MODERATOR_PASSWORD="..." npx prisma db seed
 */
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

async function main() {
	const password = process.env.SEED_MODERATOR_PASSWORD;
	if (!password || password.length < 10) {
		console.log("[seed] Bỏ qua: đặt SEED_MODERATOR_PASSWORD (>=10 ký tự) để tạo tài khoản moderator.");
		return;
	}
	const passwordHash = await bcrypt.hash(password, 12);
	const user = await prisma.user.upsert({
		where: { username: "moderator" },
		create: {
			username: "moderator",
			email: "moderator@example.invalid",
			passwordHash,
			displayName: "Club Moderator",
			role: "MODERATOR",
		},
		update: { passwordHash, role: "MODERATOR" },
	});
	console.log(`[seed] Moderator sẵn sàng: ${user.username}`);
}

main()
	.catch((error) => {
		console.error("[seed] Lỗi:", error);
		process.exitCode = 1;
	})
	.finally(async () => {
		await prisma.$disconnect();
	});
