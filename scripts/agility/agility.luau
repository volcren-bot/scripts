--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
type Tile = Host.Tile
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local Clickbox = require("@lib/main/clickbox")
local Consumables = require("@lib/main/consumables")
local Draw = require("@lib/utils/draw")
local GameState = require("@lib/main/game_state")
local Geometry = require("@lib/utils/math/geometry")
local GroundItems = require("@lib/main/entities/ground_items")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Mouse = require("@lib/utils/input/mouse")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Players = require("@lib/main/entities/players")
local Projection = require("@lib/main/projection/projection")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Walker = require("@lib/main/walker")
local Box, Point, Quad = Geometry.Box, Geometry.Point, Geometry.Quad

local NAME = "Agility"

type Step = {
	id: number,
	options: { string },
	plane: number,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	start: Tile,
	leave: number,
	xp: number,
	next: number?,
	portals: { Tile }?,
}

type Course = {
	name: string,
	level: number,
	teleport: boolean?,
	reward: string?,
	steps: { Step },
}

local CONST = {
	REPORT = { counters_key = "" },
	MARK = { NAME = "Mark of grace", OPTION = "Take", PAD = 1, TAKE_MS = 7000 },
	TICK_MS = 600,
	LOOP_MIN_MS = 200,
	LOOP_SLEEP_MS = 100,
	FALL_TICKS = 2,
	OBSTACLE_MS = 60000,
	FOOD_DELAY_TICKS = 3,
	START_TICKS = 3,
	FALL_RECOVER_TICKS = 6,
	PREHOVER = { RAISE = 0.35, SPREAD = 0.15, MIN_HALF = 8 },
	WALK_MS_PER_TILE = 450,
	NOT_OBSTACLE_OPTIONS = { ["Walk here"] = true, Examine = true, Cancel = true, Use = true },
	PORTAL = { NAME = "Portal", NEAR = 2, LEAVE_MS = 4 * 600 + 4000 },
	TELEPORT = { SPELL = "Camelot Teleport", OPTION = "Seers'", FAR = 15, ARRIVE_MS = 8000 },
	PAD = 1,
	WALK_UP = { CLOSE = 3, DIRECT = 15, MS = 20000 },
	WALK_THROUGH = { ["Chop down"] = true } :: { [string]: boolean },
	REACT_MS = { 200, 900 },
	CLICK_TRIES = 3,
	OVERLAY = { EVERY_MS = 100, FILL = { 255, 255, 0, 70 } },
	NEAREST = "Nearest course",
	COURSES = {
		canifis = {
			name = "Canifis",
			level = 40,
			steps = {
				{
					id = 14843,
					options = { "Climb" },
					plane = 0,
					x1 = 3392,
					y1 = 3392,
					x2 = 3583,
					y2 = 3584,
					start = { x = 3510, y = 3485 },
					leave = 10,
					xp = 4,
				},
				{
					id = 14844,
					options = { "Jump" },
					plane = 2,
					x1 = 3503,
					y1 = 3491,
					x2 = 3512,
					y2 = 3500,
					start = { x = 3506, y = 3492 },
					leave = 12,
					xp = 4,
				},
				{
					id = 14845,
					options = { "Jump" },
					plane = 2,
					x1 = 3495,
					y1 = 3503,
					x2 = 3505,
					y2 = 3509,
					start = { x = 3502, y = 3504 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14848,
					options = { "Jump" },
					plane = 2,
					x1 = 3484,
					y1 = 3498,
					x2 = 3494,
					y2 = 3507,
					start = { x = 3492, y = 3504 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14846,
					options = { "Jump" },
					plane = 3,
					x1 = 3473,
					y1 = 3491,
					x2 = 3481,
					y2 = 3502,
					start = { x = 3479, y = 3499 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14894,
					options = { "Vault" },
					plane = 2,
					x1 = 3476,
					y1 = 3480,
					x2 = 3485,
					y2 = 3489,
					start = { x = 3478, y = 3486 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14847,
					options = { "Jump" },
					plane = 3,
					x1 = 3487,
					y1 = 3468,
					x2 = 3506,
					y2 = 3481,
					start = { x = 3489, y = 3476 },
					leave = 12,
					xp = 4,
				},
				{
					id = 14897,
					options = { "Jump" },
					plane = 2,
					x1 = 3507,
					y1 = 3473,
					x2 = 3518,
					y2 = 3485,
					start = { x = 3510, y = 3476 },
					leave = 16,
					xp = 4,
				},
			},
		} :: Course,
		varrock = {
			name = "Varrock",
			level = 30,
			steps = {
				{
					id = 14412,
					options = { "Climb" },
					plane = 0,
					x1 = 3136,
					y1 = 3328,
					x2 = 3263,
					y2 = 3455,
					start = { x = 3236, y = 3417 },
					leave = 14,
					xp = 4,
				},
				{
					id = 14413,
					options = { "Cross" },
					plane = 3,
					x1 = 3213,
					y1 = 3410,
					x2 = 3221,
					y2 = 3421,
					start = { x = 3219, y = 3414 },
					leave = 14,
					xp = 4,
				},
				{
					id = 14414,
					options = { "Leap" },
					plane = 3,
					x1 = 3200,
					y1 = 3412,
					x2 = 3210,
					y2 = 3421,
					start = { x = 3208, y = 3414 },
					leave = 12,
					xp = 4,
				},
				{
					id = 14832,
					options = { "Balance" },
					plane = 1,
					x1 = 3192,
					y1 = 3415,
					x2 = 3198,
					y2 = 3418,
					start = { x = 3197, y = 3416 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14833,
					options = { "Leap" },
					plane = 3,
					x1 = 3191,
					y1 = 3402,
					x2 = 3199,
					y2 = 3408,
					start = { x = 3192, y = 3406 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14834,
					options = { "Leap" },
					plane = 3,
					x1 = 3181,
					y1 = 3382,
					x2 = 3209,
					y2 = 3405,
					start = { x = 3195, y = 3398 },
					leave = 16,
					xp = 4,
				},
				{
					id = 14835,
					options = { "Leap" },
					plane = 3,
					x1 = 3217,
					y1 = 3393,
					x2 = 3233,
					y2 = 3406,
					start = { x = 3218, y = 3399 },
					leave = 14,
					xp = 4,
				},
				{
					id = 14836,
					options = { "Hurdle" },
					plane = 3,
					x1 = 3235,
					y1 = 3402,
					x2 = 3242,
					y2 = 3409,
					start = { x = 3236, y = 3403 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14841,
					options = { "Jump-off" },
					plane = 3,
					x1 = 3235,
					y1 = 3409,
					x2 = 3242,
					y2 = 3418,
					start = { x = 3238, y = 3410 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		seers = {
			name = "Seers' Village",
			level = 60,
			teleport = false,
			steps = {
				{
					id = 14927,
					options = { "Climb-up" },
					plane = 0,
					x1 = 2624,
					y1 = 3392,
					x2 = 2815,
					y2 = 3520,
					start = { x = 2704, y = 3463 },
					leave = 12,
					xp = 4,
					next = 3,
				},
				{
					id = 25939,
					options = {},
					plane = 1,
					x1 = 2718,
					y1 = 3488,
					x2 = 2732,
					y2 = 3500,
					start = { x = 2728, y = 3490 },
					leave = 8,
					xp = 0,
					next = 1,
				},
				{
					id = 14928,
					options = { "Jump" },
					plane = 3,
					x1 = 2720,
					y1 = 3490,
					x2 = 2731,
					y2 = 3499,
					start = { x = 2729, y = 3491 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14932,
					options = { "Cross" },
					plane = 2,
					x1 = 2703,
					y1 = 3487,
					x2 = 2715,
					y2 = 3500,
					start = { x = 2713, y = 3494 },
					leave = 10,
					xp = 4,
				},
				{
					id = 14929,
					options = { "Jump" },
					plane = 2,
					x1 = 2708,
					y1 = 3476,
					x2 = 2717,
					y2 = 3483,
					start = { x = 2710, y = 3480 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14930,
					options = { "Jump" },
					plane = 3,
					x1 = 2698,
					y1 = 3468,
					x2 = 2718,
					y2 = 3479,
					start = { x = 2711, y = 3472 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14931,
					options = { "Jump" },
					plane = 2,
					x1 = 2689,
					y1 = 3459,
					x2 = 2704,
					y2 = 3468,
					start = { x = 2702, y = 3465 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		ardougne = {
			name = "Ardougne",
			level = 90,
			steps = {
				{
					id = 15608,
					options = { "Climb-up" },
					plane = 0,
					x1 = 2560,
					y1 = 3200,
					x2 = 2751,
					y2 = 3392,
					start = { x = 2668, y = 3297 },
					leave = 10,
					xp = 4,
				},
				{
					id = 15609,
					options = { "Jump" },
					plane = 3,
					x1 = 2667,
					y1 = 3294,
					x2 = 2680,
					y2 = 3315,
					start = { x = 2671, y = 3299 },
					leave = 12,
					xp = 4,
				},
				{
					id = 26635,
					options = { "Walk-on" },
					plane = 3,
					x1 = 2659,
					y1 = 3315,
					x2 = 2668,
					y2 = 3325,
					start = { x = 2665, y = 3318 },
					leave = 8,
					xp = 6,
				},
				{
					id = 15610,
					options = { "Jump" },
					plane = 3,
					x1 = 2650,
					y1 = 3317,
					x2 = 2658,
					y2 = 3324,
					start = { x = 2656, y = 3318 },
					leave = 8,
					xp = 4,
				},
				{
					id = 15611,
					options = { "Jump" },
					plane = 3,
					x1 = 2652,
					y1 = 3310,
					x2 = 2654,
					y2 = 3316,
					start = { x = 2653, y = 3314 },
					leave = 8,
					xp = 4,
				},
				{
					id = 28912,
					options = { "Balance-across" },
					plane = 3,
					x1 = 2650,
					y1 = 3300,
					x2 = 2654,
					y2 = 3310,
					start = { x = 2651, y = 3309 },
					leave = 12,
					xp = 4,
				},
				{
					id = 15612,
					options = { "Jump" },
					plane = 3,
					x1 = 2655,
					y1 = 3296,
					x2 = 2657,
					y2 = 3298,
					start = { x = 2656, y = 3297 },
					leave = 8,
					xp = 8,
				},
			},
		} :: Course,
		gnome = {
			name = "Gnome Stronghold",
			level = 1,
			steps = {
				{
					id = 23145,
					options = {},
					plane = 0,
					x1 = 2465,
					y1 = 3436,
					x2 = 2492,
					y2 = 3443,
					start = { x = 2484, y = 3437 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23134,
					options = {},
					plane = 0,
					x1 = 2468,
					y1 = 3414,
					x2 = 2480,
					y2 = 3430,
					start = { x = 2474, y = 3429 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23559,
					options = {},
					plane = 1,
					x1 = 2469,
					y1 = 3421,
					x2 = 2477,
					y2 = 3426,
					start = { x = 2473, y = 3423 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23557,
					options = {},
					plane = 2,
					x1 = 2471,
					y1 = 3417,
					x2 = 2477,
					y2 = 3423,
					start = { x = 2473, y = 3420 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23560,
					options = {},
					plane = 2,
					x1 = 2482,
					y1 = 3417,
					x2 = 2490,
					y2 = 3423,
					start = { x = 2483, y = 3420 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23135,
					options = {},
					plane = 0,
					x1 = 2481,
					y1 = 3414,
					x2 = 2492,
					y2 = 3426,
					start = { x = 2487, y = 3420 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23138,
					options = {},
					plane = 0,
					x1 = 2481,
					y1 = 3426,
					x2 = 2490,
					y2 = 3432,
					start = { x = 2485, y = 3428 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		shayzien_basic = {
			name = "Shayzien basic",
			level = 5,
			steps = {
				{
					id = 42209,
					options = {},
					plane = 0,
					x1 = 1472,
					y1 = 3585,
					x2 = 1599,
					y2 = 3711,
					start = { x = 1554, y = 3640 },
					leave = 8,
					xp = 4,
				},
				{
					id = 42211,
					options = {},
					plane = 3,
					x1 = 1551,
					y1 = 3631,
					x2 = 1557,
					y2 = 3636,
					start = { x = 1554, y = 3632 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42212,
					options = {},
					plane = 2,
					x1 = 1536,
					y1 = 3630,
					x2 = 1542,
					y2 = 3637,
					start = { x = 1541, y = 3633 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42213,
					options = {},
					plane = 2,
					x1 = 1520,
					y1 = 3631,
					x2 = 1529,
					y2 = 3641,
					start = { x = 1528, y = 3633 },
					leave = 8,
					xp = 4,
				},
				{
					id = 42214,
					options = {},
					plane = 3,
					x1 = 1521,
					y1 = 3643,
					x2 = 1525,
					y2 = 3647,
					start = { x = 1523, y = 3644 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42215,
					options = {},
					plane = 2,
					x1 = 1537,
					y1 = 3642,
					x2 = 1541,
					y2 = 3647,
					start = { x = 1539, y = 3644 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42216,
					options = {},
					plane = 2,
					x1 = 1551,
					y1 = 3641,
					x2 = 1557,
					y2 = 3648,
					start = { x = 1552, y = 3644 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		shayzien_advanced = {
			name = "Shayzien advanced",
			level = 48,
			steps = {
				{
					id = 42209,
					options = {},
					plane = 0,
					x1 = 1472,
					y1 = 3585,
					x2 = 1599,
					y2 = 3711,
					start = { x = 1554, y = 3640 },
					leave = 8,
					xp = 4,
				},
				{
					id = 42211,
					options = {},
					plane = 3,
					x1 = 1551,
					y1 = 3631,
					x2 = 1557,
					y2 = 3636,
					start = { x = 1554, y = 3632 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42212,
					options = {},
					plane = 2,
					x1 = 1536,
					y1 = 3630,
					x2 = 1542,
					y2 = 3637,
					start = { x = 1541, y = 3633 },
					leave = 8,
					xp = 8,
				},
				{
					id = 42217,
					options = {},
					plane = 2,
					x1 = 1520,
					y1 = 3631,
					x2 = 1529,
					y2 = 3641,
					start = { x = 1528, y = 3633 },
					leave = 16,
					xp = 4,
				},
				{
					id = 42218,
					options = {},
					plane = 2,
					x1 = 1509,
					y1 = 3635,
					x2 = 1512,
					y2 = 3639,
					start = { x = 1511, y = 3637 },
					leave = 12,
					xp = 4,
				},
				{
					id = 42219,
					options = {},
					plane = 2,
					x1 = 1508,
					y1 = 3628,
					x2 = 1512,
					y2 = 3631,
					start = { x = 1510, y = 3630 },
					leave = 8,
					xp = 4,
				},
				{
					id = 42220,
					options = {},
					plane = 2,
					x1 = 1508,
					y1 = 3618,
					x2 = 1512,
					y2 = 3621,
					start = { x = 1510, y = 3620 },
					leave = 16,
					xp = 4,
				},
				{
					id = 42221,
					options = {},
					plane = 2,
					x1 = 1520,
					y1 = 3617,
					x2 = 1524,
					y2 = 3621,
					start = { x = 1521, y = 3619 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		draynor = {
			name = "Draynor Village",
			level = 10,
			steps = {
				{
					id = 11404,
					options = {},
					plane = 0,
					x1 = 3065,
					y1 = 3229,
					x2 = 3134,
					y2 = 3309,
					start = { x = 3103, y = 3261 },
					leave = 8,
					xp = 4,
				},
				{
					id = 11405,
					options = {},
					plane = 3,
					x1 = 3096,
					y1 = 3277,
					x2 = 3103,
					y2 = 3283,
					start = { x = 3102, y = 3279 },
					leave = 12,
					xp = 4,
				},
				{
					id = 11406,
					options = {},
					plane = 3,
					x1 = 3086,
					y1 = 3272,
					x2 = 3094,
					y2 = 3281,
					start = { x = 3090, y = 3276 },
					leave = 14,
					xp = 4,
				},
				{
					id = 11430,
					options = {},
					plane = 3,
					x1 = 3088,
					y1 = 3265,
					x2 = 3095,
					y2 = 3270,
					start = { x = 3092, y = 3266 },
					leave = 8,
					xp = 4,
				},
				{
					id = 11630,
					options = {},
					plane = 3,
					x1 = 3085,
					y1 = 3256,
					x2 = 3089,
					y2 = 3263,
					start = { x = 3088, y = 3261 },
					leave = 8,
					xp = 4,
				},
				{
					id = 11631,
					options = {},
					plane = 3,
					x1 = 3086,
					y1 = 3255,
					x2 = 3095,
					y2 = 3256,
					start = { x = 3088, y = 3255 },
					leave = 8,
					xp = 4,
				},
				{
					id = 11632,
					options = {},
					plane = 3,
					x1 = 3095,
					y1 = 3255,
					x2 = 3103,
					y2 = 3263,
					start = { x = 3096, y = 3256 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		al_kharid = {
			name = "Al Kharid",
			level = 20,
			steps = {
				{
					id = 11633,
					options = {},
					plane = 0,
					x1 = 3252,
					y1 = 3148,
					x2 = 3332,
					y2 = 3227,
					start = { x = 3299, y = 3194 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14398,
					options = {},
					plane = 3,
					x1 = 3270,
					y1 = 3180,
					x2 = 3280,
					y2 = 3194,
					start = { x = 3273, y = 3192 },
					leave = 14,
					xp = 4,
				},
				{
					id = 14402,
					options = {},
					plane = 3,
					x1 = 3264,
					y1 = 3160,
					x2 = 3273,
					y2 = 3175,
					start = { x = 3272, y = 3172 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14403,
					options = {},
					plane = 3,
					x1 = 3282,
					y1 = 3159,
					x2 = 3304,
					y2 = 3178,
					start = { x = 3284, y = 3166 },
					leave = 18,
					xp = 4,
				},
				{
					id = 14404,
					options = {},
					plane = 1,
					x1 = 3312,
					y1 = 3159,
					x2 = 3320,
					y2 = 3166,
					start = { x = 3315, y = 3163 },
					leave = 8,
					xp = 4,
				},
				{
					id = 11634,
					options = {},
					plane = 2,
					x1 = 3312,
					y1 = 3174,
					x2 = 3319,
					y2 = 3181,
					start = { x = 3317, y = 3174 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14409,
					options = {},
					plane = 3,
					x1 = 3311,
					y1 = 3180,
					x2 = 3319,
					y2 = 3188,
					start = { x = 3316, y = 3180 },
					leave = 12,
					xp = 8,
				},
				{
					id = 14399,
					options = {},
					plane = 3,
					x1 = 3296,
					y1 = 3184,
					x2 = 3307,
					y2 = 3196,
					start = { x = 3302, y = 3187 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		barbarian = {
			name = "Barbarian Outpost",
			level = 35,
			steps = {
				{
					id = 23131,
					options = {},
					plane = 0,
					x1 = 2543,
					y1 = 3550,
					x2 = 2553,
					y2 = 3560,
					start = { x = 2543, y = 3553 },
					leave = 8,
					xp = 4,
					next = 3,
				},
				{
					id = 17385,
					options = {},
					plane = 0,
					x1 = 2544,
					y1 = 9946,
					x2 = 2557,
					y2 = 9958,
					start = { x = 2549, y = 9951 },
					leave = 8,
					xp = 0,
					next = 1,
				},
				{
					id = 23144,
					options = {},
					plane = 0,
					x1 = 2548,
					y1 = 3542,
					x2 = 2554,
					y2 = 3550,
					start = { x = 2551, y = 3549 },
					leave = 8,
					xp = 4,
				},
				{
					id = 20211,
					options = {},
					plane = 0,
					x1 = 2536,
					y1 = 3542,
					x2 = 2543,
					y2 = 3550,
					start = { x = 2541, y = 3546 },
					leave = 8,
					xp = 4,
				},
				{
					id = 23547,
					options = {},
					plane = 1,
					x1 = 2535,
					y1 = 3545,
					x2 = 2539,
					y2 = 3549,
					start = { x = 2537, y = 3546 },
					leave = 8,
					xp = 4,
				},
				{
					id = 42487,
					options = {},
					plane = 1,
					x1 = 2530,
					y1 = 3544,
					x2 = 2534,
					y2 = 3549,
					start = { x = 2532, y = 3546 },
					leave = 8,
					xp = 0,
				},
				{
					id = 1948,
					options = {},
					plane = 0,
					x1 = 2528,
					y1 = 3542,
					x2 = 2536,
					y2 = 3557,
					start = { x = 2532, y = 3546 },
					leave = 8,
					xp = 8,
				},
				{
					id = 1948,
					options = {},
					plane = 0,
					x1 = 2537,
					y1 = 3552,
					x2 = 2539,
					y2 = 3555,
					start = { x = 2537, y = 3553 },
					leave = 8,
					xp = 8,
				},
				{
					id = 1948,
					options = {},
					plane = 0,
					x1 = 2540,
					y1 = 3552,
					x2 = 2542,
					y2 = 3555,
					start = { x = 2540, y = 3553 },
					leave = 8,
					xp = 8,
				},
			},
		} :: Course,
		ape_atoll = {
			name = "Ape Atoll",
			level = 48,
			steps = {
				{
					id = 15412,
					options = {},
					plane = 0,
					x1 = 2754,
					y1 = 2741,
					x2 = 2803,
					y2 = 2805,
					start = { x = 2770, y = 2747 },
					leave = 16,
					xp = 4,
				},
				{
					id = 15414,
					options = {},
					plane = 0,
					x1 = 2750,
					y1 = 2741,
					x2 = 2754,
					y2 = 2744,
					start = { x = 2753, y = 2742 },
					leave = 8,
					xp = 4,
				},
				{
					id = 15417,
					options = {},
					plane = 2,
					x1 = 2751,
					y1 = 2740,
					x2 = 2755,
					y2 = 2743,
					start = { x = 2753, y = 2742 },
					leave = 8,
					xp = 4,
				},
				{
					id = 1747,
					options = {},
					plane = 0,
					x1 = 2746,
					y1 = 2740,
					x2 = 2748,
					y2 = 2743,
					start = { x = 2747, y = 2741 },
					leave = 8,
					xp = 4,
				},
				{
					id = 15487,
					options = {},
					plane = 0,
					x1 = 2737,
					y1 = 2724,
					x2 = 2754,
					y2 = 2743,
					start = { x = 2742, y = 2741 },
					leave = 12,
					xp = 4,
				},
				{
					id = 16062,
					options = {},
					plane = 0,
					x1 = 2754,
					y1 = 2721,
					x2 = 2767,
					y2 = 2738,
					start = { x = 2756, y = 2731 },
					leave = 12,
					xp = 4,
				},
			},
		} :: Course,
		falador = {
			name = "Falador",
			level = 50,
			steps = {
				{
					id = 14898,
					options = {},
					plane = 0,
					x1 = 2944,
					y1 = 3265,
					x2 = 3135,
					y2 = 3456,
					start = { x = 3029, y = 3333 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14899,
					options = {},
					plane = 3,
					x1 = 3034,
					y1 = 3341,
					x2 = 3041,
					y2 = 3350,
					start = { x = 3036, y = 3342 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14901,
					options = {},
					plane = 3,
					x1 = 3043,
					y1 = 3341,
					x2 = 3053,
					y2 = 3351,
					start = { x = 3047, y = 3344 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14903,
					options = {},
					plane = 3,
					x1 = 3047,
					y1 = 3357,
					x2 = 3051,
					y2 = 3360,
					start = { x = 3050, y = 3357 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14904,
					options = {},
					plane = 3,
					x1 = 3044,
					y1 = 3361,
					x2 = 3049,
					y2 = 3369,
					start = { x = 3048, y = 3361 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14905,
					options = {},
					plane = 3,
					x1 = 3033,
					y1 = 3361,
					x2 = 3042,
					y2 = 3366,
					start = { x = 3041, y = 3361 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14911,
					options = {},
					plane = 3,
					x1 = 3025,
					y1 = 3352,
					x2 = 3030,
					y2 = 3357,
					start = { x = 3028, y = 3354 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14919,
					options = {},
					plane = 3,
					x1 = 3008,
					y1 = 3353,
					x2 = 3022,
					y2 = 3360,
					start = { x = 3020, y = 3353 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14920,
					options = {},
					plane = 3,
					x1 = 3015,
					y1 = 3343,
					x2 = 3023,
					y2 = 3350,
					start = { x = 3017, y = 3349 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14921,
					options = {},
					plane = 3,
					x1 = 3010,
					y1 = 3343,
					x2 = 3014,
					y2 = 3347,
					start = { x = 3014, y = 3345 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14922,
					options = {},
					plane = 3,
					x1 = 3008,
					y1 = 3335,
					x2 = 3013,
					y2 = 3343,
					start = { x = 3012, y = 3342 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14924,
					options = {},
					plane = 3,
					x1 = 3011,
					y1 = 3330,
					x2 = 3018,
					y2 = 3334,
					start = { x = 3013, y = 3333 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14925,
					options = {},
					plane = 3,
					x1 = 3018,
					y1 = 3331,
					x2 = 3025,
					y2 = 3335,
					start = { x = 3019, y = 3333 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		pollnivneach = {
			name = "Pollnivneach",
			level = 70,
			steps = {
				{
					id = 14935,
					options = {},
					plane = 0,
					x1 = 3264,
					y1 = 2880,
					x2 = 3391,
					y2 = 3071,
					start = { x = 3363, y = 2998 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14936,
					options = {},
					plane = 1,
					x1 = 3344,
					y1 = 2963,
					x2 = 3352,
					y2 = 2970,
					start = { x = 3351, y = 2964 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14937,
					options = {},
					plane = 1,
					x1 = 3350,
					y1 = 2973,
					x2 = 3355,
					y2 = 2978,
					start = { x = 3352, y = 2973 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14938,
					options = {},
					plane = 1,
					x1 = 3358,
					y1 = 2976,
					x2 = 3363,
					y2 = 2981,
					start = { x = 3360, y = 2977 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14939,
					options = {},
					plane = 1,
					x1 = 3364,
					y1 = 2974,
					x2 = 3370,
					y2 = 2978,
					start = { x = 3366, y = 2976 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14940,
					options = {},
					plane = 1,
					x1 = 3363,
					y1 = 2981,
					x2 = 3370,
					y2 = 2988,
					start = { x = 3368, y = 2982 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14941,
					options = {},
					plane = 2,
					x1 = 3354,
					y1 = 2980,
					x2 = 3367,
					y2 = 2987,
					start = { x = 3365, y = 2983 },
					leave = 12,
					xp = 4,
				},
				{
					id = 14944,
					options = {},
					plane = 2,
					x1 = 3355,
					y1 = 2990,
					x2 = 3371,
					y2 = 2997,
					start = { x = 3358, y = 2991 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14945,
					options = {},
					plane = 2,
					x1 = 3355,
					y1 = 3000,
					x2 = 3363,
					y2 = 3006,
					start = { x = 3359, y = 3000 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		rellekka = {
			name = "Rellekka",
			level = 80,
			steps = {
				{
					id = 14946,
					options = {},
					plane = 0,
					x1 = 2560,
					y1 = 3585,
					x2 = 2687,
					y2 = 3712,
					start = { x = 2652, y = 3676 },
					leave = 14,
					xp = 4,
				},
				{
					id = 14947,
					options = {},
					plane = 3,
					x1 = 2619,
					y1 = 3671,
					x2 = 2629,
					y2 = 3680,
					start = { x = 2625, y = 3676 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14987,
					options = {},
					plane = 3,
					x1 = 2613,
					y1 = 3657,
					x2 = 2624,
					y2 = 3671,
					start = { x = 2622, y = 3668 },
					leave = 10,
					xp = 4,
				},
				{
					id = 14990,
					options = {},
					plane = 3,
					x1 = 2624,
					y1 = 3650,
					x2 = 2632,
					y2 = 3658,
					start = { x = 2627, y = 3654 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14991,
					options = {},
					plane = 3,
					x1 = 2637,
					y1 = 3649,
					x2 = 2646,
					y2 = 3655,
					start = { x = 2639, y = 3653 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14992,
					options = {},
					plane = 3,
					x1 = 2641,
					y1 = 3657,
					x2 = 2651,
					y2 = 3664,
					start = { x = 2644, y = 3657 },
					leave = 8,
					xp = 4,
				},
				{
					id = 14994,
					options = {},
					plane = 3,
					x1 = 2653,
					y1 = 3664,
					x2 = 2668,
					y2 = 3688,
					start = { x = 2655, y = 3670 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		prifddinas = {
			name = "Prifddinas",
			level = 75,
			reward = "Crystal shard",
			steps = {
				{
					id = 36221,
					options = {},
					plane = 0,
					x1 = 3201,
					y1 = 6024,
					x2 = 3267,
					y2 = 6140,
					start = { x = 3240, y = 6109 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36225,
					options = {},
					plane = 2,
					x1 = 3254,
					y1 = 6101,
					x2 = 3259,
					y2 = 6114,
					start = { x = 3255, y = 6109 },
					leave = 12,
					xp = 4,
					portals = { { x = 3257, y = 6111 } },
				},
				{
					id = 36227,
					options = {},
					plane = 2,
					x1 = 3271,
					y1 = 6104,
					x2 = 3277,
					y2 = 6109,
					start = { x = 3272, y = 6105 },
					leave = 8,
					xp = 4,
					next = 5,
				},
				{
					id = 36221,
					options = {},
					plane = 0,
					x1 = 3259,
					y1 = 6092,
					x2 = 3296,
					y2 = 6116,
					start = { x = 3269, y = 6110 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36228,
					options = {},
					plane = 2,
					x1 = 3268,
					y1 = 6111,
					x2 = 3271,
					y2 = 6117,
					start = { x = 3269, y = 6112 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36229,
					options = {},
					plane = 0,
					x1 = 3268,
					y1 = 6116,
					x2 = 3271,
					y2 = 6120,
					start = { x = 3269, y = 6117 },
					leave = 8,
					xp = 4,
					portals = { { x = 3270, y = 6116 } },
				},
				{
					id = 36231,
					options = {},
					plane = 0,
					x1 = 2256,
					y1 = 3387,
					x2 = 2278,
					y2 = 3400,
					start = { x = 2269, y = 3389 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36233,
					options = {},
					plane = 2,
					x1 = 2263,
					y1 = 3387,
					x2 = 2272,
					y2 = 3397,
					start = { x = 2269, y = 3393 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36234,
					options = {},
					plane = 2,
					x1 = 2253,
					y1 = 3385,
					x2 = 2259,
					y2 = 3391,
					start = { x = 2257, y = 3390 },
					leave = 8,
					xp = 4,
					next = 11,
					portals = { { x = 2258, y = 3386 } },
				},
				{
					id = 36232,
					options = {},
					plane = 0,
					x1 = 2242,
					y1 = 3386,
					x2 = 2254,
					y2 = 3396,
					start = { x = 2250, y = 3392 },
					leave = 8,
					xp = 0,
				},
				{
					id = 36235,
					options = {},
					plane = 2,
					x1 = 2242,
					y1 = 3393,
					x2 = 2248,
					y2 = 3399,
					start = { x = 2246, y = 3398 },
					leave = 8,
					xp = 4,
					portals = { { x = 2244, y = 3395 } },
				},
				{
					id = 36236,
					options = {},
					plane = 2,
					x1 = 2242,
					y1 = 3404,
					x2 = 2250,
					y2 = 3410,
					start = { x = 2246, y = 3406 },
					leave = 8,
					xp = 4,
				},
				{
					id = 36237,
					options = {},
					plane = 2,
					x1 = 2248,
					y1 = 3414,
					x2 = 2254,
					y2 = 3420,
					start = { x = 2250, y = 3416 },
					leave = 8,
					xp = 4,
					portals = { { x = 2249, y = 3419 } },
				},
				{
					id = 36238,
					options = {},
					plane = 0,
					x1 = 2252,
					y1 = 3421,
					x2 = 2275,
					y2 = 3442,
					start = { x = 2260, y = 3426 },
					leave = 8,
					xp = 4,
				},
			},
		} :: Course,
		wyrm_basic = {
			name = "Colossal Wyrm basic",
			level = 50,
			reward = "Termites",
			steps = {
				{
					id = 55178,
					options = {},
					plane = 0,
					x1 = 1600,
					y1 = 2881,
					x2 = 1727,
					y2 = 3007,
					start = { x = 1645, y = 2933 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55180,
					options = {},
					plane = 1,
					x1 = 1651,
					y1 = 2926,
					x2 = 1657,
					y2 = 2934,
					start = { x = 1653, y = 2931 },
					leave = 8,
					xp = 8,
				},
				{
					id = 55184,
					options = {},
					plane = 1,
					x1 = 1645,
					y1 = 2905,
					x2 = 1649,
					y2 = 2913,
					start = { x = 1649, y = 2910 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55186,
					options = {},
					plane = 1,
					x1 = 1631,
					y1 = 2906,
					x2 = 1635,
					y2 = 2913,
					start = { x = 1635, y = 2910 },
					leave = 8,
					xp = 8,
				},
				{
					id = 55190,
					options = {},
					plane = 1,
					x1 = 1621,
					y1 = 2930,
					x2 = 1629,
					y2 = 2935,
					start = { x = 1627, y = 2931 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55179,
					options = {},
					plane = 2,
					x1 = 1622,
					y1 = 2930,
					x2 = 1626,
					y2 = 2935,
					start = { x = 1625, y = 2932 },
					leave = 12,
					xp = 4,
				},
			},
		} :: Course,
		wyrm_advanced = {
			name = "Colossal Wyrm advanced",
			level = 62,
			reward = "Termites",
			steps = {
				{
					id = 55178,
					options = {},
					plane = 0,
					x1 = 1600,
					y1 = 2881,
					x2 = 1727,
					y2 = 3007,
					start = { x = 1645, y = 2933 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55180,
					options = {},
					plane = 1,
					x1 = 1651,
					y1 = 2926,
					x2 = 1657,
					y2 = 2934,
					start = { x = 1653, y = 2931 },
					leave = 8,
					xp = 8,
				},
				{
					id = 55191,
					options = {},
					plane = 1,
					x1 = 1645,
					y1 = 2905,
					x2 = 1649,
					y2 = 2913,
					start = { x = 1649, y = 2910 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55192,
					options = {},
					plane = 2,
					x1 = 1646,
					y1 = 2905,
					x2 = 1650,
					y2 = 2910,
					start = { x = 1648, y = 2908 },
					leave = 10,
					xp = 4,
				},
				{
					id = 55194,
					options = {},
					plane = 2,
					x1 = 1632,
					y1 = 2905,
					x2 = 1637,
					y2 = 2910,
					start = { x = 1635, y = 2907 },
					leave = 8,
					xp = 4,
				},
				{
					id = 55179,
					options = {},
					plane = 2,
					x1 = 1622,
					y1 = 2930,
					x2 = 1626,
					y2 = 2935,
					start = { x = 1624, y = 2931 },
					leave = 12,
					xp = 4,
				},
			},
		} :: Course,
	},
}

local Read, Game, Loop, Handler, Overlay = {}, {}, {}, {}, {}

local CONFIG = {
	course = "auto",
	progressive = false,
	blacklist = {
		ardougne = true,
		ape_atoll = true,
		prifddinas = true,
		wyrm_basic = true,
		wyrm_advanced = true,
	} :: { [string]: boolean },
	highlight = true,
	max_laps = 0,
	prehover = 0.8,
	seers_teleport = false,
	eat_at_hitpoints = { 12, 20 },
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local stats = { laps = 0, marks = 0, falls = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	course: Course?,
	unreachable: { [string]: boolean },
	overlay_at: number,
	overlay_drawn: boolean,
	marks_start: number,
	eat_at: number,
	ate_tick: number,
	skip: { [string]: boolean },
	camera_ready: number,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	course = nil,
	unreachable = {},
	overlay_at = 0,
	overlay_drawn = false,
	marks_start = 0,
	eat_at = 0,
	ate_tick = -math.huge,
	skip = {},
	camera_ready = 0,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	pos: Tile,
	plane: number,
	step: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LOST" | "EAT" | "NO_FOOD" | "TELEPORT" | "MARK" | "PORTAL" | "ADVANCE"

type Food = { slot: number, option: string }

type Plan = { mark: Host.GroundItem?, portal: Loc?, food: Food? }

local plan: Plan = {}

local report = StatsReport.new()

function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.in_box(step: Step, pos: Tile, plane: number, pad: number): boolean
	return plane == step.plane
		and pos.x >= step.x1 - pad
		and pos.x <= step.x2 + pad
		and pos.y >= step.y1 - pad
		and pos.y <= step.y2 + pad
end

function Read.step_of(course: Course, pos: Tile, plane: number): number
	for _, pad in ipairs({ 0, CONST.PAD }) do
		local best, best_area = 0, math.huge
		for i, step in ipairs(course.steps) do
			if Read.in_box(step, pos, plane, pad) then
				local area = (step.x2 - step.x1 + 1) * (step.y2 - step.y1 + 1)
				if area < best_area then
					best, best_area = i, area
				end
			end
		end
		if best > 0 then
			return best
		end
	end
	return 0
end

function Read.course_of(pos: Tile, plane: number): Course?
	local level = Stats.real_level("Agility") or 0
	local best: Course?, best_can, best_area = nil, false, math.huge
	for _, course: Course in pairs(CONST.COURSES :: { [string]: Course }) do
		local index = Read.step_of(course, pos, plane)
		if index > 0 then
			local step = course.steps[index]
			local can = course.level <= level
			local area = (step.x2 - step.x1 + 1) * (step.y2 - step.y1 + 1)
			local better = best == nil
			if best ~= nil then
				if can ~= best_can then
					better = can
				elseif area ~= best_area then
					better = area < best_area
				else
					better = course.level > best.level
				end
			end
			if better then
				best, best_can, best_area = course, can, area
			end
		end
	end
	return best
end

function Read.courses_by_level(): { { key: string, course: Course } }
	type Entry = { key: string, course: Course }
	local list: { Entry } = {}
	for key, course in pairs(CONST.COURSES :: { [string]: Course }) do
		table.insert(list, { key = key, course = course })
	end
	table.sort(list, function(a: Entry, b: Entry)
		if a.course.level ~= b.course.level then
			return a.course.level < b.course.level
		end
		return a.key < b.key
	end)
	return list
end

function Read.next_course(): (string?, Course?)
	local level = Stats.real_level("Agility") or 0
	local current = S.course :: Course
	local best_key, best = nil, nil
	for _, entry in ipairs(Read.courses_by_level()) do
		local course = entry.course
		if
			course.level <= level
			and course.level > current.level
			and not CONFIG.blacklist[entry.key]
			and not S.unreachable[entry.key]
		then
			best_key, best = entry.key, course
		end
	end
	return best_key, best
end

function Read.refresh_snapshot(state: ClientState): boolean
	local p = state.position
	if p == nil then
		return false
	end
	local pos, plane = { x = p.x, y = p.y }, p.plane or 0
	local server = Host.movement()
	if server and server.plane ~= nil then
		pos, plane = { x = server.x, y = server.y }, server.plane or 0
	end
	snap = {
		state = state,
		tick = Read.current_tick(state),
		pos = pos,
		plane = plane,
		step = if S.course then Read.step_of(S.course, pos, plane) else 0,
	}
	return true
end

function Read.marks_in_inventory(): number
	local total = 0
	local wanted = if S.course and S.course.reward then string.lower(S.course.reward) else "mark of grace"
	for _, item in ipairs(Inventory.items() or {}) do
		if string.lower(item.name or "") == wanted then
			total += item.quantity
		end
	end
	return total
end

function Read.busy(): boolean
	local me = Players.me()
	return me ~= nil and (me.animation ~= -1 or table.find(me.movement, me.pose) == nil)
end

function Read.agility_xp(): number
	return Stats.xp("Agility") or 0
end

function Read.hitpoints(s: ClientState): number?
	for _, skill in ipairs(s.skills or {}) do
		if skill.name == "Hitpoints" then
			return skill.level
		end
	end
	return nil
end

function Read.step_here(course: Course): number
	local p = game_state().position
	if p == nil then
		return 0
	end
	return Read.step_of(course, { x = p.x, y = p.y }, p.plane or 0)
end

function Read.walk_through(entry: Host.MenuEntry): boolean
	return CONST.WALK_THROUGH[entry.option] == true
end

function Read.on_screen(loc: Loc): boolean
	local box = Objects.clickbox(loc)
	return box ~= nil and Clickbox.target(box, loc.name or tostring(loc.id)) ~= nil
end

function Read.server_step(course: Course): number?
	local m = Host.movement()
	if m == nil or m.plane == nil then
		return nil
	end
	return Read.step_of(course, { x = m.x, y = m.y }, m.plane)
end

function Read.mark(step: Step, pos: Tile): Host.GroundItem?
	local best, best_distance = nil, math.huge
	for _, item in ipairs(GroundItems.find(CONST.MARK.NAME) or {}) do
		local inside = item.plane == step.plane
			and item.x >= step.x1 - CONST.MARK.PAD
			and item.x <= step.x2 + CONST.MARK.PAD
			and item.y >= step.y1 - CONST.MARK.PAD
			and item.y <= step.y2 + CONST.MARK.PAD
		if inside then
			local d = GroundItems.distance(item, pos)
			if d < best_distance then
				best, best_distance = item, d
			end
		end
	end
	return best
end

function Read.obstacle(step: Step, pos: Tile): Loc?
	local best, best_distance = nil, math.huge
	for _, loc in ipairs(Objects.find(step.id) or {}) do
		if loc.plane == step.plane then
			local d = Objects.distance(loc, pos)
			if d < best_distance then
				best, best_distance = loc, d
			end
		end
	end
	return best
end

function Read.menu_option(loc: Loc): string?
	if not Objects.hover(loc) then
		return nil
	end
	for _, entry in ipairs(Host.menu() or {}) do
		if Objects.owns(loc, entry) and not CONST.NOT_OBSTACLE_OPTIONS[entry.option] then
			return entry.option
		end
	end
	return nil
end

function Read.obstacle_on_plane(step: Step): Loc?
	local best, best_distance = nil, math.huge
	for _, loc in ipairs(Host.locs(step.plane) or {}) do
		if loc.id == step.id and loc.clickable then
			local d = math.max(math.abs(loc.x - step.start.x), math.abs(loc.y - step.start.y))
			if d < best_distance then
				best, best_distance = loc, d
			end
		end
	end
	return best
end

function Read.portal(step: Step, pos: Tile): Loc?
	local best, best_distance = nil, math.huge
	for _, loc in ipairs(Objects.find(CONST.PORTAL.NAME) or {}) do
		if loc.plane == step.plane and Objects.clickbox(loc) ~= nil then
			for _, at in ipairs(step.portals or {}) do
				if math.max(math.abs(loc.x - at.x), math.abs(loc.y - at.y)) <= CONST.PORTAL.NEAR then
					local d = Objects.distance(loc, pos)
					if d < best_distance then
						best, best_distance = loc, d
					end
					break
				end
			end
		end
	end
	return best
end

function Read.food(): Food?
	local levels = Consumables.levels()
	for _, item in ipairs(Inventory.items() or {}) do
		local family = Consumables.get(item.id)
		local result = family and Consumables.result(item.id, levels)
		local hitpoints = result and result.Hitpoints
		if family and hitpoints and hitpoints.low > hitpoints.from then
			return { slot = item.slot, option = family.option }
		end
	end
	return nil
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

	AntibanTasks.skills = { "Agility" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
	Antiban.add_task(AntibanTasks.handle_randoms, 30 * SECOND, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.lose_focus, 10 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.adjust_minimap_zoom, 13 * MINUTE, 0.33)

	Antiban.add_walk_task(AntibanTasks.adjust_camera, 2 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
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

function Overlay.update()
	local course = S.course
	if not CONFIG.highlight or course == nil or time() - S.overlay_at < CONST.OVERLAY.EVERY_MS then
		return
	end
	S.overlay_at = time()
	local box: Clickbox.Clickbox? = nil
	local p = game_state().position
	if p then
		local pos = { x = p.x, y = p.y }
		local step = course.steps[Read.step_of(course, pos, p.plane or 0)]
		local loc = step and Read.obstacle(step, pos)
		box = loc and Objects.clickbox(loc)
	end
	if box == nil and not S.overlay_drawn then
		return
	end
	S.overlay_drawn = box ~= nil
	Draw.batch(function()
		Draw.clear()
		if box then
			local fill = CONST.OVERLAY.FILL
			for _, triangle in ipairs(box.triangles or {}) do
				Draw.polygon(triangle, Draw.color(fill[1], fill[2], fill[3], fill[4]))
			end
			Clickbox.draw(box)
		end
	end)
end

function Overlay.clear()
	if S.overlay_drawn then
		S.overlay_drawn = false
		Draw.clear()
	end
end

function Game.ask(): boolean
	local names, keys = { CONST.NEAREST }, {}
	for _, entry in ipairs(Read.courses_by_level()) do
		local label = `{entry.course.name} (level {entry.course.level})`
		table.insert(names, label)
		keys[label] = entry.key
	end
	local default = CONST.NEAREST
	for label, key in pairs(keys) do
		if key == CONFIG.course then
			default = label
		end
	end
	local fields: { any } = {
		{ id = "course", kind = "choice", label = "Course", options = names, default = default },
		{
			id = "progressive",
			kind = "check",
			label = "Progressive (walk to the next course when unlocked)",
			default = CONFIG.progressive,
		},
		{ id = "highlight", kind = "check", label = "Highlight obstacles", default = CONFIG.highlight },
	}
	local rows = {}
	for _, entry in ipairs(Read.courses_by_level()) do
		table.insert(rows, {
			id = entry.key,
			label = `{entry.course.name} (level {entry.course.level})`,
			default = not CONFIG.blacklist[entry.key],
		})
	end
	table.insert(fields, {
		id = "courses",
		kind = "list",
		label = "Courses to walk to, in order (untick to skip one)",
		items = rows,
		enabled_by = "progressive",
	})
	local values = Host.form({ title = NAME, submit = "Start", fields = fields })
	if values == nil then
		return false
	end
	CONFIG.course = keys[values.course] or "auto"
	Game.apply_live(values)
	return true
end

function Game.apply_live(values: { [string]: any })
	CONFIG.progressive = values.progressive == true
	CONFIG.highlight = values.highlight == true
	local picked = values.courses :: { [string]: boolean }
	for _, entry in ipairs(Read.courses_by_level()) do
		CONFIG.blacklist[entry.key] = if picked[entry.key] == true then nil else true
	end
	if not CONFIG.highlight then
		Overlay.clear()
	end
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_live(values)
		Log.log(NAME, "Settings updated")
	end
end

function Game.set_course(course: Course)
	if course == CONST.COURSES.seers then
		course.teleport = CONFIG.seers_teleport
	end
	S.course = course
	CONST.REPORT.counters_key = ""
end

function Game.progress(): boolean
	local key, course = Read.next_course()
	if key == nil or course == nil then
		return false
	end
	local previous = S.course :: Course
	local first = course.steps[1]
	Log.log(NAME, `Agility unlocks {course.name}, walking there`)
	Overlay.clear()
	local walked, arrived =
		pcall(Walker.walk, first.start, { near = 2, plane = first.plane, accept = Read.walk_through })
	if not walked then
		Log.log(NAME, `No way to {course.name}: {arrived}`)
	end
	local state = game_state()
	if walked and arrived and Read.refresh_snapshot(state) and Read.step_of(course, snap.pos, snap.plane) > 0 then
		Game.set_course(course)
		snap.step = Read.step_of(course, snap.pos, snap.plane)
		S.marks_start = Read.marks_in_inventory() - stats.marks
		S.failures_in_row = 0
		return true
	end
	S.unreachable[key] = true
	Log.log(NAME, `Couldn't get to {course.name}, staying on {previous.name}`)
	local back = previous.steps[1]
	local went_back, why = pcall(Walker.walk, back.start, { near = 2, plane = back.plane, accept = Read.walk_through })
	if not went_back then
		Log.log(NAME, `No way back to {previous.name}: {why}`)
	end
	return false
end

function Game.choose_course(): boolean
	local pos, plane = snap.pos, snap.plane
	local course = if CONFIG.course == "auto"
		then Read.course_of(pos, plane)
		else CONST.COURSES[CONFIG.course :: string]
	if course == nil then
		Log.log(NAME, `Not at a supported course ({pos.x}, {pos.y}, plane {plane}), stopping the script`)
		return false
	end
	local level = Stats.real_level("Agility") or 0
	if level < course.level then
		Log.log(NAME, `Agility {level} is below {course.level}, {course.name} needs {course.level}`)
		return false
	end
	Game.set_course(course)
	snap.step = Read.step_of(course, pos, plane)
	Log.log(NAME, `{course.name} course, step {snap.step}`)
	return true
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	if not Game.choose_course() then
		S.finished = true
		return
	end
	S.marks_start = Read.marks_in_inventory()
	S.eat_at = Random.int(CONFIG.eat_at_hitpoints[1], CONFIG.eat_at_hitpoints[2])
	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
	if CONFIG.progressive then
		Game.progress()
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
	local key = `{stats.laps}/{stats.marks}/{stats.falls}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "laps", label = "Laps", value = stats.laps },
		{
			id = "marks",
			label = if S.course and S.course.reward then S.course.reward else "Marks of grace",
			value = stats.marks,
		},
		{ id = "falls", label = "Falls", value = stats.falls, percent_of = "laps" },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "laps" },
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
	elseif CONFIG.max_laps > 0 and stats.laps >= CONFIG.max_laps then
		Log.log(NAME, `Reached {CONFIG.max_laps} laps, stopping the script`)
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
	plan = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	local course = S.course :: Course
	if snap.step == 0 then
		return "LOST"
	end

	local hitpoints = Read.hitpoints(s)
	local digesting = snap.tick < S.ate_tick + CONST.FOOD_DELAY_TICKS
	if hitpoints and hitpoints <= S.eat_at and not digesting and not skipped["EAT"] then
		plan.food = Read.food()
		return if plan.food then "EAT" else "NO_FOOD"
	end

	local step = course.steps[snap.step]
	if course.teleport and snap.step == 1 and not skipped["TELEPORT"] then
		local start = Read.obstacle(step, snap.pos)
		if start == nil or Objects.distance(start, snap.pos) > CONST.TELEPORT.FAR then
			return "TELEPORT"
		end
	end
	if
		not course.reward
		and not skipped["MARK"]
		and ((Inventory.free_slots() or 0) > 0 or Read.marks_in_inventory() > 0)
	then
		plan.mark = Read.mark(step, snap.pos)
		if plan.mark then
			return "MARK"
		end
	end
	if step.portals and not skipped["PORTAL"] then
		plan.portal = Read.portal(step, snap.pos)
		if plan.portal then
			return "PORTAL"
		end
	end
	return "ADVANCE"
end

function Handler.fail(why: string)
	stats.failures += 1
	S.failures_in_row += 1
	Log.log(NAME, `Failed: {why} ({S.failures_in_row} in a row)`)
end

function Handler.fidget()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_async_tasks("game")
		Antiban.do_walking_antiban()
	end
end

function Handler.wait_until(done: () -> boolean, timeout_ms: number, quiet: boolean?): boolean
	local deadline = time() + timeout_ms
	while time() < deadline do
		if done() then
			return true
		end
		Overlay.update()
		if not quiet then
			Handler.fidget()
		end
		sleep(Random.int(80, 130))
	end
	return done()
end

function Handler.lost()
	Log.log(NAME, `Not on a known step ({snap.pos.x}, {snap.pos.y}, plane {snap.plane})`)
	S.failures_in_row += 1
	Biometrics.sleep(2 * CONST.TICK_MS, 8 * CONST.TICK_MS)
end

function Handler.eat()
	local hitpoints = Player.hitpoints() or 0
	Log.log(NAME, `Hitpoints at {hitpoints}, eating`)
	local food = plan.food :: Food
	if not Inventory.interact_slot(food.slot, food.option) then
		S.skip["EAT"] = true
		return
	end
	S.ate_tick = Read.current_tick(game_state())
	Handler.wait_until(function()
		return (Player.hitpoints() or 0) > hitpoints
	end, 2000)
	S.eat_at = Random.int(CONFIG.eat_at_hitpoints[1], CONFIG.eat_at_hitpoints[2])
end

function Handler.no_food()
	Log.log(NAME, `Hitpoints at {Player.hitpoints() or 0} and no food left, stopping the script`)
	S.finished = true
end

function Handler.teleport()
	local course = S.course :: Course
	local T = CONST.TELEPORT
	Log.log(NAME, "Casting the Camelot teleport")
	local cast = Magic.open() and Magic.cast(T.SPELL, T.OPTION)
	if not cast then
		Log.log(NAME, "The cast wasn't confirmed, waiting to see if we arrive")
	end
	local step = course.steps[1]
	local arrived = Handler.wait_until(function()
		local p = game_state().position
		local loc = p and Read.obstacle(step, { x = p.x, y = p.y })
		return loc ~= nil and Objects.distance(loc, p :: any) <= T.FAR
	end, T.ARRIVE_MS)
	if not arrived then
		S.skip["TELEPORT"] = true
		Handler.fail("the teleport didn't take us to the start")
		return
	end
	S.failures_in_row = 0
end

function Handler.mark()
	local item = plan.mark :: Host.GroundItem
	local before = Read.marks_in_inventory()
	if not GroundItems.interact(item, CONST.MARK.OPTION, false) then
		S.skip["MARK"] = true
		return
	end
	local took = Handler.wait_until(function()
		return Read.marks_in_inventory() > before
	end, CONST.MARK.TAKE_MS)
	if not took then
		S.skip["MARK"] = true
		Handler.fail("mark of grace not picked up")
		return
	end
	stats.marks = math.max(stats.marks, Read.marks_in_inventory() - S.marks_start)
	S.failures_in_row = 0
end

function Handler.portal()
	local loc = plan.portal :: Loc
	local index = snap.step
	Log.log(NAME, `Portal at {loc.x}, {loc.y} on step {index}`)
	local option = Read.menu_option(loc)
	if option == nil or not Objects.interact(loc, option, false) then
		S.skip["PORTAL"] = true
		return
	end
	local course = S.course :: Course
	local left = Handler.wait_until(function()
		return Read.step_here(course) ~= index
	end, CONST.PORTAL.LEAVE_MS + Objects.distance(loc, snap.pos) * CONST.WALK_MS_PER_TILE)
	if not left then
		S.skip["PORTAL"] = true
		Handler.fail("portal not taken")
		return
	end
	S.failures_in_row = 0
end

function Handler.prehover(course: Course, nxt: number)
	if not Random.chance(CONFIG.prehover) then
		return
	end
	local nxt_step = course.steps[nxt]
	local loc = Read.obstacle_on_plane(nxt_step)
	if loc == nil then
		Log.log(NAME, `Pre-hover: obstacle {nxt_step.id} of step {nxt} not found`)
		return
	end
	local landing: any = { x = nxt_step.start.x, y = nxt_step.start.y, plane = nxt_step.plane }
	local box = Objects.projected(loc :: Loc, landing)
	local cuboid = box and box.box
	if cuboid == nil then
		Log.log(NAME, `Pre-hover step {nxt}: no box to aim at`)
		return
	end
	local bottom, top = Quad.mean(cuboid.bottom), Quad.mean(cuboid.top)
	local x = bottom.x + (top.x - bottom.x) * CONST.PREHOVER.RAISE
	local y = bottom.y + (top.y - bottom.y) * CONST.PREHOVER.RAISE
	local size = 0
	for _, quad in ipairs({ cuboid.bottom, cuboid.top }) do
		for _, c in ipairs(Quad.corners(quad)) do
			size = math.max(size, math.abs(c.x - x), math.abs(c.y - y) * 2)
		end
	end
	local half = math.max(CONST.PREHOVER.MIN_HALF, CONST.PREHOVER.SPREAD * size * 2)
	local spot = Point.new(math.round(x), math.round(y))
	if not Toplevel.is_visible(spot, Toplevel.viewport(), Toplevel.blockers()) then
		Log.log(NAME, `Pre-hover step {nxt}: the obstacle is off screen or under an interface`)
		return
	end
	Mouse.move_async(Box.new(spot.x - half, spot.y - half, spot.x + half, spot.y + half))
	local aimed = true
	Log.log(NAME, `Pre-hover step {nxt}: {if aimed then "moving" else "no spot to aim at"}`)
end

function Read.shows_ahead(loc: Loc, from: Tile): boolean
	local base = Projection.base()
	local facing = Camera.yaw_degrees()
	if base == nil or facing == nil then
		return false
	end
	local tile = Projection.TILE
	local x = loc.scene_x * tile + loc.size_x * tile / 2 - ((from.x - base.x) * tile + tile / 2)
	local y = loc.scene_y * tile + loc.size_y * tile / 2 - ((from.y - base.y) * tile + tile / 2)
	local reach = math.sqrt(x * x + y * y)
	local ahead_x = (from.x - base.x) * tile + tile / 2 + reach * math.sin(math.rad(facing))
	local ahead_y = (from.y - base.y) * tile + tile / 2 + reach * math.cos(math.rad(facing))
	local cuboid = Projection.cuboid(ahead_x, ahead_y, math.max(loc.size_x, loc.size_y), nil, from)
	return cuboid ~= nil and Clickbox.target(Clickbox.from_cuboid(cuboid), loc.name or tostring(loc.id)) ~= nil
end

function Handler.precamera(course: Course, nxt: number): boolean
	local nxt_step = course.steps[nxt]
	local loc = Read.obstacle_on_plane(nxt_step)
	if loc == nil then
		return false
	end
	local landing: any = { x = nxt_step.start.x, y = nxt_step.start.y, plane = nxt_step.plane }
	local middle = { x = loc.x + (loc.size_x - 1) / 2, y = loc.y + (loc.size_y - 1) / 2 }
	local what = loc.name or tostring(loc.id)
	local function shows(): boolean
		local box = Objects.projected(loc, landing)
		return box ~= nil and Clickbox.target(box, what) ~= nil
	end
	if shows() then
		Camera.face(middle, false, landing)
		if shows() then
			return true
		end
	end
	if not Read.shows_ahead(loc, landing) then
		return false
	end
	Log.log(NAME, `Step {nxt}'s obstacle won't show from the landing, turning the camera to it`)
	Camera.look_at(middle, landing)
	return shows()
end

function Handler.finish_obstacle(course: Course, index: number, step: Step, nxt: number, distance: number): string
	local xp_before = Read.agility_xp()
	local walk_ms = math.max(0, distance - 2) * CONST.WALK_MS_PER_TILE
	local clicked_tick = Read.current_tick(game_state())
	local ignored, moved = false, false
	local started = Handler.wait_until(function()
		if Read.busy() or Read.step_here(course) == nxt or Read.server_step(course) == nxt then
			return true
		end
		local m = Host.movement()
		moved = moved or (m ~= nil and m.moving) or Player.destination() ~= nil
		ignored = not moved and Read.current_tick(game_state()) - clicked_tick >= CONST.START_TICKS
		return ignored
	end, walk_ms + step.leave * CONST.TICK_MS)
	if not started or ignored then
		return "failed"
	end

	Handler.fidget()
	Mouse.wait()
	S.camera_ready = if Handler.precamera(course, nxt) then nxt else 0
	Handler.prehover(course, nxt)
	return Handler.await_landing(course, index, step, nxt, xp_before)
end

function Handler.await_landing(course: Course, index: number, step: Step, nxt: number, xp_before: number): string
	local hp_before = Read.hitpoints(game_state())
	local function hurt(): boolean
		local hp = Read.hitpoints(game_state())
		return hp_before ~= nil and hp ~= nil and hp < hp_before
	end
	local still_since: number? = nil
	local function landed(): boolean
		if hurt() then
			return true
		end
		local at = Read.server_step(course)
		if at == nxt and (step.xp == 0 or Read.agility_xp() > xp_before) then
			return true
		end
		local s = game_state()
		local m = Host.movement()
		if at == nil or at == 0 or Read.scene_loading(s) or Read.busy() or (m ~= nil and m.moving) then
			still_since = nil
			return false
		end
		local tick = Read.current_tick(s)
		still_since = still_since or tick
		return tick - (still_since :: number) >= CONST.FALL_TICKS
	end
	Handler.wait_until(landed, CONST.OBSTACLE_MS, true)
	if hurt() then
		return "fell"
	end
	local at = Read.server_step(course) or Read.step_here(course)
	if at == nxt then
		Biometrics.sleep(CONST.REACT_MS[1], CONST.REACT_MS[2])
		return "ok"
	end
	return if at ~= index and at ~= 0 then "fell" else "failed"
end

function Handler.walk_closer(loc: Loc, step: Step)
	Log.log(NAME, `Obstacle {step.id} can't be brought on screen, walking closer`)
	Walker.walk({ x = loc.x, y = loc.y }, {
		near = CONST.WALK_UP.CLOSE,
		straight = step.plane ~= 0,
		plane = step.plane,
		timeout_ms = CONST.WALK_UP.MS,
		accept = Read.walk_through,
	})
end

function Handler.advance()
	local course = S.course :: Course
	local index = snap.step
	local step = course.steps[index]
	local nxt = step.next or (if index < #course.steps then index + 1 else 1)

	local loc = Read.obstacle(step, snap.pos)
	if loc == nil then
		return Handler.fail(`obstacle {step.id} not found at step {index}`)
	end

	local distance = Objects.distance(loc, snap.pos)
	if distance > CONST.WALK_UP.DIRECT and #step.options > 0 then
		return Handler.approach(course, index, step, nxt, loc, distance)
	end
	if distance > CONST.WALK_UP.DIRECT then
		Walker.walk({ x = loc.x, y = loc.y }, {
			near = CONST.WALK_UP.CLOSE,
			straight = step.plane ~= 0,
			plane = step.plane,
			timeout_ms = CONST.WALK_UP.MS,
			accept = Read.walk_through,
		})
		snap.pos = Walker.position() or snap.pos
	end

	local clicked = false
	for attempt = 1, CONST.CLICK_TRIES do
		if #step.options == 0 or attempt > 1 then
			local found = Read.menu_option(loc)
			if found then
				if found ~= step.options[1] then
					Log.log(NAME, `Step {index} ({step.id}) offers "{found}"`)
				end
				step.options = { found }
			end
		end
		if #step.options > 0 then
			local face = not (S.camera_ready == index and Read.on_screen(loc))
			clicked = Objects.interact(loc, step.options, false, face)
		end
		if clicked or attempt == CONST.CLICK_TRIES then
			break
		end
		local here = Walker.position() or snap.pos
		if not Read.on_screen(loc) and Objects.distance(loc, here) > CONST.WALK_UP.CLOSE then
			Handler.walk_closer(loc, step)
		else
			sleep(Random.int(300, 700))
		end
	end
	S.camera_ready = 0
	if not clicked then
		return Handler.fail(`couldn't click obstacle {step.id}`)
	end

	Handler.after_click(course, index, step, nxt, Objects.distance(loc, snap.pos))
end

function Handler.approach(course: Course, index: number, step: Step, nxt: number, loc: Loc, distance: number)
	S.camera_ready = 0
	local picked = Objects.approach(loc, step.options, {
		near = CONST.WALK_UP.CLOSE,
		walk = { straight = step.plane ~= 0, accept = Read.walk_through },
		timeout_ms = CONST.WALK_UP.MS,
		arrive_ms = false,
		closer = CONST.WALK_UP.CLOSE,
	})
	if not picked then
		return Handler.fail(`couldn't walk to and click obstacle {step.id}`)
	end
	Handler.after_click(course, index, step, nxt, distance)
end

function Handler.after_click(course: Course, index: number, step: Step, nxt: number, distance: number)
	local outcome = Handler.finish_obstacle(course, index, step, nxt, distance)
	if outcome == "fell" then
		stats.falls += 1
		Log.log(NAME, `Fell from step {index}, now at step {Read.step_here(course)}`)
		Handler.wait_until(function()
			return not Read.busy()
		end, CONST.FALL_RECOVER_TICKS * CONST.TICK_MS, true)
		Biometrics.sleep(CONST.REACT_MS[1], CONST.REACT_MS[2])
		return
	elseif outcome == "failed" then
		return Handler.fail(
			`step {index} didn't go: the click was ignored, there was no animation, or we never reached step {nxt}`
		)
	end

	S.failures_in_row = 0
	if nxt == 1 then
		stats.laps += 1
		Log.log(NAME, `Lap {stats.laps} done`)
	end
	if nxt == 1 and CONFIG.progressive then
		Game.progress()
	end
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	LOST = Handler.lost,
	EAT = Handler.eat,
	NO_FOOD = Handler.no_food,
	TELEPORT = Handler.teleport,
	MARK = Handler.mark,
	PORTAL = Handler.portal,
	ADVANCE = Handler.advance,
}
local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
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

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		close_stray()
		local began = time()
		Game.poll_settings()
		Handler.states[state]()
		Overlay.update()

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
			Antiban.do_antiban()
		end
		if time() - began < CONST.LOOP_MIN_MS then
			sleep(CONST.LOOP_SLEEP_MS)
		end
	end
	Overlay.clear()
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

Loop.run()
