--!strict
-- Rooftop agility: Canifis and Ardougne. The course is picked from where the player stands at the start.
-- Ported from the Simba script (wasp-premium/agility): the steps keep their object ids, the screen finders and map pixels became tiles.
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
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Box, Point, Quad = Geometry.Box, Geometry.Point, Geometry.Quad

local NAME = "Agility"

type Step = {
	-- the obstacle
	id: number,
	options: { string },
	-- the roof (or the ground) the player stands on while this is the next obstacle; marks of grace on it are picked up
	plane: number,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	-- where we stand when the step begins, to aim at the next obstacle from before we get there
	start: Tile,
	-- the most ticks each phase of an obstacle can take (the old script's delays): from the click to the animation starting
	-- (plus the walk there), from the animation to the next step being visible, and for the xp to arrive (0: it gives none)
	leave: number,
	enter: number,
	xp: number,
	-- ticks to wait after landing, the animation settling
	settle: number,
	-- the step this one leads to, when it isn't the one after it
	next: number?,
}

type Course = {
	name: string,
	level: number,
	-- cast the Camelot teleport back to the start when we are far from it
	teleport: boolean?,
	steps: { Step },
}

-- fixed values: ids, tiles, thresholds
-- The bounds are the old script's map boxes turned into world tiles, so they can be a tile off.
local CONST = {
	REPORT = { counters_key = "" },
	MARK = { NAME = "Mark of grace", OPTION = "Take", PAD = 1, TAKE_MS = 7000 },
	TICK_MS = 600,
	-- the poses of standing, walking and running: anything else (a rope, a ledge) is an obstacle in progress
	IDLE_POSES = { [808] = true, [819] = true, [820] = true, [821] = true, [822] = true, [823] = true, [824] = true },
	-- how long the animation must stay over: a jump is followed by its landing animation after a short gap
	IDLE_MS = 1000,
	-- the pre-hover aims this far up from the middle of the box's base (0 base, 1 top), within SPREAD of its size
	PREHOVER = { RAISE = 0.35, SPREAD = 0.15, MIN_HALF = 8 },
	-- ms allowed per tile of the walk to an obstacle that is far away
	WALK_MS_PER_TILE = 450,
	NOT_OBSTACLE_OPTIONS = { ["Walk here"] = true, Examine = true, Cancel = true, Use = true },
	TELEPORT = { SPELL = "Camelot Teleport", OPTION = "Seers'", FAR = 15, ARRIVE_MS = 8000 },
	-- a step is the one we are in when we stand inside its box, with this much room around it
	PAD = 1,
	-- the obstacle is walked to from this far, closer it is clicked where it stands
	APPROACH_DISTANCE = 10,
	-- tries at clicking an obstacle before it counts as a failure
	CLICK_TRIES = 3,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 14,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 0,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 10,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 6,
					settle = 2,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 0,
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
					enter = 8,
					xp = 4,
					settle = 1,
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
					enter = 26,
					xp = 8,
					settle = 0,
				},
			},
		} :: Course,
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

-- what the user can change
local CONFIG = {
	-- "canifis", "ardougne", or "auto" to take the one the player is standing in
	course = "auto",
	max_laps = 0, -- 0 is unlimited
	-- chance to move the mouse onto the next obstacle while the current one is still going
	prehover = 0.8,
	-- Seers' Village: cast the Camelot teleport (its Seers' option) back to the start instead of walking
	seers_teleport = false,
	-- eat one of these (item names, not case sensitive) when the hitpoints fall to this; empty list never eats
	food = { "shark", "monkfish", "lobster", "swordfish", "tuna", "trout", "salmon", "cake", "bread" },
	eat_at_hitpoints = { 12, 20 },
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { laps = 0, marks = 0, falls = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	course: Course?,
	-- marks in the inventory when we started, and the step we last clicked
	marks_start: number,
	eat_at: number,
	-- states to ignore for one loop
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	course = nil,
	marks_start = 0,
	eat_at = 0,
	skip = {},
}

