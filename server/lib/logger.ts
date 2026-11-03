type LogLevel = "info" | "warn" | "error";

export function log(level: LogLevel, message: string, meta: Record<string, unknown> = {}): void {
	const entry = {
		ts: new Date().toISOString(),
		level,
		msg: message,
		...meta,
	};
	const line = JSON.stringify(entry);
	if (level === "error") console.error(line);
	else if (level === "warn") console.warn(line);
	else console.log(line);
}
