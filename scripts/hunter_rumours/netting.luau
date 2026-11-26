--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type Npc = Host.Npc
type Point = Host.Tile
local Chat = require("@volcren/chat")
local Idle = require("./idle")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Npcs = require("@volcren/npcs")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Netting"

export type Tile = { x: number, y: number, plane: number }
export type Area = { name: string, spawns: { Tile } }
export type Creature = {
	name: string,
	level: number,
	barehanded: number?,
	part: number?,
	moth: boolean?,
	areas: { Area },
}
export type State = "BLOCKED" | "DONE" | "WIELD_NET" | "TRAVEL" | "CATCH" | "RETURN" | "WAIT"
export type Task = {
	creature: Creature,
	camp: Tile?,
	target: Npc?,
	fresh: boolean,
	seen: { [number]: boolean },
	catches: number,
	active_at: number,
	misses: number,
	wield: string?,
	blocked: string?,
}

local CONST = {
	NETS = { "Magic insect net", "Insect net" },
	OPTION = { CATCH = "Catch", WIELD = "Wield" },
	CAUGHT = "^You catch",
	CAMP_NEAR = 2,
	CAMP_RANGE = 6,
	LEASH = 8,
	CATCH_TIMEOUT_MS = 8000,
	RELEASE_TIMEOUT_MS = 2000,
	EQUIP_TIMEOUT_MS = 2400,
	REACT_MS = { 250, 900 },
	WAIT_MS = { 150, 400 },
	POLL_MS = 100,
	IDLE_CAMP_MS = 45000,
	MISSES = 6,
	HOME_RADIUS = 2,
}

local CREATURES: { [string]: Creature } = {
	["swarm of wasps"] = { name = "Swarm of wasps", level = 1, areas = {} },
	["ruby harvest"] = { name = "Ruby harvest", level = 15, barehanded = 25, areas = {} },
	["sapphire glacialis"] = { name = "Sapphire glacialis", level = 25, barehanded = 35, part = 29224, areas = {} },
	["snowy knight"] = {
		name = "Snowy knight",
		level = 35,
		barehanded = 45,
		part = 29227,
		areas = {
			{
				name = "Rellekka Hunter area",
				spawns = {
					{ x = 2701, y = 3804, plane = 0 },
					{ x = 2712, y = 3797, plane = 0 },
					{ x = 2737, y = 3792, plane = 0 },
					{ x = 2696, y = 3786, plane = 0 },
					{ x = 2737, y = 3778, plane = 0 },
					{ x = 2714, y = 3777, plane = 0 },
				},
			},
		},
	},
	["black warlock"] = {
		name = "Black warlock",
		level = 45,
		barehanded = 55,
		part = 29230,
		areas = {
			{
				name = "Feldip Hunter area",
				spawns = {
					{ x = 2563, y = 2920, plane = 0 },
					{ x = 2551, y = 2915, plane = 0 },
					{ x = 2540, y = 2914, plane = 0 },
					{ x = 2532, y = 2905, plane = 0 },
					{ x = 2540, y = 2898, plane = 0 },
					{ x = 2550, y = 2893, plane = 0 },
					{ x = 2566, y = 2886, plane = 0 },
				},
			},
		},
	},
	["sunlight moth"] = { name = "Sunlight moth", level = 65, barehanded = 75, part = 29237, moth = true, areas = {} },
	["moonlight moth"] = { name = "Moonlight moth", level = 75, barehanded = 85, part = 29240, moth = true, areas = {} },
}

local Netting = {}
local Read, Game, Handler = {}, {}, {}

Netting.CREATURES = table.freeze(CREATURES)

function Netting.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Netting.new(prey: string): Task?
	local creature = Netting.creature(prey)
	if creature == nil then
		return nil
	end
	return { creature = creature, fresh = false, seen = {}, catches = 0, active_at = 0, misses = 0 }
end

function Read.best_net(): (string?, boolean)
	for _, net in ipairs(CONST.NETS) do
		if Wornitems.is_wearing(net) then
			return net, true
		elseif Inventory.contains(net) then
			return net, false
		end
	end
	return nil, false
end

function Read.nearest_area(c: Creature, me: Point): Area?
	local best, best_d = nil, math.huge
	for _, area in ipairs(c.areas) do
		for _, spawn in ipairs(area.spawns) do
			local d = Walker.distance(me, spawn)
			if d < best_d then
				best, best_d = area, d
			end
		end
	end
	return best
end

