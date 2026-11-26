--!strict
local Chat = require("@volcren/chat")
local DebugDraw = require("@volcren/debug_draw")
local Draw = require("@volcren/draw")
local Host = require("@volcren/host")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Objects = require("@volcren/objects")
local Random = require("@volcren/random")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Tracking"

export type Tile = { x: number, y: number, plane: number }
type Point = { x: number, y: number }
export type Box = { x1: number, y1: number, x2: number, y2: number }
export type Area = {
	name: string,
	box: Box,
	arrive: Tile,
	burrows: { number },
	bush: number,
	hiding_varbit: number,
	hiding: { [number]: Point },
	footprints: { [number]: number },
}
export type Creature = { name: string, npc: string, part: number, area: Area }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "WIELD" | "START" | "INSPECT" | "ATTACK"
type Graph = {
	plants: { Tile },
	bushes: { Tile },
	burrows: { Tile },
	trails: { [number]: { Tile } },
	varbits: { number },
}
export type Task = {
	creature: Creature,
	graph: Graph?,
	node: Tile?,
	newest: number?,
	visited: { [string]: boolean },
	wrong: { [string]: boolean },
	empty: { [string]: boolean },
	target: { tile: Tile, label: string, loc: Host.Loc? }?,
	drawn: boolean?,
	painted: string?,
	catches: number,
	misses: number,
	blocked: string?,
}

local CONST = {
	WAND = "Noose wand",
	WIELD = "Wield",
	INSPECT = "Inspect",
	ATTACK = "Attack",
	PLANT = "Plant",
	PLANNED = { [1] = true, [2] = true },
	VISIBLE = { [3] = true, [4] = true },
	PLANNED_REACH = 3,
	BUSH_REACH = 2,
	NEAREST_BURROW = 70,
	ARRIVE_NEAR = 3,
	ACT_TIMEOUT_MS = 9000,
	WIELD_TIMEOUT_MS = 2400,
	MISSES = 4,
	POLL_MS = 100,
	PAUSE_MS = { 150, 700 },
	MESSAGES = {} :: { string },
	DRAW = {
		LAYER = "tracking",
		WIDTH = 2,
		NEWEST = Draw.color(255, 220, 60, 255),
		TRAIL = Draw.color(200, 160, 60, 160),
		PLANNED = Draw.color(120, 120, 255, 110),
		TARGET = Draw.color(60, 255, 120, 255),
		VISITED = Draw.color(150, 150, 150, 170),
		WRONG = Draw.color(255, 70, 70, 220),
		TARGET_FACES = Draw.color(60, 255, 120, 70),
	},
	MESSAGE = {
		WRONG_PLANT = "completely unassuming plant",
		WRONG_BURROW = "fail to find any sign",
		EMPTY_BUSH = "doesn't appear to be a creature",
		DEVOID_BUSH = "devoid of creatures",
		CAUGHT = "You manage to noose",
	},
}

local CREATURES: { [string]: Creature } = {
	["razor-backed kebbit"] = {
		name = "razor-backed kebbit",
		npc = "Razor-backed kebbit",
		part = 29223,
		area = {
			name = "Piscatoris Hunter area",
			box = { x1 = 2338, y1 = 3590, x2 = 2368, y2 = 3630 },
			arrive = { x = 2358, y = 3618, plane = 0 },
			burrows = { 19438, 19579, 19580 },
			bush = 19428,
			hiding_varbit = 2994,
			hiding = {
				[1] = { x = 2358, y = 3620 },
				[2] = { x = 2351, y = 3619 },
				[3] = { x = 2362, y = 3615 },
				[4] = { x = 2354, y = 3609 },
				[5] = { x = 2357, y = 3607 },
				[6] = { x = 2349, y = 3604 },
				[7] = { x = 2360, y = 3602 },
				[8] = { x = 2355, y = 3601 },
			},
			footprints = {
				[19582] = 2974,
				[19583] = 2974,
				[19585] = 2974,
				[19444] = 2975,
				[19447] = 2976,
				[19516] = 2976,
				[19589] = 2976,
				[19518] = 2977,
				[19521] = 2978,
				[19522] = 2978,
				[19592] = 2978,
				[19524] = 2979,
				[19525] = 2979,
				[19594] = 2979,
				[19527] = 2980,
				[19528] = 2980,
				[19595] = 2980,
				[19530] = 2981,
				[19531] = 2981,
				[19597] = 2981,
				[19533] = 2982,
				[19534] = 2982,
				[19536] = 2983,
				[19537] = 2983,
				[19600] = 2983,
				[19539] = 2985,
				[19540] = 2985,
				[19602] = 2985,
				[19542] = 2986,
				[19543] = 2986,
				[19603] = 2986,
				[19545] = 2987,
				[19546] = 2987,
				[19606] = 2987,
				[19548] = 2988,
				[19549] = 2988,
				[19609] = 2988,
				[19551] = 2989,
				[19612] = 2989,
				[19706] = 2989,
				[19615] = 2990,
				[19708] = 2990,
				[19709] = 2990,
				[19617] = 2991,
				[19711] = 2991,
				[19712] = 2991,
				[19714] = 2992,
				[19619] = 2993,
				[19717] = 2993,
				[19718] = 2993,
			},
		},
	},
}

