--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type GroundItem = Host.GroundItem
type Loc = Host.Loc
local Antiban = require("@volcren/antiban")
local Biometrics = require("@volcren/biometrics")
local Chat = require("@volcren/chat")
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

local NAME = "Boxing"

export type Tile = { x: number, y: number, plane: number }
export type Cluster = { Tile }
export type Area = { name: string, arrive: Tile, clusters: { Cluster } }
export type Creature = { name: string, npc: string, part: number, catch: string, areas: { Area } }
export type State =
	"BLOCKED"
	| "DONE"
	| "CAMP"
	| "HOP"
	| "SQUARE"
	| "LAY"
	| "RESET"
	| "RELAY"
	| "STEP_OFF"
	| "WAIT"
	| "PACK"
export type Status = "empty" | "set" | "sprung" | "ground" | "busy"
export type Task = {
	creature: Creature,
	area: Area?,
	cluster: Cluster?,
	square: Tile?,
	spots: { Tile },
	spare: { Tile },
	stand_fails: { [string]: number },
	stands: { Tile },
	traps: { [string]: number },
	empty_since: { [string]: number },
	bad_squares: { [string]: boolean },
	limit: number?,
	target: Tile?,
	worlds: { number }?,
	busy: string?,
	catches: number,
	idle: boolean,
	blocked: string?,
}

local CONST = {
	CAMP_NEAR = 2,
	LEASH = 8,
	CLUSTER_RANGE = 7,
	MIN_WEIGHT = 0.25,
	HOP_SETTLE_MS = { 1200, 2400 },
	TRAP = {
		ITEM = "Box trap",
		LAY = "Lay",
		RESET = "Reset",
		CHECK = "Check",
		DISMANTLE = "Dismantle",
		TAKE = "Take",
		NAMES = { "Box trap", "Shaking box" },
		CANT_LAY = "can't lay a trap here",
		TOO_MANY = "more than",
		MAX = 5,
		LEVELS_PER_TRAP = 20,
	},
	SQUARE_RADIUS = 4,
	BLOCKED_FLAGS = 0x1240100,
	ACT_TIMEOUT_MS = 12000,
	WAIT_MS = { 100, 250 },
	REACT_MS = { mode = 450, min = 0, max = 1800 },
	ANTIBAN_GAP_MS = { 3000, 9000 },
	STAND_ATTEMPTS = 2,
	STEP_OFF_WAIT_MS = 2500,
	EMPTY_GRACE_MS = 4000,
	PREHOVER_MS = { 150, 450 },
	POLL_MS = 100,
}

local CREATURES: { [string]: Creature } = {
	["embertailed jerboa"] = {
		name = "embertailed jerboa",
		npc = "Embertailed jerboa",
		part = 29228,
		catch = "Jerboa tail",
		areas = {
			{
				name = "west of the Hunter Guild",
				arrive = { x = 1517, y = 3046, plane = 0 },
				clusters = { { { x = 1517, y = 3046, plane = 0 } } },
			},
			{
				name = "north-west of the Locus Oasis",
				arrive = { x = 1667, y = 3001, plane = 0 },
				clusters = { { { x = 1667, y = 3001, plane = 0 } } },
			},
		},
	},
	["red chinchompa"] = {
		name = "red chinchompa",
		npc = "Carnivorous chinchompa",
		part = 29235,
		catch = "Red chinchompa",
		areas = {
			{
				name = "Feldip Hunter area",
				arrive = { x = 2528, y = 2912, plane = 0 },
				clusters = {
					{ { x = 2558, y = 2932, plane = 0 } },
					{ { x = 2497, y = 2901, plane = 0 } },
				},
			},
		},
	},
}

local Boxing = {}
local Read, Game, Handler = {}, {}, {}

Boxing.CREATURES = table.freeze(CREATURES)

function Boxing.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Boxing.new(prey: string): Task?
	local creature = Boxing.creature(prey)
	if creature == nil then
		return nil
	end
	return {
		creature = creature,
		spots = {},
		spare = {},
		stand_fails = {},
		stands = {},
		traps = {},
		empty_since = {},
		bad_squares = {},
		idle = false,
		catches = 0,
	}
end

function Read.key(t: { x: number, y: number }): string
	return `{t.x},{t.y}`
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

