--!strict
local Host = require("@volcren/host")
local time = Host.time
export type Npc = Host.Npc
export type Loc = Host.Loc
export type Tile = Host.Tile
export type ClientState = Host.ClientState
local Draw = require("@volcren/draw")
local Position = require("@volcren/position")
local SafeSpot = require("@volcren/safespot")
local StatsReport = require("@volcren/stats_report")
local Ticks = require("@volcren/ticks")

local CONST = {
	SINGLE_SPOTS = { [10565] = true, [10568] = true },
	DOUBLE_SPOT = 10569,
	DOUBLE_LIFE_TICKS = 40,
	DOUBLE_LIFE_MAX_TICKS = 44,
	DOUBLE_MIN_TICKS_LEFT = 8,
	FIRE = 8643,
	FIRE_LOC = 37582,
	FIRE_LOCS_MS = 600,
	NPC_RANGE = 15,
	FIRE_APPROACH_MS = 20000,
	STORM_CLOUD = 10580,
	LIGHTNING_STRIKE = 10581,
	INACTIVE_POOL = 10570,
	SPIRIT_POOL = 10571,

	TETHERED_VARBIT = 11895,
	SOUNDS = { LOAD = 4959, EXTINGUISH = 1733, COOK = 2577, POOL_HIT = 4944, VULNERABLE = 2742, TETHER = 1439 },
	FISH_CAUGHT_VARP = 4527,
	POINTS_VARP = 2933,
	POINTS_SCALE = 64,
	CATCH_GRACE_MS = 6 * 600,
	VULNERABLE_SOUND_MS = 3000,
	UNTETHER_ANIMATION = 832,
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
	SPOT_COST = { single_fish_ms = 3200, double_fish_ms = 2133, tile_ms = 300, switch_ms = 600 },
	INCOMING_FIRE = -8643,
	FIRE_SPREAD = 1839,
	SURGE_PROJECTILE = 1842,
	INCOMING_LINGER_MS = 1200,
	LANDING_MARGIN_MS = 600,
	STAND_WALK_MS = 4000,
	SURGE_FIRE_MARGIN = 1,
	CLOUD_STRIKE_MS = 6000,
	FIRE_GHOST_MS = 700,
	DOUSED_MS = 1200,
	POUR_SETTLE_MS = 2500,
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
	FIRE_DEBUG_WIDTH = 3,
	FIRE_VALUE_COLOR = Draw.color(255, 255, 255),
	FIRE_TARGET_COLOR = Draw.color(0, 255, 0),
	FIRE_VALUE_SIZE = 14,
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
	WALK_TRACE_AFTER_MS = 3000,
	WALK_TRACE_EVERY_MS = 2000,
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

	ISLAND = {
		far_steps = 40,
		min_fit = 0.05,
		fit_floor = 0.5,
		double_factor = 1.5,
		spot_fire_factor = 0.75,
		double_fire_factor = 0.95,
		p2_double_free_fires = 2,
		double_near_steps = 20,
		single_near_double = 0.5,
		look_items = 4,
		need = {
			double = 1,
			single = 0.8,
			shrine = 0.6,
			shrine_first = 0.9,
			shrine_full = 1,
			crate = 1,
			crate_waiting = 0.4,
			tether = 1,
			pump = 1,
			fire = 1,
			fire_path = 1,
			fire_waiting = 0.4,
			pier = 0.5,
			pier_after_fires = 0.45,
			attack = 1,
			crew = 1,
			tool = 1,
			humidify = 1,
			route = 0.4,
			look = 0.45,
			north = 1,
			north_later = 0.3,
			urgent = 1,
			step = 0.5,
			wait = 0.05,
			through_fire = 0.25,
			double_through_fire = 0.75,
		},
		rank = {
			crew = 9,
			stunned = 8,
			repair = 7.5,
			tether = 7,
			untether = 6,
			dodge = 5,
			surge = 5,
			load = 4.5,
			pool = 4,
			humidify = 3,
			humidify_hold = 4.9,
			step = 2.5,
			drop = 2,
			pickup = 2,
			path = 1,
		},
		alone = {
			crew = true,
			stunned = true,
			step = true,
			repair = true,
			dodge = true,
			surge = true,
			untether = true,
			pool = true,
			pier = true,
			humidify = true,
			drop = true,
			wait = true,
			tether = true,
			shrine = true,
			pump = true,
			route = true,
			north = true,
		},
		jump_range = 3,
		second_crate_fit = 0.98,
		crate_mast_range = 4,
		slow_ms = 150,
		stick = 0.05,
		multi_bonus = 0.15,
		path_step = 0.02,
		here_bonus = 0.05,
		path_rounds = 4,
		tools = {
			{ kind = "buckets", name = "Buckets" },
			{ kind = "ropes", name = "Ropes" },
			{ kind = "harpoons", name = "Harpoons" },
		},
	},
	ISLAND_DRAW = {
		text_size = 16,
		text_width = 3,
		shadow_offset = 2,
		shadow_color = Draw.color(0, 0, 0),
		score_color = Draw.color(255, 255, 255),
		best_color = Draw.color(0, 255, 0),
		default_color = Draw.color(200, 200, 200),
		outline_width = 3,
		colors = {
			single = Draw.color(0, 200, 255),
			double = Draw.color(0, 80, 255),
			shrine = Draw.color(255, 140, 0),
			crate = Draw.color(255, 255, 0),
			tether = Draw.color(255, 0, 255),
			pump = Draw.color(255, 255, 255),
			fire = Draw.color(255, 0, 0),
			pier = Draw.color(120, 255, 120),
			pool = Draw.color(0, 255, 120),
			crew = Draw.color(200, 160, 255),
			buckets = Draw.color(160, 220, 255),
			ropes = Draw.color(210, 170, 110),
			harpoons = Draw.color(255, 200, 200),
			humidify = Draw.color(0, 160, 255),
			route = Draw.color(255, 120, 200),
			pickup = Draw.color(160, 220, 255),
			look = Draw.color(255, 255, 160),
			north = Draw.color(120, 200, 255),
			dodge = Draw.color(255, 60, 160),
			surge = Draw.color(160, 120, 255),
			stunned = Draw.color(255, 255, 255),
			untether = Draw.color(255, 120, 255),
			drop = Draw.color(255, 80, 80),
			wait = Draw.color(150, 150, 150),
			step = Draw.color(255, 200, 120),
			repair = Draw.color(255, 170, 0),
			multi = Draw.color(255, 90, 0),
		},
	},
	SOLO = {
		FISH_SLOTS = 19,
		FIRST_BATCH = 17,
		SECOND_BATCH = 19,
		OPENING_ENERGY = 95,
		OPENING_FISH = 10,
		UNTETHER_SPAM_MS = 5000,
		UNTETHER_CLICK_DELAY_MS = { 400, 800 },
		START_CLICK_CHECK_MS = 400,
		PREHOVER_ENERGY = 8,
		PREHOVER_FISH = 4,
		PIER_HOVER_FISH = 3,
		HOVER_MIN_TILES = 4,
		WAYPOINT_RADIUS = 8,
		WAYPOINT_TRIES = 60,
		HUMIDIFY_RETRY_MS = 10000,
		HUMIDIFY_SETTLE_MS = 3500,
		THIRD_BATCH = 19,
		STEP_OFF_COUNT_MS = 2500,
		TAKE_BUCKETS_WAIT_MS = 2400,
		TAKE_BUCKETS_PER_CLICK = 10,
		MULTI_WALK_MS = 1200,
		MULTI_WALK_TILE_MS = 300,
		DROP_BATCH = 4,
		DROP_PACE = { shift_ms = { 60, 110 }, gap_ms = { 0, 120 }, confirm = false },
		DROP_SETTLE_MS = 1200,
		MULTI_RETRY_MS = 5000,
		TAKE_BUCKETS_SLOW_CHANCE = 0.1,
		P4_BURN_KEEP_GOING_FISH = 3,
		FISH_SEEN_MS = 2400,
		MAP_MAST = { x = 3036, y = 2850 },
		P3_ROUTE = {
			{ x = 3026, y = 2838 },
			{ x = 3030, y = 2833 },
			{ x = 3047, y = 2833 },
			{ x = 3047, y = 2842 },
			{ x = 3047, y = 2833 },
			{ x = 3050, y = 2837 },
			{ x = 3048, y = 2830 },
			{ x = 3044, y = 2825 },
			{ x = 3040, y = 2823 },
			{ x = 3032, y = 2823 },
			{ x = 3037, y = 2824 },
			{ x = 3037, y = 2828 },
			{ x = 3037, y = 2831 },
		},
		P2_ROUTE_RANGE = 1,
		P3_CLEAR_INTENSITY = 50,
		P3_SWEEP_BACK = 4,
		P3_DROP_BATCH = { 2, 3 },
		P3_DROP_WALK = 4,
		P3_MIN_BUCKETS = 7,
		P3_PICKUP_WAIT_MS = 2400,
		P4_LOAD_INTENSITY = 95,
		LEAVE_INTENSITY = 90,
		P4_LOAD_RAMP_FROM = 80,
		P4_HUMIDIFY_FIRE_RANGE = 12,
		NO_HUMIDIFY_DURING = { fish = true, cook = true, load = true, attack = true },
		P4_DOUBLE_FREE = 8,
		P5_FISH = 2,
		P5_FISH_BY_INTENSITY = 85,
		P5_LOAD_BY_INTENSITY = 92,
		P5_INTENSITY_PER_S = 0.5,
		P5_FISHING_MS = 6000,
		P5_NORTH_RANGE = 8,
		P5_ROUTE = { "south_beach", "southwest_beach", "west_shore", "northwest_beach", "north_beach", "west_ship" },
		P5_SWEEP_FROM = "north_beach",
		P5_LEAVE_INTENSITY = {
			south_beach = 40,
			southwest_beach = 50,
			west_shore = 60,
			northwest_beach = 65,
			north_beach = 75,
			west_ship = 85,
		},
		P5_LEAVE_JITTER = 3,
		P5_LOOK_STEP = 4,
		P5_LOOK_NEAR = 5,
		P5_LOOK_DETOUR = 2,
		P5_LOOK_DETOUR_STEPS = 6,
		LOAD_SOUND_MISSING = 3,
		FIRE_FORGET_RANGE = 13,
		TOP_UP_FISH = 2,
		P4_STOP_ESSENCE = 20,
		ISLAND_BOXES = {
			south_beach = { west = -2, east = 14, south = -26, north = -7 },
			southwest_beach = { west = -25, east = -3, south = -29, north = -7 },
			west_shore = { west = -25, east = -10, south = -6, north = 10 },
			west_ship = { west = -3, east = 8, south = -5, north = 10 },
			west_pier = { west = 10, east = 12, south = 7, north = 10 },
			east_ship = { west = 15, east = 25, south = -10, north = 5 },
			northwest_beach = { west = -25, east = -2, south = 11, north = 28 },
			north_beach = { west = -1, east = 14, south = 11, north = 29 },
		},
		BOX_MARGIN = 2,
		HUB_DETOUR = 2,
		GOAL_DETOUR = 2,
		SHRINE_GUARD = 2,
		CLUSTER_GAP = 3,
		FIRE_VALUE = {
			near = 0.35,
			small = 0.15,
			pair = 0.1,
			spot = 0.15,
			shrine = 0.15,
			crate = 0.15,
			pool = 0.1,
			path = 0.2,
			hub_floor = 0.55,
			near_steps = 12,
			near_min = 0.05,
			tour_step = 0.1,
			cluster_size = 0.33,
			far_steps = 30,
			crossing = 0.5,
			outside = 0.5,
			spot_range = 1,
			shrine_range = 2,
			crate_range = 1,
			pool_range = 2,
			pair_range = 3,
		},
		TETHER_POLL_MS = 60,
		WAVE_BUSY_MS = 10000,
		TETHER_WARNING_MS = 9000,
		TETHER_DOUSE_CUTOFF_MS = 2500,
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
local Island: any = {}
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
	vulnerable: boolean,
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
	load_sound_missing: boolean,
	chat_packets: boolean,
	pours: { base: number, clicks: number, last: number },
	crate_stand_off_until: number,
	arrival_fade: boolean,
	start_hover: Tile?,
	fires_shown: string,
	landing_dodged_at: number,
	planned_route: string,
	route_cache: {
		tick: number,
		routes: { [string]: { Tile } | false },
		floods: { [string]: Flood | false },
		grid: SafeSpot.Grid | false | nil,
	},
	incoming: { [string]: { tile: Tile, lands: number } },
	projectiles_seen: { [string]: boolean },
	fire_size: number?,
	fire_locs: { Npc },
	fire_locs_at: number,
	preparing: boolean,
	forfeiting: boolean,
	solo: SoloRound,
	island: { IslandItem }?,
}

export type IslandItem = {
	kind: string,
	npc: Npc?,
	loc: Loc?,
	tiles: { Tile },
	steps: number,
	fit: number,
	need: number,
	score: number,
	between: boolean?,
	slots: { number }?,
	rank: number,
	stand: Tile?,
	drop: { count: number, water: boolean }?,
	wait: State?,
	fires: { Npc }?,
}

export type Flood = {
	x: number,
	y: number,
	width: number,
	height: number,
	from: number,
	dist: { [number]: number },
	prev: { [number]: number },
	order: { [number]: number },
}

export type Box = { min_x: number, max_x: number, min_y: number, max_y: number }

export type ClearStop = { key: string, tile: Tile, rank: number }

export type SoloRound = {
	opened: boolean,
	doubled: boolean,
	loading: boolean,
	loaded: number,
	load_sounds: number,
	inventory_loads: number,
	last_raw: number,
	loaded_raw: number,
	loaded_cooked: number,
	last_fish: number,
	first_loaded_at: number?,
	p2_loading: boolean,
	humidify_at: number,
	humidify_cast: { at: number, water: number, walking: boolean, filled_at: number? }?,
	left_crate_at: number,
	p3_stage: string?,
	p4_stage: string?,
	p4_load_base: number,
	p5_load_base: number,
	p4_raw: boolean,
	crates_seen: { [string]: Tile },
	island_top: string,
	island_round: number,
	island_signature: string,
	loop_round: number,
	acting: string?,
	multi_failed: { [string]: number },
	hub_flood: { key: string, flood: Flood }?,
	poured_at: number?,
	dropped_at: number?,
	fishing_target: number,
	fishing_cook: boolean,
	watch_tick: number,
	watch_changed: boolean,
	stray_since: number?,
	stop_reason: string?,
	fish_seen: { { at: number, fish: number } },
	p5_stage: string?,
	p5_north: Side?,
	p3_humidify: boolean,
	p2_skip: { [string]: boolean },
	p2_clear: string?,
	p2_pier: boolean,
	p2_south_clicked: boolean,
	p3_buckets: Loc?,
	p3_route: { Tile },
	p3_entry: Tile?,
	clear_route: { Tile },
	clear_plan: { ClearStop },
	clear_planned: { [string]: boolean },
	clear_progress: number,
	p3_drop_batch: number,
	p3_box: Box?,
	p2_box: Box?,
	island_boxes: { [string]: Box }?,
	p5_route_at: number,
	p5_looked: { [string]: { [string]: boolean } },
	p5_seen: { [string]: Tile },
	p5_limits: { [string]: number },
	vulnerable: boolean,
	pools: number,
	pool_essence: number?,
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
		load_sounds = 0,
		multi_failed = {},
		inventory_loads = 0,
		last_raw = 0,
		loaded_raw = 0,
		loaded_cooked = 0,
		last_fish = 0,
		p4_load_base = 0,
		p5_load_base = 0,
		p4_raw = false,
		crates_seen = {},
		island_top = "",
		island_round = 0,
		island_signature = "",
		loop_round = 0,
		watch_tick = -1,
		watch_changed = false,
		fishing_target = 0,
		fishing_cook = false,
		fish_seen = {},
		p2_loading = false,
		humidify_at = 0,
		left_crate_at = 0,
		p3_humidify = false,
		p3_route = {},
		clear_route = {},
		clear_plan = {},
		clear_planned = {},
		clear_progress = 1,
		p3_drop_batch = 2,
		p2_skip = {},
		p2_pier = false,
		p2_south_clicked = false,
		p5_route_at = 1,
		p5_looked = {},
		p5_seen = {},
		p5_limits = {},
		vulnerable = false,
		pools = 0,
		ship_hover_waypoint = false,
		hover_tried = false,
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
	vulnerable = false,
	cook_fish_threshold = 0,
	pier_energy = 0,
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
	fires_known = {},
	fire_seen = {},
	fire_locs = {},
	fire_locs_at = -math.huge,
	doused = {},
	load_sound_missing = false,
	chat_packets = false,
	pours = { base = 0, clicks = 0, last = 0 },
	crate_stand_off_until = 0,
	arrival_fade = false,
	fires_shown = "",
	landing_dodged_at = 0,
	planned_route = "",
	route_cache = { tick = -1, routes = {}, floods = {} },
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
	catches: number,
	last_catch_ms: number,
}

local events = {
	wave_warning_at = nil :: number?,
	tethered = false,
	wave_hit_at = nil :: number?,
	waves_passed = 0,
	wave_hit_us = false,
	burned = false,
	burn_check = nil :: { at: number, before: number }?,
	game_result = nil :: string?,
	must_untether = false,
	surge_until = 0,
	surge_target = nil :: { tile: { x: number, y: number }, at: number }?,
	fire_in_way = nil :: Npc?,
	stunned_until = 0,
	heard = {} :: { [number]: number },
	heard_at = {} :: { [number]: number },
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
	| "LOAD_TO_TOTAL"
	| "P2_LOAD"
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
	| "LOBBY_HUMIDIFY"
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
	| "P3_ROUTE"
	| "P3_DROP"
	| "P3_PICKUP"
	| "P5_WALK"
	| "STEP_OFF"
	| "MULTI_DOUSE"
	| "DOUSE_TOP"
	| "LOAD_SCORED"

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
	drop_water: boolean?,
	after: Tile?,
	crate: IslandItem?,
	item: IslandItem?,
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
	Island = Island,
	Group = Group,
	Handler = Handler,
}
