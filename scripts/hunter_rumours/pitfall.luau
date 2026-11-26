--!strict
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type Loc = Host.Loc
type Npc = Host.Npc
local Combat = require("@volcren/combat")
local Idle = require("./idle")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Logs = require("./logs")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Travel = require("./travel")
local Walker = require("@volcren/walker")

local NAME = "Pitfall"

export type Tile = { x: number, y: number, plane: number }
export type Pit = { x: number, y: number, plane: number, rotation: number }
export type Area = { name: string, arrive: Tile, pits: { Pit } }
export type Creature = { name: string, npc: string, part: number, areas: { Area } }
export type State =
	"BLOCKED"
	| "DONE"
	| "TRAVEL"
	| "RETALIATE_OFF"
	| "RETALIATE_ON"
	| "CHOP"
	| "SET"
	| "TEASE"
	| "LURE"
	| "JUMP"
	| "DISMANTLE"
	| "WAIT"
export type PitState = "Pit" | "Spiked pit" | "Falling" | "Collapsed trap" | "unknown"
export type Task = {
	creature: Creature,
	area: Area?,
	chaser: number?,
	chaser_seen: number,
	jumped: Pit?,
	target: Pit?,
	stand: Tile?,
	teased_at: number,
	stall_key: string?,
	stall_at: number,
	log_goal: number,
	retaliate_checked: boolean,
	waypoint: Tile?,
	avoid: { [string]: boolean },
	bad_tiles: { [string]: boolean },
	catches: number,
	blocked: string?,
}

local CONST = {
	ARRIVE_NEAR = 3,
	LEASH = 14,
	LOGS = { KEEP = 2 },
	PIT = { SET = "Trap", JUMP = "Jump", DISMANTLE = "Dismantle" },
	TEASE = "Tease",
	SIZE = 2,
	NEAR = 3,
	PIT_IDS = { FIRST = 19253, LAST = 19268, FIRST_VARBIT = 2958 },
	CHASE_LOST_MS = 6000,
	TEASE_GRACE_MS = 3000,
	TEASE_TIMEOUT_MS = 8000,
	STALL_MS = 3000,
	BLOCKED_FLAGS = 0x1240100,
	SIM_STEPS = 30,
	WAYPOINT_RADIUS = 7,
	GRID_MARGIN = 12,
	LAND_TIMEOUT_MS = 5000,
	OUTCOME_MS = 6000,
	ACT_TIMEOUT_MS = 8000,
	WAIT_MS = { 80, 160 },
	POLL_MS = 100,
}

local CREATURES: { [string]: Creature } = {
	["spined larupia"] = {
		name = "spined larupia",
		npc = "Spined larupia",
		part = 29226,
		areas = {
			{
				name = "Feldip Hunter area",
				arrive = { x = 2554, y = 2898, plane = 0 },
				pits = {
					{ x = 2543, y = 2908, plane = 0, rotation = 2 },
					{ x = 2552, y = 2904, plane = 0, rotation = 1 },
					{ x = 2556, y = 2893, plane = 0, rotation = 0 },
					{ x = 2565, y = 2888, plane = 0, rotation = 1 },
					{ x = 2573, y = 2885, plane = 0, rotation = 2 },
				},
			},
		},
	},
}

local PIT_STATES: { [number]: PitState } = {
	[0] = "Pit",
	[1] = "Spiked pit",
	[2] = "Falling",
	[3] = "Collapsed trap",
	[4] = "Collapsed trap",
}

local restore_retaliate = false

local Pitfall = {}
local Read, Game, Handler = {}, {}, {}

Pitfall.CREATURES = table.freeze(CREATURES)

function Pitfall.creature(prey: string): Creature?
	return CREATURES[string.lower(prey)]
end

function Pitfall.new(prey: string): Task?
	local creature = Pitfall.creature(prey)
	if creature == nil then
		return nil
	end
	return {
		creature = creature,
		chaser_seen = 0,
		teased_at = 0,
		stall_at = 0,
		log_goal = Logs.goal(CONST.LOGS.KEEP),
		retaliate_checked = false,
		avoid = {},
		bad_tiles = {},
		catches = 0,
	}
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

