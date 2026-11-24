--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Tile = Host.Tile
type Loc = Host.Loc
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local BankpinKeypad = require("@volcren/bankpin_keypad")
local Biometrics = require("@volcren/biometrics")
local ChatOptions = require("@volcren/chat_options")
local DepositBox = require("@volcren/depositbox")
local GameState = require("@volcren/game_state")
local GroundItems = require("@volcren/ground_items")
local Handoff = require("@volcren/handoff")
local Inv = require("@volcren/inv")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Varbits = require("@volcren/varbits")
local Walker = require("@volcren/walker")
local Widgets = require("@volcren/widgets")
local Wornitems = require("@volcren/wornitems")

local NAME = "Motherlode Mine"

local CONST = {
	REPORT = { counters_key = "" },
	MIN_MINING = 30,
	UPPER_MINING = 57,
	PAYDIRT = "Pay-dirt",
	NUGGET = "Golden nugget",
	ORES = { "Coal", "Gold ore", "Mithril ore", "Adamantite ore", "Runite ore" },
	HAMMERS = { "Hammer", "Imcando hammer" } :: { number | string },
	BAGS = { "Open gem bag", "Gem bag", "Open coal bag", "Coal bag" } :: { number | string },
	VARBIT = { SACK = 5558, BIGGER_SACK = 5556 },
	SACK_SIZE = { normal = 108, bigger = 189 },
	AREA = { x1 = 3708, y1 = 5630, x2 = 3778, y2 = 5700 },
	HOPPER = { name = "Hopper", option = "Deposit", lower = { x = 3748, y = 5672 }, upper = { x = 3755, y = 5677 } },
	SACK = { id = 26688, option = "Search" },
	LADDER = {
		name = "Ladder",
		option = "Climb",
		lower = { x = 3755, y = 5673 },
		upper = { x = 3755, y = 5674 },
		top = { x = 3755, y = 5675 },
	},
	VEIN = { name = "Ore vein", depleted = "Depleted vein", option = "Mine" },
	DEPOSIT_BOX = { x = 3759, y = 5664 },
	BANK_CHEST = { x = 3761, y = 5666 },
	ROCKFALL = { name = "Rockfall", option = "Mine", cost = 8, clear_ms = 12000 },
	STRUT = { broken = "Broken strut", option = "Hammer", fix_ms = 30000 },
	CRATE = { name = "Crate", option = "Search", hammers = { { x = 3752, y = 5674 }, { x = 3756, y = 5668 } } },
	PERCY = {
		name = "Prospector Percy",
		talk = "Talk-to",
		ask = "Is there anything else I can unlock here?",
		leave = "I'll leave you alone.",
		cancel = "Cancel",
		steps = 25,
	},
	UNLOCKS = {
		upper = { label = "restricted mine access", price = 100 },
		hopper = { label = "hopper", price = 50 },
		sack = { label = "bigger sack", price = 200 },
	} :: { [string]: { label: string, price: number } },
	MINE = { START_MS = 5000, IDLE_MS = 2400, MAX_MS = 90000, POLL_MS = 100, TINY_ANTIBAN = 0.35 },
	CLUSTER = { RADIUS = 4, MAX_EXTRA = 12, HOP_BIAS = 10 },
	DEPOSIT_MS = 6000,
	BATCH_MS = 15000,
	COLLECT_MS = 6000,
	INFLIGHT_MS = 25000,
	CLIMB_MS = 10000,
	FLAG = { BLOCKED = 0x1240100, ROCK = 0x100 },
	STEPS = { { 0, 1, 0x2, 0x20 }, { 0, -1, 0x20, 0x2 }, { 1, 0, 0x8, 0x80 }, { -1, 0, 0x80, 0x8 } },
	FACING = { [0] = { -1, 0 }, [1] = { 0, 1 }, [2] = { 1, 0 }, [3] = { 0, -1 } },
}

local Read, Route, Game, Loop, Handler = {}, {}, {}, {}, {}

type UnlockKey = "upper" | "hopper" | "sack"

local CONFIG = {
	use_upper = true,
	have_upper = false,
	have_hopper = false,
	buy = { upper = 1, hopper = 2, sack = 3 } :: { [UnlockKey]: number },
	max_paydirt = 0,
	timeouts = { idle_minutes = 5, max_failures = 5 },
}

local stats = {
	paydirt = 0,
	deposits = 0,
	nuggets = 0,
	nuggets_spent = 0,
	ores = {} :: { [string]: number },
	banked = 0,
	repairs = 0,
	bought = 0,
	failures = 0,
}

type Floor = "lower" | "upper"
type DistMap = { [string]: number }

type Unlocks = { upper: boolean, hopper: boolean, sack: boolean }

type Cluster = { id: string, veins: { [string]: boolean }, size: number, hop: number }

type DroppedDirt = { x: number, y: number, floor: Floor }

type RunState = {
	finished: boolean,
	finishing: boolean,
	emptying: boolean,
	bags_filled: boolean,
	bank_nuggets: number?,
	clusters: { [Floor]: { Cluster } },
	cluster: Cluster?,
	cluster_floor: Floor?,
	dropped_dirt: DroppedDirt?,
	hopper_blocked: boolean,
	bank_locked: boolean,
	blocked: string?,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	unlocks: Unlocks?,
	inflight: number,
	inflight_at: number,
	last_sack: number,
	maps: { [Floor]: DistMap },
	floors: { [string]: Floor },
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	finishing = false,
	emptying = false,
	bags_filled = true,
	bank_nuggets = nil,
	clusters = {},
	cluster = nil,
	cluster_floor = nil,
	dropped_dirt = nil,
	hopper_blocked = false,
	bank_locked = false,
	blocked = nil,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	unlocks = nil,
	inflight = 0,
	inflight_at = 0,
	last_sack = 0,
	maps = { lower = {}, upper = {} },
	floors = {},
	skip = {},
}

type Carried = {
	dirt: number,
	free: number,
	dirt_room: number,
	capacity: number,
	loot_slots: number,
	nuggets: number,
	hammer: boolean,
}

