--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local BankpinKeypad = require("@lib/main/interfaces/mainscreen/bankpin_keypad")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local CombatSafeSpot = require("@lib/main/combat_safespot")
local Consumables = require("@lib/main/consumables")
local EquipmentLayout = require("@lib/main/equipment_layout")
local Ferox = require("@lib/main/ferox")
local GameState = require("@lib/main/game_state")
local Geometry = require("@lib/utils/math/geometry")
local GroundItems = require("@lib/main/entities/ground_items")
local House = require("@lib/main/house")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local InventoryLayout = require("@lib/main/inventory_layout")
local ItemRetrieval = require("@lib/main/interfaces/mainscreen/itemretrieval")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Melee = require("./melee")
local Minimap = require("@lib/main/interfaces/minimap")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Mouse = require("@lib/utils/input/mouse")
local NpcHealth = require("@lib/main/entities/npc_health")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Position = require("@lib/main/position")
local Prayer = require("@lib/main/interfaces/gametabs/prayer")
local PrayerLayout = require("@lib/main/prayer_layout")
local Projection = require("@lib/main/projection/projection")
local Random = require("@lib/utils/math/random")
local Ranged = require("./ranged")
local SafeSpot = require("@lib/main/safespot")
local SidePanels = require("@lib/main/interfaces/gametabs/side_panels")
local SpecialAttack = require("@lib/main/interfaces/special_attack")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Transports = require("@lib/main/transports")
local Varbits = require("@lib/main/varbits")
local Walker = require("@lib/main/walker")
local Quad = Geometry.Quad
type Point = Geometry.Point
type Rotation = {
	name: string,
	jad: number,
	phases: { string },
	clouds: { [number]: { { number } } },
}

local NAME = "Zulrah"

local FIRST_CLOUDS = { { 46, 53 }, { 46, 56 }, { 46, 59 }, { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 }, { 56, 58 } }

local CONST = {
	REPORT = { counters_key = "" },
	ARENA_CHUNKS = {
		[Position.Chunk.new(35, 47):id()] = true,
		[Position.Chunk.new(35, 48):id()] = true,
	},
	ZULANDRA_CHUNK = Position.Chunk.new(34, 47):id(),
	BOAT = "Sacrificial boat",
	PRIESTESS = "Priestess Zul-Gwenwynig",
	PRIESTESS_ID = 2124,
	PRIESTESS_TILE = { x = 2211, y = 3057, plane = 0 },
	LOOT_WAIT_MS = 1800,
	TELEPORT_LOC = 11701,
	TELEPORT_OPTION = "Read",
	LEAVE_QUESTION = "Are you ready to leave the shrine?",
	LEAVE_ANSWER = "Yes",
	TELEPORT_WAIT_MS = 8000,
	TELEPORT_START_MS = 3000,
	BOARD_QUESTION = "Return to Zulrah's shrine?",
	BOARD_ANSWER = "Yes",
	QUESTION_WAIT_MS = 5000,
	BOARD_WAIT_MS = 10000,
	ANSWER_TAKES_MS = 2000,
	ANSWER_REACTION_MS = { 350, 900 },
	RESTORE_METHODS = { "House", "Ferox Enclave" },
	MELEE_MAX_RANGE = 2,
	HOUSE_TABLET = "Teleport to house",
	HOUSE_TABLET_OPTION = "Inside",
	HOUSE_SPELL = "Teleport to House",
	HOUSE_OUTSIDE_VARBIT = 4744,
	ORNATE_POOL = "Ornate pool of Rejuvenation",
	FEROX = "Ferox Enclave",
	RESTOCK_ATTEMPTS = 3,
	DUELING_FEROX = "Ring of dueling: Ferox Enclave",
	ZULANDRA_TELEPORT = "Zul-andra teleport",
	BANKS = {
		{ name = "Grand Exchange", x = 3164, y = 3487, plane = 0 },
		{ name = "Varrock West", x = 3185, y = 3436, plane = 0 },
		{ name = "Varrock East", x = 3253, y = 3420, plane = 0 },
		{ name = "Edgeville", x = 3094, y = 3493, plane = 0 },
		{ name = "Falador East", x = 3013, y = 3355, plane = 0 },
		{ name = "Falador West", x = 2946, y = 3368, plane = 0 },
		{ name = "Draynor Village", x = 3092, y = 3243, plane = 0 },
		{ name = "Al Kharid", x = 3269, y = 3167, plane = 0 },
		{ name = "Lumbridge Castle", x = 3208, y = 3220, plane = 2 },
		{ name = "Castle Wars", x = 2443, y = 3083, plane = 0 },
		{ name = "Ferox Enclave", x = 3130, y = 3631, plane = 0 },
		{ name = "Seers' Village", x = 2725, y = 3493, plane = 0 },
		{ name = "Catherby", x = 2809, y = 3441, plane = 0 },
		{ name = "Ardougne North", x = 2616, y = 3332, plane = 0 },
		{ name = "Ardougne South", x = 2655, y = 3283, plane = 0 },
		{ name = "Yanille", x = 2613, y = 3093, plane = 0 },
		{ name = "Arceuus", x = 1629, y = 3746, plane = 0 },
	},
	THRALLS = { "Skeleton", "Ghost" },
	THRALL_EARLY_MS = 10000,
	THRALL_EARLY_CHANCE = 0.3,
	THRALL_RETRY_MS = 10000,
	POISON_VARP = 102,
	VENOM_IMMUNE_BELOW = -38,
	VENOM_RENEW_UNITS = 2,
	VENOMED = 1000000,
	VENOM_PAST_SIX = 1000001,
	ANTIPOISON_AFTER_TICKS = { 20, 25 },
	VENOM_IMMUNE_HELMS = { [12931] = true, [13197] = true, [13199] = true } :: { [number]: boolean },
	BOOST_STATS = { "Attack", "Strength", "Ranged", "Magic" },
	BOOST_DROP = 5,
	ZULRAH_MAX_HIT = 41,
	RESTORE_AT = { 10, 25 },
	CONSUME_MS = 1800,
	ATTACK_CONFIRM_MS = 1200,
	SPECIAL_RETRY_MS = 10000,
	THRALL_PROJECTILES = { [1906] = true, [1907] = true } :: { [number]: boolean },
	SHOT_GAP_TICKS = 4,
	SHOT_LEAD_MS = 600,
	SHOT_WAIT_MS = 2400,
	CLOUD_WAIT_MS = 4500,
	DEATH_ANIMATION = 5804,
	DIVE_ANIMATION = 5072,
	SURFACE_ANIMATION = 5073,
	RISING_ANIMATIONS = { [5071] = true, [5073] = true } :: { [number]: boolean },
	SURFACE_MS = 3000,
	EARLY_TICKS = { 0, 10 },
	TICK_MS = 600,
	ZULRAH_SIZE = 5,
	CLOUD_PROJECTILE = 1045,
	SNAKELING_SPAWN_PROJECTILE = 1047,
	RANGED_PROJECTILE = 1044,
	SNAKELING_PROJECTILES = { [1230] = true } :: { [number]: boolean },
	WORLD_MENU_KINDS = { [2] = true, [3] = true, [4] = true } :: { [number]: boolean },
	MAGIC_SNAKELING = 2046,
	CLOUD_SIZE = 3,
	CLOUD_AIMS = {
		{ 46, 53 },
		{ 46, 56 },
		{ 46, 59 },
		{ 49, 52 },
		{ 52, 52 },
		{ 55, 52 },
		{ 56, 55 },
		{ 56, 58 },
		{ 56, 61 },
	},
	CLOUD_LIFE_MS = 18000,
	CLOUD_SPAWN_MS = 300,
	CLOUD_LATE_SPAWN_MS = 3900,
	CLOUD_LATE_DIVE_MS = 450,
	THROW_CYCLES = 30,
	CYCLE_MS = 20,
	TICK_CYCLES = 30,
	LATER_AFTER_ATTACKS = 3,
	CLOUD_SOON_MS = 1200,
	NEAR_REACH = 2,
	DODGE_INSTEAD_CHANCE = 0.5,
	STEP_CLEAR_TILES = 4,
	JAD_MOVE_WINDOW_MS = 800,
	JAD_MOVE_MOUSE_PACE = 1.8,
	CLOUD_DODGE_REACH = 3,
	ARENA_CENTER = { x = 52, y = 56 },
	ARENA_RADIUS = 16,
	WHIP_ANIMATIONS = { [5806] = true, [5807] = true } :: { [number]: boolean },
	WHIP_MS = 4100,
	DIVE_SWITCH_DELAY_MS = 700,
	CAMERA_EVERY_MS = 2000,
	CAMERA_AHEAD_DEG = 15,
	CAMERA_ZOOM_STEPS = 2,
	CAMERA_HEIGHT = 400,
	WHIP_ATTACK_WINDOW_MS = 2500,
	POSITIONS = {
		middle = { x = 52, y = 59 },
		east = { x = 62, y = 57 },
		south = { x = 52, y = 48 },
		west = { x = 42, y = 57 },
	} :: { [string]: { x: number, y: number } },
	TILES = {
		start = { x = 56, y = 62 },
		red_dodge = { x = 58, y = 61 },
		east_pillar = { x = 56, y = 56 },
		west_pillar = { x = 48, y = 56 },
		between = { x = 52, y = 53 },
		west_side = { x = 48, y = 62 },
		west_dodge = { x = 46, y = 60 },
	} :: { [string]: { x: number, y: number } },
	DODGES = {
		start = "red_dodge",
		red_dodge = "start",
		west_side = "west_dodge",
		west_dodge = "west_side",
	} :: { [string]: string },
	WHIP_SAFE = { east_pillar = true, west_pillar = true } :: { [string]: boolean },
	WHIP_DODGE_REACH = 2,
	WHIP_DODGE_MS = 3000,
	RUN_MIN_ENERGY = 5,
	ROTATIONS = {
		{
			name = "1 (Magma A)",
			jad = 9,
			clouds = {
				[1] = FIRST_CLOUDS,
				[4] = { { 46, 53 }, { 49, 52 }, { 55, 52 }, { 56, 55 } },
				[7] = { { 46, 53 }, { 46, 56 }, { 46, 59 }, { 49, 52 }, { 52, 52 }, { 55, 52 } },
				[8] = { { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 } },
				[9] = {},
			},
			phases = {
				"serpentine middle start",
				"magma middle start",
				"tanzanite middle between",
				"serpentine south west_pillar",
				"magma middle west_pillar",
				"tanzanite west between",
				"serpentine south east_pillar",
				"tanzanite south east_pillar>west_pillar",
				"serpentine west west_pillar>east_pillar",
				"magma middle start",
			},
		},
		{
			name = "2 (Magma B)",
			jad = 9,
			clouds = {
				[1] = FIRST_CLOUDS,
				[4] = { { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 }, { 56, 58 }, { 56, 61 } },
				[5] = { { 46, 53 }, { 49, 52 }, { 55, 52 }, { 56, 55 } },
				[7] = {},
				[8] = { { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 } },
				[9] = {},
			},
			phases = {
				"serpentine middle start",
				"magma middle start",
				"tanzanite middle between",
				"serpentine west west_pillar",
				"tanzanite south west_pillar",
				"magma middle west_pillar",
				"serpentine east between",
				"tanzanite south east_pillar>west_pillar",
				"serpentine west west_pillar>east_pillar",
				"magma middle start",
			},
		},
		{
			name = "3 (Serp)",
			jad = 10,
			clouds = {
				[1] = FIRST_CLOUDS,
				[3] = { { 46, 53 }, { 46, 56 }, { 52, 52 }, { 55, 52 }, { 56, 58 }, { 56, 61 } },
				[7] = { { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 }, { 56, 58 }, { 56, 61 } },
				[9] = { { 46, 53 }, { 46, 56 }, { 46, 59 }, { 49, 52 }, { 52, 52 } },
			},
			phases = {
				"serpentine middle start",
				"serpentine east start",
				"magma middle east_pillar",
				"tanzanite west between",
				"serpentine south between",
				"tanzanite east between",
				"serpentine middle west_pillar",
				"serpentine west west_pillar",
				"tanzanite middle east_pillar",
				"serpentine east east_pillar",
				"tanzanite middle start",
			},
		},
		{
			name = "4 (Tanz)",
			jad = 11,
			clouds = {
				[1] = FIRST_CLOUDS,
				[3] = { { 46, 53 }, { 49, 52 }, { 52, 52 }, { 55, 52 } },
				[5] = { { 46, 53 }, { 49, 52 }, { 52, 52 }, { 55, 52 } },
				[7] = { { 49, 52 }, { 52, 52 }, { 55, 52 }, { 56, 55 }, { 56, 58 }, { 56, 61 } },
				[10] = { { 46, 53 }, { 46, 56 }, { 46, 59 }, { 49, 52 }, { 52, 52 }, { 55, 52 } },
			},
			phases = {
				"serpentine middle start",
				"tanzanite east start",
				"serpentine south west_pillar",
				"tanzanite west west_pillar",
				"magma middle east_pillar",
				"serpentine east east_pillar",
				"serpentine south east_pillar>west_pillar",
				"tanzanite west west_pillar",
				"serpentine middle east_pillar",
				"tanzanite middle east_pillar",
				"serpentine east east_pillar",
				"tanzanite middle start",
			},
		},
	} :: { Rotation },
	OVERHEADS = { "protect_from_melee", "protect_from_missiles", "protect_from_magic" },
	TRANSFORMATIONS = {
		{
			key = "serpentine",
			name = "Serpentine",
			label = "Serpentine (green)",
			id = 2042,
			protection = "protect_from_missiles" :: string?,
			snakeling_protection = nil :: string?,
			prayer_state = "SERPENTINE_PRAYER" :: State,
			gear_state = "SERPENTINE_GEAR" :: State,
		},
		{
			key = "magma",
			name = "Magma",
			label = "Magma (red)",
			id = 2043,
			protection = nil :: string?,
			snakeling_protection = "protect_from_magic" :: string?,
			prayer_state = "MAGMA_PRAYER" :: State,
			gear_state = "MAGMA_GEAR" :: State,
		},
		{
			key = "tanzanite",
			name = "Tanzanite",
			label = "Tanzanite (blue)",
			id = 2044,
			protection = "protect_from_magic" :: string?,
			snakeling_protection = nil :: string?,
			prayer_state = "TANZANITE_PRAYER" :: State,
			gear_state = "TANZANITE_GEAR" :: State,
		},
	},
}

type Transformation = typeof(CONST.TRANSFORMATIONS[1])

local Read, Game, Loop, Handler = {}, {}, {}, {}

type TransformationLayouts = {
	equipment: EquipmentLayout.Layout?,
	prayers: PrayerLayout.Layout?,
	snakeling_prayers: PrayerLayout.Layout?,
	special_prayers: PrayerLayout.Layout?,
	special_snakeling_prayers: PrayerLayout.Layout?,
}

local function wanted(id: number, name: string): Host.LayoutItem
	return { id = id, ids = { id }, name = name, stackable = false, min = 1, max = 1, doses = nil, locked = false }
end

