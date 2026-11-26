--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type Loc = Host.Loc
local Biometrics = require("@volcren/biometrics")
local Chat = require("@volcren/chat")
local Hop = require("./hop")
local Idle = require("./idle")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Logs = require("./logs")
local Minimenu = require("@volcren/minimenu")
local Objects = require("@volcren/objects")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Travel = require("./travel")
local Walker = require("@volcren/walker")

local NAME = "Deadfall"

export type Tile = { x: number, y: number, plane: number }
export type Area = { name: string, arrive: Tile, boulders: { Tile } }
export type Creature = { name: string, npc: string, part: number, areas: { Area } }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "HOP" | "CHOP" | "SET" | "CHECK" | "WAIT" | "PACK"
export type Status = "empty" | "set" | "caught" | "busy"
export type Task = {
	creature: Creature,
	area: Area?,
	boulders: { Tile },
	traps: { [string]: number },
	empty_since: { [string]: number },
	target: Tile?,
	busy: string?,
	idle: boolean,
	claimed: boolean,
	chopping: boolean,
	log_goal: number,
	catches: number,
	blocked: string?,
}

local CONST = {
	ARRIVE_NEAR = 3,
	LEASH = 12,
	NEAR = 5,
	TRAPS = 2,
	BOULDER = { SET = "Set-trap", CHECK = "Check", DISMANTLE = "Dismantle" },
	PLAYER_RANGE = 8,
	EMPTY_GRACE_MS = 4000,
	ACT_TIMEOUT_MS = 10000,
	WAIT_MS = { 100, 250 },
	REACT_MS = { mode = 450, min = 0, max = 1800 },
	PREHOVER_MS = { 150, 450 },
	POLL_MS = 100,
}

local CREATURES: { [string]: Creature } = {
	["sabre-toothed kebbit"] = {
		name = "sabre-toothed kebbit",
		npc = "Sabre-toothed kebbit",
		part = 29223,
		areas = {
			{
				name = "Rellekka Hunter area",
				arrive = { x = 2712, y = 3773, plane = 0 },
				boulders = {
					{ x = 2706, y = 3779, plane = 0 },
					{ x = 2708, y = 3773, plane = 0 },
					{ x = 2710, y = 3769, plane = 0 },
					{ x = 2710, y = 3777, plane = 0 },
					{ x = 2711, y = 3772, plane = 0 },
					{ x = 2714, y = 3779, plane = 0 },
					{ x = 2715, y = 3765, plane = 0 },
					{ x = 2715, y = 3769, plane = 0 },
					{ x = 2718, y = 3776, plane = 0 },
					{ x = 2719, y = 3763, plane = 0 },
				},
			},
		},
	},
	["pyre fox"] = {
		name = "pyre fox",
		npc = "Pyre fox",
		part = 29233,
		areas = {
			{
				name = "Avium Savannah",
				arrive = { x = 1616, y = 2998, plane = 0 },
				boulders = {
					{ x = 1612, y = 2997, plane = 0 },
					{ x = 1613, y = 3002, plane = 0 },
					{ x = 1616, y = 2993, plane = 0 },
					{ x = 1619, y = 3001, plane = 0 },
					{ x = 1623, y = 2996, plane = 0 },
				},
			},
		},
	},
}

local TRAP_STATES: { [number]: Status } = {
	[19215] = "empty",
	[19217] = "set",
	[19216] = "busy",
	[19218] = "busy",
	[19219] = "busy",
	[19851] = "busy",
	[20128] = "busy",
	[20129] = "busy",
	[20130] = "busy",
	[20131] = "busy",
	[20647] = "busy",
	[20652] = "busy",
	[50724] = "busy",
	[50725] = "busy",
	[20648] = "caught",
	[20649] = "caught",
	[20650] = "caught",
	[20651] = "caught",
	[50726] = "caught",
}

local Deadfall = {}
local Read, Game, Handler = {}, {}, {}

Deadfall.CREATURES = table.freeze(CREATURES)

