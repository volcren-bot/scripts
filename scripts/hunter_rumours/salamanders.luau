--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type GroundItem = Host.GroundItem
type Loc = Host.Loc
local Biometrics = require("@volcren/biometrics")
local GroundItems = require("@volcren/ground_items")
local Hop = require("./hop")
local Idle = require("./idle")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local Travel = require("./travel")
local Walker = require("@volcren/walker")

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
	busy: string?,
	idle: boolean,
	claimed: boolean,
	catches: number,
	blocked: string?,
}

local CONST = {
	ARRIVE_NEAR = 3,
	LEASH = 12,
	NEAR = 5,
	TREE = { NAME = "Young tree", SET = "Set-trap" },
	NET = { ITEM = "Net trap", RESET = "Reset", CHECK = "Check", DISMANTLE = "Dismantle", TAKE = "Take" },
	TRAPS = { MAX = 5, LEVELS_PER_TRAP = 20 },
	PLAYER_RANGE = 8,
	ACT_TIMEOUT_MS = 20000,
	EMPTY_GRACE_MS = 4000,
	WAIT_MS = { 100, 250 },
	REACT_MS = { mode = 450, min = 0, max = 1800 },
	SETTLE_MS = 2400,
	TICK_WAIT_MS = 700,
	TRAP_ACTIONS = { SET = true, RESET = true, PICKUP = true } :: { [string]: boolean },
	PREHOVER_MS = { 150, 450 },
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

local TRAP_STATES: { [number]: Status } = {
	[8732] = "empty",
	[8990] = "empty",
	[9000] = "empty",
	[9341] = "empty",
	[50721] = "empty",
	[8730] = "set",
	[8731] = "set",
	[8989] = "set",
	[8992] = "set",
	[8999] = "set",
	[9002] = "set",
	[9257] = "set",
	[9343] = "set",
	[50720] = "set",
	[50723] = "set",
	[8733] = "busy",
	[8972] = "busy",
	[8973] = "busy",
	[8974] = "busy",
	[8985] = "busy",
	[8987] = "busy",
	[8988] = "busy",
	[8991] = "busy",
	[8993] = "busy",
	[8997] = "busy",
	[8998] = "busy",
	[9001] = "busy",
	[9003] = "busy",
	[9005] = "busy",
	[9158] = "busy",
	[9342] = "busy",
	[50716] = "busy",
	[50718] = "busy",
	[50719] = "busy",
	[50722] = "busy",
	[8734] = "sprung",
	[8986] = "sprung",
	[8996] = "sprung",
	[9004] = "sprung",
	[50717] = "sprung",
	[62522] = "sprung",
	[62523] = "sprung",
	[62524] = "sprung",
	[62525] = "sprung",
	[62526] = "sprung",
	[62527] = "sprung",
	[62528] = "sprung",
	[62529] = "sprung",
	[62530] = "sprung",
	[62531] = "sprung",
}

local STATUS_RANK: { [Status]: number } = { empty = 1, busy = 2, set = 3, sprung = 4 }

local FULL_IDS: { [number]: boolean } = { [8734] = true, [8986] = true, [8996] = true, [9004] = true, [50717] = true }

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
	return { creature = creature, trees = {}, traps = {}, empty_since = {}, idle = false, claimed = false, catches = 0 }
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

function Read.tree_at(tree: Tile): (Status, Loc?)
	local best: Status? = nil
	local best_loc: Loc? = nil
	for _, loc in ipairs(Objects.find() or {}) do
		local status = TRAP_STATES[loc.id]
		if
			status
			and loc.plane == tree.plane
			and tree.x >= loc.x
			and tree.x < loc.x + math.max(loc.size_x, 1)
			and tree.y >= loc.y
			and tree.y < loc.y + math.max(loc.size_y, 1)
			and (best == nil or STATUS_RANK[status] > STATUS_RANK[best :: Status])
		then
			best, best_loc = status, loc
		end
	end
	if best then
		return best :: Status, best_loc
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

function Read.on_site(area: Area, me: Host.Tile): boolean
	if Walker.distance(me, area.arrive) <= CONST.LEASH then
		return true
	end
	for _, tree in ipairs(area.trees) do
		if Walker.distance(me, tree) <= CONST.LEASH then
			return true
		end
	end
	return false
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
	local best_state: State = "WAIT"
	local best_d: number = math.huge
	for _, tree in ipairs(sprung) do
		local d = Walker.distance(me, tree)
		if d < best_d then
			task.target = tree
			best_state = "RESET" :: State
			best_d = d
		end
	end
	local net = Read.dropped_net(task)
	if net then
		local d = Walker.distance(me, net)
		if d < best_d then
			task.net = net
			best_state = "PICKUP" :: State
			best_d = d
		end
	end
	if Inventory.contains(CONST.NET.ITEM) then
		for _, tree in ipairs(empty) do
			local d = Walker.distance(me, tree)
			if d < best_d then
				task.target = tree
				best_state = "SET" :: State
				best_d = d
			end
		end
	end
	if best_state ~= "WAIT" then
		return best_state
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
	if me.plane ~= area.arrive.plane or not Read.on_site(area, me) then
		return "TRAVEL"
	end
	if next(task.traps) == nil and #task.trees == 0 and Read.player_near(area) == nil then
		Read.adopt(task, area)
	end
	if not task.claimed then
		task.busy = Read.occupied(task, area)
		if task.busy then
			return "HOP"
		end
		task.claimed = true
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
	local goal = Travel.spread(area.arrive)
	Log.log(NAME, `Travelling to the {area.name}`)
	local walked, why = Travel.walk(goal, CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.hop(task: Task): boolean
	return Hop.away(NAME, `The young trees are taken ({task.busy})`)
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
	if not Game.use(loc :: Loc, CONST.TREE.SET) then
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

function Game.use(loc: Loc, option: string): boolean
	local me = Walker.position()
	if me and Walker.distance(me, loc) <= CONST.NEAR and Objects.interact(loc, option, false) then
		return true
	end
	return Objects.approach(loc, option)
end

function Game.reset(task: Task): boolean
	local tree = task.target :: Tile
	local status, loc = Read.tree_at(tree)
	if status ~= "sprung" or loc == nil then
		return true
	end
	local trap = loc :: Loc
	local option = CONST.NET.RESET
	Log.log(NAME, `{option} on the net trap at {tree.x}, {tree.y}`)
	return Game.counted(task, function(): boolean
		if not Game.use(trap, option) then
			return false
		end
		Game.prehover(task, tree)
		local done = Game.wait_until(function(): boolean
			local now = Read.tree_at(tree)
			return now == "set"
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
	if not GroundItems.interact(net, CONST.NET.TAKE, false) then
		return false
	end
	return Game.wait_until(function(): boolean
		return (Inventory.count_ex(CONST.NET.ITEM) or 0) > before
	end, CONST.ACT_TIMEOUT_MS)
end

function Game.wait(): boolean
	Idle.wait(CONST.WAIT_MS)
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
	if status == "busy" then
		return Game.wait()
	end
	local option = if FULL_IDS[trap.id] then CONST.NET.CHECK else CONST.NET.DISMANTLE
	Log.log(NAME, `Packing up: {option} on the net trap at {tree.x}, {tree.y}`)
	local ok = Game.counted(task, function(): boolean
		return Game.use(trap, option)
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

function Game.settle()
	local deadline = time() + CONST.SETTLE_MS
	while Player.animation() ~= -1 and time() < deadline do
		sleep(CONST.POLL_MS)
	end
	local tick = Host.game_state().tick_count
	local next_tick = time() + CONST.TICK_WAIT_MS
	while Host.game_state().tick_count == tick and time() < next_tick do
		sleep(CONST.POLL_MS)
	end
end

function Salamanders.step(task: Task, state: State): boolean
	if CONST.TRAP_ACTIONS[state] then
		Game.settle()
	end
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
