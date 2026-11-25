--!strict
local Host = require("@volcren/host")
type ClientState = Host.ClientState
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Npcs = require("@volcren/npcs")
local Position = require("@volcren/position")
local Random = require("@volcren/random")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Falconry"

export type Tile = { x: number, y: number, plane: number }
export type Area = { name: string, mapsquare: { x: number, y: number }, arrive: Tile }
export type Creature = { name: string, npc: string, part: number, fur: string, areas: { Area } }
export type State = "BLOCKED" | "DONE" | "TRAVEL" | "GET_FALCON" | "CATCH" | "RETRIEVE" | "WAIT"
export type Task = {
	creature: Creature,
	area: Area?,
	prey: number?,
	sent_at: number,
	catches: number,
	blocked: string?,
}

local CONST = {
	ARRIVE_NEAR = 3,
	ARRIVE_SPREAD = 1,
	FENCE_Y = 3620,
	FALCONER = { NPC = "Matthias", OPTION = "Quick-falcon", FEE = 500 },
	GLOVE = "Falconer's glove",
	GLOVE_READY = 10024,
	FALCON = { NPC = 1342, OPTION = "Retrieve" },
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
				mapsquare = { x = 37, y = 56 },
				arrive = { x = 2375, y = 3604, plane = 0 },
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
				mapsquare = { x = 37, y = 56 },
				arrive = { x = 2375, y = 3604, plane = 0 },
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
	return { creature = creature, sent_at = 0, catches = 0 }
end

function Read.inside(area: Area, state: ClientState): boolean
	local p = state.position
	if p == nil or p.plane ~= area.arrive.plane or p.y >= CONST.FENCE_Y then
		return false
	end
	local chunk = Position.new(p.local_x, p.local_y, p.x, p.y, p.plane):chunk()
	return chunk.x == area.mapsquare.x and chunk.y == area.mapsquare.y
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
	if not Read.inside(task.area :: Area, Host.game_state()) then
		return "TRAVEL"
	end
	if not Read.has_falcon() then
		return "GET_FALCON"
	end
	if Read.our_falcon(task) then
		return "RETRIEVE"
	end
	if not Read.falcon_ready() then
		return "WAIT"
	end
	task.prey = nil
	return "CATCH"
end

function Read.falcon_ready(): boolean
	return Wornitems.is_wearing(CONST.GLOVE_READY)
end

function Read.our_falcon(task: Task): Host.Npc?
	if task.prey == nil then
		return nil
	end
	for _, npc in ipairs(Npcs.find(CONST.FALCON.NPC) or {}) do
		if npc.index == task.prey then
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
	local me = Walker.position()
	local falconer = if me then Npcs.nearest(CONST.FALCONER.NPC, me) else nil
	if falconer == nil then
		return (Travel.walk((task.area :: Area).arrive, CONST.ARRIVE_NEAR))
	end
	Log.log(NAME, `Hiring a falcon from {CONST.FALCONER.NPC} for {fee} coins`)
	if not Npcs.approach(falconer, CONST.FALCONER.OPTION) then
		return false
	end
	local deadline = Host.time() + CONST.GLOVE_TIMEOUT_MS
	repeat
		if Read.has_falcon() then
			return true
		end
		Host.sleep(CONST.POLL_MS)
	until Host.time() >= deadline
	return Read.has_falcon()
end

function Game.catch(task: Task): boolean
	local me = Walker.position()
	local kebbit = if me then Npcs.nearest(task.creature.npc, me) else nil
	if kebbit == nil then
		return (Travel.walk((task.area :: Area).arrive, CONST.ARRIVE_NEAR))
	end
	local target = kebbit :: Host.Npc
	if not Npcs.interact(target, CONST.CATCH_OPTION, false) then
		return false
	end
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
			Log.log(NAME, `Caught a {task.creature.npc} ({task.catches} so far)`)
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
	Random.sleep(CONST.WAIT_MS[1], CONST.WAIT_MS[2])
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