function Deadfall.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Deadfall.new(prey: string): Task?
	local creature = Deadfall.creature(prey)
	if creature == nil then
		return nil
	end
	return {
		creature = creature,
		boulders = {},
		traps = {},
		empty_since = {},
		idle = false,
		claimed = false,
		chopping = false,
		log_goal = Logs.goal(1),
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

function Read.boulder_at(boulder: Tile): (Status, Loc?)
	for _, loc in ipairs(Objects.find() or {}) do
		local status = TRAP_STATES[loc.id]
		if
			status
			and loc.plane == boulder.plane
			and boulder.x >= loc.x
			and boulder.x < loc.x + math.max(loc.size_x, 1)
			and boulder.y >= loc.y
			and boulder.y < loc.y + math.max(loc.size_y, 1)
		then
			return status, loc
		end
	end
	return "busy", nil
end

function Read.player_near(area: Area): string?
	local me = Players.me()
	for _, p in ipairs(Players.find() or {}) do
		if me == nil or p.index ~= me.index then
			for _, boulder in ipairs(area.boulders) do
				if Walker.distance(boulder, p) <= CONST.PLAYER_RANGE then
					return `{p.name} is there`
				end
			end
		end
	end
	return nil
end

function Read.occupied(task: Task, area: Area): string?
	local near = Read.player_near(area)
	if near then
		return near
	end
	for _, boulder in ipairs(area.boulders) do
		if Read.boulder_at(boulder) ~= "empty" and not task.traps[Read.key(boulder)] then
			return `the boulder at {boulder.x}, {boulder.y} is in use`
		end
	end
	return nil
end

function Read.adopt(task: Task, area: Area)
	local adopted: { Tile } = {}
	for _, boulder in ipairs(area.boulders) do
		if Read.boulder_at(boulder) ~= "empty" and #adopted < CONST.TRAPS then
			task.traps[Read.key(boulder)] = time()
			table.insert(adopted, boulder)
		end
	end
	if #adopted > 0 then
		task.boulders = adopted
		Log.log(NAME, `Taking over {#adopted} traps already set here`)
	end
end

function Read.pick_boulders(task: Task, area: Area)
	local first = task.boulders[1] or area.boulders[Random.int(1, #area.boulders)]
	local by_distance = table.clone(area.boulders)
	table.sort(by_distance, function(a: Tile, b: Tile): boolean
		return Walker.distance(first, a) < Walker.distance(first, b)
	end)
	for _, boulder in ipairs(by_distance) do
		if #task.boulders >= CONST.TRAPS then
			break
		end
		if not table.find(task.boulders, boulder) then
			table.insert(task.boulders, boulder)
		end
	end
	Log.log(NAME, `Setting {#task.boulders} deadfalls around {first.x}, {first.y}`)
end

function Read.ours(task: Task): { Tile }
	local out: { Tile } = {}
	for _, boulder in ipairs(task.boulders) do
		if task.traps[Read.key(boulder)] then
			table.insert(out, boulder)
		end
	end
	return out
end

function Read.trap_state(task: Task, me: Host.Tile): State
	local caught: { Tile }, empty: { Tile } = {}, {}
	for _, boulder in ipairs(task.boulders) do
		local key = Read.key(boulder)
		local status = Read.boulder_at(boulder)
		local ours = task.traps[key] ~= nil
		if status == "caught" and ours then
			table.insert(caught, boulder)
		elseif status == "empty" then
			local since = task.empty_since[key] or time()
			task.empty_since[key] = since
			if not ours or time() - since >= CONST.EMPTY_GRACE_MS then
				task.traps[key] = nil
				table.insert(empty, boulder)
			end
		end
		if status ~= "empty" then
			task.empty_since[key] = nil
		end
	end
	local best: Tile? = nil
	local best_state: State = "WAIT"
	local best_d = math.huge
	for _, boulder in ipairs(caught) do
		local d = Walker.distance(me, boulder)
		if d < best_d then
			best, best_state, best_d = boulder, "CHECK", d
		end
	end
	if Logs.count() > 0 then
		for _, boulder in ipairs(empty) do
			local d = Walker.distance(me, boulder)
			if d < best_d then
				best, best_state, best_d = boulder, "SET", d
			end
		end
	end
	if best then
		task.target = best
		return best_state
	end
	local logs = Logs.count()
	if task.chopping and logs >= task.log_goal then
		task.chopping, task.log_goal = false, Logs.goal(1)
	elseif not task.chopping and logs == 0 then
		task.chopping = true
	end
	if task.chopping then
		return "CHOP"
	end
	return "WAIT"
end

function Deadfall.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	local me = Walker.position()
	if me == nil then
		return "WAIT"
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
	local far = me.plane ~= area.arrive.plane or Walker.distance(me, area.arrive) > CONST.LEASH
	if Inventory.contains(task.creature.part) then
		if not far then
			for _, boulder in ipairs(Read.ours(task)) do
				local status = Read.boulder_at(boulder)
				if status == "caught" or status == "set" then
					task.target = boulder
					return "PACK"
				end
			end
		end
		return "DONE"
	end
	if far then
		return "TRAVEL"
	end
	if next(task.traps) == nil and #task.boulders == 0 and Read.player_near(area) == nil then
		Read.adopt(task, area)
	end
	if not task.claimed then
		task.busy = Read.occupied(task, area)
		if task.busy then
			return "HOP"
		end
		task.claimed = true
	end
	if #task.boulders < math.min(CONST.TRAPS, #area.boulders) then
		Read.pick_boulders(task, area)
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
	Log.log(NAME, `Travelling to the boulders in the {area.name}`)
	local walked, why = Travel.walk(goal, CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.hop(task: Task): boolean
	return Hop.away(NAME, `The boulders are in use ({task.busy})`)
end

function Game.chop(task: Task): boolean
	local ok, why = Logs.chop(NAME, function(): boolean
		for _, boulder in ipairs(Read.ours(task)) do
			if Read.boulder_at(boulder) == "caught" then
				return true
			end
		end
		return false
	end)
	if why then
		task.blocked = why
	end
	return ok
end

function Game.prehover(task: Task, current: Tile)
	for _, boulder in ipairs(Read.ours(task)) do
		if boulder ~= current then
			local status, loc = Read.boulder_at(boulder)
			if (status == "caught" or status == "set") and loc then
				Random.sleep(CONST.PREHOVER_MS[1], CONST.PREHOVER_MS[2])
				Objects.hover_async(loc :: Loc)
				return
			end
		end
	end
end

function Game.set(task: Task): boolean
	local boulder = task.target :: Tile
	local status, loc = Read.boulder_at(boulder)
	if status ~= "empty" or loc == nil then
		return true
	end
	Log.log(NAME, `Setting a deadfall on the boulder at {boulder.x}, {boulder.y}`)
	if not Objects.approach(loc :: Loc, CONST.BOULDER.SET) then
		return false
	end
	Game.prehover(task, boulder)
	local set = Game.wait_until(function(): boolean
		local now = Read.boulder_at(boulder)
		return now == "set" or now == "caught"
	end, CONST.ACT_TIMEOUT_MS)
	if set then
		task.traps[Read.key(boulder)] = time()
	end
	return set
end

function Game.use(loc: Loc, option: string): boolean
	local me = Walker.position()
	if me and Walker.distance(me, loc) <= CONST.NEAR and Objects.interact(loc, option, false) then
		return true
	end
	return Objects.approach(loc, option)
end

function Game.check(task: Task): boolean
	local boulder = task.target :: Tile
	local status, loc = Read.boulder_at(boulder)
	if status ~= "caught" or loc == nil then
		return true
	end
	Log.log(NAME, `Checking the deadfall at {boulder.x}, {boulder.y}`)
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Game.use(loc :: Loc, CONST.BOULDER.CHECK) then
		Log.log(NAME, `Couldn't click Check on the deadfall at {boulder.x}, {boulder.y}`)
		return false
	end
	Game.prehover(task, boulder)
	local checked = Game.wait_until(function(): boolean
		return Read.boulder_at(boulder) == "empty"
	end, CONST.ACT_TIMEOUT_MS)
	if checked then
		task.catches += 1
		task.traps[Read.key(boulder)] = nil
		Log.log(NAME, `Caught: {task.creature.npc} ({task.catches} so far)`)
	else
		local lines: { string } = {}
		for _, m in ipairs(Chat.new_messages(seen) or {}) do
			table.insert(lines, m.text)
		end
		local clicked = Minimenu.clicked()
		local me = Walker.position()
		Log.log(
			NAME,
			`The deadfall at {boulder.x}, {boulder.y} is still {(Read.boulder_at(boulder))} after Check: clicked "{clicked and Minimenu.text(
				clicked.entry
			) or "?"}", standing at {me and me.x}, {me and me.y}, chat [{table.concat(lines, " | ")}]`
		)
	end
	return checked
end

function Game.wait(): boolean
	Idle.wait(CONST.WAIT_MS)
	return true
end

function Game.pack(task: Task): boolean
	local boulder = task.target :: Tile
	local status, loc = Read.boulder_at(boulder)
	if loc == nil or (status ~= "caught" and status ~= "set") then
		task.traps[Read.key(boulder)] = nil
		return true
	end
	local option = if status == "caught" then CONST.BOULDER.CHECK else CONST.BOULDER.DISMANTLE
	Log.log(NAME, `Packing up: {option} on the deadfall at {boulder.x}, {boulder.y}`)
	if not Game.use(loc :: Loc, option) then
		return false
	end
	local cleared = Game.wait_until(function(): boolean
		return Read.boulder_at(boulder) == "empty"
	end, CONST.ACT_TIMEOUT_MS)
	if cleared then
		task.traps[Read.key(boulder)] = nil
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
	CHOP = Game.chop,
	SET = Game.set,
	CHECK = Game.check,
	WAIT = function(_task: Task): boolean
		return Game.wait()
	end,
	PACK = Game.pack,
} :: { [State]: (Task) -> boolean }

function Deadfall.step(task: Task, state: State): boolean
	if state == "WAIT" then
		task.idle = true
	elseif task.idle then
		task.idle = false
		local react = CONST.REACT_MS
		sleep(Biometrics.random_mode_integer(react.mode, react.min, react.max))
	end
	return Handler.states[state](task)
end

return Deadfall
