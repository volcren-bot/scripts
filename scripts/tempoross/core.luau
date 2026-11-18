--!strict
local Host = require("@lib/host")
local time = Host.time
export type Npc = Host.Npc
export type Loc = Host.Loc
export type Tile = Host.Tile
export type ClientState = Host.ClientState
local Draw = require("@lib/utils/draw")
local Position = require("@lib/main/position")
local Random = require("@lib/utils/math/random")
local StatsReport = require("@lib/utils/stats_report")
local Ticks = require("@lib/utils/ticks")

local CONST = {
	SINGLE_SPOTS = { [10565] = true, [10568] = true },
	DOUBLE_SPOT = 10569,
	DOUBLE_LIFE_TICKS = 40,
	DOUBLE_LIFE_MAX_TICKS = 44,
	DOUBLE_MIN_TICKS_LEFT = 8,
	FIRE = 8643,
	STORM_CLOUD = 10580,
	LIGHTNING_STRIKE = 10581,
	INACTIVE_POOL = 10570,
	SPIRIT_POOL = 10571,

	TETHERED_VARBIT = 11895,
	UNTETHER_ANIMATION = 832,
	DOUSE_ANIMATION = 2771,
	RANDOMS_PAUSE_MS = { 800, 2600 },
	RANDOMS_RETRY_MS = 30000,
	LOBBY = 687,
	LOBBY_PLAYERS = 3,
	LOBBY_DEPARTURE = 4,

	WEST_MASTS = { [41352] = true, [40996] = true },
	EAST_MASTS = { [41353] = true, [40997] = true },

	REPORT = { counters_key = "" },

	STUN_MS = 5000,

	HOME_RADIUS = 8,

	FIRE_REACH = 0,
	CRATE_FIRE_RANGE = 5,
	CRATE_STAND_RETRY_MS = 10000,
	SPOT_COST = { single_fish_ms = 3200, double_fish_ms = 1400, tile_ms = 300, switch_ms = 600 },
	INCOMING_FIRE = -8643,
	FIRE_SPREAD = 1839,
	INCOMING_LINGER_MS = 1200,
	LANDING_MARGIN_MS = 600,
	CLOUD_STRIKE_MS = 6000,
	FIRE_GHOST_MS = 700,
	DOUSED_MS = 1200,
	CLUSTER_COLORS = {
		Draw.color(255, 0, 0),
		Draw.color(255, 140, 0),
		Draw.color(255, 255, 0),
		Draw.color(0, 255, 0),
		Draw.color(0, 255, 255),
		Draw.color(0, 120, 255),
		Draw.color(255, 0, 255),
		Draw.color(255, 150, 200),
	},
	IGNORED_CLUSTER_COLOR = Draw.color(140, 140, 140),
	FIRE_DEBUG_WIDTH = 3,
	STRIKE_REACH = 0,
	CLOUD_GROWING = 8876,
	CLOUD_CHARGING = 8877,
	CLOUD_ATTACK = 8878,
	GROWING_TICKS_MIN = 3,
	GROWING_TICKS_MAX = 8,

	POLL_MS = 50,
	START_GRACE_MS = 2 * Ticks.MS,
	IDLE_MS = {
		tether = 12000,
		cook = 3 * Ticks.MS,
		load = Ticks.MS,
	} :: { [string]: number },
	SLOW_HANDLER_MS = 1500,
	TRAIL_LENGTH = 20,
	DEFAULT_IDLE_MS = 2 * Ticks.MS,

	TARGET_NPC = 0,
	TARGET_LOC = 1,

	BLOCKED_MS = 20000,
	STRAY_MS = 600,
	PUMP_RANGE = 6,

	DOCK = { x = 3139, y = 2838 },
	BOAT_SQUARE = { x = 48, y = 44 },
	PORT_MIN_SQUARE_X = 49,

	TEMPOROSS_CHUNK_ID = Position.Chunk.new(47, 44):id(),
	TINY_ACTIVITIES = { fish = true, cook = true, load = true, attack = true } :: { [string]: boolean },

	LEAVE_WAIT_MS = 20000,
	CREW_TITLES = { "Captain", "First Mate" },

	PIER_RANGE = 4,
	PREHOVER_FISH = 2,
	PHASE_TWO_ESSENCE = 50,

	SURGE_WAIT_MS = 7000,
	CANNON_RANGE = 6,
	SURGE_CLEARANCE = 3,
	BOARD_WAIT_MS = 15000,
	BOARD_STILL_MS = 2500,
	REPAIR_STEPS = 6,
	REPAIR_WAIT_MS = 6000,

	SOLO = {
		FISH_SLOTS = 19,
		FIRST_BATCH = 17,
		SECOND_BATCH = 19,
		OPENING_ENERGY = 95,
		OPENING_FISH = 10,
		UNTETHER_SPAM_MS = 5000,
		START_CLICK_CHECK_MS = 400,
		PREHOVER_ENERGY = 8,
		PREHOVER_FISH = 4,
		PIER_HOVER_FISH = 3,
		HOVER_MIN_TILES = 4,
		WAYPOINT_RADIUS = 8,
		WAYPOINT_TRIES = 60,
		LOAD_AT_INTENSITY = 95,
		HUMIDIFY_AT_WATER = 3,
		HUMIDIFY_RETRY_MS = 10000,
		THIRD_BATCH = 19,
		STEP_OFF_COUNT_MS = 2500,
		TAKE_BUCKETS_WAIT_MS = 2400,
		DROP_MIN_TILES = 5,
		P4_LOAD_INTENSITY = 95,
		P4_DOUBLE_FREE = 8,
		P5_FISH = 2,
		P5_FISH_BY_INTENSITY = 85,
		P5_LOAD_BY_INTENSITY = 92,
		P5_ALL_FIRES_BELOW = 70,
		P5_INTENSITY_PER_S = 0.5,
		P5_FISHING_MS = 6000,
		P5_CORRIDOR = 4,
		P5_NORTH_RANGE = 8,
		P5_SHRINE_RANGE = 12,
		P5_MAX_CLUSTER = 5,
		TOP_UP_FISH = 2,
		P4_STOP_ESSENCE = 20,
		DROP_PER_STEP = 2,
		BEACH_BOX = { west = -1, east = 15, south = -4, north = 15 },
		NORTH_BOX = { west = -6, east = 15, south = -5, north = 29 },
		CLUSTER_GAP = 3,
		CLUSTER_WEIGHT = 3,
		DOUSE_SPOT_RANGE = 4,
		SHARED_SPOT_EXTRA_STEPS = 3,
		TETHER_POLL_MS = 60,
		HOVER_RAW = 2,
	},
}