CONST.MESSAGES = {
	CONST.MESSAGE.WRONG_PLANT,
	CONST.MESSAGE.WRONG_BURROW,
	CONST.MESSAGE.EMPTY_BUSH,
	CONST.MESSAGE.DEVOID_BUSH,
	CONST.MESSAGE.CAUGHT,
}

local Tracking = {}
local Read, Game, Handler = {}, {}, {}

Tracking.CREATURES = table.freeze(CREATURES)

function Tracking.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Tracking.new(prey: string): Task?
	local creature = Tracking.creature(prey)
	if creature == nil then
		return nil
	end
	return { creature = creature, visited = {}, wrong = {}, empty = {}, catches = 0, misses = 0 }
end

local function key(t: Point): string
	return `{t.x},{t.y}`
end

local function distance(a: Point, b: Point): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function reach(t: Point, tiles: { Tile }): number
	local best = math.huge
	for _, f in ipairs(tiles) do
		best = math.min(best, distance(t, f))
	end
	return best
end

function Read.graph(task: Task): Graph?
	if task.graph then
		return task.graph
	end
	local area = task.creature.area
	local locs = Host.cache_locs(area.box)
	if locs == nil then
		return nil
	end
	local burrow_ids: { [number]: boolean } = {}
	for _, id in ipairs(area.burrows) do
		burrow_ids[id] = true
	end
	local graph: Graph = { plants = {}, bushes = {}, burrows = {}, trails = {}, varbits = {} }
	for _, l in ipairs(locs) do
		local tile = { x = l.x, y = l.y, plane = l.plane }
		local varbit = area.footprints[l.id]
		if varbit then
			if graph.trails[varbit] == nil then
				graph.trails[varbit] = {}
				table.insert(graph.varbits, varbit)
			end
			table.insert(graph.trails[varbit], tile)
		elseif burrow_ids[l.id] then
			table.insert(graph.burrows, tile)
		elseif l.id == area.bush then
			table.insert(graph.bushes, tile)
		elseif l.name == CONST.PLANT then
			table.insert(graph.plants, tile)
		end
	end
	if #graph.burrows == 0 or #graph.plants == 0 or #graph.bushes == 0 or #graph.varbits == 0 then
		return nil
	end
	task.graph = graph
	return graph
end

function Read.trails(graph: Graph): ({ number }, { number })
	local planned, visible = {}, {}
	for _, varbit in ipairs(graph.varbits) do
		local value = Host.varbit(varbit) or 0
		if CONST.PLANNED[value] then
			table.insert(planned, varbit)
		elseif CONST.VISIBLE[value] then
			table.insert(visible, varbit)
		end
	end
	return planned, visible
end

function Read.inside(area: Area, me: Host.Tile): boolean
	local b = area.box
	return me.x >= b.x1 and me.x <= b.x2 and me.y >= b.y1 and me.y <= b.y2
end

function Read.newest(task: Task, graph: Graph, visible: { number }): number?
	if task.newest and table.find(visible, task.newest) then
		return task.newest
	end
	local from = task.node or Walker.position()
	local best, best_d = nil, math.huge
	for _, varbit in ipairs(visible) do
		local d = if from then reach(from :: Tile, graph.trails[varbit]) else 0
		if d < best_d then
			best, best_d = varbit, d
		end
	end
	return best
end

