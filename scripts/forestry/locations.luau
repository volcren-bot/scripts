--!strict
local Host = require("@volcren/host")
type Tile = Host.Tile

export type Location = {
	tree: string,
	logs: string,
	level: number,
	trees: { Tile },
	fallback: { Tile }?,
	bank: Tile?,
	fires: Tile?,
	current: boolean?,
}

local Locations: { [string]: Location } = {
	["Tree - Draynor Village"] = {
		tree = "Tree",
		logs = "Logs",
		level = 1,
		trees = { { x = 3099, y = 3242 }, { x = 3099, y = 3247 }, { x = 3101, y = 3252 } },
		bank = { x = 3093, y = 3243 },
		fires = { x = 3092, y = 3237 },
	},
	["Oak - Draynor Village"] = {
		tree = "Oak tree",
		logs = "Oak logs",
		level = 15,
		trees = { { x = 3102, y = 3242 } },
		bank = { x = 3093, y = 3243 },
		fires = { x = 3092, y = 3237 },
	},
	["Willow - Draynor Village"] = {
		tree = "Willow tree",
		logs = "Willow logs",
		level = 30,
		trees = {
			{ x = 3083, y = 3237 },
			{ x = 3085, y = 3235 },
			{ x = 3087, y = 3231 },
			{ x = 3088, y = 3227 },
			{ x = 3088, y = 3234 },
		},
		bank = { x = 3093, y = 3243 },
		fires = { x = 3092, y = 3237 },
	},
	["Willow - Catherby"] = {
		tree = "Willow tree",
		logs = "Willow logs",
		level = 30,
		trees = {
			{ x = 2768, y = 3426 },
			{ x = 2771, y = 3427 },
			{ x = 2781, y = 3427 },
			{ x = 2783, y = 3426 },
			{ x = 2786, y = 3429 },
		},
		bank = { x = 2809, y = 3440 },
		fires = { x = 2809, y = 3435 },
	},
	["Willow - Seers' Village"] = {
		tree = "Willow tree",
		logs = "Willow logs",
		level = 30,
		trees = {
			{ x = 2704, y = 3506 },
			{ x = 2708, y = 3513 },
			{ x = 2709, y = 3510 },
			{ x = 2711, y = 3511 },
			{ x = 2712, y = 3508 },
			{ x = 2719, y = 3505 },
		},
		bank = { x = 2727, y = 3493 },
		fires = { x = 2725, y = 3485 },
	},
	["Maple - Seers' Village"] = {
		tree = "Maple tree",
		logs = "Maple logs",
		level = 45,
		trees = { { x = 2721, y = 3501 }, { x = 2727, y = 3501 }, { x = 2730, y = 3501 }, { x = 2732, y = 3499 } },
		bank = { x = 2727, y = 3493 },
		fires = { x = 2725, y = 3485 },
	},
	["Mahogany - Farming Guild"] = {
		tree = "Mahogany tree",
		logs = "Mahogany logs",
		level = 50,
		trees = { { x = 1235, y = 3772 }, { x = 1239, y = 3769 } },
		bank = { x = 1248, y = 3757 },
		fires = { x = 1249, y = 3750 },
	},
	["Teak - Prifddinas"] = {
		tree = "Teak tree",
		logs = "Teak logs",
		level = 35,
		trees = { { x = 3309, y = 6124 }, { x = 3311, y = 6121 }, { x = 3311, y = 6123 } },
		bank = { x = 3257, y = 6107 },
	},
	["Mahogany - Prifddinas"] = {
		tree = "Mahogany tree",
		logs = "Mahogany logs",
		level = 50,
		trees = { { x = 3301, y = 6128 }, { x = 3301, y = 6132 }, { x = 3304, y = 6127 } },
		bank = { x = 3257, y = 6107 },
	},
	["Yew - Prifddinas"] = {
		tree = "Yew tree",
		logs = "Yew logs",
		level = 60,
		trees = { { x = 3287, y = 6061 }, { x = 3288, y = 6065 }, { x = 3292, y = 6067 } },
		bank = { x = 3295, y = 6059 },
	},
	["Magic - Prifddinas"] = {
		tree = "Magic tree",
		logs = "Magic logs",
		level = 75,
		trees = { { x = 3235, y = 6095 }, { x = 3235, y = 6103 } },
		fallback = { { x = 3227, y = 6095 }, { x = 3227, y = 6103 } },
		bank = { x = 3257, y = 6107 },
	},
	["Yew - Seers' Village church"] = {
		tree = "Yew tree",
		logs = "Yew logs",
		level = 60,
		trees = { { x = 2705, y = 3459 }, { x = 2705, y = 3464 }, { x = 2714, y = 3459 } },
		bank = { x = 2727, y = 3493 },
		fires = { x = 2725, y = 3485 },
	},
	["Yew - Catherby"] = {
		tree = "Yew tree",
		logs = "Yew logs",
		level = 60,
		trees = {
			{ x = 2754, y = 3433 },
			{ x = 2755, y = 3430 },
			{ x = 2757, y = 3433 },
			{ x = 2759, y = 3427 },
			{ x = 2760, y = 3431 },
			{ x = 2765, y = 3427 },
			{ x = 2770, y = 3437 },
		},
		bank = { x = 2809, y = 3440 },
		fires = { x = 2809, y = 3435 },
	},
	["Yew - Grand Exchange"] = {
		tree = "Yew tree",
		logs = "Yew logs",
		level = 60,
		trees = { { x = 3204, y = 3503 }, { x = 3208, y = 3499 }, { x = 3221, y = 3502 } },
		bank = { x = 3167, y = 3489 },
		fires = { x = 3165, y = 3480 },
	},
	["Magic - Ranging Guild"] = {
		tree = "Magic tree",
		logs = "Magic logs",
		level = 75,
		trees = { { x = 2690, y = 3427 }, { x = 2691, y = 3424 }, { x = 2696, y = 3423 } },
		bank = { x = 2727, y = 3493 },
		fires = { x = 2725, y = 3485 },
	},
	["Magic - Sorcerer's Tower"] = {
		tree = "Magic tree",
		logs = "Magic logs",
		level = 75,
		trees = { { x = 2698, y = 3396 }, { x = 2698, y = 3398 }, { x = 2705, y = 3396 }, { x = 2705, y = 3398 } },
		bank = { x = 2727, y = 3493 },
		fires = { x = 2725, y = 3485 },
	},
}

for _, kind in
	{
		{ tree = "Tree", logs = "Logs", level = 1 },
		{ tree = "Oak tree", logs = "Oak logs", level = 15 },
		{ tree = "Teak tree", logs = "Teak logs", level = 35 },
		{ tree = "Willow tree", logs = "Willow logs", level = 30 },
		{ tree = "Maple tree", logs = "Maple logs", level = 45 },
		{ tree = "Mahogany tree", logs = "Mahogany logs", level = 50 },
		{ tree = "Yew tree", logs = "Yew logs", level = 60 },
		{ tree = "Magic tree", logs = "Magic logs", level = 75 },
	}
do
	local label = if kind.tree == "Tree" then "Tree" else string.gsub(kind.tree, " tree$", "")
	Locations[`{label} - Current location`] =
		{ tree = kind.tree, logs = kind.logs, level = kind.level, trees = {}, current = true }
end

return Locations
