--!strict
local Chat = require("@volcren/chat")
local Host = require("@volcren/host")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Herbiboar"

export type Tile = { x: number, y: number, plane: number }
type Point = { x: number, y: number }
type Trail = { varbit: number, value: number }
type Spot = { at: Point, trails: { Trail } }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "WIELD" | "START" | "SEARCH" | "TUNNEL" | "HARVEST"
export type Task = {
	part: number,
	catches: number,
	misses: number,
	blocked: string?,
}

local CONST = {
	PART = 29239,
	ARRIVE = { x = 3690, y = 3862, plane = 0 },
	ARRIVE_NEAR = 4,
	REGIONS = { [14652] = true, [14651] = true, [14908] = true, [14907] = true },
	STARTS = {
		{ x = 3686, y = 3870 },
		{ x = 3705, y = 3830 },
		{ x = 3704, y = 3810 },
		{ x = 3695, y = 3800 },
		{ x = 3751, y = 3850 },
	} :: { Point },
	START_IDS = { [30519] = true, [30520] = true, [30521] = true, [30522] = true, [30523] = true },
	TUNNELS = {
		{ x = 3693, y = 3798 },
		{ x = 3702, y = 3808 },
		{ x = 3703, y = 3826 },
		{ x = 3710, y = 3881 },
		{ x = 3700, y = 3877 },
		{ x = 3715, y = 3840 },
		{ x = 3751, y = 3849 },
		{ x = 3685, y = 3869 },
		{ x = 3681, y = 3863 },
	} :: { Point },
	TUNNEL_ID = 30532,
	FINISH_VARBIT = 5766,
	HERBIBOAR = "Herbiboar",
	HERBIBOAR_IDS = {
		[7785] = true,
		[7786] = true,
		[7831] = true,
		[7832] = true,
		[7833] = true,
		[7834] = true,
		[7835] = true,
		[7836] = true,
		[7837] = true,
		[7838] = true,
		[7839] = true,
	},
	NEAR_TUNNEL = 5,
	HERBIBOAR_RANGE = 20,
	INSPECT = "Inspect",
	SECATEURS = "Magic secateurs",
	WIELD = "Wield",
	WIELD_TIMEOUT_MS = 2400,
	ATTACK = "Attack",
	HARVEST = "Harvest",
	NEAREST_START = 70,
	ACT_TIMEOUT_MS = 12000,
	HARVEST_TIMEOUT_MS = 8000,
	MISSES = 4,
	POLL_MS = 100,
	PAUSE_MS = { 150, 700 },
	CONFUSED = "confused you with its tracks",
}

local S95, S96, S91 = 5742, 5743, 5738
local SPOTS: { Spot } = {
	{ at = { x = 3670, y = 3889 }, trails = { { varbit = S95, value = 1 }, { varbit = S96, value = 1 } } },
	{ at = { x = 3672, y = 3890 }, trails = { { varbit = S91, value = 2 } } },
	{
		at = { x = 3728, y = 3893 },
		trails = {
			{ varbit = 5741, value = 2 },
			{ varbit = S95, value = 2 },
			{ varbit = 5769, value = 1 },
			{ varbit = 5770, value = 1 },
		},
	},
	{ at = { x = 3697, y = 3875 }, trails = { { varbit = 5737, value = 2 } } },
	{ at = { x = 3699, y = 3875 }, trails = { { varbit = 5740, value = 1 }, { varbit = 5741, value = 1 } } },
	{ at = { x = 3708, y = 3876 }, trails = { { varbit = 5746, value = 1 }, { varbit = 5768, value = 1 } } },
	{ at = { x = 3710, y = 3877 }, trails = { { varbit = 5740, value = 2 }, { varbit = 5770, value = 2 } } },
	{ at = { x = 3668, y = 3865 }, trails = { { varbit = 5771, value = 1 }, { varbit = 5772, value = 1 } } },
	{ at = { x = 3667, y = 3862 }, trails = { { varbit = S96, value = 2 } } },
	{
		at = { x = 3681, y = 3860 },
		trails = { { varbit = 5744, value = 1 }, { varbit = 5745, value = 1 }, { varbit = 5771, value = 2 } },
	},
	{ at = { x = 3681, y = 3859 }, trails = { { varbit = 5739, value = 2 } } },
	{ at = { x = 3694, y = 3847 }, trails = { { varbit = 5768, value = 2 }, { varbit = 5775, value = 1 } } },
	{ at = { x = 3698, y = 3847 }, trails = { { varbit = 5745, value = 2 } } },
	{ at = { x = 3715, y = 3851 }, trails = { { varbit = 5776, value = 1 }, { varbit = 5777, value = 1 } } },
	{ at = { x = 3713, y = 3850 }, trails = { { varbit = 5746, value = 2 }, { varbit = 5747, value = 1 } } },
	{ at = { x = 3680, y = 3838 }, trails = { { varbit = 5773, value = 1 }, { varbit = 5774, value = 1 } } },
	{ at = { x = 3680, y = 3836 }, trails = { { varbit = 5744, value = 2 }, { varbit = 5772, value = 2 } } },
	{ at = { x = 3713, y = 3840 }, trails = { { varbit = 5776, value = 2 }, { varbit = 5750, value = 1 } } },
	{
		at = { x = 3706, y = 3811 },
		trails = { { varbit = 5773, value = 2 }, { varbit = 5748, value = 1 }, { varbit = 5749, value = 1 } },
	},
}