function Read.pit_at(pit: Pit): (PitState, Loc?)
	for _, loc in ipairs(Objects.find() or {}) do
		local index = loc.id - CONST.PIT_IDS.FIRST
		if
			index >= 0
			and loc.id <= CONST.PIT_IDS.LAST
			and loc.x == pit.x
			and loc.y == pit.y
			and loc.plane == pit.plane
		then
			local value = Host.varbit(CONST.PIT_IDS.FIRST_VARBIT + index)
			return (if value then PIT_STATES[value] else nil) or "unknown", loc
		end
	end
	return "unknown", nil
end

function Read.north_south(pit: Pit): boolean
	return pit.rotation % 2 == 0
end

function Read.stands(pit: Pit): (Tile, Tile)
	if Read.north_south(pit) then
		return { x = pit.x, y = pit.y - 1, plane = pit.plane }, { x = pit.x, y = pit.y + 2, plane = pit.plane }
	end
	return { x = pit.x - 1, y = pit.y, plane = pit.plane }, { x = pit.x + 2, y = pit.y, plane = pit.plane }
end

function Read.footprint(npc: Npc): (number, number, number, number)
	return npc.x - CONST.SIZE + 1, npc.y - CONST.SIZE + 1, npc.x, npc.y
end

function Read.gap(t: Host.Tile, npc: Npc): number
	local x1, y1, x2, y2 = Read.footprint(npc)
	local dx = math.max(x1 - t.x, 0, t.x - x2)
	local dy = math.max(y1 - t.y, 0, t.y - y2)
	return math.max(dx, dy)
end

function Read.low_side(pit: Pit, npc: Npc): boolean
	local x1, y1, x2, y2 = Read.footprint(npc)
	if Read.north_south(pit) then
		return (y1 + y2) / 2 < pit.y + 0.5
	end
	return (x1 + x2) / 2 < pit.x + 0.5
end

function Read.chaser(task: Task): Npc?
	if task.chaser == nil then
		local me = Players.me()
		for _, npc in ipairs(Npcs.find(task.creature.npc) or {}) do
			if me and npc.interacting_player == me.index then
				task.chaser, task.chaser_seen = npc.index, time()
				Log.log(NAME, `A {task.creature.npc} is already after us`)
				return npc
			end
		end
		return nil
	end
	for _, npc in ipairs(Npcs.find(task.creature.npc) or {}) do
		if
			npc.index == task.chaser
			and (npc.interacting_player ~= -1 or time() - task.teased_at < CONST.TEASE_GRACE_MS)
		then
			task.chaser_seen = time()
			return npc
		end
	end
	if time() - task.chaser_seen > CONST.CHASE_LOST_MS then
		Log.log(NAME, `Lost the {task.creature.npc}`)
		task.chaser, task.jumped = nil, nil
	end
	return nil
end

function Read.logs(): number
	return Logs.count()
end

function Read.pits_by(task: Task, from: Host.Tile): { Pit }
	local pits = table.clone((task.area :: Area).pits)
	table.sort(pits, function(a: Pit, b: Pit): boolean
		return Walker.distance(from, a) < Walker.distance(from, b)
	end)
	return pits
end

function Read.collapsed(task: Task): (Pit?, PitState?)
	for _, pit in ipairs((task.area :: Area).pits) do
		local status = Read.pit_at(pit)
		if status == "Collapsed trap" or status == "Falling" then
			return pit, status
		end
	end
	return nil, nil
end

function Read.lure_pit(task: Task, from: Host.Tile): Pit?
	for _, pit in ipairs(Read.pits_by(task, from)) do
		local jumped = task.jumped ~= nil and pit.x == (task.jumped :: Pit).x and pit.y == (task.jumped :: Pit).y
		if not jumped and not task.avoid[`{pit.x},{pit.y}`] then
			return pit
		end
	end
	return nil