local function stack(id: number, name: string, min: number, max: number): Host.LayoutItem
	return { id = id, ids = { id }, name = name, stackable = true, min = min, max = max, doses = nil, locked = false }
end

local function dosed(id: number, name: string, doses: { number }): Host.LayoutItem
	return { id = id, ids = { id }, name = name, stackable = false, min = 1, max = 1, doses = doses, locked = false }
end

local function held(slot: number, item: Host.LayoutItem): InventoryLayout.Slot
	return {
		slot = slot,
		id = item.id,
		ids = item.ids,
		name = item.name,
		stackable = item.stackable,
		min = item.min,
		max = item.max,
		doses = item.doses,
		locked = item.locked,
	}
end

local function worn(slot: number, id: number, name: string): EquipmentLayout.Slot
	return {
		slot = slot,
		mode = "item",
		id = id,
		ids = { id },
		name = name,
		stackable = false,
		min = 1,
		max = 1,
		doses = nil,
		locked = false,
	}
end

local function empty(slot: number): EquipmentLayout.Slot
	return { slot = slot, mode = "empty" }
end

local function any(slot: number): EquipmentLayout.Slot
	return { slot = slot, mode = "any" }
end

local MAGIC_GEAR: EquipmentLayout.Layout = {
	name = "Magic",
	slots = {
		worn(0, 23971, "Crystal helm"),
		worn(1, 21791, "Imbued Saradomin cape"),
		worn(2, 19720, "Occult necklace (or)"),
		worn(3, 31113, "Eye of Ayak"),
		worn(4, 4868, "Ahrim's robetop 100"),
		empty(5),
		worn(7, 4874, "Ahrim's robeskirt 100"),
		worn(9, 31106, "Confliction gauntlets"),
		worn(10, 13237, "Pegasian boots"),
		worn(12, 20657, "Ring of suffering (ri)"),
		worn(13, 22947, "Rada's blessing 4"),
		any(14),
	},
	spell = nil,
}

local RANGED_GEAR: EquipmentLayout.Layout = {
	name = "Ranged",
	slots = {
		worn(0, 23971, "Crystal helm"),
		worn(1, 22109, "Ava's assembler"),
		worn(2, 19547, "Necklace of anguish"),
		worn(3, 25867, "Bow of Faerdhinen (c)"),
		worn(4, 23975, "Crystal body"),
		empty(5),
		worn(7, 23979, "Crystal legs"),
		worn(9, 7462, "Barrows gloves"),
		worn(10, 13237, "Pegasian boots"),
		worn(12, 20657, "Ring of suffering (ri)"),
		worn(13, 22947, "Rada's blessing 4"),
		any(14),
	},
	spell = nil,
}

local MAGIC_BOOST: PrayerLayout.Layout = { name = "Magic Boost", prayers = { "augury" } }
local RANGED_BOOST: PrayerLayout.Layout = { name = "Ranged Boost", prayers = { "rigour" } }

local SAVED_LAYOUTS = {
	inventory = {
		name = "Zulrah",
		slots = {
			held(0, wanted(25867, "Bow of Faerdhinen (c)")),
			held(1, wanted(22109, "Ava's assembler")),
			held(2, wanted(27641, "Saturated heart")),
			held(3, dosed(23733, "Divine ranging potion(4)", { 4 })),
			held(4, wanted(7462, "Barrows gloves")),
			held(5, wanted(19547, "Necklace of anguish")),
			held(6, dosed(29824, "Extended anti-venom+(4)", { 4 })),
			held(7, dosed(2434, "Prayer potion(4)", { 4 })),
			held(8, wanted(23975, "Crystal body")),
			held(9, wanted(23979, "Crystal legs")),
			held(10, dosed(2434, "Prayer potion(4)", { 4 })),
			held(11, dosed(2434, "Prayer potion(4)", { 4 })),
			held(12, wanted(3144, "Cooked karambwan")),
			held(13, wanted(3144, "Cooked karambwan")),
			held(14, wanted(3144, "Cooked karambwan")),
			held(15, wanted(3144, "Cooked karambwan")),
			held(16, wanted(13441, "Anglerfish")),
			held(17, wanted(13441, "Anglerfish")),
			held(18, wanted(13441, "Anglerfish")),
			held(19, wanted(13441, "Anglerfish")),
			held(20, wanted(13441, "Anglerfish")),
			held(21, wanted(13441, "Anglerfish")),
			held(22, wanted(13441, "Anglerfish")),
			held(23, wanted(21268, "Slayer ring (eternal)")),
			held(24, wanted(25818, "Book of the Dead")),
			held(25, wanted(9084, "Lunar staff")),
			held(26, dosed(2552, "Ring of dueling(8)", { 8, 7, 6, 5, 4, 3, 2, 1 })),
			held(27, wanted(27281, "Divine rune pouch")),
		},
		pouch = {
			stack(565, "Blood rune", 100, 5216),
			stack(554, "Fire rune", 100, 12740),
			stack(564, "Cosmic rune", 100, 14675),
		},
	} :: InventoryLayout.Layout,
	transformations = {
		serpentine = { equipment = MAGIC_GEAR, prayers = MAGIC_BOOST },
		magma = { equipment = MAGIC_GEAR, prayers = MAGIC_BOOST },
		tanzanite = { equipment = RANGED_GEAR, prayers = RANGED_BOOST },
	} :: { [string]: TransformationLayouts },
}

local CONFIG = {
	inventory = nil :: InventoryLayout.Layout?,
	transformations = {
		serpentine = {},
		magma = {},
		tanzanite = {},
	} :: { [string]: TransformationLayouts },
	max_runs = 0,
	restore = "House",
	melee = false,
	min_food = 3,
	min_prayer_doses = 2,
	min_cure_doses = 2,
	venom_proof = false,
	eat_min = 50,
	eat_max = 75,
	stay_below = 50,
	special = {
		equipment = nil :: EquipmentLayout.Layout?,
		on = { serpentine = false, magma = false, tanzanite = false } :: { [string]: boolean },
	},
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local function eat_level(): number
	return Random.int(CONFIG.eat_min, CONFIG.eat_max)
end

local stats = { runs = 0, failures = 0 }

type Cloud = {
	x: number,
	y: number,
	start_cycle: number,
	seen_at: number,
	land_at: number,
	late: boolean,
	spawn_at: number,
	gone_at: number,
}

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	skip: { [string]: boolean },
	in_arena: boolean,
	thrall_early: boolean?,
	thrall_retry_at: number,
	zulrah_alive: boolean,
	moving_to: string?,
	cloud_dodge: { key: string, x: number, y: number }?,
	hovered_dodge: string?,
	whip_at: number?,
	whip_anim: number?,
	whip_dodge: { key: string, x: number, y: number, ends_at: number }?,
	escaping: boolean,
	zulrah_hp: number?,
	staying: boolean,
	camera_at: number,
	moving_via: Host.Tile?,
	camera_goal: { x: number, y: number }?,
	no_room: { [number]: boolean },
	zulrah_attacks: number,
	last_attack_cycle: number,
	last_throw_cycle: number,
	last_spawn_cycle: number,
	clouds: { [string]: Cloud },
	arena_grid: SafeSpot.Grid?,
	hovered_on_walk: boolean,
	last_shot_cycle: number,
	last_shot_at: number,
	shot_gaps: { [string]: number },
	walk_attack: { at: number, shot: number }?,
	cloud_wait_logged: string?,
	walked: boolean,
	hovered_rising: number,
	attack_phase: number,
	eat_at: number,
	restore_at: number,
	used_at: { [string]: number },
	poison: number?,
	antipoison_tick: number,
	restock_failures: number,
	special_failed_at: number,
	scroll_missing: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	skip = {},
	in_arena = false,
	thrall_early = nil,
	thrall_retry_at = 0,
	zulrah_alive = false,
	moving_to = nil,
	no_room = {},
	zulrah_attacks = 0,
	last_attack_cycle = -1,
	last_throw_cycle = -math.huge,
	last_spawn_cycle = -math.huge,
	clouds = {},
	arena_grid = nil,
	hovered_on_walk = false,
	last_shot_cycle = -math.huge,
	last_shot_at = 0,
	shot_gaps = {},
	walk_attack = nil,
	cloud_wait_logged = nil,
	walked = false,
	hovered_rising = -1,
	attack_phase = -1,
	eat_at = eat_level(),
	restore_at = Random.int(CONST.RESTORE_AT[1], CONST.RESTORE_AT[2]),
	used_at = {},
	poison = nil,
	antipoison_tick = 0,
	restock_failures = 0,
	special_failed_at = -math.huge,
	scroll_missing = false,
	escaping = false,
	zulrah_hp = nil,
	staying = false,
	camera_at = 0,
	camera_goal = nil,
	moving_via = nil,
}

