import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";

export const metadata: Metadata = {
	title: "QUẨY BAR ONLINE — Backend",
	description: "Next.js App Router backend cho game nightclub 3D QUẨY BAR ONLINE.",
	robots: { index: false, follow: false },
};

export default function RootLayout({ children }: { children: ReactNode }) {
	return (
		<html lang="vi">
			<body>{children}</body>
		</html>
	);
}
