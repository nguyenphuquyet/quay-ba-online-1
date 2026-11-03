export type InventoryDefinition = {
	key: string;
	type: "outfit" | "accessory" | "emote";
	name: string;
	description: string;
	color?: string;
};

export const INVENTORY_CATALOG: InventoryDefinition[] = [
	{ key: "outfit_obsidian", type: "outfit", name: "Obsidian", description: "Áo da đen, dây chuyền vàng.", color: "#210d17" },
	{ key: "outfit_midnight", type: "outfit", name: "Midnight", description: "Navy lịch lãm cho lounge.", color: "#0f1729" },
	{ key: "outfit_smoke", type: "outfit", name: "Smoke", description: "Xám khói tối giản.", color: "#1a1a1c" },
	{ key: "accessory_gold_chain", type: "accessory", name: "Gold Chain", description: "Dây chuyền vàng champagne.", color: "#d9b36a" },
	{ key: "emote_dance_lotus", type: "emote", name: "Lotus Dance", description: "Điệu nhảy signature của club." },
];

export const STARTER_ITEMS = ["outfit_obsidian", "emote_dance_lotus"];

export function definitionFor(key: string): InventoryDefinition | undefined {
	return INVENTORY_CATALOG.find((item) => item.key === key);
}