function Read.pick_camp(task: Task, me: Point): Tile?
	local area = Read.nearest_area(task.creature, me)
	if area == nil then
		return nil
	end
	local choices: { Tile } = {}
	for _, spawn in ipairs(area.spawns) do
		if task.camp == nil or spawn ~= task.camp then
			table.insert(choices, spawn)
		end
	end
	if #choices == 0 then
		choices = area.spawns
	end
	local camp = choices[Random.int(1, #choices)]
	task.active_at = time()
	Log.log(NAME, `Camping the {task.creature.name} spawn at {camp.x}, {camp.y} in the {area.name}`)
	return camp
end

function Read.target(task: Task, camp: Tile): Npc?
	local best, best_d = nil, math.huge
	local seen: { [number]: boolean } = {}
	for _, npc in ipairs(Npcs.find(task.creature.name) or {}) do
		local d = Walker.distance(camp, npc)
		if d <= CONST.CAMP_RANGE then
			seen[npc.index] = true
			if d < best_d then
				best, best_d = npc, d
			end
		end
	end
	task.fresh = best ~= nil and not task.seen[best.index]
	task.seen = seen
	return best
end

function Netting.state(task: Task): State
	local c = task.creature
	if task.blocked then
		return "BLOCKED"
	end
	if c.part ~= nil and Inventory.contains(c.part) then
		return "DONE"
	end
	local hunter = Stats.level("Hunter") or 0
	local net, worn = Read.best_net()
	if net == nil then
		if c.barehanded == nil or hunter < c.barehanded then
			task.blocked = `no insect net and Hunter is below {c.barehanded or "?"} to catch {c.name} barehanded`
			return "BLOCKED"
		end
	elseif hunter < c.level then
		task.blocked = `Hunter is below {c.level} for {c.name}`
		return "BLOCKED"
	elseif not worn then
		task.wield = net
		return "WIELD_NET"
	end
	local me = Walker.position()
	if me == nil then
		return "WAIT"
	end
	if task.camp == nil then
		task.camp = Read.pick_camp(task, me)
		if task.camp == nil then
			task.blocked = `no known {c.name} spawns`
			return "BLOCKED"
		end
	end
	local camp = task.camp :: Tile
	if me.plane ~= camp.plane or Walker.distance(me, camp) > CONST.LEASH then
		return "TRAVEL"
	end
	task.target = Read.target(task, camp)
	if task.target then
		return "CATCH"
	end
	if not c.moth and Walker.distance(me, camp) > CONST.HOME_RADIUS then
		return "RETURN"
	end
	if time() - task.active_at > CONST.IDLE_CAMP_MS then
		Log.log(NAME, `Nothing has come to {camp.x}, {camp.y} for a while, moving spawns`)
		task.camp = Read.pick_camp(task, me)
		return "TRAVEL"
	end
	return "WAIT"
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

function Game.wield_net(task: Task): boolean
	local net = task.wield :: string
	Log.log(NAME, `Wielding the {net}`)
	return Inventory.interact(net, CONST.OPTION.WIELD)
		and Game.wait_until(function()
			return Wornitems.is_wearing(net)
		end, CONST.EQUIP_TIMEOUT_MS)
end

function Game.travel(task: Task): boolean
	local camp = task.camp :: Tile
	local goal = { x = camp.x + Random.int(-1, 1), y = camp.y + Random.int(-1, 1), plane = camp.plane }
	local walked, why = Travel.walk(goal, CONST.CAMP_NEAR)
	if why then
		task.blocked = `no way to the {task.creature.name} spawn at {camp.x}, {camp.y}: {why}`
	end
	return walked
end

function Game.catch(task: Task): boolean
	local target = task.target :: Npc
	if task.fresh then
		Random.sleep(CONST.REACT_MS[1], CONST.REACT_MS[2])
		local now = Npcs.refresh(target)
		if now == nil then
			return true
		end
		target = now
	end
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Npcs.interact(target, CONST.OPTION.CATCH, false) then
		Random.sleep(400, 900)
		task.misses += 1
		if task.misses < CONST.MISSES then
			return true
		end
		task.misses = 0
		return false
	end
	local deadline = time() + CONST.CATCH_TIMEOUT_MS
	repeat
		for _, m in ipairs(Chat.new_messages(seen) or {}) do
			seen = m.uid
			if string.find(m.text, CONST.CAUGHT) then
				task.catches += 1
				task.active_at, task.misses = time(), 0
				Log.log(NAME, `Caught: {task.creature.name} ({task.catches} so far)`)
				Game.wait_until(function()
					return Npcs.refresh(target) == nil
				end, CONST.RELEASE_TIMEOUT_MS)
				return true
			end
		end
		if Npcs.refresh(target) == nil then
			Log.log(NAME, `The {task.creature.name} went before it was caught`)
			return true
		end
		sleep(CONST.POLL_MS)
	until time() >= deadline
	Log.log(NAME, `Didn't catch the {task.creature.name}`)
	return false
end

function Game.return_home(task: Task): boolean
	local camp = task.camp :: Tile
	local r = CONST.HOME_RADIUS
	for _ = 1, 8 do
		local tile = { x = camp.x + Random.int(-r, r), y = camp.y + Random.int(-r, r), plane = camp.plane }
		local route = Walker.route(tile)
		if route and route.reached then
			return Walker.walk_tile(tile, 6000)
		end
	end
	return false
end

function Game.wait()
	Idle.wait(CONST.WAIT_MS)
end

Handler.states = {
	BLOCKED = function(_task: Task): boolean
		return false
	end,
	DONE = function(_task: Task): boolean
		return true
	end,
	WIELD_NET = Game.wield_net,
	TRAVEL = Game.travel,
	CATCH = Game.catch,
	RETURN = Game.return_home,
	WAIT = function(_task: Task): boolean
		Game.wait()
		return true
	end,
} :: { [State]: (Task) -> boolean }

function Netting.step(task: Task, state: State): boolean
	return Handler.states[state](task)
end

return Netting