type Snapshot = {
	state: ClientState,
	tick: number,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "ZULRAH"
	| "MOVE"
	| "CAMERA"
	| "SERPENTINE_PRAYER"
	| "SERPENTINE_GEAR"
	| "MAGMA_PRAYER"
	| "MAGMA_GEAR"
	| "TANZANITE_PRAYER"
	| "TANZANITE_GEAR"
	| "SPECIAL"
	| "JAD_PRAYER"
	| "RUN"
	| "THRALL"
	| "EAT"
	| "PRAYER_POTION"
	| "ANTIVENOM"
	| "ANTIPOISON"
	| "BOOST"
	| "ATTACK"
	| "INVENTORY"
	| "PRAYERS_OFF"
	| "LOOT"
	| "EAT_FOR_SPACE"
	| "LEAVE"
	| "CONFIRM_LEAVE"
	| "RECOVER_GEAR"
	| "PREPARE_GEAR"
	| "BOARD_BOAT"
	| "CONFIRM_BOAT"
	| "TELEPORT_HOUSE"
	| "TELEPORT_FEROX"
	| "FEROX"
	| "HOUSE"
	| "BANKING"
	| "TRAVEL_ZULANDRA"
	| "DEATH_BANK"

local fighting: Transformation? = nil
local fight: Ranged.Fight
local world_click: Host.MenuEntry? = nil
local world_click_at = 0
local last_click_key = ""

local priestess_keeps = false
local priestess_checked = false

type Phases = {
	phase: number,
	candidates: { number },
	diving: boolean,
	dive_at: number,
	dive_from: string,
	seen: string,
	last_animation: number,
	next: Transformation?,
	target: string?,
	later: string?,
	attacks_at: number,
	step: Host.Tile?,
	near: { key: string, tile: Host.Tile?, exact: boolean, checked: number?, rejected: Host.Tile? }?,
	early_at: number,
	whip_dodged: number?,
}

local function new_phases(): Phases
	return {
		phase = 0,
		candidates = { 1, 2, 3, 4 },
		diving = false,
		dive_at = 0,
		dive_from = "",
		seen = "",
		last_animation = -1,
		next = nil,
		target = nil,
		later = nil,
		attacks_at = 0,
		step = nil,
		near = nil,
		early_at = math.huge,
	}
end

local phases = new_phases()

local report = StatsReport.new()

function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	snap = {
		state = state,
		tick = Read.current_tick(state),
	}
	return true
end

function Read.zulrah(): (Host.Npc?, Transformation?)
	for _, npc in ipairs(Host.npcs() or {}) do
		for _, t in CONST.TRANSFORMATIONS do
			if npc.id == t.id then
				return npc, t
			end
		end
	end
	return nil, nil
end

local function transformation(key: string): Transformation?
	for _, t in CONST.TRANSFORMATIONS do
		if t.key == key then
			return t
		end
	end
	return nil
end

function Read.scene_tile(): Host.Tile
	local pos = assert(snap.state.position)
	return { x = pos.local_x // 128, y = pos.local_y // 128 }
end

function Read.world_tile(scene: Host.Tile): Host.Tile
	local pos = game_state().position or assert(snap.state.position)
	return { x = scene.x + pos.x - pos.local_x // 128, y = scene.y + pos.y - pos.local_y // 128 }
end

function Read.zulrah_position(npc: Host.Npc): string
	local me, base = Read.scene_tile(), assert(snap.state.position)
	local x, y = npc.x - (base.x - me.x), npc.y - (base.y - me.y)
	local best, best_d = "middle", math.huge
	for name, p in CONST.POSITIONS do
		local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
		if d < best_d then
			best, best_d = name, d
		end
	end
	return best
end

local function agreed(phase: number, part: number): string?
	if #phases.candidates == 0 then
		return nil
	end
	local word: string? = nil
	local past_all = true
	for _, i in phases.candidates do
		local step = CONST.ROTATIONS[i].phases[phase]
		if step then
			past_all = false
			local this = string.split(step, " ")[part]
			if word ~= nil and this ~= word then
				return nil
			end
			word = this
		end
	end
	if past_all then
		return string.split(CONST.ROTATIONS[1].phases[1], " ")[part]
	end
	return word
end

local function form_of_phase(phase: number): Transformation?
	local key = agreed(phase, 1)
	return if key then transformation(key) else nil
end

local function tile_label(key: string): string
	return (string.gsub(key, "_", " "))
end

local function tiles_of(word: string): (string, string?)
	local parts = string.split(word, ">")
	return parts[1], parts[2]
end

local function stand_on(key: string)
	Log.log(NAME, `Standing on {tile_label(key)}`)
	phases.target, phases.near = key, { key = key, tile = nil, exact = false, checked = nil, rejected = nil }
end

local function stand(word: string?)
	if word == nil then
		return
	end
	local key, later = tiles_of(word)
	local dodge = CONST.DODGES[key]
	if key ~= phases.target and (dodge == nil or dodge ~= phases.target) then
		local instead = dodge and fight.takes_dodge and Biometrics.random_boolean(CONST.DODGE_INSTEAD_CHANCE)
		stand_on(if instead then dodge :: string else key)
	end
	phases.later, phases.step = later, nil
end

local function past_last(phase: number): boolean
	for _, i in phases.candidates do
		if CONST.ROTATIONS[i].phases[phase] then
			return false
		end
	end
	return #phases.candidates > 0
end

local function stand_restart()
	local key = string.split(CONST.ROTATIONS[1].phases[1], " ")[3]
	local dodge = CONST.DODGES[key]
	local instead = dodge and fight.takes_dodge and Biometrics.random_boolean(CONST.DODGE_INSTEAD_CHANCE)
	stand_on(if instead then dodge :: string else key)
	local near = assert(phases.near)
	near.exact = true
	phases.later, phases.step = nil, nil
end

local function observe(t: Transformation, at: string)
	local longest = 0
	for _, i in phases.candidates do
		longest = math.max(longest, #CONST.ROTATIONS[i].phases)
	end
	phases.phase += 1
	if phases.phase > longest then
		phases.phase, phases.candidates = 1, { 1, 2, 3, 4 }
	end
	local before = #phases.candidates
	local left: { number } = {}
	for _, i in phases.candidates do
		local step = CONST.ROTATIONS[i].phases[phases.phase]
		if step and string.match(step, "^%a+ %a+") == `{t.key} {at}` then
			table.insert(left, i)
		end
	end
	phases.candidates = left
	stand(agreed(phases.phase, 3))
	phases.early_at = time() + Random.int(CONST.EARLY_TICKS[1], CONST.EARLY_TICKS[2]) * CONST.TICK_MS
	phases.attacks_at = S.zulrah_attacks
	local which = if #left == 1 then `rotation {CONST.ROTATIONS[left[1]].name}` else `{#left} rotations fit`
	Log.log(NAME, `Phase {phases.phase}: {t.label} {at}; {which}{if Read.in_jad_phase() then " (Jad phase)" else ""}`)
	if #left == 0 and before > 0 then
		Log.log(NAME, "No rotation fits: switching on what surfaces until the next cycle")
	end
end

function Read.track_phases(npc: Host.Npc, t: Transformation)
	local at = Read.zulrah_position(npc)
	local here = `{npc.id} {at}`
	if phases.phase == 0 then
		phases.seen = here
		observe(t, at)
		return
	end
	local started = npc.animation ~= phases.last_animation
	local surfacing = npc.animation == CONST.SURFACE_ANIMATION and started
	phases.last_animation = npc.animation
	if not phases.diving and npc.animation ~= CONST.DIVE_ANIMATION and (here ~= phases.seen or surfacing) then
		phases.seen = here
		observe(t, at)
		return
	end
	if not phases.diving and npc.animation == CONST.DIVE_ANIMATION then
		phases.diving, phases.dive_at, phases.dive_from = true, time(), here
		phases.next = form_of_phase(phases.phase + 1)
		if phases.next then
			Log.log(NAME, `Diving: switching to {phases.next.label} now`)
		end
		if past_last(phases.phase + 1) then
			stand_restart()
		else
			stand(agreed(phases.phase + 1, 3))
		end
		return
	end
	Read.note_whip(npc)
	local whip = S.whip_anim ~= nil and S.whip_at ~= phases.whip_dodged and not Read.whip_safe()
	if whip then
		phases.whip_dodged = S.whip_at
	end
	local dodge = phases.target and CONST.DODGES[phases.target]
	if dodge and whip then
		fight.dodge_whip(dodge)
	end
	if
		phases.diving
		and (
			npc.animation == CONST.SURFACE_ANIMATION
			or here ~= phases.dive_from
			or time() - phases.dive_at > CONST.SURFACE_MS
		)
	then
		phases.diving, phases.next = false, nil
		phases.seen = here
		observe(t, at)
	end
end

function Read.with_protection(layout: PrayerLayout.Layout?, protection: string?): PrayerLayout.Layout
	local prayers: { string } = {}
	if protection then
		table.insert(prayers, protection)
	end
	for _, key in ipairs(if layout then layout.prayers else {}) do
		table.insert(prayers, key)
	end
	return { name = if layout then layout.name else "no layout", prayers = prayers }
end

function Read.magic_snakeling_out(): boolean
	for _, npc in ipairs(Host.npcs() or {}) do
		if npc.id == CONST.MAGIC_SNAKELING then
			return true
		end
	end
	return false
end

function Read.prayers(t: Transformation): PrayerLayout.Layout?
	local layouts = CONFIG.transformations[t.key]
	local special = layouts.special_prayers ~= nil and Read.special_due(t)
	local snakeling = if special then layouts.special_snakeling_prayers else layouts.snakeling_prayers
	if snakeling and Read.magic_snakeling_out() then
		return snakeling
	end
	return if special then layouts.special_prayers else layouts.prayers
end

local my_index: number? = nil
local jad_protection: string? = nil
local jad_last: { cycle: number, ranged: boolean, seen_at: number }? = nil

function Read.incoming_attacks(): { Host.Projectile }
	local pos = game_state().position
	local found: { Host.Projectile } = {}
	if pos == nil then
		return found
	end
	local players = Host.players() or {}
	local kept = false
	for _, p in ipairs(players) do
		if p.index == my_index and p.name == snap.state.player_name then
			kept = true
		end
	end
	if not kept then
		my_index = nil
		for _, p in ipairs(players) do
			if p.name == snap.state.player_name then
				my_index = p.index
			end
		end
	end
	for _, p in ipairs(Host.projectiles() or {}) do
		local attack = p.id ~= CONST.CLOUD_PROJECTILE
			and not CONST.SNAKELING_PROJECTILES[p.id]
			and p.end_cycle > p.cycle
		local at_us = (my_index ~= nil and p.target_player == my_index)
			or (
				p.target_player == -1
				and p.target_npc == -1
				and math.abs(p.target_x - pos.x) <= 1
				and math.abs(p.target_y - pos.y) <= 1
			)
		if attack and at_us then
			table.insert(found, p)
		end
	end
	return found
end

function Read.attack_in_flight(): boolean
	return #Read.incoming_attacks() > 0
end

function Read.jad_protection(): string?
	for _, p in Read.incoming_attacks() do
		if jad_last == nil or p.start_cycle > jad_last.cycle then
			jad_last = { cycle = p.start_cycle, ranged = p.id == CONST.RANGED_PROJECTILE, seen_at = time() }
		end
	end
	if jad_last == nil then
		local npc = Read.zulrah()
		local at = npc and Read.zulrah_position(npc)
		return if at == "east" then "protect_from_magic" elseif at == "west" then "protect_from_missiles" else nil
	end
	return if jad_last.ranged then "protect_from_magic" else "protect_from_missiles"
end

function Read.move_window(): boolean
	local last = jad_last
	if phases.diving or not Read.in_jad_phase() or last == nil then
		return true
	end
	return time() - last.seen_at <= CONST.JAD_MOVE_WINDOW_MS
end

function Read.in_jad_phase(): boolean
	if #phases.candidates == 0 or phases.phase == 0 then
		return false
	end
	for _, i in phases.candidates do
		if CONST.ROTATIONS[i].jad ~= phases.phase then
			return false
		end
	end
	return true
end

function Read.fight_state(): State
	if not S.zulrah_alive then
		fighting = nil
		if Prayer.is_any_active() then
			return "PRAYERS_OFF"
		end
		if Read.kill_cure_due() then
			return "ANTIPOISON"
		end
		if Read.zulrah() then
			return "ZULRAH"
		end
		local item = Read.next_loot()
		if item then
			return if GroundItems.fits(item) then "LOOT" else "EAT_FOR_SPACE"
		end
		if Read.needs_restock() then
			return Read.restore_state()
		end
		if ChatOptions.is_title(CONST.LEAVE_QUESTION) then
			return "CONFIRM_LEAVE"
		end
		return if Read.teleport() then "LEAVE" else "ZULRAH"
	end
	local npc, t = Read.zulrah()
	if npc and npc.animation == CONST.DEATH_ANIMATION then
		S.zulrah_alive = false
		stats.runs += 1
		Log.log(NAME, "Zulrah is dead")
		return Read.fight_state()
	end
	fighting = t
	Read.track_zulrah_hp()
	if not S.staying and (S.escaping or Read.must_escape()) then
		S.escaping = true
		return Read.restore_state()
	end
	if npc == nil or t == nil then
		if npc == nil and Read.wants_move() then
			return "MOVE"
		end
		local supplies = Read.supplies_state()
		if supplies then
			return supplies
		end
		S.camera_goal = Read.camera_goal(nil)
		return if S.camera_goal then "CAMERA" else "ZULRAH"
	end
	Read.track_phases(npc, t)
	Read.count_attacks()
	Read.track_clouds()
	Read.track_shots(npc, t)
	Read.update_later(npc)
	Read.update_cloud_dodge(npc)
	local early = Read.early_tile(npc, t)
	if early then
		stand(early)
	end
	local want = if phases.diving
			and phases.next
			and time() - phases.dive_at >= CONST.DIVE_SWITCH_DELAY_MS
			and not Read.attack_in_flight()
		then phases.next
		else t
	fighting = want
	local layouts = CONFIG.transformations[want.key]
	if not Read.in_jad_phase() then
		jad_last = nil
	end
	if Read.in_jad_phase() then
		local protection = Read.jad_protection()
		if protection and not Prayer.is_on(protection) then
			jad_protection = protection
			return "JAD_PRAYER"
		end
	end
	if Read.supplies_state() == "EAT" then
		return "EAT"
	end
	if
		want.key == "magma"
		and phases.diving
		and layouts
		and layouts.equipment
		and EquipmentLayout.matches(layouts.equipment) == false
	then
		return if Read.wants_move() then "MOVE" else want.gear_state
	end
	local prayers = Read.prayers(want)
	if not Read.in_jad_phase() and prayers and not PrayerLayout.is_active(prayers) then
		return want.prayer_state
	end
	if Read.walk_attack_due(npc, t, layouts) then
		return "ATTACK"
	end
	if Read.wants_move() and not Read.waits_for_cloud() then
		return if Read.move_window() then "MOVE" else "ZULRAH"
	end
	if not Player.is_running() and (Player.run_energy() or 0) >= CONST.RUN_MIN_ENERGY then
		return "RUN"
	end
	local supplies = Read.supplies_state()
	if supplies then
		return supplies
	end
	local special = Read.special_due(want)
	local gear = if special then CONFIG.special.equipment else layouts and layouts.equipment
	if gear and EquipmentLayout.matches(gear) == false then
		return want.gear_state
	end
	if special and not SpecialAttack.is_enabled() then
		return "SPECIAL"
	end
	local attack = Read.wants_attack(npc) and fight.may_attack(npc, t.key)
	if attack and S.walked then
		return "ATTACK"
	end
	if Read.boost() then
		return "BOOST"
	end
	if Read.wants_thrall() then
		return "THRALL"
	end
	if attack then
		return "ATTACK"
	end
	S.camera_goal = Read.camera_goal(npc)
	if S.camera_goal then
		return "CAMERA"
	end
	if
		not Read.in_jad_phase()
		and not Inventory.is_open()
		and not Player.in_transit()
		and not CONST.RISING_ANIMATIONS[npc.animation]
	then
		return "INVENTORY"
	end
	return "ZULRAH"
end

type SupplyFamilies = { [string]: { [Consumables.Consumable]: boolean } }
local supply_families: SupplyFamilies? = nil
function Read.supply_families(): SupplyFamilies?
	if supply_families then
		return supply_families
	end
	local levels = Consumables.levels()
	if levels == nil then
		return nil
	end
	local families: SupplyFamilies = { food = {}, restore = {}, boost = {}, antivenom = {}, antipoison = {} }
	for _, c in ipairs(Consumables.raising("Hitpoints", 1, levels)) do
		if c.option == "Eat" then
			families.food[c] = true
		end
	end
	for _, c in ipairs(Consumables.raising("Prayer", 0, levels)) do
		families.restore[c] = true
	end
	for _, stat in CONST.BOOST_STATS do
		local level = levels[stat]
		if level then
			for _, c in ipairs(Consumables.raising(stat, level.real, levels)) do
				families.boost[c] = true
			end
		end
	end
	for _, c in ipairs(Consumables.with_special("antivenom")) do
		families.antivenom[c] = true
	end
	for _, c in ipairs(Consumables.with_special("antipoison")) do
		if not families.antivenom[c] then
			families.antipoison[c] = true
		end
	end
	supply_families = families
	return families
end

local function has_immune_helm(layout: EquipmentLayout.Layout?): boolean
	if layout == nil then
		return false
	end
	for _, slot in ipairs(layout.slots) do
		if slot.slot == 0 and slot.mode == "item" and CONST.VENOM_IMMUNE_HELMS[slot.id] then
			return true
		end
	end
	return false
end

function Read.venom_proof(
	equipment: { [string]: EquipmentLayout.Layout? },
	special: EquipmentLayout.Layout?,
	special_on: { [string]: boolean }
): boolean
	for _, t in CONST.TRANSFORMATIONS do
		if not has_immune_helm(equipment[t.key]) then
			return false
		end
		if special_on[t.key] and not has_immune_helm(special) then
			return false
		end
	end
	return true
end

function Read.worn_and_carried(layout: InventoryLayout.Layout, gear: EquipmentLayout.Layout?): { string }
	local worn: { [number]: boolean } = {}
	for _, slot in ipairs(if gear then gear.slots else {}) do
		if slot.mode == "item" then
			worn[slot.id] = true
			for _, id in ipairs(slot.ids) do
				worn[id] = true
			end
		end
	end
	local names: { string } = {}
	for _, slot in ipairs(layout.slots) do
		local clash = worn[slot.id]
		for _, id in ipairs(slot.ids) do
			clash = clash or worn[id]
		end
		if clash and not table.find(names, slot.name) then
			table.insert(names, slot.name)
		end
	end
	return names
end

function Read.inventory_problems(
	layout: InventoryLayout.Layout?,
	min_food: number,
	min_cure: number,
	venom_proof: boolean,
	start_gear: EquipmentLayout.Layout?
): { string }
	if layout == nil then
		return { "no inventory layout is picked" }
	end
	local families = Read.supply_families()
	if families == nil then
		return { "the levels can't be read to check the inventory layout" }
	end
	local food, restore, cure = 0, false, 0
	for _, slot in ipairs(layout.slots) do
		local c = Consumables.get(slot.id)
		if c then
			food += if families.food[c] then 1 else 0
			restore = restore or families.restore[c] == true
			if families.antivenom[c] or families.antipoison[c] then
				local doses = if slot.doses and #slot.doses > 0 then math.max(table.unpack(slot.doses)) else nil
				cure += doses or tonumber(string.match(slot.name, "%((%d)%)$")) or 1
			end
		end
	end
	local problems: { string } = {}
	for _, name in Read.worn_and_carried(layout, start_gear) do
		table.insert(
			problems,
			`the {layout.name} layout holds {name}, which the {if start_gear then start_gear.name else ""} layout wears when banking`
		)
	end
	if food < min_food then
		table.insert(problems, `the {layout.name} layout holds {food} food, under the minimum of {min_food}`)
	end
	if venom_proof then
		cure = min_cure
	end
	if cure == 0 then
		table.insert(problems, `the {layout.name} layout holds no antipoison or anti-venom`)
	elseif cure < min_cure then
		table.insert(
			problems,
			`the {layout.name} layout holds {cure} antipoison or anti-venom doses, under the minimum of {min_cure}`
		)
	end
	if not restore then
		table.insert(problems, `the {layout.name} layout holds no prayer restore`)
	end
	return problems
end

function Read.settings_problems(
	layout: InventoryLayout.Layout?,
	min_food: number,
	min_cure: number,
	venom_proof: boolean,
	start_gear: EquipmentLayout.Layout?,
	eat_min: number,
	eat_max: number,
	melee: boolean,
	equipment: { [string]: EquipmentLayout.Layout? },
	special: EquipmentLayout.Layout?
): { string }
	local problems = Read.inventory_problems(layout, min_food, min_cure, venom_proof, start_gear)
	if eat_min > eat_max then
		table.insert(
			problems,
			`the lowest hitpoints to eat at ({eat_min}) is above the highest hitpoints to eat at ({eat_max})`
		)
	end
	local checked: { { label: string, layout: EquipmentLayout.Layout } } = {}
	for _, t in CONST.TRANSFORMATIONS do
		local gear = equipment[t.key]
		if gear then
			table.insert(checked, { label = t.label, layout = gear })
		end
	end
	if special then
		table.insert(checked, { label = "special attack", layout = special })
	end
	for _, entry in checked do
		local problem = Read.style_problem(entry.layout, melee)
		if problem then
			table.insert(problems, `the {entry.label} equipment ({entry.layout.name}) {problem}`)
		end
	end
	return problems
end

function Read.style_problem(layout: EquipmentLayout.Layout, melee: boolean): string?
	local spell = layout.spell
	if spell and spell.autocast then
		return if melee then `autocasts {spell.name}, so it isn't melee` else nil
	end
	if spell and not melee then
		return `casts {spell.name} by hand, which the script doesn't do`
	end
	local weapon: Host.EquipmentLayoutSlot? = nil
	for _, slot in ipairs(layout.slots) do
		if slot.slot == CombatSafeSpot.WEAPON_SLOT then
			weapon = slot
		end
	end
	if weapon == nil or weapon.mode == "any" then
		return "has no set weapon, so its fight style can't be checked"
	end
	if weapon.mode == "empty" or weapon.id == nil then
		return if melee then nil else "has no weapon or autocast spell, so it isn't ranged or magic"
	end
	local params = Host.item_params({ weapon.id })
	if params == nil then
		return "has a weapon whose details can't be read"
	end
	local found = params[1]
	local range = if found then found[CombatSafeSpot.RANGE_PARAM] else nil
	local reach = if type(range) == "number" then range else 1
	local name = weapon.name or `item {weapon.id}`
	if melee and reach > CONST.MELEE_MAX_RANGE then
		return `isn't melee: the {name} attacks from {reach} tiles`
	end
	if not melee and reach <= CONST.MELEE_MAX_RANGE then
		return `isn't ranged or magic: the {name} is a melee weapon and no spell is autocast`
	end
	return nil
end

local KIND_STAT: { [string]: string } = { food = "Hitpoints", restore = "Prayer" }

local function level_of(stat: string): (number?, number?)
	if stat == "Hitpoints" then
		return Player.hitpoints()
	end
	return Player.prayer()
end

local gains: { [string]: { real: number?, by_family: { [Consumables.Consumable]: number } } } = {}
function Read.gain(c: Consumables.Consumable, stat: string, real: number?): number
	local cache = gains[stat]
	if cache == nil or cache.real ~= real then
		cache = { real = real, by_family = {} }
		gains[stat] = cache
	end
	local gain = cache.by_family[c]
	if gain then
		return gain
	end
	local levels = Consumables.levels()
	local level = if levels then levels[stat] else nil
	if level == nil then
		return 0
	end
	level.level = 0
	local r = Consumables.result(c.ids[1], levels)
	local outcome = if r then r[stat] else nil
	gain = if outcome then outcome.low else 0
	cache.by_family[c] = gain
	return gain
end

type Supply = { slot: number, name: string, option: string, family: Consumables.Consumable, uses: number }

function Read.held(kind: string): { Supply }
	local held: { Supply } = {}
	local families = Read.supply_families()
	local layout = CONFIG.inventory
	if families == nil or layout == nil then
		return held
	end
	local wanted: { [Consumables.Consumable]: boolean } = {}
	for _, slot in ipairs(layout.slots) do
		local c = Consumables.get(slot.id)
		if c and families[kind][c] then
			wanted[c] = true
		end
	end
	for _, item in ipairs(Inventory.items() or {}) do
		local c = if item.id ~= -1 then Consumables.get(item.id) else nil
		if c and wanted[c] then
			local name = item.name or c.name
			local doses = tonumber(string.match(name, "%((%d)%)$"))
			table.insert(held, { slot = item.slot, name = name, option = c.option, family = c, uses = doses or 1 })
		end
	end
	table.sort(held, function(a: Supply, b: Supply): boolean
		return a.uses < b.uses
	end)
	return held
end

function Read.uses(kind: string): number
	local uses = 0
	for _, supply in ipairs(Read.held(kind)) do
		uses += supply.uses
	end
	return uses
end

function Read.pick(kind: string): Supply?
	local stat = KIND_STAT[kind]
	local level, real = level_of(stat)
	local best: Supply?, best_gain, best_fits, best_combo = nil, -1, false, true
	for _, supply in ipairs(Read.held(kind)) do
		local gain = Read.gain(supply.family, stat, real)
		local fits = level ~= nil and real ~= nil and gain <= real - level
		local combo = supply.family.combo
		local better = if fits ~= best_fits then fits elseif combo ~= best_combo then not combo else gain > best_gain
		if best == nil or better then
			best, best_gain, best_fits, best_combo = supply, gain, fits, combo
		end
	end
	return best
end

function Read.combo_food(first: Supply): Supply?
	local level, real = Player.hitpoints()
	if first.family.combo or level == nil or real == nil then
		return nil
	end
	local room = real - level - Read.gain(first.family, "Hitpoints", real)
	local best: Supply?, best_gain = nil, 0
	for _, supply in ipairs(Read.held("food")) do
		local gain = Read.gain(supply.family, "Hitpoints", real)
		if supply.family.combo and supply.slot ~= first.slot and gain <= room and gain > best_gain then
			best, best_gain = supply, gain
		end
	end
	return best
end

function Read.just_used(key: string): boolean
	return time() - (S.used_at[key] or -math.huge) < CONST.CONSUME_MS
end

function Read.supply_ready(kind: string): boolean
	return not Read.just_used(kind) and Read.pick(kind) ~= nil
end

function Read.top_up(kind: string): number
	local stat = KIND_STAT[kind]
	local level, real = level_of(stat)
	if level == nil or real == nil then
		return 0
	end
	local each: { number } = {}
	for _, supply in ipairs(Read.held(kind)) do
		local gain = Read.gain(supply.family, stat, real)
		for _ = 1, supply.uses do
			table.insert(each, gain)
		end
	end
	table.sort(each, function(a: number, b: number): boolean
		return a > b
	end)
	local missing, uses = real - level, 0
	for _, gain in ipairs(each) do
		if gain > 0 and gain <= missing then
			missing -= gain
			uses += 1
		end
	end
	return uses
end

function Read.wants_top_up(kind: string): boolean
	return Read.top_up(kind) > 0 and Read.supply_ready(kind)
end

function Read.track_poison()
	local poison = Host.varp(CONST.POISON_VARP)
	if poison == nil or poison == S.poison then
		return
	end
	local known = S.poison ~= nil
	S.poison = poison
	if poison >= CONST.VENOMED then
		Log.log(NAME, `Venom: the next hit is {math.min(20, (poison - CONST.VENOM_PAST_SIX + 4) * 2)}`)
	end
	S.antipoison_tick = snap.tick
		+ if known then Random.int(CONST.ANTIPOISON_AFTER_TICKS[1], CONST.ANTIPOISON_AFTER_TICKS[2]) else 0
end

function Read.cure_state(): State?
	local poison = S.poison
	if poison == nil or Read.just_used("cure") then
		return nil
	end
	if #Read.held("antivenom") > 0 then
		return if poison > CONST.VENOM_IMMUNE_BELOW - CONST.VENOM_RENEW_UNITS then "ANTIVENOM" else nil
	end
	if poison >= CONST.VENOM_PAST_SIX and snap.tick >= S.antipoison_tick and #Read.held("antipoison") > 0 then
		return "ANTIPOISON"
	end
	return nil
end

function Read.kill_cure_due(): boolean
	local poison = S.poison
	return poison ~= nil
		and poison >= CONST.VENOMED
		and not Read.just_used("cure")
		and #Read.held("antivenom") == 0
		and #Read.held("antipoison") > 0
end

function Read.supplies_state(): State?
	local hp = Player.hitpoints()
	if hp and hp <= S.eat_at and Read.supply_ready("food") then
		return "EAT"
	end
	local prayer = Player.prayer()
	if prayer and prayer <= S.restore_at and Read.supply_ready("restore") then
		return "PRAYER_POTION"
	end
	return Read.cure_state()
end

function Read.track_zulrah_hp()
	local name, hp = NpcHealth.target()
	if name == nil or hp == nil or not string.find(name, NAME, 1, true) then
		return
	end
	S.zulrah_hp = hp
	if not S.staying and hp < CONFIG.stay_below then
		S.staying = true
		Log.log(NAME, `Zulrah has {hp} hitpoints left: staying until the kill`)
	end
end

function Read.must_escape(): boolean
	local hp = Player.hitpoints()
	if hp and hp < CONST.ZULRAH_MAX_HIT and Read.pick("food") == nil then
		Log.log(NAME, `Escaping: {hp} hitpoints and no food left`)
		return true
	end
	local prayer = Player.prayer()
	if prayer and prayer <= S.restore_at and Read.pick("restore") == nil then
		Log.log(NAME, `Escaping: {prayer} prayer and nothing left to restore it`)
		return true
	end
	return false
end

local function timer_runs(c: Consumables.Consumable): boolean
	for _, special in ipairs(c.special) do
		local left = Consumables.remaining(special.name)
		if left and left > 0 then
			return true
		end
	end
	return false
end

function Read.boost(): Supply?
	if Read.just_used("boost") then
		return nil
	end
	local levels = Consumables.levels()
	if levels == nil then
		return nil
	end
	local now: { [string]: number } = {}
	for _, stat in CONST.BOOST_STATS do
		local level = levels[stat]
		if level then
			now[stat], level.level = level.level, level.real
		end
	end
	local best: Supply?, best_to = nil, -1
	for _, supply in ipairs(Read.held("boost")) do
		local r = if timer_runs(supply.family) then nil else Consumables.result(supply.family.ids[1], levels)
		for _, stat in CONST.BOOST_STATS do
			local outcome, current = if r then r[stat] else nil, now[stat]
			if outcome and current and outcome.low > outcome.from then
				local due = current <= outcome.low - math.min(CONST.BOOST_DROP, outcome.low - outcome.from)
				if due and outcome.low > best_to then
					best, best_to = supply, outcome.low
				end
			end
		end
	end
	return best
end

function Read.unattackable(npc: Host.Npc): boolean
	return phases.diving or npc.animation == CONST.DIVE_ANIMATION or CONST.RISING_ANIMATIONS[npc.animation] == true
end

function Read.special_weapon(): number?
	local layout = CONFIG.special.equipment
	for _, slot in ipairs(if layout then layout.slots else {}) do
		if slot.slot == SpecialAttack.WEAPON_SLOT and slot.mode == "item" then
			return slot.id
		end
	end
	return nil
end

function Read.special_due(t: Transformation): boolean
	local layout = CONFIG.special.equipment
	if
		CONFIG.melee
		or layout == nil
		or not CONFIG.special.on[t.key]
		or phases.diving
		or time() - S.special_failed_at < CONST.SPECIAL_RETRY_MS
	then
		return false
	end
	local npc = Read.zulrah()
	local weapon, energy = Read.special_weapon(), SpecialAttack.energy()
	if npc == nil or Read.unattackable(npc) or weapon == nil or energy == nil then
		return false
	end
	local cost = SpecialAttack.cost(weapon)
	return cost ~= nil and energy >= cost and #EquipmentLayout.missing(layout) == 0
end

function Read.gear_for(t: Transformation): EquipmentLayout.Layout?
	if Read.special_due(t) then
		return CONFIG.special.equipment
	end
	return CONFIG.transformations[t.key].equipment
end

function Read.track_world_click()
	local click = Minimenu.clicked()
	if click == nil then
		return
	end
	local e = click.entry
	local key = `{e.option}|{e.index}|{e.action}|{click.x}|{click.y}`
	if key == last_click_key then
		return
	end
	last_click_key = key
	if CONST.WORLD_MENU_KINDS[e.kind] or e.option == "Walk here" then
		world_click, world_click_at = e, time()
	end
end

function Read.server_attacking(npc: Host.Npc): boolean
	for _, p in ipairs(Host.players() or {}) do
		if p.name == snap.state.player_name then
			return p.target_state == Player.INTERACTING and p.interacting_npc == npc.index
		end
	end
	return false
end

function Read.wants_attack(npc: Host.Npc): boolean
	if Read.unattackable(npc) then
		return false
	end
	if Player.in_transit() then
		local server, tile = Host.server_tile(), Read.goal()
		if server == nil or tile == nil then
			return false
		end
		local goal = Read.world_tile(tile)
		if server.x ~= goal.x or server.y ~= goal.y then
			return false
		end
	end
	if S.attack_phase == phases.phase then
		local is_attacking = world_click ~= nil
			and world_click.option == "Attack"
			and Npcs.owns(npc, world_click)
			and npc.animation ~= CONST.DIVE_ANIMATION
			and not CONST.RISING_ANIMATIONS[npc.animation]
			and (time() - world_click_at < CONST.ATTACK_CONFIRM_MS or Read.server_attacking(npc))
		if is_attacking then
			return false
		end
	end
	return true
end

function Read.count_attacks()
	local newest = S.last_attack_cycle
	for _, p in Read.incoming_attacks() do
		if p.start_cycle > S.last_attack_cycle then
			S.zulrah_attacks += 1
			newest = math.max(newest, p.start_cycle)
		end
	end
	S.last_attack_cycle = newest
	local throws: { number } = {}
	local newest_spawn = S.last_spawn_cycle
	for _, p in ipairs(Host.projectiles() or {}) do
		if p.id == CONST.CLOUD_PROJECTILE then
			table.insert(throws, p.start_cycle)
		elseif p.id == CONST.SNAKELING_SPAWN_PROJECTILE and p.start_cycle > S.last_spawn_cycle then
			S.zulrah_attacks += 1
			newest_spawn = math.max(newest_spawn, p.start_cycle)
		end
	end
	S.last_spawn_cycle = newest_spawn
	table.sort(throws)
	for _, cycle in throws do
		if cycle >= S.last_throw_cycle + CONST.THROW_CYCLES then
			S.zulrah_attacks += 1
			S.last_throw_cycle = cycle
		end
	end
end

local function time_cloud(cloud: Cloud, late: boolean)
	cloud.late = late
	cloud.spawn_at = cloud.land_at + if late then CONST.CLOUD_LATE_SPAWN_MS else CONST.CLOUD_SPAWN_MS
	cloud.gone_at = cloud.spawn_at + CONST.CLOUD_LIFE_MS
end

function Read.track_clouds()
	local now = time()
	for key, cloud in S.clouds do
		if
			not cloud.late
			and phases.diving
			and phases.dive_at >= cloud.seen_at
			and phases.dive_at <= cloud.land_at + CONST.CLOUD_LATE_DIVE_MS
		then
			time_cloud(cloud, true)
		end
		if now >= cloud.gone_at then
			S.clouds[key] = nil
		end
	end
	for _, p in ipairs(Host.projectiles() or {}) do
		if p.id == CONST.CLOUD_PROJECTILE then
			local key = `{p.target_x}:{p.target_y}`
			local cloud = S.clouds[key]
			if cloud == nil or cloud.start_cycle < p.start_cycle then
				local new: Cloud = {
					x = p.target_x,
					y = p.target_y,
					start_cycle = p.start_cycle,
					seen_at = now,
					land_at = now + math.max(p.end_cycle - p.cycle, 0) * CONST.CYCLE_MS,
					late = false,
					spawn_at = 0,
					gone_at = 0,
				}
				time_cloud(new, phases.diving)
				S.clouds[key] = new
			end
		end
	end
end

local function clouded(tile: Host.Tile): boolean
	for _, cloud in S.clouds do
		local dx, dy = tile.x - cloud.x, tile.y - cloud.y
		if dx >= 0 and dx < CONST.CLOUD_SIZE and dy >= 0 and dy < CONST.CLOUD_SIZE then
			return true
		end
	end
	return false
end

function Read.update_cloud_dodge(npc: Host.Npc)
	local key = phases.target
	local home = key and fight.stand_tile(key)
	if key == nil or home == nil or not clouded(Read.world_tile(home)) then
		if S.cloud_dodge and S.cloud_dodge.key == key then
			Log.log(NAME, `The cloud on {tile_label(key :: string)} is gone`)
		end
		S.cloud_dodge = nil
		return
	end
	local dodge = S.cloud_dodge
	if dodge and dodge.key == key and not clouded(Read.world_tile(dodge)) then
		return
	end
	local me = Read.scene_tile()
	for reach = 1, CONST.CLOUD_DODGE_REACH do
		local ring: { Host.Tile } = {}
		for dx = -reach, reach do
			for dy = -reach, reach do
				if math.max(math.abs(dx), math.abs(dy)) == reach then
					table.insert(ring, { x = home.x + dx, y = home.y + dy })
				end
			end
		end
		table.sort(ring, function(a: Host.Tile, b: Host.Tile): boolean
			return math.max(math.abs(a.x - me.x), math.abs(a.y - me.y))
				< math.max(math.abs(b.x - me.x), math.abs(b.y - me.y))
		end)
		for _, tile in ipairs(ring) do
			local world = Read.world_tile(tile)
			if not clouded(world) and Read.can_hit_from(tile, npc) and Read.arena_path(world) ~= nil then
				Log.log(NAME, `Cloud on {tile_label(key)}: standing on {tile.x},{tile.y} until it goes`)
				S.cloud_dodge = { key = key, x = tile.x, y = tile.y }
				return
			end
		end
	end
	if S.cloud_dodge then
		Log.log(NAME, `No tile around {tile_label(key)} is out of the clouds`)
	end
	S.cloud_dodge = nil
end

function Read.arena_grid(): SafeSpot.Grid?
	if S.arena_grid == nil then
		S.arena_grid = SafeSpot.grid_around(Read.world_tile(CONST.ARENA_CENTER), CONST.ARENA_RADIUS)
	end
	return S.arena_grid
end

local STEPS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

function Read.arena_path(goal: Host.Tile, clear: boolean?): { Host.Tile }?
	local grid = Read.arena_grid()
	local pos = snap.state.position
	if grid == nil or pos == nil then
		return nil
	end
	local function key(x: number, y: number): number
		return (x - grid.x) * grid.height + (y - grid.y)
	end
	local from: { [number]: number } = { [key(pos.x, pos.y)] = -1 }
	local queue, head = { { x = pos.x, y = pos.y } }, 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		if at.x == goal.x and at.y == goal.y then
			local path: { Host.Tile } = {}
			local k = key(at.x, at.y)
			while from[k] ~= -1 do
				table.insert(path, 1, { x = grid.x + k // grid.height, y = grid.y + k % grid.height })
				k = from[k]
			end
			return path
		end
		for _, d in STEPS do
			local x, y = at.x + d[1], at.y + d[2]
			local k = key(x, y)
			if
				from[k] == nil
				and SafeSpot.can_step(grid, at.x, at.y, d[1], d[2])
				and not (clear and clouded({ x = x, y = y }) and not (x == goal.x and y == goal.y))
			then
				from[k] = key(at.x, at.y)
				table.insert(queue, { x = x, y = y })
			end
		end
	end
	return nil
end

local function crosses_cloud(path: { Host.Tile }): boolean
	for _, tile in path do
		if clouded(tile) then
			return true
		end
	end
	return false
end

function Read.waits_for_cloud(): boolean
	local tile, name = Read.goal()
	if tile == nil or name == nil or Read.in_jad_phase() then
		return false
	end
	local pos = game_state().position
	local goal = Read.world_tile(tile)
	local plain = Read.arena_path(goal)
	if pos == nil or clouded(pos) or plain == nil or not crosses_cloud(plain) or Read.arena_path(goal, true) ~= nil then
		return false
	end
	local now = time()
	for _, step in plain do
		for _, cloud in S.clouds do
			local dx, dy = step.x - cloud.x, step.y - cloud.y
			local covers = dx >= 0 and dx < CONST.CLOUD_SIZE and dy >= 0 and dy < CONST.CLOUD_SIZE
			if covers and cloud.gone_at - now > CONST.CLOUD_WAIT_MS then
				return false
			end
		end
	end
	if S.cloud_wait_logged ~= name then
		S.cloud_wait_logged = name
		Log.log(NAME, `Every way to the {tile_label(name)} tile crosses a cloud about to go: waiting for it`)
	end
	return true
end

function Read.track_shots(npc: Host.Npc, t: Transformation)
	local server = Host.server_tile()
	if server == nil then
		return
	end
	for _, p in ipairs(Host.projectiles() or {}) do
		if
			p.target_npc == npc.index
			and not CONST.THRALL_PROJECTILES[p.id]
			and math.max(math.abs(p.source_x - server.x), math.abs(p.source_y - server.y)) <= 1
			and p.start_cycle > S.last_shot_cycle
		then
			local gap = p.start_cycle - S.last_shot_cycle
			if gap >= 2 * CONST.TICK_CYCLES and gap <= 8 * CONST.TICK_CYCLES then
				S.shot_gaps[t.key] = math.min(S.shot_gaps[t.key] or math.huge, gap)
			end
			S.last_shot_cycle, S.last_shot_at = p.start_cycle, time()
			S.walk_attack = nil
		end
	end
	local held = S.walk_attack
	if held and time() - held.at >= CONST.SHOT_WAIT_MS then
		S.walk_attack = nil
	end
end

function Read.walk_attack_due(npc: Host.Npc, t: Transformation, layouts: TransformationLayouts?): boolean
	if
		t.key == "magma"
		or Read.in_jad_phase()
		or Read.unattackable(npc)
		or S.walk_attack
		or not Player.in_transit()
	then
		return false
	end
	if layouts and layouts.equipment and EquipmentLayout.matches(layouts.equipment) == false then
		return false
	end
	if not Read.in_safe_reach(npc) then
		return false
	end
	local gap = (S.shot_gaps[t.key] or CONST.SHOT_GAP_TICKS * CONST.TICK_CYCLES) * CONST.CYCLE_MS
	return time() - S.last_shot_at >= gap - CONST.SHOT_LEAD_MS
end

function Read.update_later(npc: Host.Npc)
	local later = phases.later
	if later == nil or phases.diving or S.zulrah_attacks - phases.attacks_at < CONST.LATER_AFTER_ATTACKS then
		return
	end
	local step = phases.step
	if step and clouded(Read.world_tile(step)) then
		Log.log(NAME, `A cloud on {step.x},{step.y}: leaving it`)
		phases.step = nil
	end
	local goal = Read.world_tile(CONST.TILES[later])
	local path = Read.arena_path(goal)
	if path == nil then
		return
	end
	if not clouded(goal) and not crosses_cloud(path) then
		Log.log(NAME, `The phase's clouds are gone: on to {tile_label(later)}`)
		stand_on(later)
		phases.later, phases.step = nil, nil
		return
	end
	if phases.step then
		return
	end
	local now = time()
	for _, cloud in S.clouds do
		if cloud.gone_at - now <= CONST.CLOUD_SOON_MS then
			return
		end
	end
	local clear = 0
	for i, tile in path do
		if clouded(tile) then
			break
		end
		clear = i
	end
	if clear < CONST.STEP_CLEAR_TILES then
		return
	end
	local origin = Read.world_tile({ x = 0, y = 0 })
	local any: { Host.Tile }, hit: { Host.Tile } = {}, {}
	for i = math.ceil(clear / 2), clear do
		local tile = { x = path[i].x - origin.x, y = path[i].y - origin.y }
		table.insert(any, tile)
		if Read.can_hit_from(tile, npc) then
			table.insert(hit, tile)
		end
	end
	local from = fight.step_tiles(hit, any)
	if #from == 0 then
		return
	end
	local pick = from[Random.int(1, #from)]
	Log.log(NAME, `{clear} tiles of the way to {tile_label(later)} are clear: to {pick.x},{pick.y} first`)
	phases.step = pick
end

function Read.walk_via(goal: Host.Tile): Host.Tile
	local plain = Read.arena_path(goal)
	if plain == nil or not crosses_cloud(plain) then
		return goal
	end
	local round = Read.arena_path(goal, true)
	if round == nil then
		return goal
	end
	for i = #round - 1, 1, -1 do
		local to = Read.arena_path(round[i])
		if to and not crosses_cloud(to) then
			return round[i]
		end
	end
	return goal
end

function Read.attack_window(t: Transformation): boolean
	if t.key ~= "magma" or Read.whip_safe() then
		return true
	end
	local tile = Read.goal()
	local me = Read.scene_tile()
	local on_tile = tile ~= nil and me.x == tile.x and me.y == tile.y
	return on_tile
		and S.whip_anim ~= nil
		and S.whip_at == phases.whip_dodged
		and time() - (S.whip_at :: number) < CONST.WHIP_ATTACK_WINDOW_MS
end

function Read.whip_safe(): boolean
	return phases.target ~= nil and CONST.WHIP_SAFE[phases.target] == true
end

local function server_scene_tile(): Host.Tile?
	local server, pos = Host.server_tile(), game_state().position
	if server == nil or pos == nil then
		return nil
	end
	return { x = server.x - (pos.x - pos.local_x // 128), y = server.y - (pos.y - pos.local_y // 128) }
end

function Read.in_safe_reach(npc: Host.Npc): boolean
	local scene = server_scene_tile()
	return scene ~= nil and not clouded(Read.world_tile(scene)) and Read.can_hit_from(scene, npc)
end

function Read.note_whip(npc: Host.Npc): boolean
	if not CONST.WHIP_ANIMATIONS[npc.animation] then
		S.whip_anim = nil
		return false
	end
	local now = time()
	if S.whip_anim ~= npc.animation or S.whip_at == nil or now - S.whip_at >= CONST.WHIP_MS then
		S.whip_anim, S.whip_at = npc.animation, now
		S.zulrah_attacks += 1
		return true
	end
	return false
end

function Read.can_hit_from(scene: Host.Tile, npc: Host.Npc): boolean
	local range = CombatSafeSpot.weapon_range()
	local grid = Read.arena_grid()
	if range == nil or grid == nil then
		return false
	end
	return CombatSafeSpot.can_attack(grid, Read.world_tile(scene), SafeSpot.chaser(npc, CONST.ZULRAH_SIZE), range)
end

function Read.can_hit_at(scene: Host.Tile, at: { x: number, y: number }): boolean
	local range = CombatSafeSpot.weapon_range()
	local grid = Read.arena_grid()
	if range == nil or grid == nil then
		return false
	end
	local centre, half = Read.world_tile(at), CONST.ZULRAH_SIZE // 2
	local chaser = { x = centre.x - half, y = centre.y - half, size = CONST.ZULRAH_SIZE }
	return CombatSafeSpot.can_attack(grid, Read.world_tile(scene), chaser, range)
end

local function standing_phase(): number
	return if phases.diving then phases.phase + 1 else math.max(phases.phase, 1)
end

local function expected_clouds(phase: number): { { number } }
	local aims: { { number } } = {}
	for _, i in phases.candidates do
		local rotation = CONST.ROTATIONS[i]
		local known = rotation.clouds[if phase > #rotation.phases then 1 else phase]
		if known then
			for _, aim in if #known == 0 then CONST.CLOUD_AIMS else known do
				table.insert(aims, aim)
			end
		end
	end
	return aims
end

local function under(aims: { { number } }, tile: Host.Tile): boolean
	for _, aim in aims do
		local dx, dy = tile.x - aim[1], tile.y - aim[2]
		if dx >= 0 and dx < CONST.CLOUD_SIZE and dy >= 0 and dy < CONST.CLOUD_SIZE then
			return true
		end
	end
	return false
end

local function far_side(home: Host.Tile, tile: Host.Tile, at: { x: number, y: number }): boolean
	local dx, dy, zx, zy = tile.x - home.x, tile.y - home.y, at.x - home.x, at.y - home.y
	return if math.abs(zx) >= math.abs(zy) then dx * zx < 0 else dy * zy < 0
end

local function fine_near(key: string, tile: Host.Tile, aims: { { number } }): boolean
	local home = CONST.TILES[key]
	return math.abs(tile.x - home.x) <= CONST.NEAR_REACH
		and math.abs(tile.y - home.y) <= CONST.NEAR_REACH
		and not under(aims, tile)
		and not clouded(Read.world_tile(tile))
end

function Read.early_tile(npc: Host.Npc, t: Transformation): string?
	if phases.diving or t.key == "magma" or time() < phases.early_at then
		return nil
	end
	local here = agreed(phases.phase, 3)
	if here and select(2, tiles_of(here)) then
		return nil
	end
	local word = agreed(phases.phase + 1, 3)
	local key = if word then tiles_of(word) else nil
	if
		key == nil
		or key == phases.target
		or CONST.DODGES[key] == phases.target
		or not Read.can_hit_from(CONST.TILES[key], npc)
	then
		return nil
	end
	local goal = Read.world_tile(CONST.TILES[key])
	local path = Read.arena_path(goal)
	if path == nil or clouded(goal) then
		return nil
	end
	for _, tile in ipairs(path) do
		if clouded(tile) then
			return nil
		end
	end
	Log.log(NAME, "Getting ahead of the next phase")
	return word
end

local stacks: { [number]: boolean } = {}

local function stackable(id: number): boolean
	if stacks[id] == nil then
		stacks[id] = (Host.item_stackable({ id }) or {})[1] == true
	end
	return stacks[id]
end

function Read.next_loot(): Host.GroundItem?
	local me = Walker.position()
	if me == nil then
		return nil
	end
	local best: Host.GroundItem? = nil
	local best_d, best_fits = math.huge, false
	for _, item in ipairs(Host.ground_items() or {}) do
		local d, fits = GroundItems.distance(item, me), GroundItems.fits(item)
		if not S.no_room[item.id] and ((fits and not best_fits) or (fits == best_fits and d < best_d)) then
			best, best_d, best_fits = item, d, fits
		end
	end
	return best
end

function Read.pile_fits(tile: Host.Tile): boolean
	local needed, counted = 0, {}
	for _, item in ipairs(Host.ground_items() or {}) do
		if item.x == tile.x and item.y == tile.y and not S.no_room[item.id] then
			if not stackable(item.id) then
				needed += 1
			elseif not counted[item.id] and Inventory.find(item.id) == nil then
				counted[item.id] = true
				needed += 1
			end
		end
	end
	return needed <= (Inventory.free_slots() or 0)
end

function Read.teleport(): Host.Loc?
	local me = Walker.position()
	return if me then Objects.nearest(CONST.TELEPORT_LOC, me) else nil
end

function Read.wants_move(): boolean
	local tile, name = Read.goal()
	if tile == nil then
		return false
	end
	local me = Read.scene_tile()
	if me.x == tile.x and me.y == tile.y then
		return false
	end
	local pos = game_state().position
	if S.walk_attack and pos and not clouded(pos) then
		return false
	end
	if not (S.moving_to == name and Player.in_transit()) then
		return true
	end
	local dest = Player.destination()
	local goal, via = Read.world_tile(tile), S.moving_via
	if dest and via and dest.x == via.x and dest.y == via.y then
		return false
	end
	return dest ~= nil and (dest.x ~= goal.x or dest.y ~= goal.y)
end

function Read.goal(): (Host.Tile?, string?)
	local key = phases.target
	if key == nil then
		return nil, nil
	end
	local whip = S.whip_dodge
	if whip and whip.key == key and time() < whip.ends_at then
		return { x = whip.x, y = whip.y }, `whip dodge {whip.x},{whip.y}`
	end
	local step = phases.step
	if step then
		return step, `step {step.x},{step.y}`
	end
	local dodge = S.cloud_dodge
	if dodge and dodge.key == key then
		return { x = dodge.x, y = dodge.y }, `cloud dodge {dodge.x},{dodge.y}`
	end
	return fight.stand_tile(key), key
end

local fight_context = {
	name = NAME,
	tiles = CONST.TILES,
	positions = CONST.POSITIONS,
	near_reach = CONST.NEAR_REACH,
	zulrah_size = CONST.ZULRAH_SIZE,
	near = function()
		return phases.near
	end,
	phase = function(): number
		return phases.phase
	end,
	target = function(): string?
		return phases.target
	end,
	set_target = function(key: string)
		phases.target = key
	end,
	standing_phase = standing_phase,
	agreed = agreed,
	form_key = function(phase: number): string?
		local form = form_of_phase(phase)
		return if form then form.key else nil
	end,
	expected_clouds = expected_clouds,
	under = under,
	far_side = far_side,
	fine_near = fine_near,
	clouded = clouded,
	crosses_cloud = crosses_cloud,
	tile_label = tile_label,
	world_tile = Read.world_tile,
	scene_tile = Read.scene_tile,
	server_scene_tile = server_scene_tile,
	arena_path = function(goal: Host.Tile): { Host.Tile }?
		return Read.arena_path(goal)
	end,
	can_hit_at = Read.can_hit_at,
	in_safe_reach = Read.in_safe_reach,
	can_hit_from = Read.can_hit_from,
	attack_window = function(form: string): boolean
		return Read.attack_window(assert(transformation(form)))
	end,
	whip_active = function(): boolean
		return S.whip_anim ~= nil
	end,
	goal = function(): Host.Tile?
		return (Read.goal())
	end,
}
local RANGED_FIGHT, MELEE_FIGHT = Ranged.new(fight_context), Melee.new(fight_context)
fight = if CONFIG.melee then MELEE_FIGHT else RANGED_FIGHT

function Read.camera_goal(npc: Host.Npc?): { x: number, y: number }?
	if time() - S.camera_at < CONST.CAMERA_EVERY_MS then
		return nil
	end
	local view = Toplevel.viewport()
	if view == nil then
		return nil
	end
	local blockers = Toplevel.blockers()
	local function shown(points: { Point }): boolean
		for _, p in points do
			if not Toplevel.is_visible(p, view, blockers) then
				return false
			end
		end
		return true
	end
	if npc and not phases.diving then
		local box = Npcs.clickbox(npc)
		if box and #box.polygon > 0 and shown(box.polygon) then
			return nil
		end
		return { x = npc.local_x, y = npc.local_y }
	end
	local where = agreed(phases.phase + 1, 2)
	local spot = where and CONST.POSITIONS[where]
	if spot == nil then
		return nil
	end
	local at = { x = spot.x * 128 + 64, y = spot.y * 128 + 64 }
	local cuboid = Projection.cuboid(at.x, at.y, CONST.ZULRAH_SIZE, CONST.CAMERA_HEIGHT)
	if cuboid and shown(Quad.corners(cuboid.bottom)) and shown(Quad.corners(cuboid.top)) then
		return nil
	end
	return at
end

function Read.wants_thrall(): boolean
	if not Magic.is_spellbook("arceuus") or Magic.thrall_on_cooldown() or time() < S.thrall_retry_at then
		return false
	end
	if not Magic.thrall_active() then
		return true
	end
	local left = Magic.thrall_remaining_ms()
	if left == nil or left == 0 then
		return true
	end
	if left > CONST.THRALL_EARLY_MS then
		return false
	end
	if S.thrall_early == nil then
		S.thrall_early = Biometrics.random_boolean(CONST.THRALL_EARLY_CHANCE)
		if S.thrall_early then
			Log.log(NAME, `Resummoning the thrall early ({math.floor(left / 1000)} s left)`)
		end
	end
	return S.thrall_early == true
end

function Read.in_arena(): boolean
	if not Player.in_instance() then
		return false
	end
	for _, chunk in ipairs(Player.instance_chunks() or {}) do
		if CONST.ARENA_CHUNKS[chunk:id()] then
			return true
		end
	end
	return false
end

function Read.area(): State
	if Read.in_arena() and Player.hitpoints() == 0 then
		if not priestess_keeps then
			Log.log(NAME, `Died at Zulrah: {CONST.PRIESTESS} keeps what was left behind`)
		end
		priestess_keeps = true
	end
	if Prayer.is_any_active() and not Read.in_arena() then
		return "PRAYERS_OFF"
	end
	if Player.in_instance() then
		if Read.in_arena() then
			return "ZULRAH"
		end
		if House.inside() then
			return "HOUSE"
		end
		return Read.restock_state()
	end
	local pos = assert(snap.state.position)
	if Position.Chunk.new(pos.x // 64, pos.y // 64):id() == CONST.ZULANDRA_CHUNK then
		S.scroll_missing = false
		return Read.island_state()
	end
	if Read.items_held() then
		return Read.death_walk_state()
	end
	if Ferox.inside() and Read.wants_pool() then
		return "FEROX"
	end
	return Read.restock_state()
end

function Read.items_held(): boolean
	return priestess_keeps
end

function Read.death_walk_state(): State
	local held = (Inventory.quantity(CONST.ZULANDRA_TELEPORT) or 0) >= 1
	if (held or S.scroll_missing) and not Bankmain.is_open() then
		return "TRAVEL_ZULANDRA"
	end
	return "DEATH_BANK"
end

function Read.gear_short(): EquipmentLayout.Layout?
	for _, t in CONST.TRANSFORMATIONS do
		local layout = CONFIG.transformations[t.key].equipment
		if layout and #EquipmentLayout.missing(layout) > 0 then
			return layout
		end
	end
	return nil
end

function Read.first_gear_off(): EquipmentLayout.Layout?
	local first = CONFIG.transformations[CONST.TRANSFORMATIONS[1].key]
	local layout = first and first.equipment
	return if layout and EquipmentLayout.matches(layout) == false then layout else nil
end

function Read.restock_state(): State
	local open = Bankmain.is_open()
	if Read.gear_short() then
		return "BANKING"
	end
	local gear = Read.first_gear_off()
	if gear then
		return if #EquipmentLayout.missing(gear) > 0 then "BANKING" else "PREPARE_GEAR"
	end
	local layout = CONFIG.inventory
	if not open and layout and InventoryLayout.matches(layout) then
		return "TRAVEL_ZULANDRA"
	end
	return "BANKING"
end

function Read.island_state(): State
	if Read.items_held() then
		if Inventory.is_full() and not ItemRetrieval.is_open() then
			return if Read.first_gear_off() then "PREPARE_GEAR" else Read.restore_state()
		end
		return "RECOVER_GEAR"
	end
	if Read.needs_restock() or Read.gear_short() then
		return Read.restore_state()
	end
	if Read.just_used("restore") then
		return "LOADING"
	end
	if Read.wants_top_up("restore") then
		return "PRAYER_POTION"
	end
	if Read.just_used("food") then
		return "LOADING"
	end
	if Read.wants_top_up("food") then
		return "EAT"
	end
	local first = CONFIG.transformations[CONST.TRANSFORMATIONS[1].key]
	if first and first.equipment and EquipmentLayout.matches(first.equipment) == false then
		return "PREPARE_GEAR"
	end
	if ChatOptions.is_title(CONST.BOARD_QUESTION) then
		return "CONFIRM_BOAT"
	end
	return "BOARD_BOAT"
end

function Read.needs_restock(): boolean
	if Read.uses("food") - Read.top_up("food") < CONFIG.min_food then
		return true
	end
	if Read.uses("restore") - Read.top_up("restore") < CONFIG.min_prayer_doses then
		return true
	end
	return not CONFIG.venom_proof and Read.cure_doses() < CONFIG.min_cure_doses
end

function Read.cure_doses(): number
	return Read.uses("antivenom") + Read.uses("antipoison")
end

function Read.wants_pool(): boolean
	local hp, max_hp = Player.hitpoints()
	local prayer, max_prayer = Player.prayer()
	return (hp ~= nil and max_hp ~= nil and hp < max_hp)
		or (prayer ~= nil and max_prayer ~= nil and prayer < max_prayer)
end

function Read.fastest_bank(): { name: string, x: number, y: number, plane: number, ticks: number }?
	local here = Player.position()
	if here == nil then
		return nil
	end
	local best: { name: string, x: number, y: number, plane: number, ticks: number }? = nil
	for _, bank in CONST.BANKS do
		local choice = Transports.choose(here :: any, { x = bank.x, y = bank.y, plane = bank.plane })
		if choice and (best == nil or choice.ticks < best.ticks) then
			best = { name = bank.name, x = bank.x, y = bank.y, plane = bank.plane, ticks = math.floor(choice.ticks) }
		end
	end
	return best
end

function Read.restore_state(): State
	return if CONFIG.restore == "Ferox Enclave" then "TELEPORT_FEROX" else "TELEPORT_HOUSE"
end

function Game.sign_in(): boolean
	Log.log(NAME, "Logging in")
	local ok = Login.sign_in()
	if not ok then
		Log.log(NAME, "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Game.ensure_logged_in(s: ClientState): boolean
	if s.game_state == GameState.LOGGED_IN and s.position ~= nil then
		return true
	end
	if Read.scene_loading(s) then
		sleep(100)
		return false
	end
	return Game.sign_in()
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Total" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
	Antiban.add_task(AntibanTasks.handle_randoms, 30 * SECOND, 0.33)
	Antiban.add_task(AntibanTasks.adjust_camera, 3 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.lose_focus, 10 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.adjust_minimap_zoom, 13 * MINUTE, 0.33)

	Antiban.add_walk_task(AntibanTasks.adjust_camera, 2 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_chat_tab, 3 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.small_camera_rotation, 4 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_right_click, 5 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_tab, 6 * MINUTE, 0.33)

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_pitch_change, 45 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_zoom_change, 60 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_camera_rotation, 70 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_npc, 90 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_player, 120 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.random_tab, 90 * SECOND, 0.4, "game")

	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_tab, 70 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_chat_tab, 80 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_random_ground_item, 120 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.ask(): boolean
	local fields: { Host.FormField } = {
		{ id = "inventory", kind = "inventory", label = "Inventory", row = "inventory" },
		{
			id = "restore",
			kind = "choice",
			label = "Restore method:",
			options = CONST.RESTORE_METHODS,
			default = CONFIG.restore,
			row = "inventory",
		},
		{ id = "melee", kind = "check", label = "Melee", default = CONFIG.melee },
		{ kind = "label", text = "Melee is not supported yet!", visible_when = { id = "melee", equals = true } },
		{ kind = "label", text = "" },
		{
			id = "min_food",
			kind = "number",
			label = "Min food",
			box_first = true,
			default = CONFIG.min_food,
			min = 0,
			max = 28,
			integer = true,
		},
		{
			id = "min_prayer_doses",
			kind = "number",
			label = "Min prayer doses",
			box_first = true,
			default = CONFIG.min_prayer_doses,
			min = 0,
			max = 112,
			integer = true,
		},
		{
			id = "min_cure_doses",
			kind = "number",
			label = "Min cure doses",
			box_first = true,
			default = CONFIG.min_cure_doses,
			min = 0,
			max = 112,
			integer = true,
		},
		{
			id = "eat_min",
			kind = "number",
			label = "Eat from HP",
			box_first = true,
			default = CONFIG.eat_min,
			min = 1,
			max = 99,
			integer = true,
		},
		{
			id = "eat_max",
			kind = "number",
			label = "Eat up to HP",
			box_first = true,
			default = CONFIG.eat_max,
			min = 1,
			max = 99,
			integer = true,
		},
		{
			id = "stay_below",
			kind = "number",
			label = "Never escape under Zulrah HP",
			box_first = true,
			default = CONFIG.stay_below,
			min = 0,
			max = 500,
			integer = true,
		},
		{ kind = "label", text = "" },
	}
	fields[#fields + 1] = { kind = "label", text = "Forms", heading = 1 }
	for _, transformation in CONST.TRANSFORMATIONS do
		fields[#fields + 1] = { kind = "label", text = transformation.name, heading = 2 }
		fields[#fields + 1] = {
			id = `{transformation.key}_equipment`,
			kind = "equipment",
			label = "Equipment",
			row = transformation.key,
		}
		fields[#fields + 1] = {
			id = `{transformation.key}_prayers`,
			kind = "prayer",
			label = "Prayers",
			locked = CONST.OVERHEADS,
			row = transformation.key,
		}
	end
	fields[#fields + 1] = { kind = "label", text = "" }
	fields[#fields + 1] = { kind = "label", text = "Special attacks", heading = 1 }
	fields[#fields + 1] = { id = "special_equipment", kind = "equipment", label = "Equipment", row = "special" }
	fields[#fields + 1] = {
		id = "special_prayers",
		kind = "prayer",
		label = "Prayers",
		locked = CONST.OVERHEADS,
		row = "special",
	}
	for _, transformation in CONST.TRANSFORMATIONS do
		fields[#fields + 1] = {
			id = `{transformation.key}_special`,
			kind = "check",
			label = `Use on {transformation.label}`,
			default = CONFIG.special.on[transformation.key],
		}
	end
	for _, field in fields do
		if field.kind ~= "label" and field.id ~= "melee" then
			field.disabled_by = "melee"
		end
	end
	local values = Host.form({ title = NAME, submit = "Start", fields = fields })
	if values == nil then
		return false
	end
	Game.apply_settings(values)
	return true
end

function Game.apply_settings(values: { [string]: any })
	CONFIG.inventory = values.inventory or SAVED_LAYOUTS.inventory
	CONFIG.restore = values.restore or CONFIG.restore
	CONFIG.melee = values.melee == true
	fight = if CONFIG.melee then MELEE_FIGHT else RANGED_FIGHT
	CONFIG.min_food = values.min_food or CONFIG.min_food
	CONFIG.min_prayer_doses = values.min_prayer_doses or CONFIG.min_prayer_doses
	CONFIG.min_cure_doses = values.min_cure_doses or CONFIG.min_cure_doses
	CONFIG.eat_min = values.eat_min or CONFIG.eat_min
	CONFIG.eat_max = values.eat_max or CONFIG.eat_max
	CONFIG.stay_below = values.stay_below or CONFIG.stay_below
	S.eat_at = eat_level()
	CONFIG.special.equipment = values.special_equipment
	local special_chosen = values.special_prayers
	for _, transformation in CONST.TRANSFORMATIONS do
		CONFIG.special.on[transformation.key] = values[`{transformation.key}_special`] == true
		local saved = SAVED_LAYOUTS.transformations[transformation.key]
		local chosen = values[`{transformation.key}_prayers`] or saved.prayers
		CONFIG.transformations[transformation.key] = {
			equipment = values[`{transformation.key}_equipment`] or saved.equipment,
			prayers = Read.with_protection(chosen, transformation.protection),
			snakeling_prayers = if transformation.snakeling_protection
				then Read.with_protection(chosen, transformation.snakeling_protection)
				else nil,
			special_prayers = if special_chosen
				then Read.with_protection(special_chosen, transformation.protection)
				else nil,
			special_snakeling_prayers = if special_chosen and transformation.snakeling_protection
				then Read.with_protection(special_chosen, transformation.snakeling_protection)
				else nil,
		}
	end
	CONFIG.venom_proof = Read.venom_proof(Read.equipment_layouts(), CONFIG.special.equipment, CONFIG.special.on)
end

function Read.equipment_layouts(): { [string]: EquipmentLayout.Layout? }
	local equipment = {}
	for key, layouts in CONFIG.transformations do
		equipment[key] = layouts.equipment
	end
	return equipment
end

function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	local equipment, special_on = {}, {}
	for _, t in CONST.TRANSFORMATIONS do
		equipment[t.key] = values[`{t.key}_equipment`] or SAVED_LAYOUTS.transformations[t.key].equipment
		special_on[t.key] = values[`{t.key}_special`] == true
	end
	local problems = Read.settings_problems(
		values.inventory or SAVED_LAYOUTS.inventory,
		values.min_food or CONFIG.min_food,
		values.min_cure_doses or CONFIG.min_cure_doses,
		Read.venom_proof(equipment, values.special_equipment, special_on),
		equipment[CONST.TRANSFORMATIONS[1].key],
		values.eat_min or CONFIG.eat_min,
		values.eat_max or CONFIG.eat_max,
		values.melee == true,
		equipment,
		values.special_equipment
	)
	if #problems > 0 then
		Log.warn(NAME, `Settings not updated: {table.concat(problems, "; ")}`)
		return
	end
	Game.apply_settings(values)
	Log.log(NAME, "Settings updated")
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	local problems = Read.settings_problems(
		CONFIG.inventory,
		CONFIG.min_food,
		CONFIG.min_cure_doses,
		CONFIG.venom_proof,
		CONFIG.transformations[CONST.TRANSFORMATIONS[1].key].equipment,
		CONFIG.eat_min,
		CONFIG.eat_max,
		CONFIG.melee,
		Read.equipment_layouts(),
		CONFIG.special.equipment
	)
	if #problems > 0 then
		local message = `Can't start: {table.concat(problems, "; ")}`
		Log.warn(NAME, message)
		error(message, 0)
	end

	PrayerLayout.is_active({ name = "", prayers = {} })

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

function Loop.report_counters()
	local key = `{stats.runs}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "runs", label = "Runs", value = stats.runs },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "runs" },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_runs > 0 and stats.runs >= CONFIG.max_runs and not S.in_arena then
		Log.log(NAME, `Reached {CONFIG.max_runs} runs, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.finished = true
	end
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	S.last_progress_at += time() - S.antiban_began_at
end

function Loop.hook_antiban_timeouts()
	Antiban.on_start_task, Antiban.on_finish_task = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.antiban_began, Loop.antiban_ended
end

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()
	Read.track_poison()

	local area = Read.area()
	if area == "ZULRAH" and not S.in_arena then
		S.zulrah_alive = Read.teleport() == nil
		phases = new_phases()
		stand(string.split(CONST.ROTATIONS[1].phases[1], " ")[3])
		S.attack_phase, S.moving_to, S.cloud_dodge, S.whip_dodge = -1, nil, nil, nil
		S.walked, S.hovered_rising = false, -1
		S.last_shot_cycle, S.last_shot_at, S.walk_attack, S.cloud_wait_logged = -math.huge, 0, nil, nil
		S.clouds, S.arena_grid, S.no_room = {}, nil, {}
		S.zulrah_hp, S.staying = nil, false
		S.zulrah_attacks, S.last_attack_cycle, S.last_throw_cycle, S.last_spawn_cycle = 0, -1, -math.huge, -math.huge
	end
	S.in_arena = area == "ZULRAH"
	if not S.in_arena then
		S.escaping = false
	end
	if S.in_arena then
		area = Read.fight_state()
	end
	if skipped[area] then
		return "LOADING"
	end
	return area
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	ZULRAH = function()
		local npc, t = Read.zulrah()
		if npc and S.walked and not S.hovered_on_walk and Player.in_transit() and not Read.unattackable(npc) then
			S.hovered_on_walk = true
			Npcs.hover_async(npc)
			return
		end
		if npc and CONST.RISING_ANIMATIONS[npc.animation] and S.hovered_rising ~= phases.phase then
			S.hovered_rising = phases.phase
			Npcs.hover_async(npc)
			return
		end
		local dodge = phases.target and CONST.DODGES[phases.target]
		if
			npc
			and t
			and t.key == "magma"
			and dodge
			and S.attack_phase == phases.phase
			and S.hovered_dodge ~= `{phases.phase}:{dodge}`
			and not Player.in_transit()
		then
			S.hovered_dodge = `{phases.phase}:{dodge}`
			Walker.hover_tile_async(Read.world_tile(CONST.TILES[dodge]))
		end
	end,
	ATTACK = function()
		local npc = Read.zulrah()
		if npc == nil then
			return
		end
		local walking = Player.in_transit()
		if Handler.attack(npc) then
			S.attack_phase, S.walked = phases.phase, false
			fight.attacked()
			if walking then
				S.walk_attack = { at = time(), shot = S.last_shot_cycle }
			end
			return
		end
		local now = Npcs.refresh(npc)
		if now and Read.unattackable(now) then
			return
		end
		if Read.wants_move() then
			Handler.states.MOVE()
			return
		end
		Log.log(NAME, "Couldn't click Attack on Zulrah")
		S.skip["ATTACK"] = true
	end,
	INVENTORY = function()
		if not SidePanels.open(SidePanels.INVENTORY) then
			S.skip["INVENTORY"] = true
		end
	end,
	EAT = function()
		local food = Read.pick("food")
		local combo = if S.zulrah_alive and food then Read.combo_food(food) else nil
		if Handler.consume(food, "food", "EAT") then
			S.eat_at = eat_level()
			if combo then
				Handler.consume(combo, "food", "EAT")
			end
		end
	end,
	PRAYER_POTION = function()
		if Handler.consume(Read.pick("restore"), "restore", "PRAYER_POTION") then
			S.restore_at = Random.int(CONST.RESTORE_AT[1], CONST.RESTORE_AT[2])
		end
	end,
	ANTIVENOM = function()
		Handler.consume(Read.held("antivenom")[1], "cure", "ANTIVENOM")
	end,
	ANTIPOISON = function()
		Handler.consume(Read.held("antipoison")[1], "cure", "ANTIPOISON")
	end,
	BOOST = function()
		Handler.consume(Read.boost(), "boost", "BOOST")
	end,
	MOVE = function()
		local tile, name = Read.goal()
		if tile == nil or name == nil then
			return
		end
		local goal = Read.world_tile(tile)
		local world = Read.walk_via(goal)
		local via = if world.x ~= goal.x or world.y ~= goal.y then world else nil
		if via then
			Log.log(NAME, `Walking round a cloud: by {via.x},{via.y} to the {tile_label(name)} tile`)
		end
		local by_minimap = false
		Camera.face_enabled = false
		local pace = Mouse.pace
		if Read.in_jad_phase() and not phases.diving then
			Mouse.pace = pace * CONST.JAD_MOVE_MOUSE_PACE
		end
		local clicked = Walker.click_tile(world)
		Camera.face_enabled = true
		if not clicked and Walker.on_minimap(world) then
			by_minimap = true
			clicked = Walker.click_minimap(world)
		end
		local me = Player.position()
		if not clicked and me and Walker.distance(me, world) <= Walker.SCREEN_REACH and Camera.face(world, true) then
			Log.log(NAME, `Turned the camera to the {tile_label(name)} tile`)
			clicked = Walker.click_tile(world)
		end
		Mouse.pace = pace
		if clicked then
			local function arrived(): boolean
				local pos = Player.position()
				return pos ~= nil and pos.x == world.x and pos.y == world.y
			end
			local started, dest = time(), Player.destination()
			while dest == nil and not arrived() and time() - started < CONST.TICK_MS do
				sleep(30)
				dest = Player.destination()
			end
			if dest == nil and not arrived() then
				Log.log(NAME, `The click on the {tile_label(name)} tile didn't start a walk`)
			elseif dest and (dest.x ~= world.x or dest.y ~= world.y) then
				Log.log(
					NAME,
					`Walking to {dest.x},{dest.y}, not the {tile_label(name)} tile at {world.x},{world.y} (clicked on the {if by_minimap
						then "minimap"
						else "game view"})`
				)
			end
			S.moving_to, S.moving_via, S.attack_phase, S.walked = name, via, -1, true
			local npc = Read.zulrah()
			S.hovered_on_walk = npc ~= nil and not Read.unattackable(npc) and Npcs.hover_async(npc)
		else
			Log.log(NAME, `Couldn't click the {tile_label(name)} tile`)
			S.skip["MOVE"] = true
		end
	end,
	SERPENTINE_PRAYER = function()
		Handler.fix_prayers("SERPENTINE_PRAYER")
	end,
	SERPENTINE_GEAR = function()
		Handler.fix_gear("SERPENTINE_GEAR")
	end,
	SPECIAL = function()
		if not SpecialAttack.enable() then
			Log.log(NAME, "Couldn't switch the special attack on: trying again later")
			S.special_failed_at = time()
		end
	end,
	MAGMA_PRAYER = function()
		Handler.fix_prayers("MAGMA_PRAYER")
	end,
	MAGMA_GEAR = function()
		Handler.fix_gear("MAGMA_GEAR")
	end,
	TANZANITE_PRAYER = function()
		Handler.fix_prayers("TANZANITE_PRAYER")
	end,
	CAMERA = function()
		S.camera_at = time()
		local goal, pos = S.camera_goal, snap.state.position
		local facing = Camera.yaw_degrees()
		if goal == nil or pos == nil or facing == nil then
			return
		end
		local bearing = math.deg(math.atan2(goal.x - pos.local_x, goal.y - pos.local_y))
		local ahead = (bearing - facing + 180) % 360 - 180
		local pitch = Camera.PITCH_MAX - Random.int(0, Camera.FACE_PITCH_SLACK)
		if math.abs(ahead) > CONST.CAMERA_AHEAD_DEG or (Camera.pitch() or 0) < pitch - Camera.tolerance then
			local yaw = bearing + Random.float(-CONST.CAMERA_AHEAD_DEG, CONST.CAMERA_AHEAD_DEG) / 2
			Camera.set_angles(Camera.degrees_to_yaw(yaw), pitch)
			S.camera_at = 0
			local shown = Read.camera_goal(fighting and Read.zulrah()) == nil
			S.camera_at = time()
			Log.log(
				NAME,
				`Camera: turned {math.round(ahead)} degrees (from {math.round(facing)} to {math.round(
					Camera.yaw_degrees() or -1
				)}, bearing {math.round(bearing)}); {if shown then "in view" else "still not in view"}`
			)
			return
		end
		local zoom = Camera.zoom()
		if zoom and zoom > Camera.ZOOM_MIN + Camera.zoom_tolerance then
			Log.log(NAME, "Camera: zooming out to keep Zulrah in view")
			Camera.set_zoom(math.max(Camera.ZOOM_MIN, zoom - CONST.CAMERA_ZOOM_STEPS * Camera.ZOOM_STEP))
		end
	end,
	RUN = function()
		if not Minimap.set_run(true) then
			Log.log(NAME, "Couldn't turn run on")
			S.skip["RUN"] = true
		end
	end,
	JAD_PRAYER = function()
		local protection = jad_protection
		if protection and not Prayer.activate(protection) then
			Log.log(NAME, `Couldn't switch to {protection} for the Jad phase`)
		end
	end,
	TANZANITE_GEAR = function()
		Handler.fix_gear("TANZANITE_GEAR")
	end,
	LOOT = function()
		local item = Read.next_loot()
		if item == nil then
			return
		end
		local tile = { x = item.x, y = item.y }
		if Read.pile_fits(tile) then
			local taken, why = GroundItems.take_pile(tile)
			if why == "failed" then
				Log.log(NAME, `Couldn't take the pile at {tile.x},{tile.y} ({taken} taken)`)
				S.skip["LOOT"] = true
			end
			return
		end
		if not GroundItems.interact(item, "Take") then
			Log.log(NAME, `Couldn't take the {item.name or item.id}`)
			S.skip["LOOT"] = true
			return
		end
		local started = time()
		while GroundItems.refresh(item) ~= nil and time() - started < CONST.LOOT_WAIT_MS do
			sleep(100)
		end
	end,
	EAT_FOR_SPACE = function()
		local item = Read.next_loot()
		if item == nil then
			return
		end
		local food = Read.pick("food")
		if food == nil then
			Log.log(NAME, `No room for the {item.name or item.id} and no food to eat for it: leaving it`)
			S.no_room[item.id] = true
			return
		end
		local free = Inventory.free_slots() or 0
		if Handler.consume(food, "food", "EAT_FOR_SPACE") then
			local started = time()
			while (Inventory.free_slots() or 0) <= free and time() - started < CONST.CONSUME_MS do
				sleep(50)
			end
		end
	end,
	LEAVE = function()
		local scroll = Read.teleport()
		if scroll == nil or not Objects.interact(scroll, CONST.TELEPORT_OPTION) then
			Log.log(NAME, "Couldn't read the teleport scroll")
			S.skip["LEAVE"] = true
			return
		end
		if not ChatOptions.wait_title(CONST.LEAVE_QUESTION, CONST.QUESTION_WAIT_MS) then
			Log.log(NAME, "The teleport scroll didn't ask to leave")
		end
	end,
	CONFIRM_LEAVE = function()
		Random.sleep(CONST.ANSWER_REACTION_MS[1], CONST.ANSWER_REACTION_MS[2])
		local answered = ChatOptions.select(CONST.LEAVE_ANSWER)
		local started = time()
		while Player.in_instance() and time() - started < CONST.TELEPORT_WAIT_MS do
			if time() - started > CONST.ANSWER_TAKES_MS and ChatOptions.is_title(CONST.LEAVE_QUESTION) then
				break
			end
			sleep(100)
		end
		if Player.in_instance() then
			Log.log(
				NAME,
				`Couldn't answer "{CONST.LEAVE_ANSWER}" to the teleport scroll{if answered then " (still here)" else ""}`
			)
			S.skip["CONFIRM_LEAVE"] = true
		end
	end,
	PRAYERS_OFF = function()
		if not PrayerLayout.deactivate() then
			Log.log(NAME, "Couldn't turn the prayers off")
			S.skip["PRAYERS_OFF"] = true
		end
	end,
	THRALL = function()
		local kind = CONST.THRALLS[if Biometrics.random_boolean(0.5) then 1 else 2] :: Magic.Thrall
		if Magic.summon_thrall(kind) then
			S.thrall_early = nil
			Log.log(NAME, `Summoned a {string.lower(kind)} thrall`)
		else
			S.thrall_retry_at = time() + CONST.THRALL_RETRY_MS
		end
	end,
	RECOVER_GEAR = function()
		if ItemRetrieval.is_open() then
			local kept = ItemRetrieval.count() or 0
			if kept == 0 then
				Log.log(NAME, `{CONST.PRIESTESS} keeps nothing more`)
				ItemRetrieval.close()
				return
			end
			Log.log(NAME, `Taking {kept} stacks (worth about {ItemRetrieval.value() or "?"}) from {CONST.PRIESTESS}`)
			if not ItemRetrieval.take_all() then
				Log.log(NAME, "Take-All took nothing")
				S.skip["RECOVER_GEAR"] = true
				return
			end
			local left = ItemRetrieval.count() or 0
			if left == 0 then
				Log.log(NAME, `Took everything back from {CONST.PRIESTESS}`)
				priestess_keeps = false
			elseif Inventory.is_full() then
				Log.log(NAME, `{left} stacks left with {CONST.PRIESTESS}: no room for them`)
				ItemRetrieval.close()
			end
			return
		end
		Handler.antiban("RECOVER_GEAR")
		local priestess = Npcs.nearest(CONST.PRIESTESS_ID, assert(Walker.position()))
		if priestess == nil then
			if not Walker.walk(CONST.PRIESTESS_TILE) then
				Log.log(NAME, `Couldn't walk to {CONST.PRIESTESS}`)
				S.skip["RECOVER_GEAR"] = true
			end
			return
		end
		if not Npcs.interact(priestess, "Collect") then
			Log.log(NAME, `Couldn't click Collect on {CONST.PRIESTESS}`)
			S.skip["RECOVER_GEAR"] = true
			return
		end
		if not ItemRetrieval.wait_open() then
			Log.log(NAME, `{CONST.PRIESTESS} keeps nothing`)
			priestess_keeps = false
		end
	end,
	BOARD_BOAT = function()
		Handler.antiban("BOARD_BOAT")
		local boat = Objects.nearest(CONST.BOAT, assert(Walker.position()))
		if boat == nil or not Objects.approach(boat, "Board") then
			Log.log(NAME, `Couldn't board the {CONST.BOAT}`)
			S.skip["BOARD_BOAT"] = true
			return
		end
		if not ChatOptions.wait_title(CONST.BOARD_QUESTION, CONST.QUESTION_WAIT_MS) then
			Log.log(NAME, "The boat didn't ask to go to the shrine")
		end
	end,
	CONFIRM_BOAT = function()
		Random.sleep(CONST.ANSWER_REACTION_MS[1], CONST.ANSWER_REACTION_MS[2])
		local answered = ChatOptions.select(CONST.BOARD_ANSWER)
		local started = time()
		while not Player.in_instance() and time() - started < CONST.BOARD_WAIT_MS do
			if time() - started > CONST.ANSWER_TAKES_MS and ChatOptions.is_title(CONST.BOARD_QUESTION) then
				break
			end
			sleep(100)
		end
		if not Player.in_instance() then
			Log.log(NAME, `Couldn't answer "{CONST.BOARD_ANSWER}" to the boat{if answered then " (no arena)" else ""}`)
			S.skip["CONFIRM_BOAT"] = true
		end
	end,
	PREPARE_GEAR = function()
		if Bankmain.is_open() and not Bankmain.close() then
			S.skip["PREPARE_GEAR"] = true
			return
		end
		local t = CONST.TRANSFORMATIONS[1]
		local layout = CONFIG.transformations[t.key].equipment
		if layout and not EquipmentLayout.equip(layout) then
			Log.log(NAME, `Couldn't put on the {t.label} gear ({layout.name})`)
			S.skip["PREPARE_GEAR"] = true
		end
	end,
	TELEPORT_HOUSE = function()
		local tablet = Inventory.find(CONST.HOUSE_TABLET)
		local outside = Varbits.get(CONST.HOUSE_OUTSIDE_VARBIT) == 1
		local tablets = Inventory.count_ex(CONST.HOUSE_TABLET) or 0
		local ok = if tablet
			then Inventory.interact_slot(tablet, CONST.HOUSE_TABLET_OPTION)
			else Magic.cast(CONST.HOUSE_SPELL, if outside then "Inside" else nil)
		if not ok then
			Log.log(NAME, "Couldn't teleport to the house: no tablet held, or the spell can't be cast")
			S.skip["TELEPORT_HOUSE"] = true
			return
		end
		if tablet then
			local clicked_at = time()
			while
				(Inventory.count_ex(CONST.HOUSE_TABLET) or 0) >= tablets
				and time() - clicked_at < CONST.TELEPORT_START_MS
			do
				sleep(100)
			end
			if (Inventory.count_ex(CONST.HOUSE_TABLET) or 0) >= tablets then
				Log.log(NAME, "The house tablet didn't break: trying again")
				S.skip["TELEPORT_HOUSE"] = true
				return
			end
		end
		Log.log(
			NAME,
			`Teleporting to the house to restock ({Read.uses("food")} food, {Read.uses("restore")} prayer and {Read.cure_doses()} cure doses left)`
		)
		local started = time()
		while not House.inside() and time() - started < CONST.TELEPORT_WAIT_MS do
			sleep(200)
		end
		if not House.inside() then
			Log.log(NAME, `The house teleport didn't take us there in {CONST.TELEPORT_WAIT_MS // 1000} s`)
		end
	end,
	TELEPORT_FEROX = function()
		Log.log(NAME, `Teleporting to the {CONST.FEROX} to restock`)
		local landed, pointless = Transports.teleport_item(CONST.DUELING_FEROX)
		if landed then
			return
		end
		if pointless then
			local message =
				`Couldn't teleport to the {CONST.FEROX}: bring a ring of dueling, or pick another restore method`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, `The ring of dueling didn't take us to the {CONST.FEROX}`)
		S.skip["TELEPORT_FEROX"] = true
	end,
	FEROX = function()
		local restored, why = Ferox.restore()
		if not restored then
			Log.log(NAME, `Couldn't restore at the {CONST.FEROX} pool: {why}`)
			S.skip["FEROX"] = true
		end
	end,
	HOUSE = function()
		House.survey()
		if House.furniture("pool") == CONST.ORNATE_POOL then
			if Read.wants_pool() then
				local restored, why = House.restore()
				if not restored then
					Log.log(NAME, `Couldn't restore at the pool: {why}`)
					S.skip["HOUSE"] = true
				end
				return
			end
			Handler.go_to_bank("HOUSE")
			return
		end
		if not table.find(House.offers(CONST.FEROX), "box") then
			local message =
				`No {CONST.ORNATE_POOL} or jewellery box in this house: use a ring of dueling to teleport to the {CONST.FEROX} instead`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, `Teleporting to the {CONST.FEROX} with the jewellery box`)
		local left, why = House.teleport(CONST.FEROX)
		if not left then
			Log.log(NAME, `Couldn't teleport to the {CONST.FEROX}: {why}`)
			S.skip["HOUSE"] = true
		end
	end,
	BANKING = function()
		local layout = CONFIG.inventory
		if layout == nil then
			local message = "No inventory layout to restock: pick one in the script's settings"
			Log.warn(NAME, message)
			error(message, 0)
		end
		if InventoryLayout.matches(layout) then
			if Bankmain.is_open() and not Bankmain.close() then
				S.skip["BANKING"] = true
				return
			end
			if not InventoryLayout.reorder(layout) then
				Log.log(NAME, `Couldn't put the inventory in the order of the {layout.name} layout`)
			end
			Log.log(NAME, "Restocked")
			return
		end
		if not Bankmain.is_open() and Bankmain.nearest() == nil then
			Handler.go_to_bank("BANKING")
			return
		end
		if not Bankmain.is_open() then
			Handler.antiban("BANKING")
			if not Bankmain.open() then
				Handler.restock_failed("Couldn't open a bank")
				return
			end
		end
		local gear = Read.gear_short() or Read.first_gear_off()
		local done = if gear then EquipmentLayout.withdraw(gear) else InventoryLayout.withdraw(layout)
		if done then
			S.restock_failures = 0
			return
		end
		if gear and not priestess_checked and #EquipmentLayout.missing(gear) > 0 then
			priestess_checked, priestess_keeps = true, true
			Log.log(NAME, `The bank is short of the {gear.name} gear: going to see if {CONST.PRIESTESS} keeps it`)
			return
		end
		Handler.restock_failed(`Couldn't restock the {layout.name} layout: is the bank out of something?`)
	end,
	DEATH_BANK = function()
		if not Bankmain.is_open() and Bankmain.nearest() == nil then
			Handler.go_to_bank("DEATH_BANK")
			return
		end
		if not Bankmain.is_open() then
			Handler.antiban("DEATH_BANK")
			if not Bankmain.open() then
				Handler.restock_failed("Couldn't open a bank")
				return
			end
		end
		S.restock_failures = 0
		if
			(Inventory.quantity(CONST.ZULANDRA_TELEPORT) or 0) < 1 and not Bankmain.withdraw(CONST.ZULANDRA_TELEPORT, 1)
		then
			S.scroll_missing = true
			Log.log(NAME, "No Zul-andra teleport in the bank: walking back to the priestess")
		else
			Log.log(NAME, "Took a teleport scroll for the walk back to the priestess")
		end
		Bankmain.close()
	end,
	TRAVEL_ZULANDRA = function()
		Log.log(NAME, "Travelling to Zul-Andra")
		local ok, walked = pcall(Walker.walk, CONST.PRIESTESS_TILE)
		if not ok then
			local message = `Couldn't find a way to Zul-Andra: {walked}`
			Log.warn(NAME, message)
			error(message, 0)
		end
		if not walked then
			Log.log(NAME, "The walk to Zul-Andra stopped before getting there")
			S.skip["TRAVEL_ZULANDRA"] = true
		end
	end,
}

function Handler.consume(supply: Supply?, key: string, state: State): boolean
	if supply and Inventory.interact_slot(supply.slot, supply.option) then
		S.used_at[key] = time()
		Log.log(NAME, `{supply.option}: {supply.name}`)
		return true
	end
	Log.log(NAME, `Couldn't use the {key}`)
	S.skip[state] = true
	return false
end

function Handler.attack(npc: Host.Npc): boolean
	local aim = Clickbox.walking(function()
		local now = Npcs.refresh(npc)
		if now == nil or Read.unattackable(now) or (Read.note_whip(now) and not Read.whip_safe()) then
			return nil
		end
		return Npcs.clickbox(npc)
	end, function()
		local now = Npcs.refresh(npc)
		return if now then { x = now.local_x, y = now.local_y } else nil
	end, npc.name)
	return Clickbox.interact(
		aim,
		function(): boolean
			return Npcs.hovered(npc)
		end,
		npc.name,
		"Attack",
		function(entry: Host.MenuEntry): boolean
			return Npcs.owns(npc, entry)
		end,
		function(): Host.Tile?
			local now = Npcs.refresh(npc)
			return if now then { x = now.x, y = now.y } else nil
		end,
		false
	)
end

function Handler.fix_prayers(state: State)
	local t = fighting
	local layout = t and Read.prayers(t)
	if t == nil or layout == nil then
		return
	end
	if not PrayerLayout.activate(layout) then
		Log.log(NAME, `Couldn't switch to the {t.label} prayers ({layout.name})`)
		S.skip[state] = true
	end
end

function Handler.fix_gear(state: State)
	local t = fighting
	local layout = t and Read.gear_for(t)
	if t == nil or layout == nil then
		return
	end
	local function whipped(): boolean
		local npc = Read.zulrah()
		return npc ~= nil and Read.note_whip(npc) and not Read.whip_safe()
	end
	local function toward_zulrah()
		local npc = Read.zulrah()
		if npc then
			Npcs.hover_async(npc)
		end
	end
	if not EquipmentLayout.equip(layout, { stop = whipped, after_clicks = toward_zulrah }) then
		if S.whip_anim ~= nil and not Read.whip_safe() then
			return
		end
		Log.log(NAME, `Couldn't switch to the {t.label} gear ({layout.name})`)
		S.skip[state] = true
	end
end

function Handler.go_to_bank(state: State)
	local bank = Read.fastest_bank()
	if bank == nil then
		Log.log(NAME, "The planner found no way to a bank from here: stopping the script")
		S.finished = true
		return
	end
	Log.log(NAME, `Going to the {bank.name} bank, the fastest from here (about {bank.ticks} ticks)`)
	if not Walker.walk({ x = bank.x, y = bank.y, plane = bank.plane }) then
		Log.log(NAME, `Couldn't get to the {bank.name} bank`)
		S.skip[state] = true
	end
end

function Handler.restock_failed(why: string)
	S.restock_failures += 1
	if S.restock_failures >= CONST.RESTOCK_ATTEMPTS then
		local message = `{why} ({S.restock_failures} times in a row)`
		Log.warn(NAME, message)
		error(message, 0)
	end
	Log.log(NAME, `{why}; trying again`)
	S.skip["BANKING"] = true
end

function Handler.antiban(state: State)
	if CONFIG.antiban and S.antiban_ready and not Antiban.do_antiban() then
		S.skip[state] = true
	end
end
local last_stray_at = 0
local function close_stray(state: State)
	if state == "LOADING" or not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	if
		(state == "BANKING" or state == "DEATH_BANK")
		and (Toplevel.is_open(Bankmain.GROUP) or Toplevel.is_open(BankpinKeypad.GROUP))
	then
		return
	end
	if state == "RECOVER_GEAR" then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	local last_state: State? = nil
	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		if state ~= last_state and state ~= "LOADING" then
			Log.log(NAME, `State: {state}`)
			last_state = state
		end
		close_stray(state)
		Game.poll_settings()
		if state ~= "ZULRAH" and state ~= "MOVE" then
			S.hovered_on_walk = false
		end
		local ok, err = pcall(Handler.states[state])
		Read.track_world_click()
		if not ok then
			if S.in_arena then
				Log.warn(NAME, `The {state} state failed in the arena ({err}): teleporting out before stopping`)
				pcall(Handler.states[Read.restore_state()])
			end
			error(err, 0)
		end

		if CONFIG.antiban and S.antiban_ready and not S.in_arena and not Toplevel.is_open(Bankmain.GROUP) then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
