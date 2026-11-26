--!strict
local Host = require("@volcren/host")
type ClientState = Host.ClientState
local Idle = require("./idle")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Npcs = require("@volcren/npcs")
local Random = require("@volcren/random")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Falconry"

export type Tile = { x: number, y: number, plane: number }
export type Box = { x1: number, y1: number, x2: number, y2: number }
export type Area = { name: string, anchor: Tile, box: Box }
export type Creature = { name: string, npc: string, part: number, fur: string, areas: { Area } }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "GET_FALCON" | "CATCH" | "RETRIEVE" | "WAIT"
export type Task = {
	creature: Creature,
	area: Area?,
	prey: number?,
	sent_at: number,
	catches: number,
	missed: { [number]: number },
	misses: number,
	blocked: string?,
}

local CONST = {
	MISSED_MS = 6000,
	MISSES = 6,
	ARRIVE_NEAR = 3,
	ANCHOR_NEAR = 4,
	FALCONER = {
		NPC = "Matthias",
		OPTION = "Quick-falcon",
		FEE = 500,
		BOX = { x1 = 2370, y1 = 3600, x2 = 2381, y2 = 3612 },
		SEEN = 10,
	},
	GLOVE = "Falconer's glove",
	GLOVE_READY = 10024,
	FALCON = { NPCS = { [1342] = true, [1343] = true, [1344] = true }, OPTION = "Retrieve" },
	CATCH_OPTION = "Catch",
	CAUGHT = "captures the kebbit",
	RETRIEVED = "You retrieve the falcon",
	FLIGHT_TIMEOUT_MS = 6000,
	RETRIEVE_TIMEOUT_MS = 8000,
	WAIT_MS = { 100, 250 },
	HANDS = { "weapon", "shield", "hands" },
	GLOVE_TIMEOUT_MS = 6000,
	POLL_MS = 100,
}

local CREATURES: { [string]: Creature } = {
	["dark kebbit"] = {
		name = "dark kebbit",
		npc = "Dark kebbit",
		part = 29223,
		fur = "Dark kebbit fur",
		areas = {
			{
				name = "Piscatoris falconry area",
				anchor = { x = 2375, y = 3587, plane = 0 },
				box = { x1 = 2364, y1 = 3573, x2 = 2393, y2 = 3597 },
			},
		},
	},
	["dashing kebbit"] = {
		name = "dashing kebbit",
		npc = "Dashing kebbit",
		part = 29223,
		fur = "Dashing kebbit fur",
		areas = {
			{
				name = "Piscatoris falconry area",
				anchor = { x = 2375, y = 3587, plane = 0 },
				box = { x1 = 2364, y1 = 3573, x2 = 2393, y2 = 3597 },
			},
		},
	},
	["spotted kebbit"] = {
		name = "spotted kebbit",
		npc = "Spotted kebbit",
		part = 29223,
		fur = "Spotted kebbit fur",
		areas = {
			{
				name = "Piscatoris falconry area",
				anchor = { x = 2375, y = 3587, plane = 0 },
				box = { x1 = 2364, y1 = 3573, x2 = 2393, y2 = 3597 },
			},
		},
	},
}

local Falconry = {}
local Read, Game, Handler = {}, {}, {}

Falconry.CREATURES = table.freeze(CREATURES)

function Falconry.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Falconry.new(prey: string): Task?
	local creature = Falconry.creature(prey)
	if creature == nil then
		return nil
	end
	return { creature = creature, sent_at = 0, catches = 0, missed = {}, misses = 0 }
end

function Read.in_box(b: Box, p: { x: number, y: number }): boolean
	return p.x >= b.x1 and p.x <= b.x2 and p.y >= b.y1 and p.y <= b.y2
end

function Read.target(task: Task): Host.Npc?
	local me = Walker.position()
	local area = task.area
	if me == nil or area == nil then
		return nil
	end
	local now, best, best_d = Host.time(), nil, math.huge
	for _, npc in ipairs(Npcs.find(task.creature.npc) or {}) do
		local d = Walker.distance(me, npc)
		if Read.in_box((area :: Area).box, npc) and (task.missed[npc.index] or 0) < now and d < best_d then
			best, best_d = npc, d
		end
	end
	return best
end

function Read.falconer(): Host.Npc?
	local me = Walker.position()
	if me == nil then
		return nil
	end
	local falconer = Npcs.nearest(CONST.FALCONER.NPC, me)
	if falconer and Walker.distance(me, falconer) <= CONST.FALCONER.SEEN then
		return falconer
	end
	return nil
end

function Read.inside(area: Area, state: ClientState): boolean
	local p = state.position
	return p ~= nil and p.plane == area.anchor.plane and Read.in_box(area.box, p)
end

function Read.nearest_area(c: Creature, me: Host.Tile): Area?
	local best, best_d = nil, math.huge
	for _, area in ipairs(c.areas) do
		local d = Walker.distance(me, area.anchor)
		if d < best_d then
			best, best_d = area, d
		end
	end
	return best
end