local Read: any = {}
local Geo: any = {}
local Chat: any = {}
local Ship: any = {}
local Hazard: any = {}
local Route: any = {}
local Doing: any = {}
local Task: any = {}
local Game: any = {}
local Loop: any = {}
local Solo: any = {}
local Group: any = {}
local Handler: any = {}

local CONFIG = {
	world = 422,
	solo = false,
	boarding = { min_players = 14, players_variance = 0.1, min_time = 10 },
	barehand = true,
	buckets = 3,
	cook = {
		enabled = true,
		min = 5,
		max = 7,
		min_storm = 3,
	},

	load = { intensity = 60, energy = 25 },
	pier = { min_energy = 2, max_energy = 4 },
	max_games = 0,
	timeouts = { idle_minutes = 5, max_losses = 4 },
	antiban = true,
	antiban_departure = 30,
}

local Items = {
	RAW_FISH = 25564,
	COOKED_FISH = 25565,
	CRYSTAL_FISH = 25566,
	BUCKET = 1925,
	WATER = 1929,
	ROPE = 954,
	HAMMER = 2347,
	IMCANDO_HAMMER = 25644,
}

local HUD = {
	GROUP = 437,
	POINTS = 25,
	ENERGY = 35,
	ESSENCE = 45,
	INTENSITY = 55,
}

local stats = { games = 0, wins = 0, losses = 0, points = 0, permits = 0 }