function Read.pick_cluster(area: Area): Cluster
	local hash = Biometrics.hash()
	local weights: { number } = {}
	local total = 0
	for i = 1, #area.clusters do
		local byte = hash[((i + #area.name - 1) % #hash) + 1] or 0
		weights[i] = CONST.MIN_WEIGHT + byte / 255
		total += weights[i]
	end
	local roll = Random.float(0, total)
	for i, w in ipairs(weights) do
		roll -= w
		if roll <= 0 then
			return area.clusters[i]
		end
	end
	return area.clusters[#area.clusters]
end

function Read.occupied(task: Task, cluster: Cluster): string?
	local center = cluster[1]
	local me = Players.me()
	for _, p in ipairs(Players.find() or {}) do
		if (me == nil or p.index ~= me.index) and Walker.distance(center, p) <= CONST.CLUSTER_RANGE then
			return `{p.name} is there`
		end
	end
	for _, loc in ipairs(Objects.find() or {}) do
		local name = loc.name or ""
		for _, trap in ipairs(CONST.TRAP.NAMES) do
			if
				name == trap
				and loc.plane == center.plane
				and Walker.distance(center, loc) <= CONST.CLUSTER_RANGE
				and not task.traps[Read.key(loc)]
			then
				return `someone's {string.lower(trap)} is at {loc.x}, {loc.y}`
			end
		end
	end
	return nil
end

function Read.limit(task: Task): number
	if task.limit then
		return task.limit :: number
	end
	local level = Stats.real_level("Hunter") or 1
	return math.min(CONST.TRAP.MAX, 1 + level // CONST.TRAP.LEVELS_PER_TRAP)
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

function Read.has_action(loc: Loc, action: string): boolean
	return table.find(Read.actions(loc), action) ~= nil
end

function Read.trap_at(spot: Tile): (Status, Loc?, GroundItem?)
	for _, loc in ipairs(Objects.find() or {}) do
		if
			loc.x == spot.x
			and loc.y == spot.y
			and loc.plane == spot.plane
			and table.find(CONST.TRAP.NAMES, loc.name or "")
		then
			if Read.has_action(loc, CONST.TRAP.RESET) or Read.has_action(loc, CONST.TRAP.CHECK) then
				return "sprung", loc, nil
			elseif #Read.actions(loc) == 0 then
				return "busy", loc, nil
			end
			return "set", loc, nil
		end
	end
	for _, item in ipairs(GroundItems.find(CONST.TRAP.ITEM) or {}) do
		if item.x == spot.x and item.y == spot.y and item.plane == spot.plane then
			return "ground", nil, item
		end
	end
	return "empty", nil, nil
end

function Read.free_tiles(center: Tile): { Tile }
	local tiles: { Tile } = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			table.insert(tiles, { x = center.x + dx, y = center.y + dy, plane = center.plane })
		end
	end
	for _, d in ipairs({ { 2, 1 }, { 2, -1 }, { -2, 1 }, { -2, -1 }, { 1, 2 }, { -1, 2 }, { 1, -2 }, { -1, -2 } }) do
		table.insert(tiles, { x = center.x + d[1], y = center.y + d[2], plane = center.plane })
	end
	return tiles
end

function Read.pick_square(task: Task): Tile?
	local center = (task.cluster :: Cluster)[1]
	local reach = CONST.SQUARE_RADIUS + 2
	local grid =
		Host.collision({ x1 = center.x - reach, y1 = center.y - reach, x2 = center.x + reach, y2 = center.y + reach })
	if grid == nil then
		return nil
	end
	local g = grid :: Host.Collision
	local taken: { [string]: boolean } = {}
	for _, loc in ipairs(Objects.find() or {}) do
		for x = loc.x, loc.x + math.max(1, loc.size_x) - 1 do
			for y = loc.y, loc.y + math.max(1, loc.size_y) - 1 do
				taken[Read.key({ x = x, y = y })] = true
			end
		end
	end
	for _, item in ipairs(GroundItems.find() or {}) do
		taken[Read.key(item)] = true
	end
	local function open_tile(t: Tile): boolean
		local i, j = t.x - g.x, t.y - g.y
		if i < 0 or j < 0 or i >= g.width or j >= g.height then
			return false
		end
		local flags = g.flags[i * g.height + j + 1] or CONST.BLOCKED_FLAGS
		return bit32.band(flags, CONST.BLOCKED_FLAGS) == 0 and not taken[Read.key(t)]
	end
	local options: { Tile } = {}
	for dx = -CONST.SQUARE_RADIUS, CONST.SQUARE_RADIUS do
		for dy = -CONST.SQUARE_RADIUS, CONST.SQUARE_RADIUS do
			local c = { x = center.x + dx, y = center.y + dy, plane = center.plane }
			if not task.bad_squares[Read.key(c)] then
				local ok = true
				for _, t in ipairs(Read.free_tiles(c)) do
					if not open_tile(t) then
						ok = false
						break
					end
				end
				if ok then
					table.insert(options, c)
				end
			end
		end
	end
	if #options == 0 then
		return nil
	end
	return options[Random.int(1, #options)]
end

function Read.layout(task: Task, square: Tile)
	local positions = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } }
	for i = #positions, 2, -1 do
		local j = Random.int(1, i)
		positions[i], positions[j] = positions[j], positions[i]
	end
	task.spots, task.spare = {}, {}
	local limit = Read.limit(task)
	for i, d in ipairs(positions) do
		local tile = { x = square.x + d[1], y = square.y + d[2], plane = square.plane }
		table.insert(if i <= limit then task.spots else task.spare, tile)
	end
	task.stands = {}
	for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		table.insert(task.stands, { x = square.x + d[1], y = square.y + d[2], plane = square.plane })
	end
end

function Read.nearest(me: Host.Tile, spots: { Tile }): Tile?
	local best, best_d = nil, math.huge
	for _, spot in ipairs(spots) do
		local d = Walker.distance(me, spot)
		if d < best_d then
			best, best_d = spot, d
		end
	end
	return best
end

function Read.ours(task: Task): { Tile }
	local out: { Tile } = {}
	for _, spot in ipairs(task.spots) do
		if task.traps[Read.key(spot)] then
			table.insert(out, spot)
		end
	end
	return out
end

function Read.on_spot(task: Task, me: Host.Tile): boolean
	for _, spot in ipairs(task.spots) do
		if spot.x == me.x and spot.y == me.y then
			return true
		end
	end
	return false
end

function Read.trap_state(task: Task, me: Host.Tile): State
	local sprung: { Tile }, ground: { Tile }, empty: { Tile } = {}, {}, {}
	for _, spot in ipairs(task.spots) do
		local status = Read.trap_at(spot)
		local ours = task.traps[Read.key(spot)]
		if status == "sprung" and ours then
			table.insert(sprung, spot)
		elseif status == "ground" and ours then
			table.insert(ground, spot)
		elseif status == "empty" then
			local key = Read.key(spot)
			local since = task.empty_since[key] or time()
			task.empty_since[key] = since
			if not ours or time() - since >= CONST.EMPTY_GRACE_MS then
				task.traps[key] = nil
				table.insert(empty, spot)
			end
		end
		if status ~= "empty" then
			task.empty_since[Read.key(spot)] = nil
		end
	end
	local pending = table.clone(sprung)
	table.move(ground, 1, #ground, #pending + 1, pending)
	if #pending > 0 then
		table.sort(pending, function(a: Tile, b: Tile): boolean
			return (task.traps[Read.key(a)] or 0) < (task.traps[Read.key(b)] or 0)
		end)
		task.target = pending[1]
		return if table.find(sprung, pending[1]) then "RESET" else "RELAY"
	end
	if #empty > 0 and Inventory.contains(CONST.TRAP.ITEM) then
		task.target = Read.nearest(me, empty)
		return "LAY"
	end
	if #empty > 0 and #Read.ours(task) == 0 then
		task.blocked = "no box traps left to lay"
		return "BLOCKED"
	end
	if Read.on_spot(task, me) then
		return "STEP_OFF"
	end
	return "WAIT"
end

function Boxing.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	local me = Walker.position()
	if me == nil then
		return "WAIT"
	end
	if Inventory.contains(task.creature.part) then
		for _, spot in ipairs(task.spots) do
			local status = Read.trap_at(spot)
			if task.traps[Read.key(spot)] and status ~= "empty" then
				task.target = spot
				return "PACK"
			end
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
	if #area.clusters == 0 then
		task.blocked = `no known {task.creature.npc} spawns in the {area.name}`
		return "BLOCKED"
	end
	if task.cluster == nil then
		local picked = Read.pick_cluster(area)
		task.cluster = picked
		Log.log(NAME, `Picked the cluster at {picked[1].x}, {picked[1].y}`)
	end
	local cluster = task.cluster :: Cluster
	local center = cluster[1]
	if me.plane ~= center.plane or Walker.distance(me, center) > CONST.LEASH then
		return "CAMP"
	end
	if next(task.traps) == nil then
		task.busy = Read.occupied(task, cluster)
		if task.busy then
			return "HOP"
		end
	end
	if task.square == nil then
		return "SQUARE"
	end
	return Read.trap_state(task, me)
end

function Game.walk(goal: Tile, near: number, what: string, task: Task): boolean
	Log.log(NAME, `Walking to {what}`)
	local walked, why = Travel.walk(goal, near)
	if why then
		task.blocked = `no way to {what}: {why}`
	end
	return walked
end

function Game.spread(t: Tile, by: number): Tile
	return { x = t.x + Random.int(-by, by), y = t.y + Random.int(-by, by), plane = t.plane }
end

function Game.camp(task: Task): boolean
	local center = (task.cluster :: Cluster)[1]
	return Game.walk(Game.spread(center, 1), CONST.CAMP_NEAR, `the cluster at {center.x}, {center.y}`, task)
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
	Log.log(NAME, `The cluster is taken ({task.busy}), hopping worlds`)
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

function Game.square(task: Task): boolean
	local square = Read.pick_square(task)
	if square == nil then
		task.blocked =
			`no clear 3x3 square near the cluster at {(task.cluster :: Cluster)[1].x}, {(task.cluster :: Cluster)[1].y}`
		return false
	end
	task.square = square
	Read.layout(task, square)
	Log.log(NAME, `Setting {#task.spots} traps around {square.x}, {square.y}`)
	return true
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

function Game.stand_on(tile: Tile): boolean
	local me = Walker.position()
	if me and me.x == tile.x and me.y == tile.y then
		return true
	end
	if Walker.on_screen(tile) and Walker.walk_tile(tile) then
		return true
	end
	return Walker.walk(tile, { near = 0, plane = tile.plane }) and Walker.wait_arrival(tile)
end

function Game.watch_chat(): () -> { string }
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	return function(): { string }
		local lines = {}
		for _, m in ipairs(Chat.new_messages(seen) or {}) do
			seen = m.uid
			table.insert(lines, string.lower(m.text))
		end
		return lines
	end
end

function Game.lay(task: Task): boolean
	local spot = task.target :: Tile
	if not Game.stand_on(spot) then
		local key = Read.key(spot)
		task.stand_fails[key] = (task.stand_fails[key] or 0) + 1
		if task.stand_fails[key] >= CONST.STAND_ATTEMPTS then
			local index = table.find(task.spots, spot)
			if index then
				table.remove(task.spots, index)
			end
			local replacement = table.remove(task.spare)
			if replacement then
				table.insert(task.spots, replacement)
			end
			Log.log(NAME, `Can't stand on {spot.x}, {spot.y}, laying elsewhere`)
		end
		return false
	end
	local chat = Game.watch_chat()
	Log.log(NAME, `Laying a trap at {spot.x}, {spot.y}`)
	if not Inventory.interact(CONST.TRAP.ITEM, CONST.TRAP.LAY) then
		return false
	end
	local refused: string? = nil
	local laid = Game.wait_until(function(): boolean
		for _, line in ipairs(chat()) do
			if string.find(line, CONST.TRAP.CANT_LAY, 1, true) or string.find(line, CONST.TRAP.TOO_MANY, 1, true) then
				refused = line
			end
		end
		return refused ~= nil or Read.trap_at(spot) == "set"
	end, CONST.ACT_TIMEOUT_MS)
	if refused then
		local line = refused :: string
		Log.log(NAME, `Couldn't lay a trap at {spot.x}, {spot.y}: {line}`)
		if string.find(line, CONST.TRAP.TOO_MANY, 1, true) then
			task.limit = #Read.ours(task)
			task.spots = Read.ours(task)
		else
			task.bad_squares[Read.key(task.square :: Tile)] = true
			task.square = nil
		end
		return false
	end
	if laid then
		task.traps[Read.key(spot)] = time()
	end
	return laid
end

function Game.counted(task: Task, act: () -> boolean): boolean
	local before = Inventory.count_ex(task.creature.catch) or 0
	local ok = act()
	local gained = (Inventory.count_ex(task.creature.catch) or before) - before
	if gained > 0 then
		task.catches += gained
		Log.log(NAME, `Caught a {task.creature.npc} ({task.catches} so far)`)
	end
	return ok
end

function Game.prehover(task: Task, current: Tile)
	local best: Tile? = nil
	local best_rank, best_time = math.huge, math.huge
	for _, spot in ipairs(Read.ours(task)) do
		if spot ~= current then
			local status = Read.trap_at(spot)
			local rank = if status == "sprung" or status == "ground" then 1 elseif status == "set" then 2 else 3
			local laid = task.traps[Read.key(spot)] or 0
			if rank < 3 and (rank < best_rank or (rank == best_rank and laid < best_time)) then
				best, best_rank, best_time = spot, rank, laid
			end
		end
	end
	if best == nil then
		return
	end
	Random.sleep(CONST.PREHOVER_MS[1], CONST.PREHOVER_MS[2])
	local _, loc, item = Read.trap_at(best :: Tile)
	if loc then
		Objects.hover_async(loc)
	elseif item then
		GroundItems.hover_async(item)
	end
end

function Game.reset(task: Task): boolean
	local spot = task.target :: Tile
	local status, loc = Read.trap_at(spot)
	if status ~= "sprung" or loc == nil then
		return true
	end
	local trap = loc :: Loc
	local option = if Read.has_action(trap, CONST.TRAP.RESET) then CONST.TRAP.RESET else CONST.TRAP.CHECK
	Log.log(NAME, `{option} on the {string.lower(trap.name or "trap")} at {spot.x}, {spot.y}`)
	return Game.counted(task, function(): boolean
		if not Objects.interact(trap, option, false) then
			return false
		end
		Game.prehover(task, spot)
		local done = Game.wait_until(function(): boolean
			return Read.trap_at(spot) == "set" or (option == CONST.TRAP.CHECK and Read.trap_at(spot) == "empty")
		end, CONST.ACT_TIMEOUT_MS)
		if done then
			task.traps[Read.key(spot)] = time()
		end
		return done
	end)
end

function Game.relay(task: Task): boolean
	local spot = task.target :: Tile
	local status, _, item = Read.trap_at(spot)
	if status ~= "ground" or item == nil then
		return true
	end
	local trap = item :: GroundItem
	if not GroundItems.interact(trap, CONST.TRAP.LAY) and not GroundItems.interact(trap, CONST.TRAP.TAKE) then
		return false
	end
	Game.prehover(task, spot)
	local done = Game.wait_until(function(): boolean
		return Read.trap_at(spot) == "set"
	end, CONST.ACT_TIMEOUT_MS)
	if done then
		task.traps[Read.key(spot)] = time()
	end
	return done
end

function Game.step_off(task: Task): boolean
	local stepped = Game.wait_until(function(): boolean
		local now = Walker.position()
		return now ~= nil and not Read.on_spot(task, now)
	end, CONST.STEP_OFF_WAIT_MS)
	if stepped then
		return true
	end
	local me = Walker.position()
	local free: { Tile } = {}
	for _, t in ipairs(task.stands) do
		if Read.trap_at(t) == "empty" then
			table.insert(free, t)
		end
	end
	local stand = if me then Read.nearest(me, free) else nil
	if stand == nil then
		return false
	end
	return Game.stand_on(stand)
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
	local spot = task.target :: Tile
	local status, loc, item = Read.trap_at(spot)
	if status == "empty" then
		task.traps[Read.key(spot)] = nil
		return true
	elseif status == "busy" then
		return Game.wait()
	end
	Log.log(NAME, `Packing up the trap at {spot.x}, {spot.y}`)
	local ok = Game.counted(task, function(): boolean
		if item then
			return GroundItems.interact(item, CONST.TRAP.TAKE)
		end
		local trap = loc :: Loc
		local option = if Read.has_action(trap, CONST.TRAP.CHECK) then CONST.TRAP.CHECK else CONST.TRAP.DISMANTLE
		return Objects.interact(trap, option, false)
	end)
	if not ok then
		return false
	end
	local cleared = Game.wait_until(function(): boolean
		return Read.trap_at(spot) == "empty"
	end, CONST.ACT_TIMEOUT_MS)
	if cleared then
		task.traps[Read.key(spot)] = nil
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
	CAMP = Game.camp,
	HOP = Game.hop,
	SQUARE = Game.square,
	LAY = Game.lay,
	RESET = Game.reset,
	RELAY = Game.relay,
	STEP_OFF = Game.step_off,
	WAIT = function(_task: Task): boolean
		return Game.wait()
	end,
	PACK = Game.pack,
} :: { [State]: (Task) -> boolean }

function Boxing.step(task: Task, state: State): boolean
	if state == "WAIT" then
		task.idle = true
	elseif task.idle then
		task.idle = false
		local react = CONST.REACT_MS
		sleep(Biometrics.random_mode_integer(react.mode, react.min, react.max))
	end
	return Handler.states[state](task)
end

return Boxing
