"use client";

import { useEffect, useState } from "react";

type Health = { database: string; version: string } | null;

export function HealthBadge() {
	const [health, setHealth] = useState<Health>(null);
	const [failed, setFailed] = useState(false);

	useEffect(() => {
		let cancelled = false;
		fetch("/api/health", { cache: "no-store" })
			.then((response) => response.json())
			.then((data: { database?: string; version?: string }) => {
				if (!cancelled) setHealth({ database: data.database ?? "unknown", version: data.version ?? "0.1.0" });
			})
			.catch(() => {
				if (!cancelled) setFailed(true);
			});
		return () => {
			cancelled = true;
		};
	}, []);

	const databaseUp = health?.database === "up";
	const label = failed
		? "Không gọi được API"
		: health === null
			? "Đang kiểm tra…"
			: databaseUp
				? `Backend online • MySQL up • v${health.version}`
				: "Backend online • MySQL chưa kết nối";

	return (
		<span className="badge">
			<span className={`dot ${databaseUp ? "up" : failed ? "down" : ""}`} />
			{label}
		</span>
	);
}
