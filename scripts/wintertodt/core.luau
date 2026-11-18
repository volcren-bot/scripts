--!strict
local Host = require("@lib/host")
export type ClientState = Host.ClientState
export type Tile = Host.Tile
export type Loc = Host.Loc
export type Npc = Host.Npc
local Item = require("@lib/utils/item")
local Random = require("@lib/utils/math/random")
local StatsReport = require("@lib/utils/stats_report")
local Ticks = require("@lib/utils/ticks")

local NAME = "Wintertodt"
local TICK = Ticks.MS

export type Mode = "group" | "solo"
export type Side = "west" | "east"
export type Corner = "sw" | "se" | "nw" | "ne"
export type SoloGoal = "points" | "xp"
export type Danger = { x: number, y: number, radius: number }
export type BrazierState = "UNLIT" | "LIT" | "BROKEN" | "DEAD"
export type Tool = "axe" | "tinderbox" | "knife" | "hammer"

export type SideSpots = {
	brazier: Tile,
	stand: { Tile },
	root: Tile,
	root_stand: Tile,
	pyromancer: Tile,
	break_z: number,
}

local function line(x1: number, y1: number, x2: number, y2: number): { Tile }
	local tiles: { Tile } = {}
	for x = math.min(x1, x2), math.max(x1, x2) do
		for y = math.min(y1, y2), math.max(y1, y2) do
			table.insert(tiles, { x = x, y = y })
		end
	end
	return tiles
end

local function joined(a: { Tile }, b: { Tile }): { Tile }
	local out = table.clone(a)
	table.move(b, 1, #b, #out + 1, out)
	return out
end

local WEST: SideSpots = {
	brazier = { x = 1621, y = 3998 },
	stand = joined(line(1619, 3997, 1619, 3999), line(1620, 3996, 1622, 3996)),
	root = { x = 1620, y = 3988 },
	root_stand = { x = 1622, y = 3988 },
	pyromancer = { x = 1619, y = 3996 },
	break_z = -2246,
}

local EAST: SideSpots = {
	brazier = { x = 1639, y = 3998 },
	stand = joined(line(1641, 3997, 1641, 3999), line(1638, 3996, 1640, 3996)),
	root = { x = 1639, y = 3988 },
	root_stand = { x = 1638, y = 3988 },
	pyromancer = { x = 1641, y = 3996 },
	break_z = -2246,
}

local CONST = {
	HUD = { GROUP = 396, POINTS = 6, WARMTH = 20, ENERGY = 26 },
	BRAZIER_STATES = { [29312] = "UNLIT", [29313] = "BROKEN", [29314] = "LIT" } :: { [number]: BrazierState },
	SIDES = { west = WEST, east = EAST } :: { [Side]: SideSpots },
	SOLO = {
		CORNERS = {
			sw = WEST,
			se = EAST,
			nw = {
				brazier = { x = 1621, y = 4016 },
				stand = joined(line(1619, 4015, 1619, 4017), line(1620, 4018, 1622, 4018)),
				root = { x = 1621, y = 4025 },
				root_stand = { x = 1623, y = 4025 },
				pyromancer = { x = 1619, y = 4018 },
				break_z = -2238,
			},
			ne = {
				brazier = { x = 1639, y = 4016 },
				stand = joined(line(1641, 4015, 1641, 4017), line(1638, 4018, 1640, 4018)),
				root = { x = 1638, y = 4025 },
				root_stand = { x = 1637, y = 4025 },
				pyromancer = { x = 1641, y = 4018 },
				break_z = -2246,
			},
		} :: { [Corner]: SideSpots },
		ROUTE_GAP = { "se", "ne", "nw", "sw" } :: { Corner },
		ROUTE_AROUND = { "ne", "se", "sw", "nw" } :: { Corner },
		FOCUS = "sw" :: Corner,
		END_CORNERS = { "sw", "se" } :: { Corner },
		GAP = "Jump Gap 29326",
		OPEN_UNTIL = { 20, 30 },
		LOW_ENERGY = 8,
		REWARD_POINTS = 500,
		POINTS_SPREAD = 1000,
		DOSES_PER_POTION = 4,
		VISIT_MS = { 90000, 150000 },
		VIALS = {
			{ count = 10, option = "Take-10 concoctions" },
			{ count = 5, option = "Take-5 concoctions" },
			{ count = 1, option = "Take-concoction" },
		},
		SNOW = { CENTRE = 502, CORNER = 1311, LANDED_CYCLES = 15, REACH = 3, AREA = 1, BLAST = 2, Z_SLACK = 4 },
		IDLE_MS = { 600, 1800 },
		CHECK_MS = 300,
	},
	HALL = { x1 = 1627, y1 = 3979, x2 = 1633, y2 = 3985 },
	DOORS = { x = 1630, y = 3965 },
	VIAL_CRATES = { { x = 1626, y = 3982 }, { x = 1634, y = 3982 } } :: { Tile },
	SPROUTING_ROOTS = { { x = 1635, y = 3978 }, { x = 1625, y = 3978 } } :: { Tile },
	BREWMA = { x = 1635, y = 3986 },
	TOOL_CRATES = {
		axe = { x = 1626, y = 3984 },
		tinderbox = { x = 1634, y = 3984 },
		hammer = { x = 1626, y = 3980 },
		knife = { x = 1634, y = 3980 },
	} :: { [Tool]: Tile },
	TOOL_ORDER = { "axe", "tinderbox", "knife", "hammer" } :: { Tool },
	VIAL_OPTION = "Take-5 concoctions",
	FIND_RANGE = 3,
	NEAR_BRAZIER = 2,
	HOVER_RANGE = 15,
	BREWMA_RANGE = 10,
	HERBS_NEEDED = 5,
	SPACE_NEEDED = 5,
	KEEP_ITEMS = 10,
	TOOL_ATTEMPTS = 5,
	POLL_MS = 50,
	TINY_ANTIBAN_CHANCE = 0.4,
	ACTIVITY_WAITS = {
		WAIT_PICKING = true,
		WAIT_MIXING = true,
		WAIT_CUTTING = true,
		WAIT_FLETCHING = true,
		WAIT_BURNING = true,
		WAIT_BOSS = true,
		SOLO_IDLE = true,
	} :: { [string]: boolean },
	REPORT = { counters_key = "" },
}

local ITEMS = {
	ROOT = "Bruma root",
	KINDLING = "Bruma kindling",
	HERB = "Bruma herb",
	UNF = "Rejuvenation potion (unf)",
	POTION = "Rejuvenation potion (1..4)",
	POTION_1 = "Rejuvenation potion (1)",
	KNIVES = { "Knife", "Fletching knife" } :: { Item.Item },
}

local TOOL_NAMES: { [Tool]: { [string]: boolean } } = {
	axe = {},
	tinderbox = { ["tinderbox"] = true, ["bruma torch"] = true, ["bruma torch (off-hand)"] = true },
	knife = { ["knife"] = true, ["fletching knife"] = true },
	hammer = { ["hammer"] = true, ["imcando hammer"] = true, ["imcando hammer (off-hand)"] = true },
}

local Read: any = {}
local Wait: any = {}
local Task: any = {}
local Game: any = {}
local Loop: any = {}
local Solo: any = {}
local Group: any = {}
local Handler: any = {}

local CONFIG = {
	mode = "group" :: Mode,
	solo_goal = "points" :: SoloGoal,
	solo_potions = 8,
	solo_points = 5000,
	side = "west" :: Side,
	alternate = true,
	prioritize_brazier = false,
	help_pyromancers = true,
	wintertodt_worlds = true,
	stop_fletch_energy = 20,
	max_kills = 0,
	max_minutes = 0,
	max_firemaking = 0,
	timeouts = { idle_minutes = 5 },
	antiban = true,
}

local stats = { kills = 0, rewarded = 0, rewards = 0, points = 0, owed = 0 }

export type SoloRound = {
	started: boolean,
	opened: boolean,
	lit: { [Corner]: boolean },
	open_until: number,
	ending: boolean,
	end_corner: Corner,
	points_bonus: number,
	visited: { [Corner]: number },
	visit_every: number,
	checked_at: number,
	at: Corner?,
	turn_back: boolean,
}

local function new_round(): SoloRound
	return {
		started = false,
		opened = false,
		lit = {},
		open_until = Random.int(CONST.SOLO.OPEN_UNTIL[1], CONST.SOLO.OPEN_UNTIL[2]),
		ending = false,
		end_corner = CONST.SOLO.FOCUS,
		points_bonus = Random.int(0, CONST.SOLO.POINTS_SPREAD),
		visited = {},
		visit_every = Random.int(CONST.SOLO.VISIT_MS[1], CONST.SOLO.VISIT_MS[2]),
		checked_at = 0,
		at = nil,
		turn_back = false,
	}
end

export type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	started_at: number,
	last_progress_at: number,
	last_xp: number,
	current: Side,
	corner: Corner,
	round: SoloRound,
	worlds: { number }?,
	herbs_wanted: number,
	has_herblore: boolean,
	warmth: number,
	boss: number,
	min_warmth: number,
	chat_uid: number,
	round_points: number,
	stale_points: number?,
	subdued: number?,
	picking: boolean,
	mixing: boolean,
	cutting: boolean,
	fletching: boolean,
	burning: boolean,
	hovering: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	started_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	current = "west",
	corner = CONST.SOLO.FOCUS,
	round = new_round(),
	herbs_wanted = CONST.HERBS_NEEDED,
	has_herblore = false,
	warmth = 100,
	boss = 0,
	min_warmth = 50,
	chat_uid = -1,
	round_points = 0,
	picking = false,
	mixing = false,
	cutting = false,
	fletching = false,
	burning = false,
	hovering = false,
}

