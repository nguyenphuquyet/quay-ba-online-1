import { HealthBadge } from "./components/health-badge";

const endpoints = [
	{
		title: "Authentication",
		items: [
			"POST /api/auth/register",
			"POST /api/auth/login",
			"POST /api/auth/logout",
			"POST /api/auth/refresh",
			"GET /api/users/me",
		],
	},
	{
		title: "Rooms & game tickets",
		items: [
			"GET /api/rooms",
			"POST /api/rooms",
			"GET /api/rooms/[code]",
			"POST /api/rooms/[code]/join",
			"POST /api/rooms/[code]/leave",
			"POST /api/game/ticket",
			"POST /api/game/ticket/verify",
		],
	},
	{
		title: "Social",
		items: [
			"GET /api/friends",
			"POST /api/friends/request",
			"POST /api/friends/accept",
			"DELETE /api/friends/[id]",
			"POST /api/reports",
		],
	},
	{
		title: "Profile & inventory",
		items: ["GET /api/users/[id]", "PATCH /api/users/me", "GET /api/inventory", "POST /api/inventory/equip"],
	},
];

export default function Home() {
	return (
		<main className="wrap">
			<p className="eyebrow">Backend • Next.js App Router • Prisma + MySQL 8</p>
			<h1>QUẨY BAR ONLINE</h1>
			<p className="lead">
				API chính thức cho game nightclub 3D đa nền tảng. Godot client xác thực bằng access token, xin game ticket
				trước khi vào phòng và dedicated server xác minh ticket bằng secret chia sẻ. Không dùng Express hay NestJS.
			</p>
			<HealthBadge />

			<section className="grid">
				{endpoints.map((group) => (
					<div className="card" key={group.title}>
						<h2>{group.title}</h2>
						<ul>
							{group.items.map((item) => (
								<li key={item}>
									<code>{item}</code>
								</li>
							))}
						</ul>
					</div>
				))}
			</section>

			<p className="foot">
				QUẨY BAR ONLINE • v0.1.0 — Xem <code>docs/API.md</code> để biết schema request/response, rate limit và quy
				tắc bảo mật. Đây là backend service, không phải landing page công khai.
			</p>
		</main>
	);
}