end

export type Grid = { collision: Host.Collision, tiles: { [string]: boolean } }

function Read.grid(area: Area): Grid?
	local m: number = CONST.GRID_MARGIN
	local xs: { number }, ys: { number } = { area.arrive.x }, { area.arrive.y }
	for _, pit in ipairs(area.pits) do
		table.insert(xs, pit.x)
		table.insert(xs, pit.x + 1)
		table.insert(ys, pit.y)
		table.insert(ys, pit.y + 1)
	end
	local left: number, right: number = math.min(table.unpack(xs)), math.max(table.unpack(xs))
	local bottom: number, top: number = math.min(table.unpack(ys)), math.max(table.unpack(ys))
	local corners: Host.Corners = { x1 = left - m, y1 = bottom - m, x2 = right + m, y2 = top + m }
	local collision = Host.collision(corners)
	if collision == nil then
		return nil
	end
	return { collision = collision :: Host.Collision, tiles = {} }
end

function Read.free(grid: Grid, x: number, y: number): boolean
	local key = `{x},{y}`
	local known = grid.tiles[key]
	if known ~= nil then
		return known
	end
	local c = grid.collision
	local i, j = x - c.x, y - c.y
	local free = i >= 0
		and j >= 0
		and i < c.width
		and j < c.height
		and bit32.band(c.flags[i * c.height + j + 1], CONST.BLOCKED_FLAGS) == 0
	grid.tiles[key] = free
	return free
end

function Read.fits(grid: Grid, x1: number, y1: number): boolean
	for dx = 0, CONST.SIZE - 1 do
		for dy = 0, CONST.SIZE - 1 do
			if not Read.free(grid, x1 + dx, y1 + dy) then
				return false
			end
		end
	end
	return true
end

function Read.toward(value: number, low: number, high: number): number
	if value < low then
		return -1
	elseif value > high then
		return 1
	end
	return 0
end

function Read.chase(grid: Grid, x1: number, y1: number, target: Tile): (boolean, number, number)
	local size = CONST.SIZE
	for _ = 1, CONST.SIM_STEPS do
		local dx = Read.toward(target.x, x1, x1 + size - 1)
		local dy = Read.toward(target.y, y1, y1 + size - 1)
		local gx = math.max(x1 - target.x, 0, target.x - (x1 + size - 1))
		local gy = math.max(y1 - target.y, 0, target.y - (y1 + size - 1))
		if math.max(gx, gy) <= 1 then
			return true, x1, y1
		end
		if
			dx ~= 0
			and dy ~= 0
			and Read.fits(grid, x1 + dx, y1 + dy)
			and Read.fits(grid, x1 + dx, y1)
			and Read.fits(grid, x1, y1 + dy)
		then
			x1, y1 = x1 + dx, y1 + dy
		elseif dx ~= 0 and Read.fits(grid, x1 + dx, y1) then
			x1 = x1 + dx
		elseif dy ~= 0 and Read.fits(grid, x1, y1 + dy) then
			y1 = y1 + dy
		else
			return false, x1, y1
		end
	end
	return false, x1, y1
end

function Read.on_side(pit: Pit, x1: number, y1: number, low: boolean): boolean
	local centre = if Read.north_south(pit) then y1 + (CONST.SIZE - 1) / 2 else x1 + (CONST.SIZE - 1) / 2
	local edge = if Read.north_south(pit) then pit.y + 0.5 else pit.x + 0.5
	return (centre < edge) == low
end

function Read.key(t: { x: number, y: number }): string
	return `{t.x},{t.y}`
end