function Read.loc(id: number?, tile: Tile, name: string?): Host.Loc?
	for _, loc in ipairs(Objects.find(id) or {}) do
		if loc.x == tile.x and loc.y == tile.y and (name == nil or loc.name == name) then
			return loc
		end
	end
	return nil
end

function Read.any_trail(graph: Graph): boolean
	for _, varbit in ipairs(graph.varbits) do
		if (Host.varbit(varbit) or 0) ~= 0 then
			return true
		end
	end
	return false
end

function Read.tile_of(t: Point): Tile
	return { x = t.x, y = t.y, plane = 0 }
end

local function outline(tiles: { Tile }, color: Draw.Color, width: number)
	DebugDraw.outline(tiles :: any, color, width)
end

function Game.paint(task: Task)
	local graph = task.graph
	if graph == nil then
		return
	end
	local planned, visible = Read.trails(graph)
	local newest = Read.newest(task, graph, visible)
	for _, varbit in ipairs(planned) do
		outline(graph.trails[varbit], CONST.DRAW.PLANNED, 1)
	end
	for _, varbit in ipairs(visible) do
		if varbit ~= newest then
			outline(graph.trails[varbit], CONST.DRAW.TRAIL, CONST.DRAW.WIDTH)
		end
	end
	if newest then
		outline(graph.trails[newest], CONST.DRAW.NEWEST, CONST.DRAW.WIDTH)
	end
	for _, group in ipairs({
		{ task.visited, CONST.DRAW.VISITED },
		{ task.wrong, CONST.DRAW.WRONG },
		{ task.empty, CONST.DRAW.WRONG },
	}) do
		for k in pairs(group[1] :: { [string]: boolean }) do
			local x, y = string.match(k, "^(%-?%d+),(%-?%d+)$")
			if x and y then
				outline(
					{ Read.tile_of({ x = tonumber(x) :: number, y = tonumber(y) :: number }) },
					group[2] :: Draw.Color,
					CONST.DRAW.WIDTH
				)
			end
		end
	end
	local target = task.target
	if target then
		if target.loc then
			DebugDraw.loc(target.loc :: Host.Loc, CONST.DRAW.TARGET_FACES, CONST.DRAW.TARGET)
		else
			outline({ target.tile }, CONST.DRAW.TARGET, CONST.DRAW.WIDTH + 1)
		end
		DebugDraw.label(target.tile, target.label, CONST.DRAW.TARGET, true)
	end
end

function Game.draw(task: Task?)
	if task == nil then
		DebugDraw.set(CONST.DRAW.LAYER, nil)
		return
	end
	local t = task :: Task
	if not DebugDraw.on() then
		return
	end
	local signature = Read.signature(t)
	if not t.drawn then
		t.drawn, t.painted = true, signature
		DebugDraw.set(CONST.DRAW.LAYER, function()
			Game.paint(t)
		end)
	elseif signature ~= t.painted then
		t.painted = signature
		DebugDraw.render()
	end
end

function Read.signature(task: Task): string
	local parts: { string } = {}
	local graph = task.graph
	for _, varbit in ipairs(if graph then graph.varbits else {}) do
		table.insert(parts, tostring(Host.varbit(varbit) or 0))
	end
	for _, set in ipairs({ task.visited, task.wrong, task.empty }) do
		local n = 0
		for _ in pairs(set) do
			n += 1
		end
		table.insert(parts, tostring(n))
	end
	local target = task.target
	table.insert(parts, if target then `{key(target.tile)} {target.label}` else "-")
	return table.concat(parts, ",")
end

function Game.aim(task: Task, tile: Tile, label: string, loc: Host.Loc?)
	task.target = { tile = tile, label = label, loc = loc }
	Game.draw(task)
end

function Tracking.state(task: Task): State
	local state = Read.state(task)
	if state == "DONE" or state == "BLOCKED" then
		task.drawn = false
		Game.draw(nil)
	else
		Game.draw(task)
	end
	return state
end

function Read.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	local graph = Read.graph(task)
	if graph == nil then
		task.blocked = `couldn't read the {task.creature.area.name} trails from the cache`
		return "BLOCKED"
	end
	local me = Walker.position()
	if me == nil or not Read.inside(task.creature.area, me) then
		if Inventory.contains(task.creature.part) then
			return "DONE"
		end
		return "TRAVEL"
	end
	local planned, visible = Read.trails(graph)
	if #planned == 0 and #visible == 0 and Inventory.contains(task.creature.part) then
		return "DONE"
	end
	if not Wornitems.is_wearing(CONST.WAND) then
		return "WIELD"
	end
	if #planned > 0 then
		return "INSPECT"
	end
	if #visible > 0 then
		return "ATTACK"
	end
	return "START"