export type RunState = {
	hud_cache: { [number]: number | false },
	double_first_seen: { [string]: number },
	in_game: boolean,
	hud_up: boolean,
	activity: Activity?,
	chat_uid: number,
	side: Side?,
	growing_due: { [number]: number },
	cloud_started: { [number]: number },
	last_detour: string,
	item_names_cache: { [number]: string },
	worn_cache: { number }?,
	blocked_since: { [string]: number },
	dodging_to: Tile?,
	stray_since: number?,
	energy_dir: "up" | "down",
	last_energy: number?,
	cook_fish_threshold: number,
	pier_energy: number,
	last_status: number,
	antiban_ready: boolean,
	leaving_since: number?,
	leave_by_crew: boolean,
	required_players: number,
	skip: { [State]: boolean },
	finished: boolean,
	last_progress_at: number,
	losses_in_row: number,
	last_xp: number,
	last_fish: number,
	last_cooked: number,
	antiban_began_at: number,
	was_in_game: boolean,
	played_here: boolean,
	game_started: number,
	click_continue_dialogue: boolean?,
	end_dialogue: boolean,
	pier_logged: boolean,
	randoms_retry_at: number,
	surge_logged: boolean,
	arrived: boolean,
	trail: { string },
	trail_last: Tile?,
	fires_known: { [string]: boolean },
	fire_seen: { [string]: { npc: Npc, at: number } },
	doused: { [string]: number },
	crate_stand_off_until: number,
	arrival_fade: boolean,
	start_hover: Tile?,
	fires_shown: string,
	incoming: { [string]: { tile: Tile, lands: number } },
	projectiles_seen: { [string]: boolean },
	fire_size: number?,
	preparing: boolean,
	forfeiting: boolean,
	solo: SoloRound,
}

export type Box = { min_x: number, max_x: number, min_y: number, max_y: number }

export type SoloRound = {
	opened: boolean,
	doubled: boolean,
	loading: boolean,
	loaded: number,
	last_fish: number,
	first_loaded_at: number?,
	p2_loading: boolean,
	humidify_at: number,
	left_crate_at: number,
	p3_stage: string?,
	p4_stage: string?,
	p5_stage: string?,
	p5_north: Side?,
	p5_shrine: Tile?,
	p5_box: Box?,
	p3_humidify: boolean,
	p2_clear: string?,
	p2_skip: { [string]: boolean },
	p3_buckets: Loc?,
	p3_pier: Tile?,
	p3_box: Box?,
	p2_box: Box?,
	vulnerable: boolean,
	pools: number,
	waypoint: Tile?,
	pier_hover: Tile?,
	ship_hover: Tile?,
	ship_hover_waypoint: boolean,
	hover_tried: boolean,
	faced: string?,
	fire_hover: Npc?,
}

local function new_solo_round(): SoloRound
	return {
		opened = false,
		doubled = false,
		loading = false,
		loaded = 0,
		last_fish = 0,
		first_loaded_at = nil,
		p2_loading = false,
		humidify_at = 0,
		left_crate_at = 0,
		p3_stage = nil,
		p3_humidify = false,
		p2_clear = nil,
		p2_skip = {},
		p3_buckets = nil,
		p3_pier = nil,
		p3_box = nil,
		p2_box = nil,
		vulnerable = false,
		pools = 0,
		waypoint = nil,
		pier_hover = nil,
		ship_hover = nil,
		ship_hover_waypoint = false,
		hover_tried = false,
		fire_hover = nil,
	}
end

local S: RunState = {
	hud_cache = {},
	double_first_seen = {},
	in_game = false,
	hud_up = false,
	chat_uid = -1,
	growing_due = {},
	cloud_started = {},
	last_detour = "",
	item_names_cache = {},
	blocked_since = {},
	energy_dir = "up",
	cook_fish_threshold = Random.int(CONFIG.cook.min, CONFIG.cook.max),
	pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy),
	last_status = 0,
	antiban_ready = false,
	leave_by_crew = true,
	required_players = 0,
	skip = {},
	finished = false,
	last_progress_at = time(),
	losses_in_row = 0,
	last_xp = -1,
	last_fish = 0,
	last_cooked = 0,
	antiban_began_at = 0,
	was_in_game = false,
	randoms_retry_at = 0,
	played_here = false,
	game_started = 0,
	end_dialogue = false,
	pier_logged = false,
	surge_logged = false,
	arrived = false,
	trail = {},
	trail_last = nil,
	fires_known = {},
	fire_seen = {},
	doused = {},
	crate_stand_off_until = 0,
	arrival_fade = false,
	start_hover = nil,
	fires_shown = "",
	incoming = {},
	projectiles_seen = {},
	preparing = false,
	forfeiting = false,
	solo = new_solo_round(),
}

export type Snapshot = {
	state: ClientState,
	me: Tile,
	npcs: { Npc },
	locs: { Loc }?,
	inv: { [number]: number },
	free: number,
	tick: number,
	tethered: boolean,
	busy: boolean,
	walking: boolean,
}