export type State =
	"LOADING"
	| "LOGIN"
	| "LEVEL_UP"
	| "ENTER_ROOM"
	| "DROP_ITEMS"
	| "MAKE_SPACE"
	| "GET_VIALS"
	| "PICK_HERBS"
	| "MIX_POTIONS"
	| "TALK_TO_BREWMA"
	| "SWITCH_SIDES"
	| "WARM_UP"
	| "WALK_ROOT"
	| "WALK_BRAZIER"
	| "USE_SPEC"
	| "CUT_ROOTS"
	| "FLETCH_LOGS"
	| "BURN_FUEL"
	| "HOVER_BRAZIER"
	| "FIX_BRAZIER"
	| "HELP_PYRO"
	| "WAIT_PICKING"
	| "WAIT_MIXING"
	| "WAIT_CUTTING"
	| "WAIT_FLETCHING"
	| "WAIT_BURNING"
	| "WAIT_BOSS"
	| "HOP_WORLD"
	| "DODGE"
	| "SOLO_IDLE"
	| "STOP"

local report = StatsReport.new()

return {
	NAME = NAME,
	TICK = TICK,
	CONST = CONST,
	ITEMS = ITEMS,
	TOOL_NAMES = TOOL_NAMES,
	CONFIG = CONFIG,
	stats = stats,
	S = S,
	report = report,
	new_round = new_round,
	Read = Read,
	Wait = Wait,
	Task = Task,
	Game = Game,
	Loop = Loop,
	Solo = Solo,
	Group = Group,
	Handler = Handler,
}