type Snapshot = {
	state: ClientState,
	me: Tile,
	floor: Floor,
	carried: Carried,
	sack: number,
	cap: number,
	mining: number,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "BUY"
	| "BANK"
	| "COLLECT"
	| "WAIT_SACK"
	| "REPAIR"
	| "DEPOSIT"
	| "MINE"
	| "NUGGETS"
	| "RECOVER"

type Plan = { buy: UnlockKey? }

local plan: Plan = {}

local report = StatsReport.new()

local function key(x: number, y: number): string
	return `{x},{y}`
end

local function lower_name(name: string?): string
	return string.lower(name or "")
end

local BAG_NAMES: { [string]: boolean } = {}
for _, name in ipairs(CONST.BAGS) do
	BAG_NAMES[string.lower(tostring(name))] = true
end

local HAMMER_NAMES: { [string]: boolean } = {}
for _, name in ipairs(CONST.HAMMERS) do
	HAMMER_NAMES[string.lower(tostring(name))] = true
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.cap(): number
	return if Varbits.get(CONST.VARBIT.BIGGER_SACK) == 1 then CONST.SACK_SIZE.bigger else CONST.SACK_SIZE.normal
end

function Read.carried(): Carried
	local items = Inventory.items() or {}
	local c: Carried =
		{ dirt = 0, free = 28 - #items, dirt_room = 0, capacity = 0, loot_slots = 0, nuggets = 0, hammer = false }
	local held = 0
	local locked = Inventory.locked_slots() or {}
	local repairing = Read.wheels_broken()
	for _, item in ipairs(items) do
		if item.name == CONST.NUGGET then
			c.nuggets += item.quantity
		end
		if HAMMER_NAMES[lower_name(item.name)] then
			c.hammer = true
		end
		if item.name == CONST.PAYDIRT then
			c.dirt += 1
		elseif locked[item.slot] or Read.is_tool(item.name) or (repairing and HAMMER_NAMES[lower_name(item.name)]) then
			held += 1
		else
			c.loot_slots += 1
		end
	end
	c.hammer = c.hammer or Read.wearing_hammer()
	c.capacity = 28 - held
	c.dirt_room = c.capacity - c.loot_slots
	return c
end

function Read.is_tool(name: string?): boolean
	local lower = lower_name(name)
	return string.find(lower, "pickaxe", 1, true) ~= nil or BAG_NAMES[lower] == true
end

function Read.wearing_hammer(): boolean
	for _, item in ipairs(Wornitems.items() or {}) do
		if HAMMER_NAMES[lower_name(item.name)] then
			return true
		end
	end
	return false
end

function Read.floor(tile: Tile): Floor
	return S.floors[key(tile.x, tile.y)] or "lower"
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	local me = { x = state.position.x, y = state.position.y }
	local sack = Varbits.get(CONST.VARBIT.SACK) or 0
	if sack > S.last_sack then
		S.inflight = math.max(0, S.inflight - (sack - S.last_sack))
	end
	S.last_sack = sack
	if not Read.wheels_broken() then
		S.hopper_blocked = false
	end
	if S.inflight > 0 and Read.wheels_broken() then
		S.inflight_at = time()
	elseif S.inflight > 0 and time() - S.inflight_at > CONST.INFLIGHT_MS then
		Log.log(NAME, `{S.inflight} pay-dirt never reached the sack, no longer waiting for it`)
		S.inflight = 0
	end
	local mining = Stats.get("Mining")
	snap = {
		state = state,
		me = me,
		floor = Read.floor(me),
		carried = Read.carried(),
		sack = sack,
		cap = Read.cap(),
		mining = mining and mining.real_level or 0,
	}
	return true
end

function Read.batch_out(timeout_ms: number): boolean
	return Widgets.wait_until(function()
		local sack = Varbits.get(CONST.VARBIT.SACK) or S.last_sack
		if sack > S.last_sack then
			S.inflight = math.max(0, S.inflight - (sack - S.last_sack))
		end
		S.last_sack = sack
		return S.inflight == 0
	end, timeout_ms, 200)
end

function Read.wheels_broken(): boolean
	return #(Objects.find(CONST.STRUT.broken) or {}) >= 2
end

function Read.stand_tile(vein: Loc): Tile
	local f = CONST.FACING[vein.rotation or 0] or CONST.FACING[0]
	return { x = vein.x + f[1], y = vein.y + f[2] }
end

function Read.upper_allowed(): boolean
	return CONFIG.use_upper and snap.mining >= CONST.UPPER_MINING and S.unlocks ~= nil and S.unlocks.upper
end

function Read.hopper_floor(): Floor
	return if Read.upper_allowed() and (S.unlocks :: Unlocks).hopper then "upper" else "lower"
end

function Route.grid(): (Host.Collision?, { [string]: boolean })
	local rocks: { [string]: boolean } = {}
	for _, loc in ipairs(Objects.find(CONST.ROCKFALL.name) or {}) do
		rocks[key(loc.x, loc.y)] = true
	end
	return Host.collision(CONST.AREA), rocks
end

function Route.search(
	sources: { Tile },
	goals: { [string]: boolean }?
): (DistMap, { [string]: string }, { [string]: boolean })
	local c, rocks = Route.grid()
	local dist: DistMap = {}
	local prev: { [string]: string } = {}
	if c == nil then
		return dist, prev, rocks
	end
	local grid = c :: Host.Collision
	local function flag(x: number, y: number): number
		local i, j = x - grid.x, y - grid.y
		if i < 0 or j < 0 or i >= grid.width or j >= grid.height then
			return CONST.FLAG.BLOCKED
		end
		local f = grid.flags[i * grid.height + j + 1]
		if rocks[key(x, y)] then
			f = bit32.band(f, bit32.bnot(CONST.FLAG.ROCK))
		end
		return f
	end
	local buckets: { [number]: { Tile } } = { [0] = {} }
	for _, t in ipairs(sources) do
		dist[key(t.x, t.y)] = 0
		table.insert(buckets[0], t)
	end
	local d, top = 0, 0
	while d <= top do
		for _, t in ipairs(buckets[d] or {}) do
			local k = key(t.x, t.y)
			if dist[k] == d then
				if goals and goals[k] then
					return dist, prev, rocks
				end
				for _, step in ipairs(CONST.STEPS) do
					local nx, ny = t.x + step[1], t.y + step[2]
					local nk = key(nx, ny)
					if
						bit32.band(flag(t.x, t.y), step[3]) == 0
						and bit32.band(flag(nx, ny), bit32.bor(CONST.FLAG.BLOCKED, step[4])) == 0
					then
						local nd = d + (if rocks[nk] then CONST.ROCKFALL.cost else 1)
						if dist[nk] == nil or nd < dist[nk] then
							dist[nk], prev[nk] = nd, k
							buckets[nd] = buckets[nd] or {}
							table.insert(buckets[nd], { x = nx, y = ny })
							top = math.max(top, nd)
						end
					end
				end
			end
		end
		buckets[d] = nil
		d += 1
	end
	return dist, prev, rocks
end

function Route.neighbours(tile: Tile): { Tile }
	local out = {}
	for _, step in ipairs(CONST.STEPS) do
		table.insert(out, { x = tile.x + step[1], y = tile.y + step[2] })
	end
	return out
end

function Route.map_floors()
	local lower = Route.search(Route.neighbours(CONST.HOPPER.lower))
	local upper = Route.search({ CONST.LADDER.top })
	S.floors = {}
	for k in pairs(upper) do
		if lower[k] == nil then
			S.floors[k] = "upper"
		end
	end
	for k in pairs(lower) do
		S.floors[k] = "lower"
	end
	S.maps.lower = lower
	Route.map_upper()
end

function Route.map_upper()
	local from = if Read.hopper_floor() == "upper" then Route.neighbours(CONST.HOPPER.upper) else { CONST.LADDER.top }
	local upper = Route.search(from)
	local only: DistMap = {}
	for k, d in pairs(upper) do
		if S.floors[k] == "upper" then
			only[k] = d
		end
	end
	S.maps.upper = only
	S.clusters = {}
	S.cluster = nil
end

function Route.first_rockfall(goals: { Tile }): Loc?
	local wanted: { [string]: boolean } = {}
	for _, g in ipairs(goals) do
		wanted[key(g.x, g.y)] = true
	end
	local _, prev, rocks = Route.search({ snap.me }, wanted)
	local reached: string? = nil
	for k in pairs(wanted) do
		if prev[k] or k == key(snap.me.x, snap.me.y) then
			reached = k
			break
		end
	end
	local path = {}
	local at = reached
	while at do
		table.insert(path, 1, at)
		at = prev[at]
	end
	for _, k in ipairs(path) do
		if rocks[k] then
			for _, loc in ipairs(Objects.find(CONST.ROCKFALL.name) or {}) do
				if key(loc.x, loc.y) == k then
					return loc
				end
			end
		end
	end
	return nil
end

function Route.clear_way(goals: { Tile }): boolean
	for _ = 1, 3 do
		local rock = Route.first_rockfall(goals)
		if rock == nil then
			return true
		end
		Log.log(NAME, `Mining the rockfall at {rock.x}, {rock.y} in the way`)
		if not Objects.approach(rock, CONST.ROCKFALL.option) then
			return false
		end
		local rx, ry = rock.x, rock.y
		local cleared = Widgets.wait_until(function()
			for _, loc in ipairs(Objects.find(CONST.ROCKFALL.name) or {}) do
				if loc.x == rx and loc.y == ry then
					return false
				end
			end
			return true
		end, CONST.ROCKFALL.clear_ms, 200)
		if not cleared then
			return false
		end
		local s = game_state()
		if s.position then
			snap.me = { x = s.position.x, y = s.position.y }
		end
	end
	return Route.first_rockfall(goals) == nil
end

function Route.crowded(tile: Tile): boolean
	local name = Player.name()
	for _, p in ipairs(Players.find() or {}) do
		if p.name ~= name and math.max(math.abs(p.x - tile.x), math.abs(p.y - tile.y)) <= 1 then
			return true
		end
	end
	return false
end

type Candidate = { vein: Loc, stand: Tile, hop: number }

function Route.all_veins(): { Loc }
	local out: { Loc } = {}
	for _, name in ipairs({ CONST.VEIN.name, CONST.VEIN.depleted }) do
		for _, vein in ipairs(Objects.find(name) or {}) do
			table.insert(out, vein)
		end
	end
	return out
end

function Route.build_clusters(floor: Floor)
	local map = S.maps[floor]
	local members: { Candidate } = {}
	for _, vein in ipairs(Route.all_veins()) do
		local stand = Read.stand_tile(vein)
		local hop = map[key(stand.x, stand.y)]
		if hop then
			table.insert(members, { vein = vein, stand = stand, hop = hop })
		end
	end
	table.sort(members, function(x: Candidate, y: Candidate)
		return x.hop < y.hop
	end)
	local taken: { [number]: boolean } = {}
	local clusters: { Cluster } = {}
	for i, seed in ipairs(members) do
		if not taken[i] then
			local c: Cluster = { id = key(seed.vein.x, seed.vein.y), veins = {}, size = 0, hop = 0 }
			for j = i, #members do
				local m = members[j]
				local near = math.max(math.abs(m.stand.x - seed.stand.x), math.abs(m.stand.y - seed.stand.y))
				if not taken[j] and near <= CONST.CLUSTER.RADIUS then
					taken[j] = true
					c.veins[key(m.vein.x, m.vein.y)] = true
					c.size += 1
					c.hop += m.hop
				end
			end
			c.hop /= c.size
			table.insert(clusters, c)
		end
	end
	local listed = {}
	for _, c in ipairs(clusters) do
		table.insert(listed, `{c.id}:{c.size}@{math.floor(c.hop)}`)
	end
	Log.log(NAME, `{floor} floor clusters (veins@tiles): {table.concat(listed, " ")}`)
	S.clusters[floor] = clusters
	S.cluster = nil
end

function Route.preference(cluster: Cluster): number
	local seed = Biometrics.seed() or ""
	local hash: number = Biometrics.murmur2a(seed .. cluster.id)
	return 0.5 + (hash % 1000) / 1000
end

function Route.choose_cluster(floor: Floor, skip: { [string]: boolean })
	local clusters: { Cluster } = S.clusters[floor] or {}
	local nearest = math.huge
	for _, c in ipairs(clusters) do
		if not skip[c.id] then
			nearest = math.min(nearest, c.hop)
		end
	end
	local total = 0
	local weights: { [Cluster]: number } = {}
	for _, c in ipairs(clusters) do
		if not skip[c.id] and c.hop <= nearest + CONST.CLUSTER.MAX_EXTRA then
			local weight = c.size / (c.hop + CONST.CLUSTER.HOP_BIAS) * Route.preference(c)
			weights[c] = weight
			total += weight
		end
	end
	local roll = Random.float(0, total)
	S.cluster = nil
	for c, weight in pairs(weights) do
		S.cluster = c
		roll -= weight
		if roll <= 0 then
			break
		end
	end
	if S.cluster then
		Log.log(
			NAME,
			`Mining the cluster of {S.cluster.size} veins at {S.cluster.id} ({math.floor(S.cluster.hop)} tiles out)`
		)
	end
end

function Route.cluster_veins(cluster: Cluster, floor: Floor): { Candidate }
	local map = S.maps[floor]
	local out: { Candidate } = {}
	for _, vein in ipairs(Objects.find(CONST.VEIN.name) or {}) do
		if cluster.veins[key(vein.x, vein.y)] then
			local stand = Read.stand_tile(vein)
			if not Route.crowded(stand) then
				table.insert(out, { vein = vein, stand = stand, hop = map[key(stand.x, stand.y)] or 0 })
			end
		end
	end
	return out
end

function Route.pick_vein(floor: Floor): Candidate?
	if S.clusters[floor] == nil then
		Route.build_clusters(floor)
	end
	local skip: { [string]: boolean } = {}
	for _ = 1, #(S.clusters[floor] or {}) do
		local cluster = S.cluster
		if cluster == nil or S.cluster_floor ~= floor then
			Route.choose_cluster(floor, skip)
			S.cluster_floor = floor
			cluster = S.cluster
		end
		if cluster == nil then
			return nil
		end
		local current: Cluster = cluster
		local live = Route.cluster_veins(current, floor)
		if #live > 0 then
			local best: Candidate? = nil
			local best_score = math.huge
			for _, c in ipairs(live) do
				local score = math.max(math.abs(c.stand.x - snap.me.x), math.abs(c.stand.y - snap.me.y))
					+ Random.int(0, 2)
				if score < best_score then
					best, best_score = c, score
				end
			end
			return best
		end
		Log.log(NAME, `The cluster at {current.id} is mined out, switching`)
		skip[current.id] = true
		S.cluster = nil
	end
	return nil
end

function Game.next_purchase(): UnlockKey?
	local u = S.unlocks
	if u == nil then
		return nil
	end
	local order: { UnlockKey } = { "upper", "hopper", "sack" }
	table.sort(order, function(a, b)
		return CONFIG.buy[a] < CONFIG.buy[b]
	end)
	for _, k in ipairs(order) do
		if CONFIG.buy[k] > 0 and not (u :: any)[k] then
			if k == "hopper" and not u.upper then
				continue
			end
			if k == "upper" and (snap == nil or snap.mining < CONST.UPPER_MINING) then
				return nil
			end
			return k
		end
	end
	return nil
end

function Game.fetch_nuggets_for(buy: UnlockKey): boolean
	if S.bank_locked or snap.carried.dirt > 0 or S.emptying or snap.floor ~= "lower" then
		return false
	end
	local price = CONST.UNLOCKS[buy].price
	return snap.carried.nuggets < price and (S.bank_nuggets == nil or S.bank_nuggets + snap.carried.nuggets >= price)
end

function Game.sign_in(): boolean
	Log.log(NAME, "Logging in")
	local ok = Login.sign_in()
	if not ok then
		Log.log(NAME, "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Game.ensure_logged_in(s: ClientState): boolean
	if s.game_state == GameState.LOGGED_IN and s.position ~= nil then
		return true
	end
	if Read.scene_loading(s) then
		sleep(100)
		return false
	end
	return Game.sign_in()
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Mining" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
	Antiban.add_task(AntibanTasks.handle_randoms, 30 * SECOND, 0.33)
	Antiban.add_task(AntibanTasks.adjust_camera, 3 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.lose_focus, 10 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.adjust_minimap_zoom, 13 * MINUTE, 0.33)

	Antiban.add_walk_task(AntibanTasks.adjust_camera, 2 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_chat_tab, 3 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.small_camera_rotation, 4 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_right_click, 5 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_tab, 6 * MINUTE, 0.33)

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_pitch_change, 45 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_zoom_change, 60 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_camera_rotation, 70 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_npc, 90 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_player, 120 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.random_tab, 90 * SECOND, 0.4, "game")

	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_tab, 70 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_chat_tab, 80 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_random_ground_item, 120 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.tiny_antiban()
	if S.antiban_ready and Biometrics.random_boolean(CONST.MINE.TINY_ANTIBAN) then
		Antiban.do_async_tasks("game")
	end
end

function Game.stop(reason: string)
	Log.log(NAME, `Stopping: {reason}`)
	S.blocked = reason
	S.finished = true
end

function Game.fail(reason: string)
	Log.log(NAME, reason)
	S.failures_in_row += 1
	stats.failures += 1
end

function Game.progress()
	S.failures_in_row = 0
	S.last_progress_at = time()
end

function Game.open_bags()
	for _, bag in ipairs({ "Gem bag", "Coal bag" }) do
		if Inventory.contains(bag) then
			Log.log(NAME, `Opening the {string.lower(bag)} so it fills itself`)
			if Inventory.interact(bag, "Open") then
				sleep(Random.int(400, 800))
			end
		end
	end
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end
	if Toplevel.has_interface() then
		Toplevel.escape_clear()
	end
	if snap.mining < CONST.MIN_MINING then
		Game.stop(`Pay-dirt needs {CONST.MIN_MINING} Mining, this account has {snap.mining}`)
		return
	end
	local function has_pickaxe(items: { Inv.Slot }?): boolean
		for _, item in ipairs(items or {}) do
			if string.find(lower_name(item.name), "pickaxe", 1, true) then
				return true
			end
		end
		return false
	end
	if not has_pickaxe(Inventory.items()) and not has_pickaxe(Wornitems.items()) then
		Game.stop("No pickaxe: equip one or carry it")
		return
	end
	Game.open_bags()
	S.unlocks = {
		upper = CONFIG.have_upper,
		hopper = CONFIG.have_upper and CONFIG.have_hopper,
		sack = Varbits.get(CONST.VARBIT.BIGGER_SACK) == 1,
	}
	local u = S.unlocks :: Unlocks
	Log.log(NAME, `Unlocks: upper floor {u.upper}, upper hopper {u.hopper}, bigger sack {u.sack}`)
	Route.map_floors()
	S.last_sack = Varbits.get(CONST.VARBIT.SACK) or 0
	Game.setup_antiban()
end

function Game.climb(to: Floor): boolean
	if snap.floor == to then
		return true
	end
	local at = if to == "upper" then CONST.LADDER.lower else CONST.LADDER.upper
	local ladder: Loc? = nil
	for _, loc in ipairs(Objects.find(CONST.LADDER.name) or {}) do
		if loc.x == at.x and loc.y == at.y then
			ladder = loc
		end
	end
	if ladder == nil then
		Game.fail(`No ladder at {at.x}, {at.y}`)
		return false
	end
	Log.log(NAME, `Climbing to the {to} floor`)
	Route.clear_way(if to == "upper" then Route.neighbours(at) else { CONST.LADDER.top })
	if not Objects.approach(ladder, CONST.LADDER.option) then
		Game.fail("Couldn't click the ladder")
		return false
	end
	local arrived = Widgets.wait_until(function()
		local s = game_state()
		return s.position ~= nil and Read.floor({ x = s.position.x, y = s.position.y }) == to
	end, CONST.CLIMB_MS, 100)
	if not arrived then
		Game.fail(`The ladder didn't take us to the {to} floor`)
		if to == "upper" and ChatOptions.speech() ~= nil and S.unlocks then
			Log.log(NAME, "The upper floor seems locked after all")
			S.unlocks.upper = false
		end
		return false
	end
	sleep(Random.int(300, 700))
	local s = game_state()
	if s.position then
		snap.me = { x = s.position.x, y = s.position.y }
		snap.floor = to
	end
	return true
end

function Game.wait_dialog_options(timeout_ms: number): { ChatOptions.Option }?
	local deadline = time() + timeout_ms
	while time() < deadline do
		local options = ChatOptions.get()
		if options and #options > 0 then
			return options
		end
		if ChatOptions.contains_continue() then
			ChatOptions.continue_chat()
			sleep(Random.int(500, 900))
		else
			sleep(150)
		end
	end
	return nil
end

function Game.finish_dialog()
	for _ = 1, 6 do
		if ChatOptions.contains(CONST.PERCY.leave) then
			ChatOptions.select(CONST.PERCY.leave)
		elseif ChatOptions.contains_continue() then
			ChatOptions.continue_chat()
		elseif not Toplevel.has_interface() and ChatOptions.speech() == nil then
			return
		end
		sleep(Random.int(600, 1000))
	end
	Toplevel.escape_clear()
end

function Game.read_unlock_list(options: { ChatOptions.Option }): Unlocks
	local locked = { upper = false, hopper = false, sack = false }
	for _, option in ipairs(options) do
		local text = string.lower(option.text)
		for k, unlock in pairs(CONST.UNLOCKS) do
			if string.find(text, unlock.label, 1, true) then
				(locked :: any)[k] = true
			end
		end
	end
	local bigger = Varbits.get(CONST.VARBIT.BIGGER_SACK) == 1
	return {
		upper = not locked.upper,
		hopper = not locked.upper and not locked.hopper,
		sack = bigger or not locked.sack,
	}
end

function Game.talk_to_percy(buy: UnlockKey?): boolean
	if Toplevel.has_interface() then
		Toplevel.escape_clear()
	end
	local percy = Npcs.nearest(CONST.PERCY.name, snap.me)
	if percy == nil then
		Walker.walk(CONST.HOPPER.lower, { near = 4 })
		local s = game_state()
		percy = s.position and Npcs.nearest(CONST.PERCY.name, { x = s.position.x, y = s.position.y })
	end
	if percy then
		Route.clear_way(Route.neighbours(percy))
	end
	if percy == nil or not Npcs.approach(percy, CONST.PERCY.talk) then
		Game.fail("Couldn't talk to Prospector Percy")
		return false
	end
	local options = Game.wait_dialog_options(8000)
	if options == nil or not ChatOptions.select(CONST.PERCY.ask) then
		Game.fail("Prospector Percy didn't offer to talk about unlocks")
		Game.finish_dialog()
		return false
	end
	local list = Game.wait_dialog_options(15000)
	if list == nil or not ChatOptions.contains(CONST.PERCY.cancel) then
		Log.log(NAME, "Prospector Percy has nothing left to unlock")
		S.unlocks = { upper = true, hopper = true, sack = true }
		Game.finish_dialog()
		return true
	end
	S.unlocks = Game.read_unlock_list(list)
	local u = S.unlocks :: Unlocks
	Log.log(NAME, `Unlocks: upper floor {u.upper}, upper hopper {u.hopper}, bigger sack {u.sack}`)
	if buy == nil then
		ChatOptions.select(CONST.PERCY.cancel)
		Game.finish_dialog()
		return true
	end
	local choice: string? = nil
	for _, option in ipairs(list) do
		if string.find(string.lower(option.text), CONST.UNLOCKS[buy].label, 1, true) then
			choice = option.text
		end
	end
	if choice == nil then
		Log.log(NAME, `Prospector Percy doesn't offer the {buy} unlock`)
		ChatOptions.select(CONST.PERCY.cancel)
		Game.finish_dialog()
		return false
	end
	local before = Inventory.count_ex(CONST.NUGGET) or 0
	Log.log(NAME, `Buying "{choice}"`)
	ChatOptions.select(choice)
	for _ = 1, CONST.PERCY.steps do
		sleep(Random.int(500, 900))
		local options2 = ChatOptions.get()
		if options2 and #options2 > 0 then
			local yes: string? = nil
			for _, option in ipairs(options2) do
				if string.find(string.lower(option.text), "yes", 1, true) == 1 then
					yes = option.text
				end
			end
			if yes == nil then
				break
			end
			ChatOptions.select(yes)
		elseif ChatOptions.contains_continue() then
			ChatOptions.continue_chat()
		elseif (Inventory.count_ex(CONST.NUGGET) or 0) < before then
			break
		end
	end
	local paid = (Inventory.count_ex(CONST.NUGGET) or 0) <= before - CONST.UNLOCKS[buy].price
	Game.finish_dialog()
	if paid then
		stats.bought += 1
		stats.nuggets_spent += CONST.UNLOCKS[buy].price
		local owned: any = u
		owned[buy] = true
		Log.log(NAME, `Bought the {buy} unlock`)
		Route.map_upper()
		Game.progress()
		return true
	end
	Game.fail(`Buying the {buy} unlock didn't take the nuggets`)
	S.unlocks = nil
	return false
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

function Loop.report_counters()
	local counters: { any } = {
		{ id = "paydirt", label = "Pay-dirt mined", value = stats.paydirt },
		{ id = "nuggets", label = "Golden nuggets", value = stats.nuggets },
	}
	for _, ore in ipairs(CONST.ORES) do
		local amount = stats.ores[ore] or 0
		if amount > 0 then
			table.insert(counters, { id = string.lower((string.gsub(ore, " ", "_"))), label = ore, value = amount })
		end
	end
	if stats.nuggets_spent > 0 then
		table.insert(counters, { id = "nuggets_spent", label = "Nuggets spent", value = stats.nuggets_spent })
		table.insert(counters, { id = "bought", label = "Unlocks bought", value = stats.bought })
	end
	table.insert(counters, { id = "banked", label = "Deposit box trips", value = stats.banked })
	table.insert(counters, { id = "repairs", label = "Struts repaired", value = stats.repairs })
	table.insert(counters, { id = "failures", label = "Failures", value = stats.failures })
	local parts = {}
	for _, counter in ipairs(counters) do
		table.insert(parts, `{counter.id}={counter.value}`)
	end
	local k = table.concat(parts, "/")
	if k == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = k
	Host.report_counters(counters)
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	if time() - S.last_progress_at >= t.idle_minutes * 60000 then
		Game.stop(`no progress for {t.idle_minutes} minutes`)
	elseif S.failures_in_row >= t.max_failures then
		Game.stop(`{S.failures_in_row} failures in a row`)
	elseif CONFIG.max_paydirt > 0 and stats.paydirt >= CONFIG.max_paydirt and not S.finishing then
		Log.log(NAME, `Mined {CONFIG.max_paydirt} pay-dirt, emptying the sack before stopping`)
		S.finishing = true
	end
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	S.last_progress_at += time() - S.antiban_began_at
end

function Loop.hook_antiban_timeouts()
	Antiban.on_start_task, Antiban.on_finish_task = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.antiban_began, Loop.antiban_ended
end

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}
	plan = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	local c = snap.carried
	if S.dropped_dirt then
		if Read.wheels_broken() then
			return "REPAIR"
		elseif not skipped["RECOVER"] then
			return "RECOVER"
		end
	end
	local buy = Game.next_purchase()
	if buy and c.dirt == 0 and c.nuggets >= CONST.UNLOCKS[buy].price and not skipped["BUY"] then
		plan.buy = buy
		return "BUY"
	end
	if buy and Game.fetch_nuggets_for(buy) and not skipped["NUGGETS"] then
		plan.buy = buy
		return "NUGGETS"
	end
	local room = snap.cap - snap.sack - S.inflight
	local fits = c.dirt <= room
	if snap.sack > 0 and room < c.capacity / 2 and not S.emptying then
		Log.log(NAME, `The sack holds {snap.sack} and can't take half a load, emptying it`)
		S.emptying = true
	elseif S.emptying and snap.sack == 0 and S.inflight == 0 and c.loot_slots == 0 then
		S.emptying = false
	end
	local deposit_now = S.emptying or S.finishing or not fits or c.dirt_room < c.capacity / 2
	if S.emptying and snap.sack > 0 and c.free > 0 and not skipped["COLLECT"] then
		return "COLLECT"
	end
	if c.loot_slots > 0 and deposit_now and not skipped["BANK"] then
		return "BANK"
	end
	if c.dirt > 0 and fits and not S.emptying then
		if not (S.finishing or c.free == 0 or c.dirt >= math.min(c.dirt_room, room)) then
			return "MINE"
		end
		if S.hopper_blocked and Read.wheels_broken() then
			return "REPAIR"
		end
		return "DEPOSIT"
	end
	if not fits or S.emptying or S.finishing then
		if snap.sack > 0 then
			return "COLLECT"
		end
		if S.inflight > 0 then
			return if Read.wheels_broken() then "REPAIR" else "WAIT_SACK"
		end
		if S.finishing then
			S.finished = true
			return "LOADING"
		end
	end
	if skipped["MINE"] then
		return "LOADING"
	end
	return "MINE"
end

function Handler.mine()
	if Read.upper_allowed() and snap.floor == "lower" then
		Game.climb("upper")
		return
	end
	local target = math.min(snap.carried.dirt_room, snap.cap - snap.sack - S.inflight)
	local pick = Route.pick_vein(snap.floor)
	if pick == nil then
		Log.log(NAME, "No ore vein to mine, waiting")
		S.skip["MINE"] = true
		sleep(Random.int(1200, 2400))
		return
	end
	local vein = pick.vein
	S.bags_filled = true
	if not Route.clear_way({ pick.stand }) then
		Game.fail("Couldn't clear the way to the vein")
		return
	end
	if not Objects.approach(vein, CONST.VEIN.option, { stand = { pick.stand } }) then
		local mining_anyway = Widgets.wait_until(Player.is_animating, CONST.MINE.START_MS, 100)
		if not mining_anyway then
			Game.fail(`Couldn't mine the vein at {vein.x}, {vein.y}`)
			return
		end
	end
	Inventory.open()
	local dirt = Inventory.count(CONST.PAYDIRT) or 0
	local started, last_busy = time(), time()
	local mined = 0
	while time() - started < CONST.MINE.MAX_MS do
		local now = Inventory.count(CONST.PAYDIRT) or dirt
		if now > dirt then
			mined += now - dirt
			stats.paydirt += now - dirt
			dirt = now
			Game.progress()
			last_busy = time()
		end
		if dirt >= target or Inventory.is_full() then
			break
		end
		local still_there = false
		for _, loc in ipairs(Objects.find(vein.id) or {}) do
			if loc.x == vein.x and loc.y == vein.y then
				still_there = true
			end
		end
		if not still_there then
			break
		end
		if Player.is_animating() or Player.is_moving() then
			last_busy = time()
		end
		local idle = time() - last_busy
		if mined == 0 and time() - started > CONST.MINE.START_MS and idle > CONST.MINE.IDLE_MS then
			Game.fail(`The vein at {vein.x}, {vein.y} gave nothing`)
			return
		elseif mined > 0 and idle > CONST.MINE.IDLE_MS then
			break
		end
		Game.tiny_antiban()
		sleep(CONST.MINE.POLL_MS)
	end
	if S.antiban_ready and not Antiban.do_antiban() then
		S.skip["MINE"] = true
	end
end

function Handler.deposit()
	local floor = Read.hopper_floor()
	if snap.floor ~= floor then
		Game.climb(floor)
		return
	end
	local at = CONST.HOPPER[floor]
	local hopper: Loc? = nil
	for _, loc in ipairs(Objects.find(CONST.HOPPER.name) or {}) do
		if loc.x == at.x and loc.y == at.y then
			hopper = loc
		end
	end
	if hopper == nil then
		Game.fail(`No hopper at {at.x}, {at.y}`)
		return
	end
	if not Route.clear_way(Route.neighbours(at)) then
		Game.fail("Couldn't clear the way to the hopper")
		return
	end
	local broken = Read.wheels_broken()
	if not broken and not Read.batch_out(CONST.BATCH_MS) then
		Game.fail("The last batch is still in the machine")
		return
	end
	local before = Inventory.count(CONST.PAYDIRT) or snap.carried.dirt
	if not Objects.approach(hopper, CONST.HOPPER.option) then
		Game.fail("Couldn't click the hopper")
		return
	end
	local emptied = Widgets.wait_until(function()
		return (Inventory.count(CONST.PAYDIRT) or before) < before
	end, CONST.DEPOSIT_MS, 100)
	if not emptied and broken then
		Log.log(NAME, "The hopper is full until the wheels are fixed")
		S.hopper_blocked = true
		if Inventory.is_full() and not snap.carried.hammer then
			local slot = Inventory.index_of(CONST.PAYDIRT)
			local me = Walker.position()
			if slot and me and Inventory.drop_slots({ slot }) then
				Log.log(NAME, "Dropped a pay-dirt by the hopper to make room for a hammer")
				S.dropped_dirt = { x = me.x, y = me.y, floor = floor }
			end
		end
		return
	end
	if not emptied then
		if floor == "upper" and S.unlocks then
			Log.log(NAME, "The upper hopper didn't take the pay-dirt, using the lower one")
			S.unlocks.hopper = false
			Route.map_upper()
		end
		Game.fail("The hopper didn't take the pay-dirt")
		return
	end
	local after = Inventory.count(CONST.PAYDIRT) or 0
	S.hopper_blocked = false
	S.inflight += before - after
	S.inflight_at = time()
	stats.deposits += 1
	Game.progress()
	Log.log(NAME, `Deposited {before - after} pay-dirt, sack {snap.sack} + {S.inflight} on the way of {snap.cap}`)
end

function Handler.ensure_lower(): boolean
	if snap.floor == "lower" then
		return true
	end
	Game.climb("lower")
	return false
end

function Handler.collect()
	if not Handler.ensure_lower() then
		return
	end
	local sack = Objects.nearest(CONST.SACK.id, snap.me)
	if sack == nil then
		Game.fail("Couldn't find the sack")
		return
	end
	if S.inflight > 0 and not Read.wheels_broken() then
		Read.batch_out(CONST.BATCH_MS)
	end
	local before = #(Inventory.items() or {})
	local counted: { [string]: number } = {}
	for _, ore in ipairs(CONST.ORES) do
		counted[ore] = Inventory.count_ex(ore) or 0
	end
	local nuggets = Inventory.count_ex(CONST.NUGGET) or 0
	local had = Varbits.get(CONST.VARBIT.SACK) or snap.sack
	Route.clear_way(Route.neighbours(sack))
	if not Objects.approach(sack, CONST.SACK.option) then
		Game.fail("Couldn't search the sack")
		S.skip["COLLECT"] = true
		return
	end
	local took = Widgets.wait_until(function()
		return #(Inventory.items() or {}) > before or (Varbits.get(CONST.VARBIT.SACK) or had) < had
	end, CONST.COLLECT_MS, 100)
	if not took then
		Game.fail("Searching the sack took nothing")
		S.skip["COLLECT"] = true
		return
	end
	sleep(Random.int(300, 600))
	S.last_sack = Varbits.get(CONST.VARBIT.SACK) or 0
	for _, ore in ipairs(CONST.ORES) do
		local gained = (Inventory.count_ex(ore) or 0) - counted[ore]
		if gained > 0 then
			stats.ores[ore] = (stats.ores[ore] or 0) + gained
		end
	end
	stats.nuggets += math.max(0, (Inventory.count_ex(CONST.NUGGET) or 0) - nuggets)
	Game.progress()
end

function Handler.lock_tools()
	local locked = Inventory.locked_slots() or {}
	for _, item in ipairs(Inventory.items() or {}) do
		if Read.is_tool(item.name) and not locked[item.slot] then
			Log.log(NAME, `Locking the {item.name} slot so it stays in the inventory`)
			DepositBox.lock_slot(item.slot, true)
		end
	end
end

function Handler.deposit_loot(): boolean
	local locked = Inventory.locked_slots() or {}
	local kinds: { [number]: boolean } = {}
	local kind_count, only = 0, -1
	for _, item in ipairs(Inventory.items() or {}) do
		if item.name ~= CONST.PAYDIRT and not locked[item.slot] and not kinds[item.id] then
			kinds[item.id] = true
			kind_count += 1
			only = item.id
		end
	end
	if kind_count == 0 then
		return true
	end
	if Inventory.locks_ignored() then
		local keep: { number | string } = { CONST.PAYDIRT }
		for _, item in ipairs(Inventory.items() or {}) do
			if Read.is_tool(item.name) then
				table.insert(keep, item.id)
			end
		end
		return DepositBox.deposit_different(keep :: any)
	end
	if kind_count == 1 and Biometrics.random_boolean() then
		return DepositBox.deposit(only)
	end
	return DepositBox.deposit_inventory()
end

function Handler.bank()
	if not Handler.ensure_lower() then
		return
	end
	Log.log(NAME, "Depositing the ore")
	Route.clear_way(Route.neighbours(CONST.DEPOSIT_BOX))
	if not DepositBox.open() then
		Game.fail("The deposit box didn't open")
		S.skip["BANK"] = true
		return
	end
	Handler.lock_tools()
	local nuggets = Inventory.count_ex(CONST.NUGGET) or 0
	local deposited = Handler.deposit_loot()
		and Widgets.wait_until(function()
			return Read.carried().loot_slots == 0
		end, 2400, 100)
	if deposited then
		if S.bank_nuggets then
			S.bank_nuggets += nuggets
		end
		stats.banked += 1
		Game.progress()
	else
		Game.fail("Couldn't deposit the ore")
	end
	if S.bags_filled and Inventory.contains_any(CONST.BAGS) and DepositBox.deposit_loot_bag() then
		S.bags_filled = false
		sleep(Random.int(400, 800))
	end
	DepositBox.close()
end

function Handler.fetch_nuggets()
	local buy = plan.buy :: UnlockKey
	local price = CONST.UNLOCKS[buy].price
	Log.log(NAME, `Checking the bank for {price} golden nuggets to buy the {buy} unlock`)
	Route.clear_way(Route.neighbours(CONST.BANK_CHEST))
	if not Bankmain.open() then
		if BankpinKeypad.is_open() then
			local result = BankpinKeypad.enter()
			if result ~= "entered" then
				Log.log(
					NAME,
					`The bank wants a PIN the loader couldn't enter ({result}), so no unlocks get bought; save it on the Accounts page`
				)
				S.bank_locked = true
				Toplevel.escape_clear()
				return
			end
		end
		Game.fail("The bank chest didn't open")
		S.skip["NUGGETS"] = true
		return
	end
	local banked = Bankmain.count_ex(CONST.NUGGET) or 0
	S.bank_nuggets = banked
	if banked + snap.carried.nuggets >= price then
		if Bankmain.withdraw(CONST.NUGGET, 0) then
			S.bank_nuggets = 0
			Game.progress()
		else
			Game.fail("Couldn't take the golden nuggets out")
		end
	else
		Log.log(NAME, `Only {banked} golden nuggets in the bank, mining on`)
	end
	Bankmain.close()
end

function Handler.wait_sack()
	if not Handler.ensure_lower() then
		return
	end
	local sack = Objects.nearest(CONST.SACK.id, snap.me)
	if sack and Objects.distance(sack, snap.me) > 3 then
		Walker.walk({ x = sack.x + Random.int(-1, 1), y = sack.y + Random.int(1, 2) }, { near = 1 })
	end
	Widgets.wait_until(function()
		return (Varbits.get(CONST.VARBIT.SACK) or 0) > S.last_sack or Read.wheels_broken()
	end, 4000, 200)
end

function Handler.get_hammer(): boolean
	local crate: Loc? = nil
	for _, loc in ipairs(Objects.find(CONST.CRATE.name) or {}) do
		for _, at in ipairs(CONST.CRATE.hammers) do
			if
				loc.x == at.x
				and loc.y == at.y
				and (crate == nil or Objects.distance(loc, snap.me) < Objects.distance(crate, snap.me))
			then
				crate = loc
			end
		end
	end
	if crate == nil then
		return false
	end
	Log.log(NAME, `Taking a hammer from the crate at {crate.x}, {crate.y}`)
	Route.clear_way(Route.neighbours(crate))
	if Objects.approach(crate, CONST.CRATE.option) then
		Widgets.wait_until(function()
			return Inventory.contains_any(CONST.HAMMERS)
		end, 4000, 100)
	end
	if Inventory.contains_any(CONST.HAMMERS) then
		return true
	end
	return false
end

function Handler.recover_dirt()
	local at = S.dropped_dirt :: DroppedDirt
	if snap.floor ~= at.floor then
		Game.climb(at.floor)
		return
	end
	if Inventory.is_full() then
		local hammer = Inventory.index_of(CONST.HAMMERS)
		if hammer == nil or not Inventory.drop_slots({ hammer }) then
			Game.fail("No room to pick the pay-dirt back up")
			return
		end
	end
	local dirt: Host.GroundItem? = nil
	for _, item in ipairs(GroundItems.find(CONST.PAYDIRT) or {}) do
		if math.max(math.abs(item.x - at.x), math.abs(item.y - at.y)) <= 1 then
			dirt = item
		end
	end
	if dirt == nil then
		Log.log(NAME, "The dropped pay-dirt is gone")
		S.dropped_dirt = nil
		return
	end
	local before = Inventory.count(CONST.PAYDIRT) or 0
	if
		GroundItems.approach(dirt, "Take")
		and Widgets.wait_until(function()
			return (Inventory.count(CONST.PAYDIRT) or 0) > before
		end, 4000, 100)
	then
		Log.log(NAME, "Picked the pay-dirt back up")
		S.dropped_dirt = nil
		Game.progress()
	else
		Game.fail("Couldn't pick the pay-dirt back up")
	end
end

function Handler.repair()
	if not Handler.ensure_lower() then
		return
	end
	if not snap.carried.hammer then
		if Inventory.is_full() then
			local slot = Inventory.index_of(CONST.PAYDIRT)
			if slot and Inventory.drop_slots({ slot }) then
				Log.log(NAME, "Dropped a pay-dirt to make room for a hammer")
				S.dropped_dirt = { x = snap.me.x, y = snap.me.y, floor = snap.floor }
			end
			return
		end
		if not Handler.get_hammer() then
			Game.fail("No hammer yet")
		end
		return
	end
	local strut = Objects.nearest(CONST.STRUT.broken, snap.me)
	if strut == nil then
		return
	end
	Log.log(NAME, `Both wheels are broken, repairing the strut at {strut.x}, {strut.y}`)
	Route.clear_way(Route.neighbours(strut))
	if not Objects.approach(strut, CONST.STRUT.option) then
		Game.fail("Couldn't hammer the strut")
		return
	end
	local sx, sy = strut.x, strut.y
	local fixed = Widgets.wait_until(function()
		for _, loc in ipairs(Objects.find(CONST.STRUT.broken) or {}) do
			if loc.x == sx and loc.y == sy then
				return false
			end
		end
		return true
	end, CONST.STRUT.fix_ms, 200)
	if fixed then
		stats.repairs += 1
		S.inflight_at = time()
		Game.progress()
	else
		Game.fail("The strut is still broken")
	end
end

function Handler.percy(buy: UnlockKey?)
	if not Handler.ensure_lower() then
		return
	end
	if not Game.talk_to_percy(buy) then
		S.skip["BUY"] = true
		return
	end
	Route.map_upper()
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	BUY = function()
		Handler.percy(plan.buy)
	end,
	BANK = Handler.bank,
	NUGGETS = Handler.fetch_nuggets,
	RECOVER = Handler.recover_dirt,
	COLLECT = Handler.collect,
	WAIT_SACK = Handler.wait_sack,
	REPAIR = Handler.repair,
	DEPOSIT = Handler.deposit,
	MINE = Handler.mine,
}

