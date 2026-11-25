--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type GroundItem = Host.GroundItem
type Loc = Host.Loc
local Antiban = require("@volcren/antiban")
local Biometrics = require("@volcren/biometrics")
local GroundItems = require("@volcren/ground_items")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Objects = require("@volcren/objects")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local WorldSwitcher = require("@volcren/worldswitcher")

local NAME = "Salamanders"

export type Tile = { x: number, y: number, plane: number }
export type Area = { name: string, arrive: Tile, trees: { Tile } }
export type Creature = { name: string, npc: string, part: number, catch: string, areas: { Area } }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "HOP" | "SET" | "RESET" | "PICKUP" | "WAIT" | "PACK"
export type Status = "empty" | "set" | "sprung" | "busy"
export type Task = {
	creature: Creature,
	area: Area?,
	trees: { Tile },
	traps: { [string]: number },
	empty_since: { [string]: number },
	limit: number?,
	target: Tile?,
	net: GroundItem?,
	worlds: { number }?,
	busy: string?,
	idle: boolean,
	catches: number,
	blocked: string?,
}

local CONST = {
	ARRIVE_NEAR = 3,
	ARRIVE_SPREAD = 1,
	LEASH = 12,
	TREE = { NAME = "Young tree", SET = "Set-trap" },
	NET = { ITEM = "Net trap", RESET = "Reset", CHECK = "Check", DISMANTLE = "Dismantle", TAKE = "Take" },
	TRAPS = { MAX = 5, LEVELS_PER_TRAP = 20 },
	PLAYER_RANGE = 8,
	ACT_TIMEOUT_MS = 12000,
	EMPTY_GRACE_MS = 4000,
	HOP_SETTLE_MS = { 1200, 2400 },
	WAIT_MS = { 100, 250 },
	REACT_MS = { mode = 450, min = 0, max = 1800 },
	PREHOVER_MS = { 150, 450 },
	ANTIBAN_GAP_MS = { 3000, 9000 },
	POLL_MS = 100,
}

local CREATURES: { [string]: Creature } = {
	["red salamander"] = {
		name = "red salamander",
		npc = "Red salamander",
		part = 29234,
		catch = "Red salamander",
		areas = {
			{
				name = "south-west of the Ourania Hunter area",
				arrive = { x = 2453, y = 3224, plane = 0 },
				trees = {
					{ x = 2447, y = 3225, plane = 0 },
					{ x = 2449, y = 3228, plane = 0 },
					{ x = 2451, y = 3225, plane = 0 },
					{ x = 2453, y = 3219, plane = 0 },
					{ x = 2455, y = 3223, plane = 0 },
					{ x = 2459, y = 3220, plane = 0 },
				},
			},
			{
				name = "north-east of the Ourania Hunter area",
				arrive = { x = 2470, y = 3243, plane = 0 },
				trees = {
					{ x = 2463, y = 3251, plane = 0 },
					{ x = 2467, y = 3242, plane = 0 },
					{ x = 2468, y = 3247, plane = 0 },
					{ x = 2472, y = 3238, plane = 0 },
					{ x = 2475, y = 3236, plane = 0 },
					{ x = 2477, y = 3242, plane = 0 },
				},
			},
		},
	},
	["orange salamander"] = {
		name = "orange salamander",
		npc = "Orange salamander",
		part = 29231,
		catch = "Orange salamander",
		areas = {
			{
				name = "Uzer Hunter area",
				arrive = { x = 3405, y = 3088, plane = 0 },
				trees = {
					{ x = 3404, y = 3092, plane = 0 },
					{ x = 3407, y = 3088, plane = 0 },
					{ x = 3407, y = 3093, plane = 0 },
					{ x = 3411, y = 3081, plane = 0 },
					{ x = 3412, y = 3075, plane = 0 },
					{ x = 3412, y = 3087, plane = 0 },
					{ x = 3414, y = 3078, plane = 0 },
					{ x = 3414, y = 3084, plane = 0 },
					{ x = 3415, y = 3073, plane = 0 },
				},
			},
		},
	},
}

local Salamanders = {}
local Read, Game, Handler = {}, {}, {}

Salamanders.CREATURES = table.freeze(CREATURES)

function Salamanders.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Salamanders.new(prey: string): Task?
	local creature = Salamanders.creature(prey)
	if creature == nil then
		return nil
	end
	return { creature = creature, trees = {}, traps = {}, empty_since = {}, idle = false, catches = 0 }
end

function Read.key(t: { x: number, y: number }): string
	return `{t.x},{t.y}`
end