local Herbiboar = {}
local Read, Game, Handler = {}, {}, {}

function Herbiboar.new(prey: string): Task?
	if string.lower(prey) ~= "herbiboar" then
		return nil
	end
	return { part = CONST.PART, catches = 0, misses = 0 }
end

function Read.region(me: Host.Tile): number
	return (me.x // 64) * 256 + me.y // 64
end

function Read.active_spot(): Spot?
	for _, spot in ipairs(SPOTS) do
		for _, trail in ipairs(spot.trails) do
			if Host.varbit(trail.varbit) == trail.value then
				return spot
			end
		end
	end
	return nil
end

function Read.any_trail(): boolean
	if (Host.varbit(CONST.FINISH_VARBIT) or 0) > 0 then
		return true
	end
	for _, spot in ipairs(SPOTS) do
		for _, trail in ipairs(spot.trails) do
			if (Host.varbit(trail.varbit) or 0) ~= 0 then
				return true
			end
		end
	end
	return false
end

function Read.herbiboar(): Host.Npc?
	local me = Walker.position()
	if me == nil then
		return nil
	end
	for _, npc in ipairs(Npcs.find() or {}) do
		local named = npc.name == CONST.HERBIBOAR or CONST.HERBIBOAR_IDS[npc.id] == true
		if named and Walker.distance(me, npc) <= CONST.HERBIBOAR_RANGE then
			return npc
		end
	end
	return nil
end

function Read.loc_at(at: Point, accept: (Host.Loc) -> boolean): Host.Loc?
	for _, loc in ipairs(Objects.find() or {}) do
		if loc.x == at.x and loc.y == at.y and accept(loc) then
			return loc
		end
	end
	return nil
end

function Herbiboar.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	local me = Walker.position()
	local inside = me ~= nil and CONST.REGIONS[Read.region(me :: Host.Tile)] == true
	if Read.herbiboar() then
		return "HARVEST"
	end
	if not Read.any_trail() and Inventory.contains(task.part) then
		return "DONE"
	end
	if not inside then
		return "TRAVEL"
	end
	if Inventory.contains(CONST.SECATEURS) and not Wornitems.is_wearing(CONST.SECATEURS) then
		return "WIELD"
	end
	if (Host.varbit(CONST.FINISH_VARBIT) or 0) > 0 then
		return "TUNNEL"
	end
	if Read.active_spot() then
		return "SEARCH"
	end
	return "START"
end

function Game.travel(task: Task): boolean
	if task.catches == 0 then
		Log.log(NAME, "Travelling to the Mushroom Forest")
	end
	local walked, why = Travel.walk(Travel.spread(CONST.ARRIVE), CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the Mushroom Forest: {why}`
	end
	return walked
end

function Game.wield(task: Task): boolean
	if not Inventory.interact(CONST.SECATEURS, CONST.WIELD) then
		return Game.miss(task, "wield the magic secateurs")
	end
	local deadline = Host.time() + CONST.WIELD_TIMEOUT_MS
	repeat
		if Wornitems.is_wearing(CONST.SECATEURS) then
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return Game.miss(task, "wield the magic secateurs")
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

function Game.act(loc: Host.Loc, option: string, done: () -> boolean): (boolean, boolean)
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Objects.approach(loc, option) then
		return false, false
	end
	local deadline = Host.time() + CONST.ACT_TIMEOUT_MS
	repeat
		if done() then
			return true, false
		end
		for _, m in ipairs(Chat.new_messages(seen) or {}) do
			seen = m.uid
			if string.find(m.text, CONST.CONFUSED, 1, true) then
				return false, true
			end
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return done(), false
end

function Game.start(task: Task): boolean
	local me = Walker.position() :: Host.Tile
	local starts = table.clone(CONST.STARTS)
	table.sort(starts, function(a, b)
		return Walker.distance(me, a) < Walker.distance(me, b)
	end)
	local pick = if Random.int(1, 100) <= CONST.NEAREST_START then starts[1] else starts[Random.int(1, #starts)]
	local loc = Read.loc_at(pick, function(l)
		return CONST.START_IDS[l.id] == true
	end)
	if loc == nil then
		return (Travel.walk({ x = pick.x, y = pick.y, plane = 0 }, CONST.ARRIVE_NEAR))
	end
	local ok = Game.act(loc :: Host.Loc, CONST.INSPECT, Read.any_trail)
	if not ok then
		return Game.miss(task, `start a trail at {pick.x}, {pick.y}`)
	end
	task.misses = 0
	Log.log(NAME, `Started a trail at {pick.x}, {pick.y}`)
	Random.sleep(CONST.PAUSE_MS[1], CONST.PAUSE_MS[2])
	return true
end

function Game.search(task: Task): boolean
	local spot = Read.active_spot() :: Spot
	local loc = Read.loc_at(spot.at, function(l)
		return l.name ~= nil and l.name ~= ""
	end)
	if loc == nil then
		return (Travel.walk({ x = spot.at.x, y = spot.at.y, plane = 0 }, CONST.ARRIVE_NEAR))
	end
	local ok, confused = Game.act(loc :: Host.Loc, CONST.INSPECT, function()
		return Read.active_spot() ~= spot
	end)
	if confused then
		Log.log(NAME, "The herbiboar confused us, starting a new trail")
		return true
	end
	if not ok then
		return Game.miss(task, `search the spot at {spot.at.x}, {spot.at.y}`)
	end
	task.misses = 0
	Random.sleep(CONST.PAUSE_MS[1], CONST.PAUSE_MS[2])
	return true
end

function Game.tunnel(task: Task): boolean
	local finish = Host.varbit(CONST.FINISH_VARBIT) or 0
	local at = CONST.TUNNELS[finish]
	if at == nil then
		task.blocked = `unknown herbiboar tunnel {finish}`
		return false
	end
	local loc = Read.loc_at(at, function(l)
		return l.id == CONST.TUNNEL_ID
	end)
	if loc == nil then
		return (Travel.walk({ x = at.x, y = at.y, plane = 0 }, CONST.ARRIVE_NEAR))
	end
	local xp = Stats.xp("Hunter") or 0
	local ok = Game.act(loc :: Host.Loc, CONST.ATTACK, function()
		return Read.herbiboar() ~= nil or (Stats.xp("Hunter") or 0) > xp
	end)
	if not ok then
		return Game.miss(task, `attack the tunnel at {at.x}, {at.y}`)
	end
	task.misses = 0
	if Read.herbiboar() == nil then
		local seen: { string } = {}
		for _, npc in ipairs(Npcs.find() or {}) do
			if Walker.distance(at, npc) <= CONST.NEAR_TUNNEL then
				table.insert(seen, `{npc.id} "{npc.name}" at {npc.x}, {npc.y}`)
			end
		end
		Log.log(NAME, `Caught at the tunnel, but no herbiboar to harvest; next to it: {table.concat(seen, "; ")}`)
	end
	return true
end

function Game.harvest(task: Task): boolean
	local boar = Read.herbiboar() :: Host.Npc
	if not Npcs.interact(boar, CONST.HARVEST) then
		return Game.miss(task, "harvest the herbiboar")
	end
	local deadline = Host.time() + CONST.HARVEST_TIMEOUT_MS
	repeat
		if Read.herbiboar() == nil then
			task.misses = 0
			task.catches += 1
			Log.log(NAME, `Caught: Herbiboar ({task.catches} so far)`)
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return Game.miss(task, "finish harvesting the herbiboar")
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
	SEARCH = Game.search,
	TUNNEL = Game.tunnel,
	HARVEST = Game.harvest,
} :: { [State]: (Task) -> boolean }

function Herbiboar.step(task: Task, state: State): boolean
	return Handler.states[state](task)
end

return Herbiboar