function Game.apply_settings(values: { [string]: any })
	if values.use_upper ~= nil then
		CONFIG.use_upper = values.use_upper
	end
	if values.have_upper ~= nil then
		CONFIG.have_upper = values.have_upper
	end
	if values.have_hopper ~= nil then
		CONFIG.have_hopper = values.have_hopper
	end
	CONFIG.buy.upper = values.buy_upper or CONFIG.buy.upper
	CONFIG.buy.hopper = values.buy_hopper or CONFIG.buy.hopper
	CONFIG.buy.sack = values.buy_sack or CONFIG.buy.sack
	CONFIG.max_paydirt = values.max_paydirt or CONFIG.max_paydirt
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

local last_stray_at = 0
local function close_stray(state: State)
	if state == "BUY" or state == "BANK" or state == "NUGGETS" or BankpinKeypad.is_open() then
		return
	end
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.wrap_up()
	local settled, why = Handoff.settle()
	if not settled then
		error(`Couldn't leave the account settled: {why}`, 0)
	end
	if S.blocked then
		Handoff.blocked(S.blocked)
	else
		Handoff.done()
	end
end

function Loop.run()
	Game.apply_settings(Host.settings())
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() and not S.finishing then
			Log.log(NAME, "The queue asked to wrap up, emptying the sack first")
			S.finishing = true
		end
		Game.poll_settings()
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		close_stray(state)
		Handler.states[state]()

		if S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Loop.wrap_up()
	Log.log(NAME, "Done")
end

Loop.run()