type Snapshot = {
	state: ClientState,
	tick: number,
	pos: Tile,
	plane: number,
	-- index in course.steps of the step we are in, 0 when none
	step: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LOST" | "EAT" | "TELEPORT" | "MARK" | "ADVANCE"

-- what get_state found that its handler needs
type Plan = { mark: Host.GroundItem?, food: number? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

---------------------------------------------------------------------------------------------------
-- Reading the client

-- falls back to wall clock ticks
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

-- the step we stand in; a box we stand exactly in beats one we are only near, and the smallest box wins so the ground (a whole region) only counts when no roof does
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
	for _, course: Course in pairs(CONST.COURSES :: { [string]: Course }) do
		if Read.step_of(course, pos, plane) > 0 then
			return course
		end
	end
	return nil
end

function Read.refresh_snapshot(state: ClientState): boolean
	local p = state.position
	if p == nil then
		return false
	end
	local pos, plane = { x = p.x, y = p.y }, p.plane or 0
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
	for _, item in ipairs(Inventory.items() or {}) do
		if string.lower(item.name or "") == "mark of grace" then
			total += item.quantity
		end
	end
	return total
end

-- whether an obstacle animation is playing (or the pose is one of a rope or ledge)
function Read.busy(): boolean
	local me = Players.me()
	return me ~= nil and (me.animation ~= -1 or not CONST.IDLE_POSES[me.pose])
end

function Read.agility_xp(): number
	return Stats.xp("Agility") or 0
end

-- the step we stand in right now, straight from the client
function Read.step_here(course: Course): number
	local p = game_state().position
	if p == nil then
		return 0
	end
	return Read.step_of(course, { x = p.x, y = p.y }, p.plane or 0)
end

-- whether the obstacle of a step is in the scene and on screen
function Read.visible(step: Step): boolean
	local p = game_state().position
	if p == nil then
		return false
	end
	local loc = Read.obstacle(step, { x = p.x, y = p.y })
	return loc ~= nil and Objects.clickbox(loc) ~= nil
end

-- a mark of grace on the roof we stand on
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

-- the obstacle of a step, on the plane it is for
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

-- what the menu offers on an obstacle, for steps whose option we don't know or got wrong
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

-- the obstacle of a step on its own floor, found from the step's start tile and not from where we stand
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

-- slot of the first food we carry
function Read.food(): number?
	local names: { [string]: boolean } = {}
	for _, name in ipairs(CONFIG.food) do
		names[string.lower(name)] = true
	end
	for _, item in ipairs(Inventory.items() or {}) do
		if names[string.lower(item.name or "")] then
			return item.slot
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Game setup

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
	-- scene reload while logged in
	if Read.scene_loading(s) then
		sleep(100)
		return false
	end
	return Game.sign_in()
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, HOUR, SECOND = Antiban.MINUTE, Antiban.HOUR, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Agility" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
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

	-- queued without blocking: camera, hover and random tab in the game, tabs and chat outside it
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

	Antiban.add_break(30 * MINUTE, 2 * MINUTE, 0.33, 0.01)
	Antiban.add_break(45 * MINUTE, 5 * MINUTE, 0.33, 0.02)
	Antiban.add_break(
		60 * MINUTE,
		10 * MINUTE,
		0.33,
		math.floor(0.05 * Biometrics.random_double(1.0) * 100 + 0.5) / 100
	)
	Antiban.add_break(
		250 * MINUTE,
		20 * MINUTE,
		0.33,
		math.floor(0.5 * Biometrics.random_double(1.3) * 100 + 0.5) / 100
	)

	Antiban.add_sleep(
		Biometrics.sleep_hour(),
		Biometrics.sleep_length() * HOUR,
		0.1,
		0.8 * Biometrics.random_double(1.3)
	)
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

-- picks the course and checks the level; false stops the script
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
	if course == CONST.COURSES.seers then
		course.teleport = CONFIG.seers_teleport
	end
	S.course = course
	snap.step = Read.step_of(course, pos, plane)
	Log.log(NAME, `{course.name} rooftop course, step {snap.step}`)
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
end

---------------------------------------------------------------------------------------------------
-- Loop

-- resets the idle timeout on xp and reports it
function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

-- what the loader's XP tracker shows next to the skills: the totals, it works out the rates itself
function Loop.report_counters()
	local key = `{stats.laps}/{stats.marks}/{stats.falls}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "laps", label = "Laps", value = stats.laps },
		{ id = "marks", label = "Marks of grace", value = stats.marks },
		{ id = "falls", label = "Falls", value = stats.falls, percent_of = "laps" },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "laps" },
	})
end

-- stops the script when it hasn't progressed or keeps failing
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

-- time spent in antiban doesn't count as idle
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

-- reads the client and decides what to do next; handlers do it
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

	local hitpoints = Player.hitpoints()
	if hitpoints and hitpoints <= S.eat_at and not skipped["EAT"] then
		plan.food = Read.food()
		if plan.food then
			return "EAT"
		end
	end

	local step = course.steps[snap.step]
	if course.teleport and snap.step == 1 and not skipped["TELEPORT"] then
		local start = Read.obstacle(step, snap.pos)
		if start == nil or Objects.distance(start, snap.pos) > CONST.TELEPORT.FAR then
			return "TELEPORT"
		end
	end
	-- a mark needs a free slot unless we already carry a stack of them
	if not skipped["MARK"] and ((Inventory.free_slots() or 0) > 0 or Read.marks_in_inventory() > 0) then
		plan.mark = Read.mark(step, snap.pos)
		if plan.mark then
			return "MARK"
		end
	end
	return "ADVANCE"
end

---------------------------------------------------------------------------------------------------
-- Handlers

function Handler.fail(why: string)
	stats.failures += 1
	S.failures_in_row += 1
	Log.log(NAME, `Failed: {why} ({S.failures_in_row} in a row)`)
end

-- waits for something while letting the walking antiban run
function Handler.wait_until(done: () -> boolean, timeout_ms: number): boolean
	local deadline = time() + timeout_ms
	while time() < deadline do
		if done() then
			return true
		end
		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_walking_antiban()
		end
		sleep(Random.int(80, 130))
	end
	return done()
end

function Handler.lost()
	-- off the course, or on a roof the course doesn't know: wait for the scene to settle, the game moves us after a fall
	Log.log(NAME, `Not on a known step ({snap.pos.x}, {snap.pos.y}, plane {snap.plane})`)
	S.failures_in_row += 1
	Biometrics.sleep(2 * CONST.TICK_MS, 8 * CONST.TICK_MS)
end

function Handler.eat()
	local hitpoints = Player.hitpoints() or 0
	Log.log(NAME, `Hitpoints at {hitpoints}, eating`)
	if not Inventory.interact_slot(plan.food :: number, "Eat") then
		S.skip["EAT"] = true
		return
	end
	Handler.wait_until(function()
		return (Player.hitpoints() or 0) > hitpoints
	end, 2000)
	S.eat_at = Random.int(CONFIG.eat_at_hitpoints[1], CONFIG.eat_at_hitpoints[2])
end

-- casts the Camelot teleport to Seers' Village, back to the start of the course
function Handler.teleport()
	local course = S.course :: Course
	local T = CONST.TELEPORT
	Log.log(NAME, "Casting the Camelot teleport")
	-- the cast can report false even though the teleport went off, so arriving is what counts
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

-- starts the mouse towards the next obstacle, aimed at where it will be on screen once we stand at the next step's start
function Handler.prehover(course: Course, nxt: number)
	if not Random.chance(CONFIG.prehover) then
		return
	end
	local nxt_step = course.steps[nxt]
	-- the next obstacle is usually on another floor, which Objects.find doesn't list
	local loc = Read.obstacle_on_plane(nxt_step)
	if loc == nil then
		Log.log(NAME, `Pre-hover: obstacle {nxt_step.id} of step {nxt} not found`)
		return
	end
	-- where we will stand, and on which floor: the camera follows the ground there
	local landing: any = { x = nxt_step.start.x, y = nxt_step.start.y, plane = nxt_step.plane }
	local box = Objects.projected(loc :: Loc, landing)
	local cuboid = box and box.box
	if cuboid == nil then
		Log.log(NAME, `Pre-hover step {nxt}: no box to aim at`)
		return
	end
	-- the middle of the box, a little above its base because these obstacles are low; the cuboid's edges are mostly empty air
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

-- follows an obstacle after the click: the animation starts, the xp comes, the animation is over and the next step is in view;
-- the old script's delays are the limits. "ok" when we stand in the next step, "fell" when somewhere else, "failed" when nothing happened
function Handler.finish_obstacle(course: Course, index: number, step: Step, nxt: number, distance: number): string
	local tick = CONST.TICK_MS
	local xp_before = Read.agility_xp()

	-- the click is in: the mouse goes ahead to the next obstacle while we walk to this one and do it
	Handler.prehover(course, nxt)

	-- 1. the animation starts, after the walk to the obstacle
	local walk_ms = math.max(0, distance - 2) * CONST.WALK_MS_PER_TILE
	local started = Handler.wait_until(function()
		return Read.busy() or Read.step_here(course) == nxt
	end, walk_ms + step.leave * tick)
	if not started then
		return "failed"
	end

	-- 2. the xp, if it gives any (a fall gives none)
	if step.xp > 0 then
		Handler.wait_until(function()
			return Read.agility_xp() > xp_before
		end, (step.leave + step.xp) * tick)
	end

	-- 3. the animation stays over, we are in the next step and can see its obstacle
	local idle_since: number? = nil
	local function settled(): boolean
		if Read.busy() then
			idle_since = nil
			return false
		end
		local since = idle_since or time()
		idle_since = since
		if time() - since < CONST.IDLE_MS then
			return false
		end
		local now = Read.step_here(course)
		if now == nxt then
			return Read.visible(course.steps[nxt])
		end
		-- somewhere else than where we were: no need to wait for the rest
		return now ~= index and now ~= 0
	end
	Handler.wait_until(settled, (step.leave + step.enter) * tick)

	local now = Read.step_here(course)
	if now == nxt then
		return "ok"
	end
	return if now ~= index then "fell" else "failed"
end

-- clicks the obstacle of the step we are in and waits until we stand in the next one
function Handler.advance()
	local course = S.course :: Course
	local index = snap.step
	local step = course.steps[index]
	local nxt = step.next or (if index < #course.steps then index + 1 else 1)

	local loc = Read.obstacle(step, snap.pos)
	if loc == nil then
		-- the ground step covers the whole region, so the obstacle may simply be out of the scene
		return Handler.fail(`obstacle {step.id} not found at step {index}`)
	end

	-- a miss is usually the obstacle off screen after a camera change: hover it (that turns the camera) and try again;
	-- with no option known, or after a miss, the menu says what the obstacle offers
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
			if Objects.distance(loc, snap.pos) > CONST.APPROACH_DISTANCE then
				clicked = Objects.approach(loc, step.options)
			else
				clicked = Objects.interact(loc, step.options, false)
			end
		end
		if clicked or attempt == CONST.CLICK_TRIES then
			break
		end
		sleep(Random.int(300, 700))
	end
	if not clicked then
		return Handler.fail(`couldn't click obstacle {step.id}`)
	end

	local outcome = Handler.finish_obstacle(course, index, step, nxt, Objects.distance(loc, snap.pos))
	if outcome == "fell" then
		-- a failed obstacle drops us elsewhere (the ground, an earlier roof): that is part of the game, not a stuck script
		stats.falls += 1
		Log.log(NAME, `Fell from step {index}, now at step {Read.step_here(course)}`)
		sleep(Random.int(CONST.TICK_MS, 3 * CONST.TICK_MS))
		return
	elseif outcome == "failed" then
		return Handler.fail(`step {index} didn't go: no animation, or we never reached step {nxt}`)
	end

	S.failures_in_row = 0
	if nxt == 1 then
		stats.laps += 1
		Log.log(NAME, `Lap {stats.laps} done`)
	end
	if step.settle > 0 then
		sleep(Random.int(0, step.settle * CONST.TICK_MS))
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
	TELEPORT = Handler.teleport,
	MARK = Handler.mark,
	ADVANCE = Handler.advance,
}

function Loop.run()
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
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
			Antiban.do_antiban()
		end
		sleep(Random.int(60, 140))
	end
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

Loop.run()