function Read.plan(grid: Grid, pit: Pit, npc: Npc, me: Host.Tile, bad: { [string]: boolean }): (Tile?, Tile?)
	local low, high = Read.stands(pit)
	local x1, y1 = Read.footprint(npc)
	local options: { { stand: Tile, low: boolean } } = {}
	local first_low = Read.low_side(pit, npc)
	for _, option in ipairs({
		{ stand = if first_low then low else high, low = first_low },
		{ stand = if first_low then high else low, low = not first_low },
	}) do
		if not bad[Read.key(option.stand)] then
			table.insert(options, option)
		end
	end
	for _, option in ipairs(options) do
		local reached, fx, fy = Read.chase(grid, x1, y1, option.stand)
		if reached and Read.on_side(pit, fx, fy, option.low) then
			return option.stand, nil
		end
	end
	local r = CONST.WAYPOINT_RADIUS
	local candidates: { Tile } = {}
	local fx1, fy1, fx2, fy2 = Read.footprint(npc)
	for dx = -r, r do
		for dy = -r, r do
			local w = { x = me.x + dx, y = me.y + dy, plane = pit.plane }
			local under = w.x >= fx1 and w.x <= fx2 and w.y >= fy1 and w.y <= fy2
			if not under and not bad[Read.key(w)] and Read.free(grid, w.x, w.y) then
				table.insert(candidates, w)
			end
		end
	end
	table.sort(candidates, function(a: Tile, b: Tile): boolean
		return Walker.distance(me, a) < Walker.distance(me, b)
	end)
	for _, w in ipairs(candidates) do
		local reached, fx, fy = Read.chase(grid, x1, y1, w)
		if reached then
			for _, option in ipairs(options) do
				local ok, sx, sy = Read.chase(grid, fx, fy, option.stand)
				if ok and Read.on_side(pit, sx, sy, option.low) then
					local route = Walker.route(w)
					if route and route.reached then
						return option.stand, w
					end
					bad[Read.key(w)] = true
					break
				end
			end
		end
	end
	return nil, nil
end

function Pitfall.state(task: Task): State
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
	local far = me.plane ~= area.arrive.plane or Walker.distance(me, area.arrive) > CONST.LEASH * 2
	local collapsed: Pit?, fall: PitState? = nil, nil
	if not far then
		collapsed, fall = Read.collapsed(task)
	end
	if collapsed then
		if fall == "Falling" then
			return "WAIT"
		end
		task.target = collapsed
		return "DISMANTLE"
	end
	if Inventory.contains(task.creature.part) then
		return if restore_retaliate then "RETALIATE_ON" else "DONE"
	end
	if far then
		return "TRAVEL"
	end
	if not task.retaliate_checked then
		return "RETALIATE_OFF"
	end
	local chaser = Read.chaser(task)
	local from: Host.Tile = if chaser then chaser else me
	local pit = Read.lure_pit(task, from)
	if pit == nil then
		task.blocked = "no pit to lure into"
		return "BLOCKED"
	end
	task.target = pit
	local status = Read.pit_at(pit :: Pit)
	if status == "Pit" then
		if Read.logs() == 0 then
			return "CHOP"
		end
		return "SET"
	end
	if chaser == nil then
		if task.chaser ~= nil then
			return "WAIT"
		end
		if Read.logs() < task.log_goal then
			return "CHOP"
		end
		return "TEASE"
	end
	if status ~= "Spiked pit" then
		return "WAIT"
	end
	local low, high = Read.stands(pit :: Pit)
	local npc = chaser :: Npc
	local near_side = if Read.low_side(pit :: Pit, npc) then low else high
	if me.x == near_side.x and me.y == near_side.y and Read.gap(me, npc) <= 1 then
		return "JUMP"
	end
	if task.waypoint and Read.gap(task.waypoint :: Tile, npc) <= 1 then
		task.waypoint = nil
	end
	if task.waypoint == nil then
		local grid = Read.grid(area)
		local stand, waypoint = nil, nil
		if grid then
			stand, waypoint = Read.plan(grid :: Grid, pit :: Pit, npc, me, task.bad_tiles)
		end
		if stand == nil then
			Log.log(NAME, `No way to lead the {task.creature.npc} to the pit at {(pit :: Pit).x}, {(pit :: Pit).y}`)
			task.avoid[`{(pit :: Pit).x},{(pit :: Pit).y}`] = true
			return "WAIT"
		end
		task.stand, task.waypoint = stand, waypoint
		if waypoint then
			Log.log(
				NAME,
				`Leading the {task.creature.npc} round through {(waypoint :: Tile).x}, {(waypoint :: Tile).y}`
			)
		end
	end
	return "LURE"
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
	Log.log(NAME, `Travelling to the pits in the {area.name}`)
	local walked, why = Travel.walk(goal, CONST.ARRIVE_NEAR)
	if why then
		task.blocked = `no way to the {area.name}: {why}`
	end
	return walked
