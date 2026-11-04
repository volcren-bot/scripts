--!strict
-- Solves the Rogues' Den maze.
--
-- The route is the sequence of tiles and obstacles a player clicks by hand, one
-- at a time (object ids and options come from the game cache). Every step is
-- position-gated: a click is only made while the player stands where the
-- previous step left them, the route the game would take is checked first, and
-- a step only counts as done once the player has arrived on the expected side.
-- A crossing (door, bars, ledge, passageway, crack) is never followed by
-- another click until the player is confirmed through, so a half finished
-- squeeze cannot become a walk around the obstacle, and a caught run cannot
-- become a walk back into the maze. Anything unexpected stops the script with
-- the player standing still.
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local GameState = require("@lib/main/game_state")
local Geometry = require("@lib/utils/math/geometry")
local GroundItems = require("@lib/main/entities/ground_items")
local Host = require("@lib/host")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Minimap = require("@lib/main/interfaces/minimap")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Walker = require("@lib/main/walker")

local NAME = "Rogues Den"

-- Camera.face runs the camera antiban now and then; here it would zoom in on a route that has to stay in view.
Camera.face_task = nil

-- what the user can change
local CONFIG = {
	-- how many rounds to do, 0 to keep going until stopped
	rounds = 0,
	-- the banker next to the maze, where whatever the safe gave is banked before the next round
	banker = "Emerald Benedict",
	-- the run trick only works while running: a round starts with at least this much run energy (percent)
	min_energy = 90,
	-- how long after a step ends the next one starts (ms): the mouse is already there, so this is the reaction time
	reaction_ms = { min = 120, max = 380 },
	-- the script stops when stuck: no stage done for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 6 },
	antiban = true,
}

type Tile = { x: number, y: number }
type Area = { x1: number, y1: number, x2: number, y2: number }
type Stage = {
	kind: "walk" | "object" | "mosaic" | "stun" | "route" | "blades",
	to: Tile,
	id: number?,
	options: { string }?,
	land: Area,
	crossing: boolean?,
	once: boolean?,
	choices: { Tile }?,
	even: boolean?,
	route: { Tile }?,
	-- the parity of the route's tile indexes that are safe to land on, when it crosses traps
	safe: number?,
	retry: boolean?,
	menu: boolean?,
	approach: boolean?,
	planned: boolean?,
	animation: number?,
	hold: { late_x: number }?,
}

local function area(x: number, y: number, r: number): Area
	return { x1 = x - r, y1 = y - r, x2 = x + r, y2 = y + r }
end

local function rect(x1: number, y1: number, x2: number, y2: number): Area
	return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

local function inside(p: Tile, a: Area): boolean
	return p.x >= a.x1 and p.x <= a.x2 and p.y >= a.y1 and p.y <= a.y2
end

local function pos(): Tile
	local p = Player.position()
	if not p then
		error("no position (logged out?)", 0)
	end
	return { x = p.x, y = p.y }
end

local function here(): string
	local p = pos()
	return `{p.x},{p.y}`
end

local ANTE = rect(3044, 4980, 3072, 4991)

-- The player must end up exactly here: the plugin marks these tiles as the safe
-- spot next to a trap, so stopping one tile short is not good enough.
local function stand(to: Tile): Stage
	return { kind = "walk", to = to, land = area(to.x, to.y, 0) }
end

local function mosaic(at: Tile, land: Area): Stage
	return { kind = "mosaic", to = at, id = 7234, options = { "Open" }, land = land, crossing = true }
end

local function stun(land: Area): Stage
	return { kind = "stun", to = { x = 3014, y = 5063 }, land = land }
end