local snap: Snapshot = {} :: any

export type Activity = {
	kind: string,
	npc: Npc?,
	loc: Loc?,
	last_progress_ms: number,
	double: boolean,
	last_signature: string,
	last_tile: string,
}

local events = {
	wave_warning_at = nil :: number?,
	tethered = false,
	wave_hit_at = nil :: number?,
	waves_passed = 0,
	wave_hit_us = false,
	burned = false,
	game_result = nil :: string?,
	must_untether = false,
	surge_until = 0,
	fire_in_way = nil :: Npc?,
	stunned_until = 0,
}

export type Side = {
	name: string,
	mast: Loc,
	totem: Loc,
	shrine: Loc,
}

export type WayOptions = {
	avoid: boolean?,
	ignore: Npc?,
	urgent: boolean?,
}

export type State =
	"LOADING"
	| "LOGIN"
	| "FADING"
	| "NEW_GAME"
	| "GAME_OVER"
	| "WAIT_SIDE"
	| "STUNNED"
	| "TETHER"
	| "UNTETHER_STRAY"
	| "WAIT_TETHERED"
	| "WAIT_FREE"
	| "UNTETHER_NEARBY"
	| "DODGE"
	| "DOUSE_FIRE"
	| "ATTACK"
	| "GO_TO_PIER"
	| "REPAIR"
	| "FISH_DOUBLE"
	| "CONTINUE"
	| "TAKE_HARPOON"
	| "TAKE_ROPE"
	| "LOAD_CANNON"
	| "TAKE_HAMMER"
	| "TAKE_BUCKETS"
	| "FILL_BUCKETS"
	| "COOK"
	| "COOK_STORM"
	| "FISH"
	| "WAIT_SPOT"
	| "IDLE"
	| "WAIT_VOYAGE"
	| "LEAVE"
	| "HOP_WORLD"
	| "WALK_DOCK"
	| "WALK_LADDER"
	| "SOLO_START"
	| "RANDOM_EVENT"
	| "LOBBY_ANTIBAN"
	| "LEAVE_BOAT"
	| "BOAT_PUMP"
	| "ON_BOAT"
	| "WAIT_NEXT_BOAT"
	| "BOARD_NOW"
	| "BOARD_WALK"
	| "WAIT_LOBBY"
	| "WAIT_SURGE"
	| "WALK_PUMP"
	| "DROP_BUCKET"
	| "BANK_BUCKETS"
	| "WALK_SHIP"
	| "LEAVE_PREPARED"
	| "FISH_TO_TARGET"
	| "WAIT_DOUBLE"
	| "WAIT_WAVE"
	| "FISHING_TO_COOK"
	| "COOKING_TO_LOAD"
	| "WALK_TO_LOAD"
	| "FISH_SAFELY"
	| "COOK_SAFELY"
	| "LOAD_ALL"
	| "GO_TO_PIER_SOLO"
	| "LOAD_EXACT"
	| "FORFEIT"
	| "SOLO_STOP"
	| "HUMIDIFY"
	| "P3_BUCKETS"
	| "P3_CROSS"
	| "P3_CLEAR"
	| "P2_CLEAR"
	| "P3_DROP"
	| "P4_COOK_DROP"
	| "P5_CLEAR"
	| "P5_HUMIDIFY_WALK"
	| "P5_FISHING"

export type Plan = {
	hazard: Npc?,
	broken: Loc?,
	fire: Npc?,
	spot: Npc?,
	ladder: Loc?,
	box: Loc?,
	pump: Loc?,
	players: number?,
	departure: number?,
	drop: number?,
}

local plan: Plan = {}

local report = StatsReport.new()

return {
	CONST = CONST,
	CONFIG = CONFIG,
	Items = Items,
	HUD = HUD,
	stats = stats,
	S = S,
	snap = snap,
	events = events,
	plan = plan,
	report = report,
	new_solo_round = new_solo_round,
	Read = Read,
	Geo = Geo,
	Chat = Chat,
	Ship = Ship,
	Hazard = Hazard,
	Route = Route,
	Doing = Doing,
	Task = Task,
	Game = Game,
	Loop = Loop,
	Solo = Solo,
	Group = Group,
	Handler = Handler,
}