end

function Game.chop(task: Task): boolean
	local ok, why = Logs.chop(NAME, function(): boolean
		return Read.logs() >= task.log_goal
	end)
	if why then
		task.blocked = why
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

function Game.set(task: Task): boolean
	local pit = task.target :: Pit
	local status, loc = Read.pit_at(pit)
	if status ~= "Pit" or loc == nil then
		return true
	end
	Log.log(NAME, `Setting the pit at {pit.x}, {pit.y}`)
	if not Game.use(loc :: Loc, CONST.PIT.SET) then
		return false
	end
	return Game.wait_until(function(): boolean
		return Read.pit_at(pit) == "Spiked pit"
	end, CONST.ACT_TIMEOUT_MS)
end

function Game.tease(task: Task): boolean
	local area = task.area :: Area
	local me = Walker.position()
	local best: Npc? = nil
	local best_d = math.huge
	for _, npc in ipairs(Npcs.find(task.creature.npc) or {}) do
		local d = Walker.distance(area.arrive, npc)
		if npc.interacting_player == -1 and d <= CONST.LEASH and d < best_d then
			best, best_d = npc, d
		end
	end
	if best == nil then
		if me and Walker.distance(me, area.arrive) > 2 then
			return (Travel.walk(area.arrive, CONST.ARRIVE_NEAR))
		end
		sleep(Random.int(400, 900))
		return true
	end
	local npc = best :: Npc
	Log.log(NAME, `Teasing the {task.creature.npc} at {npc.x}, {npc.y}`)
	if not Npcs.interact(npc, CONST.TEASE, false) then
		return false
	end
	local angry = Game.wait_until(function(): boolean
		local now = Npcs.refresh(npc)
		return now ~= nil and now.interacting_player ~= -1
	end, CONST.TEASE_TIMEOUT_MS)
	if not angry then
		Log.log(NAME, `The {task.creature.npc} didn't take the bait`)
		return false
	end
	task.chaser, task.chaser_seen, task.teased_at, task.jumped = npc.index, time(), time(), nil
	task.log_goal = Logs.goal(CONST.LOGS.KEEP)
	task.waypoint, task.avoid, task.bad_tiles = nil, {}, {}
	return true
end

function Game.lure(task: Task): boolean
	local stand = (task.waypoint or task.stand) :: Tile
	local me = Walker.position()
	if me == nil then
		return false
	end
	if me.x ~= stand.x or me.y ~= stand.y then
		if Walker.walk_tile(stand, 4000) then
			return true
		end
		if
			Walker.walk(stand, { near = 0, plane = stand.plane, transports = false })
			and Walker.wait_arrival(stand, 3000)
		then
			return true
		end
		Log.log(NAME, `Can't reach {stand.x}, {stand.y}, planning another way`)
		task.bad_tiles[Read.key(stand)] = true
		task.waypoint = nil
		return true
	end
	local npc = Read.chaser(task)
	if npc and Read.gap(me, npc :: Npc) > 1 then
		local key = `{npc.x},{npc.y}`
		if task.stall_key ~= key then
			task.stall_key, task.stall_at = key, time()
		elseif time() - task.stall_at > CONST.STALL_MS then
			Log.log(
				NAME,
				`The {task.creature.npc} is stuck at {npc.x}, {npc.y} and can't reach {stand.x}, {stand.y}, planning another way`
			)
			task.bad_tiles[Read.key(stand)] = true
			task.waypoint, task.stall_key = nil, nil
			return true
		end
	end
	Random.sleep(CONST.WAIT_MS[1], CONST.WAIT_MS[2])
	return true