-- Clicks one of `choices` (the last is the likeliest), and the trap (blade or pendulum) carries the player to `landing`.
local function trap_click(choices: { Tile }, landing: Tile): Stage
	return {
		kind = "walk",
		to = choices[#choices],
		choices = choices,
		land = area(landing.x, landing.y, 0),
		once = true,
		crossing = true,
	}
end

-- A hard-coded route walked as overlapping clicks. Only the route's own tiles have to be exact: `land` is past its end.
local function chain(route: { Tile }, safe: number?, land: Area): Stage
	return {
		kind = "route",
		to = route[#route],
		route = route,
		safe = safe,
		land = land,
		once = true,
		crossing = true,
	}
end

local function blades(land: Area): Stage
	return { kind = "blades", to = { x = 2969, y = 5018 }, land = land, once = true, crossing = true }
end

local function walk(to: Tile): Stage
	return { kind = "walk", to = to, land = area(to.x, to.y, 1) }
end

-- Walks to one of `choices` (the last is the likeliest) and may end anywhere on them.
local function walk_any(choices: { Tile }): Stage
	local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
	for _, tile in ipairs(choices) do
		x1, y1, x2, y2 = math.min(x1, tile.x), math.min(y1, tile.y), math.max(x2, tile.x), math.max(y2, tile.y)
	end
	return { kind = "walk", to = choices[#choices], choices = choices, land = rect(x1, y1, x2, y2) }
end

-- Where the player ends up after using each object (measured), for aiming the next pre-hover.
local LANDINGS: { [string]: Tile } = {
	["3056,4991"] = { x = 3056, y = 4992 },
	["3049,4997"] = { x = 3048, y = 4997 },
	["3024,5001"] = { x = 3023, y = 5001 },
	["2993,5004"] = { x = 2988, y = 5004 },
	["2958,5031"] = { x = 2958, y = 5035 },
	["2957,5069"] = { x = 2957, y = 5072 },
	["2955,5095"] = { x = 2955, y = 5098 },
	["2972,5097"] = { x = 2972, y = 5094 },
	["2972,5094"] = { x = 2972, y = 5093 },
	["2983,5087"] = { x = 2991, y = 5087 },
	["2993,5087"] = { x = 2993, y = 5088 },
	["3030,5079"] = { x = 3031, y = 5079 },
	["3032,5078"] = { x = 3032, y = 5077 },
	["3036,5076"] = { x = 3037, y = 5076 },
	["3039,5079"] = { x = 3040, y = 5079 },
	["3042,5076"] = { x = 3043, y = 5076 },
	["3044,5069"] = { x = 3044, y = 5068 },
	["3041,5068"] = { x = 3041, y = 5069 },
	["3040,5070"] = { x = 3039, y = 5070 },
	["3038,5069"] = { x = 3038, y = 5068 },
	["3027,5032"] = { x = 3030, y = 5033 },
	["3015,5033"] = { x = 3014, y = 5033 },
	["3010,5033"] = { x = 3009, y = 5033 },
}

local function use(at: Tile, id: number, options: { string }, land: Area?, crossing: boolean?): Stage
	local known = LANDINGS[`{at.x},{at.y}`]
	return {
		kind = "object",
		to = at,
		id = id,
		options = options,
		land = land or (if known then area(known.x, known.y, 0) else area(at.x, at.y, 3)),
		crossing = crossing,
	}
end

-- An object whose left click is a walk: pick the option from the right click menu.
local function menu(stage: Stage): Stage
	stage.menu = true
	return stage
end

-- An object too far to be listed yet: the lib walks towards it and clicks it as soon as it can.
local function approaching(stage: Stage, planned: boolean?): Stage
	stage.approach = true
	stage.planned = planned
	return stage
end

-- While this object is crossed, the menu of the next step's object is opened and held, so the pick is one click once across.
-- It is opened at the start of the crossing or, by chance, once the player has got past `late_x`.
local function holding(stage: Stage, late_x: number): Stage
	stage.hold = { late_x = late_x }
	return stage
end

-- A walk that the walker plans from the collision map, not a click on the goal.
local function planned(stage: Stage): Stage
	stage.planned = true
	return stage
end

-- Walks with the walker to exactly one of two tiles, each as likely as the other.
local function walk_either(a: Tile, b: Tile): Stage
	local stage = planned(walk_any({ a, b }))
	stage.even = true
	return stage
end

-- A step that only counts once the player has played this animation, whatever tile they stand on.
local function playing(stage: Stage, animation: number): Stage
	stage.animation = animation
	return stage
end

-- For an obstacle a pendulum fall can interrupt before the crossing starts.
local function retrying(stage: Stage): Stage
	stage.retry = true
	return stage
end

local function t(x: number, y: number): Tile
	return { x = x, y = y }
end

local CORRIDOR: { Tile } = {}
for y = 5045, 5075 do
	table.insert(CORRIDOR, t(2992, y))
end

local BLADE_LAND = rect(2965, 5016, 2967, 5020)

local STAGES: { Stage } = {
	-- Antechamber to the first squeeze, then around the blade corridor.
	use({ x = 3056, y = 4991 }, 7256, { "Open" }, rect(3052, 4992, 3060, 4994), true),
	use({ x = 3049, y = 4997 }, 7251, { "Enter" }, rect(3044, 4995, 3048, 4999), true),
	-- Any of the four tiles crosses the pendulum and ends on 3039,4999; the last is the likeliest.
	trap_click(
		{ { x = 3042, y = 4999 }, { x = 3041, y = 4999 }, { x = 3040, y = 4999 }, { x = 3039, y = 4999 } },
		{ x = 3039, y = 4999 }
	),
	walk({ x = 3029, y = 5003 }),
	use({ x = 3024, y = 5001 }, 7255, { "Open" }),
	walk({ x = 3011, y = 5005 }),
	approaching(use({ x = 2993, y = 5004 }, 7240, { "Climb" }, rect(2984, 5003, 2988, 5006), true)),

	-- Wall blade lane: they knock the player across, so it is never clicked again.
	blades(BLADE_LAND),

	-- Crush corridor and the first two squeezes.
	retrying(use({ x = 2958, y = 5031 }, 7239, { "Climb" }, rect(2956, 5034, 2960, 5038), true)),
	planned(stand({ x = 2962, y = 5050 })),
	-- TODO: with 80 Thieving, fork here: pick-lock the door at 2967,5061 (id 7246, "Pick-lock") as a shortcut.
	use({ x = 2957, y = 5069 }, 7219, { "Enter" }, rect(2955, 5072, 2959, 5076), true),
	trap_click({ { x = 2957, y = 5074 }, { x = 2957, y = 5075 }, { x = 2957, y = 5076 } }, { x = 2957, y = 5076 }),
	approaching(use({ x = 2955, y = 5095 }, 7219, { "Enter" }, rect(2953, 5098, 2957, 5102), true)),
	approaching(use({ x = 2972, y = 5097 }, 7219, { "Enter" }, nil, true)),
	use({ x = 2972, y = 5094 }, 7255, { "Open" }),

	-- One of the two ledges (south of the trap block), then the two searchable walls.
	-- An L around the spinning blades (2977..2979, 5088..5090): south-west of them, then east along their south side.
	walk_any({ { x = 2975, y = 5086 }, { x = 2976, y = 5086 }, { x = 2975, y = 5087 }, { x = 2976, y = 5087 } }),
	approaching(holding(use({ x = 2983, y = 5087 }, 7240, { "Climb" }, rect(2990, 5086, 2992, 5088), true), 2987)),
	playing(menu(use({ x = 2993, y = 5087 }, 7249, { "Search" }, rect(2991, 5086, 2996, 5090))), 2246),
	walk({ x = 2997, y = 5088 }),

	-- Grill maze.
	mosaic({ x = 3023, y = 5082 }, rect(3024, 5080, 3026, 5084)),
	use({ x = 3030, y = 5079 }, 7255, { "Open" }),
	use({ x = 3032, y = 5078 }, 7255, { "Open" }),
	use({ x = 3036, y = 5076 }, 7255, { "Open" }),
	use({ x = 3039, y = 5079 }, 7255, { "Open" }),
	use({ x = 3042, y = 5076 }, 7255, { "Open" }),
	use({ x = 3044, y = 5069 }, 7255, { "Open" }),
	use({ x = 3041, y = 5068 }, 7255, { "Open" }),
	use({ x = 3040, y = 5070 }, 7255, { "Open" }),
	use({ x = 3038, y = 5069 }, 7255, { "Open" }),

	-- Back south to the next wall trap lane (one of two): search the first wall, then run it.
	walk_either({ x = 3028, y = 5033 }, { x = 3028, y = 5034 }),
	approaching(use({ x = 3015, y = 5033 }, 7255, { "Open" }), true),
	use({ x = 3010, y = 5033 }, 7255, { "Open" }),
	stand({ x = 3000, y = 5034 }),
	planned(stand({ x = 2992, y = 5045 })),
	chain(CORRIDOR, 0, rect(2991, 5075, 2993, 5077)),
	stun(rect(3011, 5056, 3030, 5066)),
	walk({ x = 3028, y = 5056 }),
	-- After the guard: the pendulum carries a click on any of these four tiles to 3028,5051; the last is the likeliest.
	trap_click(
		{ { x = 3028, y = 5054 }, { x = 3028, y = 5053 }, { x = 3028, y = 5052 }, { x = 3028, y = 5051 } },
		{ x = 3028, y = 5051 }
	),
	trap_click(
		{ { x = 3028, y = 5050 }, { x = 3028, y = 5049 }, { x = 3028, y = 5048 }, { x = 3028, y = 5047 } },
		{ x = 3028, y = 5047 }
	),
	retrying(use({ x = 3018, y = 5047 }, 7237, { "Crack" }, rect(3040, 4960, 3075, 4992), true)),
}

local function find_listed(stage: Stage)
	local at = stage.to
	for _, loc in ipairs(Objects.find(stage.id) or {}) do
		local covers = at.x >= loc.x and at.x < loc.x + loc.size_x and at.y >= loc.y and at.y < loc.y + loc.size_y
		if covers then
			return loc
		end
	end
	return nil
end

-- The object from the game cache, for one beyond the listed range.
local function find_cached(stage: Stage): Host.Loc?
	local at = stage.to
	local p = Host.game_state().position
	if not p then
		return nil
	end
	local found = Host.cache_locs({ x1 = at.x, y1 = at.y, x2 = at.x, y2 = at.y }, { plane = p.plane })
	for _, c in ipairs(found or {}) do
		if c.id == stage.id then
			return {
				id = c.id,
				name = c.name,
				kind = 2,
				x = c.x,
				y = c.y,
				plane = c.plane,
				scene_x = c.x - (p.x - p.local_x // 128),
				scene_y = c.y - (p.y - p.local_y // 128),
				size_x = c.size_x,
				size_y = c.size_y,
				shape = c.shape,
				rotation = c.rotation,
				clickable = true,
			}
		end
	end
	return nil
end

local function find_object(stage: Stage)
	return find_listed(stage) or (if stage.approach then find_cached(stage) else nil)
end

-- The tiles the game itself would walk, so a click that cannot reach its target
-- (a trap wall is down, a door is shut) is waited out rather than made.
local function preflight(to: Tile, timeout: number, adjacent_ok: boolean): number
	local started = Host.time()
	repeat
		local me = pos()
		local route = Host.scene_route(me, to)
		if route and (route.reached or adjacent_ok) then
			local last = route.tiles[#route.tiles]
			local near = math.max(math.abs(me.x - to.x), math.abs(me.y - to.y)) <= 1
			if route.reached or near or (last and math.max(math.abs(last.x - to.x), math.abs(last.y - to.y)) <= 1) then
				return #route.tiles - 1
			end
		end
		Host.sleep(250)
	until Host.time() - started > timeout
	error(`no walkable route from {here()} to {to.x},{to.y}`, 0)
end

local function carried(id: number): number
	local count = 0
	for _, item in ipairs(Host.item_container(93) or {}) do
		if item.id == id then
			count += item.quantity
		end
	end
	return count
end

-- The jewel the maze gives on the way in and takes back when the player leaves or is thrown out.
local JEWEL = 5561

-- Inside the maze, the jewel gone means the player was thrown out: no step can finish any more.
local function check_inside(i: number)
	if i > 1 and i < #STAGES and carried(JEWEL) == 0 then
		error(`step {i}: thrown out, at {here()}`, 0)
	end
end

-- Logs each new animation the player plays, to learn what the obstacles use.
local last_animation = -1

local function track_animation(step: string)
	local id = Player.animation()
	if id ~= nil and id ~= last_animation then
		last_animation = id
		print(`  {step}: animation {id} at {here()}`)
	end
end

-- Waits until the game is done with the player: no path left to animate, the server tile still, no animation.
-- This is the fact itself, with no pause on top: the pause before the next click is `CONFIG.reaction_ms`.
local function wait_settled(timeout: number, on_poll: (() -> ())?): boolean
	local started = Host.time()
	while Player.in_transit() or Player.is_moving() or Player.is_animating() do
		if on_poll then
			on_poll()
		end
		if Host.time() - started > timeout then
			return false
		end
		Host.sleep(30)
	end
	return true
end

-- How long the player may stand doing nothing after a click before it is taken as having failed.
local IDLE_GIVE_UP_MS = 3000

local function wait_land(stage: Stage, i: number, timeout: number)
	local started = Host.time()
	local last = pos()
	local moved_at = started
	repeat
		check_inside(i)
		local p = pos()
		if p.x ~= last.x or p.y ~= last.y or Player.in_transit() or Player.is_animating() then
			last, moved_at = p, Host.time()
		elseif Host.time() - moved_at > IDLE_GIVE_UP_MS and not inside(p, stage.land) then
			break
		end
		if inside(p, stage.land) then
			if stage.crossing or stage.kind ~= "walk" then
				wait_settled(10000, function()
					track_animation(`{stage.to.x},{stage.to.y}`)
				end)
			end
			if inside(pos(), stage.land) then
				return
			end
		end
		Host.sleep(60)
	until Host.time() - started > timeout
	error(`step {i}: ended at {here()}, outside {stage.land.x1}..{stage.land.x2},{stage.land.y1}..{stage.land.y2}`, 0)
end

-- Where the player will stand when this step is done.
local function arrival(stage: Stage): Tile
	if stage.kind == "walk" and not stage.once then
		return stage.to
	end
	local known = LANDINGS[`{stage.to.x},{stage.to.y}`]
	if known then
		return known
	end
	local l = stage.land
	return { x = (l.x1 + l.x2) // 2, y = (l.y1 + l.y2) // 2 }
end

-- Moves the mouse over the next step, aimed as the screen will show it once the current step has put the player at `at`.
local function prehover(j: number, at: Tile)
	local nxt = STAGES[j]
	if not nxt then
		return
	end
	if nxt.kind == "walk" then
		Walker.hover_tile_async(nxt.to, at)
		return
	end
	if not nxt.id then
		return
	end
	local loc = find_object(nxt)
	if loc then
		Objects.hover_async(loc, at)
	end
end

-- Where the walker hands over to the blade click: the east end of the lane, a few tiles short of the blades.
local BLADE_APPROACH = { x = 2972, y = 5016 }
-- The lane tile 2969,5018 is the quickest; its neighbours on the lane are used now and then.
local NEIGHBOUR_CHANCE = 0.1

local function blade_lane_tile(): number
	if Biometrics.random_boolean(NEIGHBOUR_CHANCE) then
		return if math.random(2) == 1 then 5017 else 5019
	end
	return 5018
end

-- Whether `goal` is the destination the player now has. A tile off is a miss: on a trap route that is what ejects.
local function placed(goal: Tile): boolean
	local destination = Host.game_state().destination
	return destination ~= nil and destination.x == goal.x and destination.y == goal.y
end

-- Clicks the tile; when it can't be seen from the camera as it is (the walker's fidgets and the antiban move it), the
-- camera is raised and zoomed out a notch and it is tried again. The minimap, which is only as exact as a tile, is the last resort.
local function click_goal(goal: Tile): boolean
	for attempt = 1, 4 do
		local me = pos()
		if (me.x == goal.x and me.y == goal.y) or Walker.click_tile(goal) or placed(goal) then
			return true
		end
		if attempt < 4 then
			local zoom = Camera.zoom()
			print(`  {goal.x},{goal.y} not clickable from {here()}, raising and zooming out the camera`)
			Camera.set_pitch(Camera.PITCH_MAX)
			if zoom then
				Camera.set_zoom(math.max(Camera.ZOOM_MIN, zoom - 96))
			end
		end
	end
	return Walker.click_minimap(goal)
end

-- the animation of a blade or pendulum knocking the player back
local KNOCKED = 1115

-- East of the blades, where a click that missed them leaves the player: they are clicked again from there.
local LANE_EAST = rect(2970, 5016, 2974, 5019)
-- everything between the ledge and the blades: the player there is still on the blade stage
local BLADE_SECTION = rect(2969, 4996, 2983, 5020)
local LANE_TILE = { x = 2969, y = 5018 }
-- from the wall search to the mosaic door: the player there is still on the mosaic stage, picking up the tile
local MOSAIC_SECTION = rect(2998, 5078, 3023, 5090)

-- Whether the blades have the player: they knock them across, so the lane must not be clicked again.
local function in_blades(): boolean
	return inside(pos(), BLADE_LAND) or Player.animation() == KNOCKED
end

-- Whether the game took the click as a walk into the lane. A click on any other tile walks the long way around the blades.
local function into_lane(before: Tile?): boolean
	local destination = nil
	local deadline = Host.time() + 600
	repeat
		destination = Host.game_state().destination
		if destination and not (before and destination.x == before.x and destination.y == before.y) then
			break
		end
		Host.sleep(40)
	until Host.time() > deadline
	return destination ~= nil and destination.x == LANE_TILE.x and math.abs(destination.y - LANE_TILE.y) <= 1
end

-- The blades' tile of the lane's row, clicked as a tile. A click that sends the player anywhere else is made again.
local function click_blade(y: number): boolean
	for _ = 1, 4 do
		local before = Host.game_state().destination
		local clicked = click_goal({ x = LANE_TILE.x, y = y })
		if in_blades() or (clicked and into_lane(before)) then
			return true
		end
		print(`  the blade click at {LANE_TILE.x},{y} did not go into the blades, clicking again`)
	end
	return false
end

local function cross_blades(i: number)
	if not inside(pos(), LANE_EAST) then
		local ok = Walker.walk(BLADE_APPROACH, { straight = true, near = 3 })
		if not ok and not inside(pos(), LANE_EAST) then
			error(`step {i}: the walker did not get to the blades, at {here()}`, 0)
		end
	end
	if not click_blade(blade_lane_tile()) then
		error(`step {i}: could not click the blades from {here()}`, 0)
	end
	-- the blades can stop the player a tile short of them
	wait_settled(4000)
	if not in_blades() and inside(pos(), LANE_EAST) then
		print(`  stopped beside the blades at {here()}, clicking them again`)
		if not click_blade(LANE_TILE.y) then
			error(`step {i}: could not click the blades from {here()}`, 0)
		end
	end
end

-- The run trick: the player may stand on any tile, but every tile clicked on a trap strip must have the safe parity.
-- When the destination the game took is not one (a click lands a tile off), the nearest safe tile of the route is clicked at once.
local function fix_destination(route: { Tile }, safe: number, i: number)
	local destination = nil
	local deadline = Host.time() + 400
	repeat
		destination = Host.game_state().destination
		if destination == nil then
			Host.sleep(40)
		end
	until destination ~= nil or Host.time() > deadline
	if destination == nil then
		return
	end
	for idx, tile in ipairs(route) do
		if tile.x == destination.x and tile.y == destination.y and (idx - 1) % 2 ~= safe then
			local target = route[idx + 1] or route[idx - 1]
			print(`  clicked {destination.x},{destination.y}, a trap tile: clicking {target.x},{target.y}`)
			if not click_goal(target) then
				error(`step {i}: {target.x},{target.y} could not be clicked from {here()}`, 0)
			end
			return
		end
	end
end

-- Walks a hard-coded route as overlapping clicks: the next one is made while the player is still moving.
local function follow_route(route: { Tile }, i: number, safe: number?)
	local me = pos()
	local from, nearest = 0, 3
	for k, tile in ipairs(route) do
		local distance = math.max(math.abs(tile.x - me.x), math.abs(tile.y - me.y))
		if distance <= nearest then
			from, nearest = k, distance
		end
	end
	if from == 0 then
		error(`step {i}: {me.x},{me.y} is not near the route`, 0)
	end
	local clicks: { Tile } = {}
	local k = from
	while k < #route do
		k = math.min(#route, k + math.random(6, 8))
		if #route - k < 4 then
			k = #route
		end
		if safe and (k - 1) % 2 ~= safe then
			k = if k < #route then k + 1 else k - 1
		end
		table.insert(clicks, route[k])
	end
	for n, goal in ipairs(clicks) do
		if not click_goal(goal) then
			error(`step {i}: {goal.x},{goal.y} could not be clicked from {here()}`, 0)
		end
		if safe then
			fix_destination(route, safe, i)
		end
		local nxt = clicks[n + 1]
		if nxt then
			Walker.hover_tile_async(nxt, goal)
			local lead = math.random(3, 4)
			local started = Host.time()
			local at, moved_at = pos(), Host.time()
			local reached = false
			local fidget_at = if not safe and math.random() < 0.6 then started + math.random(400, 1200) else nil
			repeat
				Host.sleep(60)
				local p = pos()
				if p.x ~= at.x or p.y ~= at.y then
					at, moved_at = p, Host.time()
				end
				reached = math.max(math.abs(p.x - goal.x), math.abs(p.y - goal.y)) <= lead and Walker.on_screen(nxt)
				if fidget_at and Host.time() >= fidget_at then
					fidget_at = nil
					if math.max(math.abs(p.x - goal.x), math.abs(p.y - goal.y)) > lead + 2 then
						if math.random() < 0.7 then
							AntibanTasks.tiny_camera_rotation()
						else
							AntibanTasks.tiny_zoom_change()
						end
					end
				end
			-- standing still short of the goal: the next click goes out at once
			until reached or Host.time() - started > 20000 or Host.time() - moved_at > 2500
		end
	end
	wait_settled(20000)
end

-- Waits until the click has played out: true once the player stands on the step's tile, false if they stopped elsewhere.
local function wait_arrival(stage: Stage, i: number): boolean
	local goal = arrival(stage)
	local started, idle_since = Host.time(), Host.time()
	while Host.time() - started < 20000 do
		check_inside(i)
		local p = pos()
		if p.x == goal.x and p.y == goal.y then
			return true
		end
		local busy = Player.in_transit() or Player.is_moving() or Player.is_animating()
		if busy then
			idle_since = Host.time()
		elseif inside(p, stage.land) then
			return true
		elseif Host.time() - idle_since > 600 then
			return false
		end
		Host.sleep(30)
	end
	error(`step {i}: still walking after 20s, at {here()}`, 0)
end

local function walk_to(stage: Stage, i: number)
	local goal = stage.to
	if stage.planned then
		if inside(pos(), stage.land) then
			return
		end
		if not Walker.walk(goal, { near = 0 }) then
			error(`step {i}: the walker could not get to {goal.x},{goal.y} from {here()}`, 0)
		end
		wait_settled(3000)
		return
	end
	local tried_minimap = false
	for _ = 1, 16 do
		local me = pos()
		if inside(me, stage.land) then
			return
		end
		local clicked = click_goal(goal)
		if not clicked then
			error(`step {i}: {goal.x},{goal.y} could not be clicked from {here()}`, 0)
		end
		prehover(i + 1, arrival(stage))
		if wait_arrival(stage, i) or stage.once then
			return
		end
		local now = pos()
		if now.x == me.x and now.y == me.y then
			if tried_minimap or not Walker.click_minimap(goal) then
				error(`step {i}: the click did not move the player from {here()}`, 0)
			end
			tried_minimap = true
			wait_arrival(stage, i)
		end
	end
	error(`step {i}: did not reach {goal.x},{goal.y}, at {here()}`, 0)
end

local held: { loc: Host.Loc, option: string }? = nil

-- Right clicks the next step's object and rests the mouse on its option, ready to be clicked.
local function open_held_menu(nxt: Stage): boolean
	local loc = find_object(nxt)
	if not loc or not Objects.hover(loc) then
		return false
	end
	Mouse.click(nil, "right")
	local started = Host.time()
	while not Minimenu.is_open() and Host.time() - started < 1500 do
		Host.sleep(40)
	end
	if not Minimenu.is_open() then
		return false
	end
	local option = (nxt.options or { "Open" })[1]
	local index = Minimenu.find(option, loc.name)
	local row = if index then Minimenu.row(index) else nil
	if not row then
		Minimenu.close()
		return false
	end
	Mouse.move(row)
	held = { loc = loc, option = option }
	return true
end

-- The pre-hover has put the mouse on the object: click it at once, and check that the client took it for the right option.
local function fast_click(loc: Host.Loc, options: { string }): boolean
	if Minimenu.is_open() or not Objects.hovered(loc) then
		return false
	end
	-- same-id neighbours (the grills) pass the hover check, so the mouse must also be inside this one's own box
	local box, at = Objects.clickbox(loc), Mouse.position()
	if not box or not at or not Geometry.Polygon.contains(box.polygon, at) then
		return false
	end
	local top = Minimenu.entries()
	local entry = top and top[1]
	if not entry or not Objects.owns(loc, entry) then
		return false
	end
	local wanted = false
	for _, option in ipairs(options) do
		if Minimenu.matches(entry, option, nil) then
			wanted = true
		end
	end
	if not wanted then
		return false
	end
	local before = Minimenu.clicked()
	Mouse.click(nil)
	local clicked = Minimenu.wait_click(before)
	if clicked == nil then
		return false
	end
	for _, option in ipairs(options) do
		if Minimenu.matches(clicked.entry, option, nil) then
			return true
		end
	end
	return false
end

local function last_chat_uid(): number
	local seen = Host.chat_messages() or {}
	return if #seen > 0 then seen[#seen].uid else 0
end

-- The game's refusals that mean the click did nothing and should be made again.
local REFUSALS = { "can't reach that", "won't open" }

local function refused_since(mark: number): string?
	for _, message in ipairs(Host.chat_messages() or {}) do
		if message.uid > mark then
			for _, text in ipairs(REFUSALS) do
				if string.find(message.text, text, 1, true) then
					return text
				end
			end
		end
	end
	return nil
end

-- Follows a click on an object to its end: across, refused by the game, knocked back on the way, or nothing happened.
-- A knock isn't over with its animation: the trap carries the player one more tile, and a click made before then is refused.
local function play_out(stage: Stage, i: number, mark: number): (string, string?)
	local nxt = STAGES[i + 1]
	local late = stage.hold ~= nil and Biometrics.random_boolean(0.5)
	local last_try, knocked, seen = 0, false, stage.animation == nil
	local idle_since = Host.time()
	while true do
		check_inside(i)
		track_animation(`{stage.to.x},{stage.to.y}`)
		local animation = Player.animation()
		seen = seen or animation == stage.animation
		if seen and inside(pos(), stage.land) then
			return "done"
		end
		local refusal = refused_since(mark)
		if refusal then
			return "refused", refusal
		end
		knocked = knocked or animation == KNOCKED
		if Player.in_transit() or Player.is_moving() or Player.is_animating() then
			idle_since = Host.time()
		elseif knocked and stage.retry then
			return "knocked"
		elseif Host.time() - idle_since > IDLE_GIVE_UP_MS then
			return "idle"
		end
		if stage.hold and nxt and not held and Host.time() - last_try > 700 then
			if not late or pos().x >= stage.hold.late_x then
				last_try = Host.time()
				open_held_menu(nxt)
			end
		end
		Host.sleep(60)
	end
end

-- Whether a click went to this object. Same-id neighbours (two walls, two ledges) have identical menu rows; what tells them
-- apart is the destination the click gives the client, which is the tile of the object clicked. No new one says nothing.
local function went_to(loc: Host.Loc, previous: Tile?): boolean
	local deadline = Host.time() + 300
	repeat
		local to = Host.game_state().destination
		if to and not (previous and to.x == previous.x and to.y == previous.y) then
			return to.x >= loc.x and to.x < loc.x + loc.size_x and to.y >= loc.y and to.y < loc.y + loc.size_y
		end
		Host.sleep(20)
	until Host.time() > deadline
	return true
end

local function use_object(stage: Stage, i: number)
	local loc = find_object(stage)
	if not loc then
		error(`step {i}: no object {stage.id} at {stage.to.x},{stage.to.y}`, 0)
	end
	local clicks = 0
	for attempt = 1, 4 do
		local used = false
		local mark = last_chat_uid()
		local previous = Host.game_state().destination
		local reuse = held
		held = nil
		if stage.menu and reuse and reuse.loc.x == loc.x and reuse.loc.y == loc.y and Minimenu.is_open() then
			local before = Minimenu.clicked()
			Mouse.click(nil)
			local clicked = Minimenu.wait_click(before)
			used = clicked ~= nil and Minimenu.matches(clicked.entry, reuse.option, loc.name)
			if not used and Minimenu.is_open() then
				Minimenu.close()
			end
		elseif stage.menu then
			if Minimenu.is_open() then
				Minimenu.close()
			end
			if stage.approach and math.max(math.abs(pos().x - loc.x), math.abs(pos().y - loc.y)) > 6 then
				Walker.walk({ x = loc.x, y = loc.y }, { near = 5 })
			end
			used = Objects.hover(loc)
			if used then
				local before = Minimenu.clicked()
				Mouse.click(nil, "right")
				local opened = Host.time()
				while not Minimenu.is_open() and Host.time() - opened < 1500 do
					Host.sleep(40)
				end
				used = Minimenu.is_open()
					and Minimenu.select((stage.options or { "Open" })[1], loc.name)
					and Minimenu.wait_click(before) ~= nil
				if not used and Minimenu.is_open() then
					Minimenu.close()
				end
			end
		elseif stage.approach then
			used = Objects.approach(
				loc,
				stage.options or { "Open" },
				{ walk = { straight = not stage.planned }, arrive_ms = false }
			)
			if not used then
				print(`  approach to {loc.name} at {loc.x},{loc.y} returned false from {here()}`)
			end
		else
			local options = stage.options or { "Open" }
			used = (attempt == 1 and fast_click(loc, options)) or Objects.interact(loc, options, false, true)
		end
		if not used then
			-- a click made on the way can land after the call gave up on it
			local waited = Host.time()
			while not used and Host.time() - waited < 1500 do
				if Player.is_animating() or (stage.animation == nil and inside(pos(), stage.land)) then
					used = true
				else
					Host.sleep(100)
				end
			end
		end
		if not used then
			if clicks == 0 and attempt < 3 then
				print(`  could not use {loc.name} yet, trying again`)
				Host.sleep(700)
				continue
			end
			error(`step {i}: could not use {loc.name} at {loc.x},{loc.y}`, 0)
		end
		if not stage.approach and not went_to(loc, previous) then
			print(`  the click on {loc.name} went to its neighbour, clicking again`)
			continue
		end
		clicks += 1
		if not stage.hold then
			prehover(i + 1, arrival(stage))
		end
		local outcome, refusal = play_out(stage, i, mark)
		if outcome == "done" then
			return
		end
		if outcome == "refused" then
			print(`  "{refusal}" for {loc.name} at {loc.x},{loc.y} from {here()}, trying again`)
			wait_settled(3000)
			Host.sleep(Random.int(400, 900))
		elseif not stage.retry and not stage.animation then
			error(`step {i}: {loc.name} at {loc.x},{loc.y} did nothing, at {here()}`, 0)
		else
			print(`  not across yet at {here()}, clicking {loc.name} again`)
		end
	end
	error(`step {i}: could not get across {loc.name} at {loc.x},{loc.y}, at {here()}`, 0)
end

local TILE_ITEM = 5568
local TILE_AT = { x = 3018, y = 5080 }
local MOSAIC_UI = "roguesden_mosaic"
local MOSAIC_GROUP = 688
-- The four corner pieces of the puzzle, the bottom right one first (the usual answer).
local MOSAIC_PIECES = { 5, 6, 7, 8 }

local function solve_mosaic(stage: Stage, i: number)
	if carried(TILE_ITEM) == 0 then
		local tile = nil
		for _, item in ipairs(GroundItems.find(TILE_ITEM) or {}) do
			if item.x == TILE_AT.x and item.y == TILE_AT.y then
				tile = item
			end
		end
		local here = pos()
		local distance = math.max(math.abs(here.x - TILE_AT.x), math.abs(here.y - TILE_AT.y))
		if not tile or not GroundItems.approach(tile, "Take", { walk = { straight = true }, arrive_ms = false }) then
			error(`step {i}: the tile is neither carried nor on the ground`, 0)
		end
		local door = find_object(stage)
		if door then
			Objects.hover_async(door, TILE_AT)
		end
		local deadline = Host.time() + 3000 + distance * 700
		while carried(TILE_ITEM) == 0 and Host.time() < deadline do
			Host.sleep(100)
		end
		if carried(TILE_ITEM) == 0 then
			error(`step {i}: could not take the tile`, 0)
		end
	end
	for _, piece in ipairs(MOSAIC_PIECES) do
		if inside(pos(), stage.land) then
			return
		end
		if not Toplevel.is_open(MOSAIC_UI) then
			local loc = find_object(stage)
			if not loc then
				error(`step {i}: no object {stage.id} at {stage.to.x},{stage.to.y}`, 0)
			end
			local opened = false
			for _ = 1, 3 do
				opened = Objects.interact(loc, "Open", 15000, true)
				if opened then
					break
				end
				Host.sleep(500)
			end
			if not opened then
				error(`step {i}: could not open the mosaic door`, 0)
			end
			local started = Host.time()
			while not Toplevel.is_open(MOSAIC_UI) and Host.time() - started < 5000 do
				Host.sleep(150)
			end
		end
		local w = Host.widget(MOSAIC_GROUP, piece)
		if not w then
			error(`step {i}: the mosaic piece {piece} is missing`, 0)
		end
		Mouse.move({ x = w.x + w.width / 2, y = w.y + w.height / 2 })
		-- "Select" is the piece's left click: once it is the top entry, it is clicked
		local hovered = Host.time()
		local top = nil
		repeat
			local entries = Minimenu.entries()
			top = entries and entries[1]
			if top and Minimenu.matches(top, "Select", nil) then
				break
			end
			Host.sleep(25)
		until Host.time() - hovered > 1500
		if not (top and Minimenu.matches(top, "Select", nil)) then
			error(`step {i}: mosaic piece {piece} did not offer "Select"`, 0)
		end
		Mouse.click(nil)
		local started = Host.time()
		while not inside(pos(), stage.land) and Host.time() - started < 6000 do
			Host.sleep(150)
		end
	end
end

local POWDER = 5559
local POWDER_AT = { x = 3009, y = 5063 }
-- Where the patrol guard can be met: its beat and the ground it crosses when it comes for the player. The other guard
-- walks north of a wall, past the top of this.
local GUARD_AREA = rect(2998, 5055, 3027, 5067)

local function find_guard(): Host.Npc?
	local at = pos()
	local best, best_distance = nil, math.huge
	for _, n in ipairs(Npcs.find("Rogue Guard") or {}) do
		local distance = math.max(math.abs(n.x - at.x), math.abs(n.y - at.y))
		if inside({ x = n.x, y = n.y }, GUARD_AREA) and distance < best_distance then
			best, best_distance = n, distance
		end
	end
	return best
end

local function powder_slot(): number?
	for _, it in ipairs(Host.item_container(93) or {}) do
		if it.id == POWDER then
			return it.slot
		end
	end
	return nil
end

-- One try of the powder on the guard. The stack going down at any moment is the success. Failed: it did not go down within
-- 10 s, or the player stood still for 1.5 s after the click with it unchanged (the throw comes a tick or two after a click
-- from in range, so a player that never moves is normal for that long).
local function throw_powder(before: number): boolean
	local slot = powder_slot()
	local guard = find_guard()
	if not slot or not guard or not Inventory.select_slot(slot) then
		return false
	end
	if not Npcs.interact(guard, "Use", false) then
		return false
	end
	local deadline = Host.time() + 10000
	local still_since = Host.time()
	while Host.time() < deadline do
		if carried(POWDER) < before then
			return true
		end
		if Player.is_moving() then
			still_since = Host.time()
		elseif Host.time() - still_since > 1500 then
			return carried(POWDER) < before
		end
		Host.sleep(50)
	end
	return carried(POWDER) < before
end

-- Takes flash powder, stuns the guard on the way and leaves at once: the next step runs past while it is stunned.
-- The guard comes for a player it sees, so there is no standing around between the two.
local function stun_guard(i: number)
	if not powder_slot() then
		local found = nil
		for _, it in ipairs(GroundItems.find(POWDER) or {}) do
			if it.x == POWDER_AT.x and it.y == POWDER_AT.y then
				found = it
			end
		end
		local me = pos()
		local distance = math.max(math.abs(me.x - POWDER_AT.x), math.abs(me.y - POWDER_AT.y))
		if not found or not GroundItems.approach(found, "Take", { walk = { straight = true }, arrive_ms = false }) then
			error(`step {i}: no flash powder to take`, 0)
		end
		local deadline = Host.time() + 3000 + distance * 700
		while not powder_slot() and Host.time() < deadline do
			check_inside(i)
			Host.sleep(50)
		end
		if not powder_slot() then
			error(`step {i}: could not take the flash powder`, 0)
		end
	end
	local started = Host.time()
	while not find_guard() and Host.time() - started < 40000 do
		check_inside(i)
		Host.sleep(100)
	end
	local before = carried(POWDER)
	for attempt = 1, 3 do
		if throw_powder(before) then
			prehover(i + 1, pos())
			return
		end
		check_inside(i)
		print(`  the powder did not reach the guard (try {attempt}), trying again`)
		Host.sleep(300)
	end
	error(`step {i}: the powder never reached the guard`, 0)
end

local START = { x = 3056, y = 4988 }
-- the maze proper: the lobby is south of it
local MAZE_AREA = rect(2940, 4992, 3075, 5125)

local stats = { runs = 0, rewards = 0, failures = 0 }
local report = StatsReport.new()
local chat_mark = 0

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	last_progress_at: number,
	failures_in_row: number,
	counters_key: string,
	-- the stage last attempted: a failure near it is retried from where the player stands
	last_stage: number?,
	-- thrown out of the maze: the next round starts at once, with no lobby pause
	restarted: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	last_progress_at = 0,
	failures_in_row = 0,
	counters_key = "",
	last_stage = nil,
	restarted = false,
}

type State = "LOADING" | "LOGIN" | "MAZE" | "BANK" | "TO_START"

local plan: { stage: number?, retry: boolean? } = {}

local function blade_stage(): number
	for i, stage in ipairs(STAGES) do
		if stage.kind == "blades" then
			return i
		end
	end
	error("the course has no blade stage", 0)
end

-- The stage to do next from where the player stands: the one after the last that ended here, 1 at the start, nil when
-- the course can't be resumed from here.
local function resume_index(): number?
	local at = pos()
	if inside(at, LANE_EAST) or inside(at, BLADE_SECTION) then
		return blade_stage()
	end
	if inside(at, MOSAIC_SECTION) then
		for i, stage in ipairs(STAGES) do
			if stage.kind == "mosaic" then
				return i
			end
		end
	end
	local from = 0
	for i = 1, #STAGES - 1 do
		local landing = arrival(STAGES[i])
		if at.x == landing.x and at.y == landing.y then
			from = i + 1
		end
	end
	if from == 0 then
		for i = 1, #STAGES - 1 do
			if inside(at, STAGES[i].land) then
				from = i + 1
			end
		end
	end
	if from > 0 then
		return from
	end
	if inside(at, ANTE) then
		return 1
	end
	return nil
end

-- The course clicks far ahead, so the camera stays high and zoomed out; the lobby's antiban can leave it anywhere.
local MAZE_PITCH_SLACK = 200
local MAZE_ZOOM_MAX = 200

local function maze_camera()
	local pitch, zoom = Camera.pitch(), Camera.zoom()
	if pitch and pitch < Camera.PITCH_MAX - MAZE_PITCH_SLACK then
		Camera.set_pitch(Camera.PITCH_MAX)
	end
	if zoom and zoom > MAZE_ZOOM_MAX then
		Camera.set_zoom(Camera.ZOOM_MIN)
	end
end

local function do_stage(i: number, retry: boolean?)
	local stage = STAGES[i]
	local prev = STAGES[i - 1]
	maze_camera()
	local p = pos()
	if prev and not retry and not inside(p, prev.land) then
		error(`step {i}: at {p.x},{p.y}, expected to be where step {i - 1} ended`, 0)
	end
	local steps = preflight(stage.to, if stage.kind ~= "walk" then 8000 else 4000, stage.kind ~= "walk")
	print(`{i}: {stage.kind} {stage.to.x},{stage.to.y} from {p.x},{p.y}, {steps} steps`)
	local stage_started = Host.time()
	if i == #STAGES then
		chat_mark = last_chat_uid()
	end
	if stage.choices then
		if stage.even then
			stage.to = stage.choices[if Biometrics.random_boolean(0.5) then 1 else 2]
		else
			stage.to = stage.choices[Biometrics.random_mode_integer(#stage.choices - 1, 0, #stage.choices - 1) + 1]
		end
	end
	if stage.kind == "walk" then
		walk_to(stage, i)
	elseif stage.kind == "route" then
		follow_route(stage.route :: { Tile }, i, stage.safe)
	elseif stage.kind == "blades" then
		cross_blades(i)
	elseif stage.kind == "mosaic" then
		solve_mosaic(stage, i)
	elseif stage.kind == "stun" then
		stun_guard(i)
	else
		use_object(stage, i)
	end
	if stage.kind ~= "stun" then
		wait_land(stage, i, if stage.crossing then 20000 else 12000)
	end
	print(`  ok {here()} {math.floor(Host.time() - stage_started)} ms, energy {math.floor(Player.run_energy() or 0)}%`)
end

local function finish_round()
	local failed = false
	for _, message in ipairs(Host.chat_messages() or {}) do
		if message.uid > chat_mark and string.find(message.text, "slip and trigger", 1, true) then
			failed = true
		end
	end
	stats.runs += 1
	if not failed then
		stats.rewards += 1
	end
	S.last_stage = nil
	print(if failed then "round done, but the safe was not cracked (no reward)" else "round done")
end

local function carrying(): boolean
	for _, item in ipairs(Host.item_container(93) or {}) do
		if item.id ~= -1 and item.id ~= JEWEL then
			return true
		end
	end
	return false
end

local BANKER_AT = { x = 3043, y = 4973 }

-- The maze takes nothing in, so whatever the safe gave goes to the bank first.
local function bank_rewards()
	local banker = Npcs.nearest(CONFIG.banker, pos())
	local waited = Host.time()
	while not banker and Host.time() - waited < 5000 do
		Host.sleep(250)
		banker = Npcs.nearest(CONFIG.banker, pos())
	end
	if not banker then
		-- the lobby right after the safe: the banker stands out of sight, so the player goes to where he usually is
		Walker.walk(BANKER_AT, { near = 3 })
		banker = Npcs.nearest(CONFIG.banker, pos())
	end
	if not banker then
		error(`carrying items but {CONFIG.banker} is not in sight`, 0)
	end
	print(`banking at {CONFIG.banker}`)
	if not Bankmain.open({ npc = banker }) then
		error(`could not open the bank with {CONFIG.banker}`, 0)
	end
	if not Bankmain.deposit_inventory() then
		error("could not deposit the inventory", 0)
	end
	local started = Host.time()
	while carrying() and Host.time() - started < 4000 do
		Host.sleep(100)
	end
	Bankmain.close()
	if carrying() then
		error("could not bank everything", 0)
	end
end

local function to_start()
	if not Walker.walk(START, { near = 0, transports = false }) then
		error("could not walk back to the start of the maze", 0)
	end
end

-- Game setup

local function sign_in(): boolean
	Log.log(NAME, "Logging in")
	if not Login.sign_in() then
		Log.log(NAME, "Login failed")
		Host.sleep(5000)
		return false
	end
	return true
end

local function scene_loading(s: Host.ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

local function setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	AntibanTasks.skills = { "Thieving", "Agility" }
	-- only ever run in the lobby: the maze needs every click
	Antiban.add_task(AntibanTasks.adjust_camera, 3 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.lose_focus, 10 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_tab, 70 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_chat_tab, 80 * SECOND, 0.4, "outside")
	-- breaks and sleeps come from the loader's Breaks tab
	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

local function setup()
	while true do
		local s = Host.game_state()
		if s.game_state == GameState.LOGGED_IN and s.position ~= nil then
			break
		end
		if not scene_loading(s) then
			sign_in()
		end
		Host.sleep(100)
	end
	if CONFIG.antiban and not S.antiban_ready then
		setup_antiban()
	end
end

-- Loop

local function report_counters()
	local key = `{stats.runs}/{stats.rewards}/{stats.failures}`
	if key == S.counters_key then
		return
	end
	S.counters_key = key
	Host.report_counters({
		{ id = "runs", label = "Rounds", value = stats.runs },
		{ id = "rewards", label = "Rewards", value = stats.rewards, percent_of = "runs" },
		{ id = "failures", label = "Thrown out", value = stats.failures },
	})
end

-- The stage that ends nearest to the player, for a position the course doesn't know.
local function nearest_stage(): number
	local at = pos()
	local best, best_distance = 1, math.huge
	for i = 1, #STAGES - 1 do
		local landing = arrival(STAGES[i])
		local distance = math.max(math.abs(at.x - landing.x), math.abs(at.y - landing.y))
		if distance < best_distance then
			best, best_distance = i, distance
		end
	end
	return best
end

-- Reads the client and decides what to do next; the handlers do it.
local function get_state(): State
	plan = {}
	local s = Host.game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if scene_loading(s) then "LOADING" else "LOGIN"
	end
	StatsReport.update(report, s.skills)
	report_counters()
	if S.last_stage and S.last_stage > 1 and carried(JEWEL) == 0 then
		Log.log(NAME, `Thrown out of the maze at step {S.last_stage}, starting over`)
		stats.failures += 1
		S.last_stage = nil
		S.restarted = true
	end
	local index = resume_index()
	plan.stage = index
	plan.retry = index ~= nil
		and (inside(pos(), LANE_EAST) or inside(pos(), BLADE_SECTION) or inside(pos(), MOSAIC_SECTION))
	if index and index > 1 then
		return "MAZE"
	end
	if not index and inside(pos(), MAZE_AREA) then
		-- inside the maze the player is never lost: the stage that just failed is tried again, else the one after the nearest
		plan.retry = true
		plan.stage = S.last_stage
		if not plan.stage then
			-- standing at an object a step is about to use: that step comes next
			local at = pos()
			for i, stage in ipairs(STAGES) do
				if stage.kind ~= "walk" and math.max(math.abs(at.x - stage.to.x), math.abs(at.y - stage.to.y)) <= 1 then
					plan.stage = i
					break
				end
			end
		end
		plan.stage = plan.stage or nearest_stage() + 1
		return "MAZE"
	end
	if carrying() then
		return "BANK"
	end
	if index == 1 then
		return "MAZE"
	end
	return "TO_START"
end

-- stops the script when it hasn't progressed or keeps failing
local function check_timeouts()
	local t = CONFIG.timeouts
	local reason: string? = nil
	if Host.time() - S.last_progress_at >= t.idle_minutes * 60000 then
		reason = `no stage done for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.rounds > 0 and stats.runs >= CONFIG.rounds and not carrying() then
		Log.log(NAME, `Reached {CONFIG.rounds} rounds, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.finished = true
	end
end

local function attempt(action: () -> ())
	local ok, err = pcall(action)
	if ok then
		S.failures_in_row = 0
		S.last_progress_at = Host.time()
	else
		S.failures_in_row += 1
		Log.log(NAME, `{err}`)
		Host.sleep(1500)
	end
end

-- breaks, sleeps and the antiban tasks, in the lobby only
local function lobby_antiban()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_antiban()
		Antiban.do_async_tasks("outside")
	end
end

-- One small camera, zoom or pitch change.
local function tiny_antiban()
	local roll = math.random(3)
	if roll == 1 then
		AntibanTasks.tiny_camera_rotation()
	elseif roll == 2 then
		AntibanTasks.tiny_zoom_change()
	else
		AntibanTasks.tiny_pitch_change()
	end
end

-- Waits (standing still) until the run energy is at least `target` percent, up to five minutes.
local function wait_energy(target: number)
	local started = Host.time()
	local logged = started
	local tiny_at = started + math.random(3000, 9000)
	while (Player.run_energy() or 100) < target and Host.time() - started < 300000 do
		S.last_progress_at = Host.time()
		if Host.time() >= tiny_at then
			tiny_at = Host.time() + math.random(4000, 12000)
			tiny_antiban()
		end
		if Host.time() - logged >= 30000 then
			logged = Host.time()
			print(`  waiting for run energy: {math.floor(Player.run_energy() or 0)}% of {target}%`)
		end
		Host.sleep(1000)
	end
end

-- Where the energy is gathered before the powder.
local REST_AT = { x = 3002, y = 5067 }

-- Walks to one random tile around REST_AT with run off and waits there, with tiny antibans, until the energy reaches a
-- random 30 to 40 percent; then run goes back on. Whether the player had to go there.
local function recover_energy(): boolean
	local need = Random.int(30, 40)
	if (Player.run_energy() or 100) >= need then
		return false
	end
	Minimap.set_run(false)
	for _ = 1, 4 do
		local tile = { x = REST_AT.x + Random.int(-3, 3), y = REST_AT.y + Random.int(-3, 3) }
		if Walker.walk(tile, { near = 0 }) then
			break
		end
	end
	print(`  waiting at {here()} until the run energy is {need}%`)
	wait_energy(need)
	Minimap.set_run(true)
	return true
end

local HANDLERS: { [State]: () -> () } = {
	LOADING = function()
		Host.sleep(100)
	end,
	LOGIN = function()
		sign_in()
	end,
	MAZE = function()
		local index = plan.stage :: number
		if index == 1 then
			if not S.restarted then
				lobby_antiban()
			end
			S.restarted = false
			Minimap.set_run(true)
			wait_energy(CONFIG.min_energy)
		elseif STAGES[index].kind == "stun" then
			-- the run after the stun must start at once, so the energy is gathered before the powder is taken
			if recover_energy() then
				plan.retry = true
			end
		elseif STAGES[index - 1].kind ~= "stun" and (Player.run_energy() or 100) < 15 then
			-- inside the maze it is safe to stand still: the traps only go off when moving
			wait_energy(35)
		end
		S.last_stage = index
		attempt(function()
			do_stage(index, plan.retry)
			if index == #STAGES then
				finish_round()
			end
		end)
		Host.sleep(Random.trunc(Random.left(CONFIG.reaction_ms.min, CONFIG.reaction_ms.max)))
	end,
	BANK = function()
		lobby_antiban()
		attempt(bank_rewards)
	end,
	TO_START = function()
		lobby_antiban()
		attempt(to_start)
	end,
}

-- an interface opened by accident (a click on the wrong thing) blocks every click: closed
local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or Host.time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = Host.time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

local function main()
	Log.log(NAME, `{NAME} started`)
	setup()
	S.last_progress_at, S.failures_in_row = Host.time(), 0
	while not S.finished do
		local state = get_state()
		check_timeouts()
		if S.finished then
			break
		end
		close_stray()
		HANDLERS[state]()
		Host.sleep(Random.int(60, 140))
	end
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

main()