function Read.limit(task: Task): number
	if task.limit then
		return task.limit :: number
	end
	local level = Stats.real_level("Hunter") or 1
	return math.min(CONST.TRAPS.MAX, 1 + level // CONST.TRAPS.LEVELS_PER_TRAP)
end

function Read.nearest_area(c: Creature, me: Host.Tile): Area?
	local best, best_d = nil, math.huge
	for _, area in ipairs(c.areas) do
		local d = Walker.distance(me, area.arrive)
		if d < best_d then
			best, best_d = area, d
		end
	end
	return best
end

function Read.nearest(me: Host.Tile, tiles: { Tile }): Tile?
	local best, best_d = nil, math.huge
	for _, t in ipairs(tiles) do
		local d = Walker.distance(me, t)
		if d < best_d then
			best, best_d = t, d
		end
	end
	return best
end

local actions_of: { [number]: { string } } = {}

function Read.actions(loc: Loc): { string }
	local known = actions_of[loc.id]
	if known == nil then
		local views = Host.loc_shown({ loc.id })
		known = if views and views[1] then views[1].actions else {}
		actions_of[loc.id] = known
	end
	return known
end

function Read.tree_at(tree: Tile): (Status, Loc?)
	for _, loc in ipairs(Objects.find() or {}) do
		if loc.x == tree.x and loc.y == tree.y and loc.plane == tree.plane then
			local name = loc.name or ""
			if name ~= CONST.TREE.NAME and name ~= CONST.NET.ITEM then
				continue
			end
			local actions = Read.actions(loc)
			if table.find(actions, CONST.TREE.SET) then
				return "empty", loc
			elseif table.find(actions, CONST.NET.CHECK) or table.find(actions, CONST.NET.RESET) then
				return "sprung", loc
			elseif #actions == 0 then
				return "busy", loc
			end
			return "set", loc
		end
	end
	return "busy", nil
end

function Read.dropped_net(task: Task): GroundItem?
	for _, item in ipairs(GroundItems.find(CONST.NET.ITEM) or {}) do
		for _, tree in ipairs(task.trees) do
			if Walker.distance(item, tree) <= 1 then
				return item
			end
		end
	end
	return nil
end

function Read.player_near(area: Area): string?
	local me = Players.me()
	for _, p in ipairs(Players.find() or {}) do
		if me == nil or p.index ~= me.index then
			for _, tree in ipairs(area.trees) do
				if Walker.distance(tree, p) <= CONST.PLAYER_RANGE then
					return `{p.name} is there`
				end
			end
		end
	end
	return nil
end

function Read.adopt(task: Task, area: Area)
	local adopted: { Tile } = {}
	for _, tree in ipairs(area.trees) do
		if Read.tree_at(tree) ~= "empty" and #adopted < Read.limit(task) then
			task.traps[Read.key(tree)] = time()
			table.insert(adopted, tree)
		end
	end
	if #adopted > 0 then
		task.trees = adopted
		Log.log(NAME, `Taking over {#adopted} traps already set here`)
	end
end

function Read.occupied(task: Task, area: Area): string?
	local near = Read.player_near(area)
	if near then
		return near
	end
	for _, tree in ipairs(area.trees) do
		local status = Read.tree_at(tree)
		if status ~= "empty" and not task.traps[Read.key(tree)] then
			return `the young tree at {tree.x}, {tree.y} is taken`
		end
	end
	return nil
end

function Read.pick_trees(task: Task, area: Area)
	local first = task.trees[1] or area.trees[Random.int(1, #area.trees)]
	local by_distance = table.clone(area.trees)
	table.sort(by_distance, function(a: Tile, b: Tile): boolean
		return Walker.distance(first, a) < Walker.distance(first, b)
	end)
	for _, tree in ipairs(by_distance) do
		if #task.trees >= Read.limit(task) then
			break
		end
		if not table.find(task.trees, tree) then
			table.insert(task.trees, tree)
		end
	end
	Log.log(NAME, `Setting {#task.trees} traps around {first.x}, {first.y}`)
end

function Read.ours(task: Task): { Tile }
	local out: { Tile } = {}
	for _, tree in ipairs(task.trees) do
		if task.traps[Read.key(tree)] then
			table.insert(out, tree)
		end
	end
	return out
end

function Read.trap_state(task: Task, me: Host.Tile): State
	local sprung: { Tile }, empty: { Tile } = {}, {}
	for _, tree in ipairs(task.trees) do
		local key = Read.key(tree)
		local status = Read.tree_at(tree)
		local ours = task.traps[key] ~= nil
		if status == "sprung" and ours then
			table.insert(sprung, tree)
		elseif status == "empty" then
			local since = task.empty_since[key] or time()
			task.empty_since[key] = since
			if not ours or time() - since >= CONST.EMPTY_GRACE_MS then
				task.traps[key] = nil
				table.insert(empty, tree)
			end
		end
		if status ~= "empty" then
			task.empty_since[key] = nil
		end
	end
	if #sprung > 0 then
		table.sort(sprung, function(a: Tile, b: Tile): boolean
			return (task.traps[Read.key(a)] or 0) < (task.traps[Read.key(b)] or 0)
		end)
		task.target = sprung[1]
		return "RESET"
	end
	local net = Read.dropped_net(task)
	if net then
		task.net = net
		return "PICKUP"
	end
	if #empty > 0 and Inventory.contains(CONST.NET.ITEM) then
		task.target = Read.nearest(me, empty)
		return "SET"
	end
	if #empty > 0 and #Read.ours(task) == 0 then
		task.blocked = "no net traps left to set"
		return "BLOCKED"
	end
	return "WAIT"
end

function Salamanders.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	local me = Walker.position()
	if me == nil then
		return "WAIT"
	end
	if Inventory.contains(task.creature.part) then
		for _, tree in ipairs(Read.ours(task)) do
			if Read.tree_at(tree) ~= "empty" then
				task.target = tree
				return "PACK"
			end
		end
		local net = Read.dropped_net(task)
		if net then
			task.net = net
			return "PICKUP"
		end
		return "DONE"
	end
	if task.area == nil then
		task.area = Read.nearest_area(task.creature, me)
		if task.area == nil then
			task.blocked = `no known {task.creature.npc} areas`
			return "BLOCKED"
		end
		Log.log(NAME, `Hunting {task.creature.npc} in the {(task.area :: Area).name}`)
	end
	local area = task.area :: Area
	if me.plane ~= area.arrive.plane or Walker.distance(me, area.arrive) > CONST.LEASH then
		return "TRAVEL"
	end
	if next(task.traps) == nil and #task.trees == 0 and Read.player_near(area) == nil then
		Read.adopt(task, area)
	end
	if next(task.traps) == nil then
		task.busy = Read.occupied(task, area)
		if task.busy then
			return "HOP"
		end
	end
	if #task.trees < math.min(Read.limit(task), #area.trees) then
		Read.pick_trees(task, area)
	end
	return Read.trap_state(task, me)
end

function Game.wait_until(done: () -> boolean, timeout_ms: number): boolean
	local deadline = time() + timeout_ms
	repeat
		if done() then
			return true
		end
		sleep(CONST.POLL_MS)
	until time() >= deadline
	return done()
end

function Game.travel(task: Task): boolean
	local area = task.area :: Area
	local spread = CONST.ARRIVE_SPREAD
	local goal = {
		x = area.arrive.x + Random.int(-spread, spread),
		y = area.arrive.y + Random.int(-spread, spread),
		plane = area.arrive.plane,
	}
	Log.log(NAME, `Travelling to the {area.name}`)
	local walked, why = Travel.walk(goal, CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.worlds(): { number }
	local worlds: { number } = {}
	if WorldSwitcher.open(true) then
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.members and row.available and (row.activity == nil or row.activity == "-") then
				table.insert(worlds, row.world)
			end
		end
	end
	return worlds
end

function Game.hop(task: Task): boolean
	Log.log(NAME, `The young trees are taken ({task.busy}), hopping worlds`)
	if task.worlds == nil or #(task.worlds :: { number }) == 0 then
		task.worlds = Game.worlds()
	end
	if not WorldSwitcher.random(task.worlds :: { number }) then
		Log.log(NAME, "Couldn't hop")
		return false
	end
	Log.log(NAME, `Now on world {WorldSwitcher.current() or "?"}`)
	Random.sleep(CONST.HOP_SETTLE_MS[1], CONST.HOP_SETTLE_MS[2])
	return true
end

function Game.prehover(task: Task, current: Tile)
	local best: Tile? = nil
	local best_rank, best_time = math.huge, math.huge
	for _, tree in ipairs(Read.ours(task)) do
		if tree ~= current then
			local status = Read.tree_at(tree)
			local rank = if status == "sprung" then 1 elseif status == "set" then 2 else 3
			local laid = task.traps[Read.key(tree)] or 0
			if rank < 3 and (rank < best_rank or (rank == best_rank and laid < best_time)) then
				best, best_rank, best_time = tree, rank, laid
			end
		end
	end
	if best == nil then
		return
	end
	Random.sleep(CONST.PREHOVER_MS[1], CONST.PREHOVER_MS[2])
	local _, loc = Read.tree_at(best :: Tile)
	if loc then
		Objects.hover_async(loc)
	end
end

function Game.set(task: Task): boolean
	local tree = task.target :: Tile
	local status, loc = Read.tree_at(tree)
	if status ~= "empty" or loc == nil then
		return true
	end
	Log.log(NAME, `Setting a net trap on the young tree at {tree.x}, {tree.y}`)
	if not Objects.interact(loc :: Loc, CONST.TREE.SET, false) then
		return false
	end
	local set = Game.wait_until(function(): boolean
		local now = Read.tree_at(tree)
		return now == "set" or now == "sprung"
	end, CONST.ACT_TIMEOUT_MS)
	if set then
		task.traps[Read.key(tree)] = time()
	end
	return set
end

function Game.counted(task: Task, act: () -> boolean): boolean
	local before = Inventory.count_ex(task.creature.catch) or 0
	local ok = act()
	local gained = (Inventory.count_ex(task.creature.catch) or before) - before
	if gained > 0 then
		task.catches += gained
		Log.log(NAME, `Caught: {task.creature.npc} ({task.catches} so far)`)
	end
	return ok
end

function Game.reset(task: Task): boolean
	local tree = task.target :: Tile
	local status, loc = Read.tree_at(tree)
	if status ~= "sprung" or loc == nil then
		return true
	end
	local trap = loc :: Loc
	local option = if table.find(Read.actions(trap), CONST.NET.RESET) then CONST.NET.RESET else CONST.NET.CHECK
	Log.log(NAME, `{option} on the net trap at {tree.x}, {tree.y}`)
	return Game.counted(task, function(): boolean
		if not Objects.interact(trap, option, false) then
			return false
		end
		Game.prehover(task, tree)
		local done = Game.wait_until(function(): boolean
			local now = Read.tree_at(tree)
			return now == "set" or (option == CONST.NET.CHECK and now == "empty")
		end, CONST.ACT_TIMEOUT_MS)
		if done then
			task.traps[Read.key(tree)] = time()
		end
		return done
	end)
end

function Game.pickup(task: Task): boolean
	local net = task.net :: GroundItem
	local before = Inventory.count_ex(CONST.NET.ITEM) or 0
	Log.log(NAME, `Picking up the net trap at {net.x}, {net.y}`)
	if not GroundItems.interact(net, CONST.NET.TAKE) then
		return false
	end
	return Game.wait_until(function(): boolean
		return (Inventory.count_ex(CONST.NET.ITEM) or 0) > before
	end, CONST.ACT_TIMEOUT_MS)
end

local next_antiban = 0

function Game.wait(): boolean
	if time() >= next_antiban and Antiban.do_async_tasks("game") then
		next_antiban = time() + Random.int(CONST.ANTIBAN_GAP_MS[1], CONST.ANTIBAN_GAP_MS[2])
	end
	Random.sleep(CONST.WAIT_MS[1], CONST.WAIT_MS[2])
	return true
end

function Game.pack(task: Task): boolean
	local tree = task.target :: Tile
	local status, loc = Read.tree_at(tree)
	if status == "empty" or loc == nil then
		task.traps[Read.key(tree)] = nil
		return true
	end
	local trap = loc :: Loc
	local actions = Read.actions(trap)
	local option = if table.find(actions, CONST.NET.CHECK) then CONST.NET.CHECK else CONST.NET.DISMANTLE
	if not table.find(actions, option) then
		return Game.wait()
	end
	Log.log(NAME, `Packing up: {option} on the net trap at {tree.x}, {tree.y}`)
	local ok = Game.counted(task, function(): boolean
		return Objects.interact(trap, option, false)
	end)
	if not ok then
		return false
	end
	local cleared = Game.wait_until(function(): boolean
		return Read.tree_at(tree) == "empty"
	end, CONST.ACT_TIMEOUT_MS)
	if cleared then
		task.traps[Read.key(tree)] = nil
	end
	return cleared
end

Handler.states = {
	BLOCKED = function(_task: Task): boolean
		return false
	end,
	DONE = function(_task: Task): boolean
		return true
	end,
	TRAVEL = Game.travel,
	HOP = Game.hop,
	SET = Game.set,
	RESET = Game.reset,
	PICKUP = Game.pickup,
	WAIT = function(_task: Task): boolean
		return Game.wait()
	end,
	PACK = Game.pack,
} :: { [State]: (Task) -> boolean }

function Salamanders.step(task: Task, state: State): boolean
	if state == "WAIT" then
		task.idle = true
	elseif task.idle then
		task.idle = false
		local react = CONST.REACT_MS
		sleep(Biometrics.random_mode_integer(react.mode, react.min, react.max))
	end
	return Handler.states[state](task)
end

return Salamanders