end

function Game.jump(task: Task): boolean
	local pit = task.target :: Pit
	local _, loc = Read.pit_at(pit)
	if loc == nil then
		return false
	end
	local start = Walker.position()
	local before = Read.chaser(task)
	Log.log(
		NAME,
		`Jumping the pit at {pit.x}, {pit.y} from {start and start.x or "?"}, {start and start.y or "?"} with the {task.creature.npc} at {before and before.x or "?"}, {before and before.y or "?"}`
	)
	if not Objects.interact(loc :: Loc, CONST.PIT.JUMP, false) then
		return false
	end
	local landed = Game.wait_until(function(): boolean
		local now = Walker.position()
		return now ~= nil and start ~= nil and Walker.distance(now, start) >= 3
	end, CONST.LAND_TIMEOUT_MS)
	if not landed then
		return false
	end
	local caught = Game.wait_until(function(): boolean
		local status = Read.pit_at(pit)
		return status == "Collapsed trap" or status == "Falling"
	end, CONST.OUTCOME_MS)
	if not caught then
		local after = Read.chaser(task)
		local now = Walker.position()
		Log.log(
			NAME,
			`No catch at {pit.x}, {pit.y}: we're at {now and now.x or "?"}, {now and now.y or "?"}, the {task.creature.npc} at {after and after.x or "?"}, {after and after.y or "?"}`
		)
		task.jumped = pit
	end
	return true
end

function Game.dismantle(task: Task): boolean
	local pit = task.target :: Pit
	local status, loc = Read.pit_at(pit)
	if status ~= "Collapsed trap" or loc == nil then
		return true
	end
	Game.wait_until(function(): boolean
		return not Player.is_animating()
	end, CONST.LAND_TIMEOUT_MS)
	Log.log(NAME, `Dismantling the collapsed trap at {pit.x}, {pit.y}`)
	if not Game.use(loc :: Loc, CONST.PIT.DISMANTLE) then
		Random.sleep(600, 1200)
		return false
	end
	local done = Game.wait_until(function(): boolean
		return Read.pit_at(pit) ~= "Collapsed trap"
	end, CONST.ACT_TIMEOUT_MS)
	if done then
		task.catches += 1
		task.chaser, task.jumped = nil, nil
		Log.log(NAME, `Caught: {task.creature.npc} ({task.catches} so far)`)
	end
	return done
end

Handler.states = {
	BLOCKED = function(_task: Task): boolean
		return false
	end,
	RETALIATE_OFF = function(task: Task): boolean
		local on = Combat.auto_retaliate()
		if on and not Combat.set_auto_retaliate(false) then
			return false
		end
		if on then
			Log.log(NAME, `Turned auto retaliate off so the {task.creature.npc} can't interrupt us`)
		end
		task.retaliate_checked = true
		restore_retaliate = restore_retaliate or on == true
		return true
	end,
	RETALIATE_ON = function(_task: Task): boolean
		if not Combat.set_auto_retaliate(true) then
			return false
		end
		Log.log(NAME, "Turned auto retaliate back on")
		restore_retaliate = false
		return true
	end,
	DONE = function(_task: Task): boolean
		return true
	end,
	TRAVEL = Game.travel,
	CHOP = Game.chop,
	SET = Game.set,
	TEASE = Game.tease,
	LURE = Game.lure,
	JUMP = Game.jump,
	DISMANTLE = Game.dismantle,
	WAIT = function(_task: Task): boolean
		Idle.wait(CONST.WAIT_MS)
		return true
	end,
} :: { [State]: (Task) -> boolean }

function Pitfall.step(task: Task, state: State): boolean
	return Handler.states[state](task)
end

return Pitfall