end

function Game.travel(task: Task): boolean
	local area = task.creature.area
	if task.catches == 0 then
		Log.log(NAME, `Hunting {task.creature.npc} in the {area.name}`)
	end
	local walked, why = Travel.walk(Travel.spread(area.arrive), CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.wield(task: Task): boolean
	if not Inventory.contains(CONST.WAND) then
		task.blocked = "no noose wand"
		return false
	end
	if not Inventory.interact(CONST.WAND, CONST.WIELD) then
		return false
	end
	local deadline = Host.time() + CONST.WIELD_TIMEOUT_MS
	repeat
		if Wornitems.is_wearing(CONST.WAND) then
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return false
end

function Game.act(task: Task, loc: Host.Loc, option: string, done: () -> boolean): (boolean, string?)
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Objects.approach(loc, option) then
		return false, nil
	end
	local deadline = Host.time() + CONST.ACT_TIMEOUT_MS
	repeat
		Game.draw(task)
		if done() then
			return true, nil
		end
		for _, m in ipairs(Chat.new_messages(seen) or {}) do
			seen = m.uid
			for _, text in ipairs(CONST.MESSAGES) do
				if string.find(m.text, text, 1, true) then
					return done(), text
				end
			end
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return done(), nil
end

function Game.miss(task: Task, what: string): boolean
	task.misses += 1
	Log.log(NAME, `Couldn't {what} ({task.misses} in a row)`)
	if task.misses < CONST.MISSES then
		return true
	end
	task.misses = 0
	return false
end

function Game.start(task: Task): boolean
	local graph = task.graph :: Graph
	local me: Point = Walker.position() :: Host.Tile
	local burrows = table.clone(graph.burrows)
	table.sort(burrows, function(a, b)
		return distance(me, a) < distance(me, b)
	end)
	local pick = if Random.int(1, 100) <= CONST.NEAREST_BURROW then burrows[1] else burrows[Random.int(1, #burrows)]
	local loc = nil
	for _, id in ipairs(task.creature.area.burrows) do
		loc = loc or Read.loc(id, pick)
	end
	Game.aim(task, pick, "Inspect burrow", loc)
	if loc == nil then
		return (Travel.walk(pick, CONST.ARRIVE_NEAR))
	end
	task.node, task.newest, task.visited, task.wrong, task.empty = nil, nil, {}, {}, {}
	local ok = Game.act(task, loc :: Host.Loc, CONST.INSPECT, function()
		return Read.any_trail(graph)
	end)
	if not ok then
		return Game.miss(task, `find tracks at the burrow at {pick.x}, {pick.y}`)
	end
	task.misses = 0
	task.node = pick
	task.visited[key(pick)] = true
	Log.log(NAME, `Found tracks at the burrow at {pick.x}, {pick.y}`)
	Random.sleep(CONST.PAUSE_MS[1], CONST.PAUSE_MS[2])
	return true
end

function Game.inspect(task: Task): boolean
	local graph = task.graph :: Graph
	local planned, visible = Read.trails(graph)
	local next_trail = planned[1]
	local trail_tiles = graph.trails[next_trail]
	local newest = Read.newest(task, graph, visible)
	local newest_tiles = if newest then graph.trails[newest] else trail_tiles
	local best: Tile? = nil
	local best_a, best_b = math.huge, math.huge
	for _, plant in ipairs(graph.plants) do
		local k = key(plant)
		if not task.visited[k] and not task.wrong[k] then
			local a, b = reach(plant, trail_tiles), reach(plant, newest_tiles)
			if a <= CONST.PLANNED_REACH and (a < best_a or (a == best_a and b < best_b)) then
				best, best_a, best_b = plant, a, b
			end
		end
	end
	if best == nil then
		task.wrong = {}
		return Game.miss(task, "find the plant the trail leads to")
	end
	local plant = best :: Tile
	local loc = Read.loc(nil, plant, CONST.PLANT)
	Game.aim(task, plant, `Inspect ({best_a}/{best_b})`, loc)
	if loc == nil then
		return (Travel.walk(plant, CONST.ARRIVE_NEAR))
	end
	local ok, message = Game.act(task, loc :: Host.Loc, CONST.INSPECT, function()
		return CONST.VISIBLE[Host.varbit(next_trail) or 0] == true
	end)
	if not ok then
		if message == CONST.MESSAGE.WRONG_PLANT then
			task.wrong[key(plant)] = true
			return true
		end
		return Game.miss(task, `inspect the plant at {plant.x}, {plant.y}`)
	end
	task.misses = 0
	task.node, task.newest, task.wrong = plant, next_trail, {}
	task.visited[key(plant)] = true
	Random.sleep(CONST.PAUSE_MS[1], CONST.PAUSE_MS[2])
	return true
end

function Read.hiding_bush(task: Task, graph: Graph, visible: { number }): Tile?
	local area = task.creature.area
	local known = area.hiding[Host.varbit(area.hiding_varbit) or 0]
	if known and not task.empty[key(known)] then
		for _, b in ipairs(graph.bushes) do
			if b.x == known.x and b.y == known.y then
				return b
			end
		end
	end
	local newest = Read.newest(task, graph, visible)
	local from: Point = task.node or (Walker.position() :: Host.Tile)
	local far: Tile? = nil
	for _, t in ipairs(if newest then graph.trails[newest] else {}) do
		if far == nil or distance(from, t) > distance(from, far :: Tile) then
			far = t
		end
	end
	local trail_tiles: { Tile } = {}
	for _, varbit in ipairs(visible) do
		for _, t in ipairs(graph.trails[varbit]) do
			table.insert(trail_tiles, t)
		end
	end
	local best: Tile? = nil
	local best_rank, best_d = math.huge, math.huge
	for _, b in ipairs(graph.bushes) do
		if not task.empty[key(b)] then
			local rank = if reach(b, trail_tiles) <= CONST.BUSH_REACH then 0 else 1
			local d = if far then distance(far :: Tile, b) else distance(from, b)
			if rank < best_rank or (rank == best_rank and d < best_d) then
				best, best_rank, best_d = b, rank, d
			end
		end
	end
	return best
end

function Game.attack(task: Task): boolean
	local graph = task.graph :: Graph
	local area = task.creature.area
	local _, visible = Read.trails(graph)
	local hiding = Host.varbit(area.hiding_varbit) or 0
	local bush = Read.hiding_bush(task, graph, visible)
	if bush == nil then
		task.empty = {}
		return Game.miss(task, "find the bush the trail leads to")
	end
	local spot = bush :: Tile
	local loc = Read.loc(area.bush, spot)
	Game.aim(task, spot, `Attack (hiding {hiding})`, loc)
	if loc == nil then
		return (Travel.walk(spot, CONST.ARRIVE_NEAR))
	end
	local before = Inventory.free_slots() or 0
	local ok, message = Game.act(task, loc :: Host.Loc, CONST.ATTACK, function()
		return not Read.any_trail(graph)
	end)
	if message == CONST.MESSAGE.EMPTY_BUSH or message == CONST.MESSAGE.DEVOID_BUSH then
		task.empty[key(spot)] = true
		return true
	end
	if not ok and message ~= CONST.MESSAGE.CAUGHT then
		task.empty[key(spot)] = true
		return Game.miss(task, `catch the kebbit in the bush at {spot.x}, {spot.y}`)
	end
	task.misses = 0
	task.node, task.newest, task.empty = nil, nil, {}
	if area.hiding[hiding] == nil then
		Log.log(NAME, `Hiding bush {hiding} is at {spot.x}, {spot.y}`)
	end
	if message == CONST.MESSAGE.CAUGHT or (Inventory.free_slots() or 0) < before then
		task.catches += 1
		Log.log(NAME, `Caught: {task.creature.npc} ({task.catches} so far)`)
	else
		Log.log(NAME, "The trail ended without a catch")
	end
	return true
end

Handler.states = {
	BLOCKED = function(_task: Task): boolean
		return false
	end,
	DONE = function(_task: Task): boolean
		return true
	end,
	TRAVEL = Game.travel,
	WIELD = Game.wield,
	START = Game.start,
	INSPECT = Game.inspect,
	ATTACK = Game.attack,
} :: { [State]: (Task) -> boolean }

function Tracking.step(task: Task, state: State): boolean
	return Handler.states[state](task)
end

return Tracking