function Falconry.state(task: Task): State
	if task.blocked then
		return "BLOCKED"
	end
	if task.prey == nil and Inventory.contains(task.creature.part) then
		return "DONE"
	end
	local me = Walker.position()
	if me == nil then
		return "TRAVEL"
	end
	if task.area == nil then
		task.area = Read.nearest_area(task.creature, me)
		if task.area == nil then
			task.blocked = `no known {task.creature.npc} areas`
			return "BLOCKED"
		end
		Log.log(NAME, `Hunting {task.creature.npc} in the {(task.area :: Area).name}`)
	end
	if not Read.has_falcon() then
		return "GET_FALCON"
	end
	if Read.our_falcon(task) then
		return "RETRIEVE"
	end
	if not Read.falcon_ready() then
		return if task.prey == nil then "GET_FALCON" else "WAIT"
	end
	task.prey = nil
	if Read.target(task) then
		return "CATCH"
	end
	local area = task.area :: Area
	if not Read.inside(area, Host.game_state()) or Walker.distance(me, area.anchor) > CONST.ANCHOR_NEAR then
		return "TRAVEL"
	end
	return "WAIT"
end

function Read.falcon_ready(): boolean
	return Wornitems.is_wearing(CONST.GLOVE_READY)
end

function Read.our_falcon(task: Task): Host.Npc?
	if task.prey == nil then
		return nil
	end
	for _, npc in ipairs(Npcs.find() or {}) do
		if npc.index == task.prey and CONST.FALCON.NPCS[npc.id] then
			return npc
		end
	end
	return nil
end

function Read.has_falcon(): boolean
	return Wornitems.is_wearing(CONST.GLOVE)
end

function Read.hands_to_free(): number
	local worn = Wornitems.worn() or {}
	local n = 0
	for _, slot in ipairs(CONST.HANDS) do
		if worn[slot] ~= nil then
			n += 1
		end
	end
	return n
end

function Game.travel(task: Task): boolean
	local area = task.area :: Area
	local goal = Travel.spread(area.anchor)
	local walked, why = Travel.walk(goal, CONST.ARRIVE_NEAR, function(): boolean
		return Read.falcon_ready() and Read.target(task) ~= nil
	end)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.get_falcon(task: Task): boolean
	local fee = CONST.FALCONER.FEE
	if (Inventory.count_ex("Coins") or 0) < fee then
		task.blocked = `fewer than {fee} coins to hire a falcon`
		return false
	end
	if (Inventory.free_slots() or 0) < Read.hands_to_free() then
		task.blocked = "no inventory space for the gear the falcon glove replaces"
		return false
	end
	local falconer = Read.falconer()
	if falconer == nil then
		local b = CONST.FALCONER.BOX
		local goal = { x = math.round(Random.mean(b.x1, b.x2)), y = math.round(Random.mean(b.y1, b.y2)), plane = 0 }
		Log.log(NAME, `Walking to {CONST.FALCONER.NPC} for a falcon`)
		Travel.walk(goal, 0, function(): boolean
			return Read.falconer() ~= nil
		end)
		falconer = Read.falconer()
		if falconer == nil then
			return false
		end
	end
	Log.log(NAME, `Hiring a falcon from {CONST.FALCONER.NPC} for {fee} coins`)
	if not Npcs.approach(falconer :: Host.Npc, CONST.FALCONER.OPTION) then
		return false
	end
	local deadline = Host.time() + CONST.GLOVE_TIMEOUT_MS
	repeat
		if Read.falcon_ready() then
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return Read.falcon_ready()
end

function Game.catch(task: Task): boolean
	local kebbit = Read.target(task)
	if kebbit == nil then
		return true
	end
	local target = kebbit :: Host.Npc
	if not Npcs.interact(target, CONST.CATCH_OPTION, false) then
		task.missed[target.index] = Host.time() + CONST.MISSED_MS
		task.misses += 1
		if task.misses < CONST.MISSES then
			return true
		end
		task.misses = 0
		return false
	end
	task.misses = 0
	task.prey = target.index
	task.sent_at = Host.time()
	local deadline = Host.time() + CONST.FLIGHT_TIMEOUT_MS
	repeat
		if not Read.falcon_ready() then
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return false
end

function Game.retrieve(task: Task): boolean
	local falcon = Read.our_falcon(task)
	if falcon == nil then
		return true
	end
	local before = Inventory.count_ex(task.creature.fur) or 0
	if not Npcs.interact(falcon :: Host.Npc, CONST.FALCON.OPTION, false) then
		return false
	end
	local deadline = Host.time() + CONST.RETRIEVE_TIMEOUT_MS
	repeat
		if Read.falcon_ready() then
			task.prey = nil
			task.catches += 1
			Log.log(NAME, `Caught: {task.creature.npc} ({task.catches} so far)`)
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return (Inventory.count_ex(task.creature.fur) or 0) > before
end

function Game.wait(task: Task): boolean
	if task.prey ~= nil and Host.time() - task.sent_at > CONST.RETRIEVE_TIMEOUT_MS then
		task.prey = nil
	end
	Idle.wait(CONST.WAIT_MS)
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
	GET_FALCON = Game.get_falcon,
	CATCH = Game.catch,
	RETRIEVE = Game.retrieve,
	WAIT = Game.wait,
} :: { [State]: (Task) -> boolean }

function Falconry.step(task: Task, state: State): boolean
	return Handler.states[state](task)
end

return Falconry
