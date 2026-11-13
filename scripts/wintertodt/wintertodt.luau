--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local widget = Host.widget
local loc_shown = Host.loc_shown
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Tile = Host.Tile
type Loc = Host.Loc
type Npc = Host.Npc
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local Chat = require("@lib/main/interfaces/chatbox/chat")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Item = require("@lib/utils/item")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Players = require("@lib/main/entities/players")
local Random = require("@lib/utils/math/random")
local SpecialAttack = require("@lib/main/interfaces/special_attack")
local SpotAnims = require("@lib/main/entities/spot_anims")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Ticks = require("@lib/utils/ticks")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Transports = require("@lib/main/transports")
local Walker = require("@lib/main/walker")
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Wintertodt"
local TICK = Ticks.MS

type Mode = "group" | "solo"
type Side = "west" | "east"
type Corner = "sw" | "se" | "nw" | "ne"
type SoloGoal = "points" | "xp"
type Danger = { x: number, y: number, radius: number }
type BrazierState = "UNLIT" | "LIT" | "BROKEN" | "DEAD"
type Tool = "axe" | "tinderbox" | "knife" | "hammer"

type SideSpots = {
	brazier: Tile,
	stand: { Tile },
	root: Tile,
	root_stand: Tile,
	pyromancer: Tile,
	break_z: number,
}

local function line(x1: number, y1: number, x2: number, y2: number): { Tile }
	local tiles: { Tile } = {}
	for x = math.min(x1, x2), math.max(x1, x2) do
		for y = math.min(y1, y2), math.max(y1, y2) do
			table.insert(tiles, { x = x, y = y })
		end
	end
	return tiles
end

local function joined(a: { Tile }, b: { Tile }): { Tile }
	local out = table.clone(a)
	table.move(b, 1, #b, #out + 1, out)
	return out
end

local WEST: SideSpots = {
	brazier = { x = 1621, y = 3998 },
	stand = joined(line(1619, 3997, 1619, 3999), line(1620, 3996, 1622, 3996)),
	root = { x = 1620, y = 3988 },
	root_stand = { x = 1622, y = 3988 },
	pyromancer = { x = 1619, y = 3996 },
	break_z = -2246,
}

local EAST: SideSpots = {
	brazier = { x = 1639, y = 3998 },
	stand = joined(line(1641, 3997, 1641, 3999), line(1638, 3996, 1640, 3996)),
	root = { x = 1639, y = 3988 },
	root_stand = { x = 1638, y = 3988 },
	pyromancer = { x = 1641, y = 3996 },
	break_z = -2246,
}

local CONST = {
	HUD = { GROUP = 396, POINTS = 6, WARMTH = 20, ENERGY = 26 },
	BRAZIER_STATES = { [29312] = "UNLIT", [29313] = "BROKEN", [29314] = "LIT" } :: { [number]: BrazierState },
	SIDES = { west = WEST, east = EAST } :: { [Side]: SideSpots },
	SOLO = {
		CORNERS = {
			sw = WEST,
			se = EAST,
			nw = {
				brazier = { x = 1621, y = 4016 },
				stand = joined(line(1619, 4015, 1619, 4017), line(1620, 4018, 1622, 4018)),
				root = { x = 1621, y = 4025 },
				root_stand = { x = 1623, y = 4025 },
				pyromancer = { x = 1619, y = 4018 },
				break_z = -2238,
			},
			ne = {
				brazier = { x = 1639, y = 4016 },
				stand = joined(line(1641, 4015, 1641, 4017), line(1638, 4018, 1640, 4018)),
				root = { x = 1638, y = 4025 },
				root_stand = { x = 1637, y = 4025 },
				pyromancer = { x = 1641, y = 4018 },
				break_z = -2246,
			},
		} :: { [Corner]: SideSpots },
		ROUTE_GAP = { "se", "ne", "nw", "sw" } :: { Corner },
		ROUTE_AROUND = { "ne", "se", "sw", "nw" } :: { Corner },
		FOCUS = "sw" :: Corner,
		END_CORNERS = { "sw", "se" } :: { Corner },
		GAP = "Jump Gap 29326",
		OPEN_UNTIL = { 20, 30 },
		LOW_ENERGY = 8,
		REWARD_POINTS = 500,
		POINTS_SPREAD = 1000,
		DOSES_PER_POTION = 4,
		VISIT_MS = { 90000, 150000 },
		VIALS = {
			{ count = 10, option = "Take-10 concoctions" },
			{ count = 5, option = "Take-5 concoctions" },
			{ count = 1, option = "Take-concoction" },
		},
		SNOW = { CENTRE = 502, CORNER = 1311, LANDED_CYCLES = 15, REACH = 3, AREA = 1, BLAST = 2, Z_SLACK = 4 },
		IDLE_MS = { 600, 1800 },
		CHECK_MS = 300,
	},
	HALL = { x1 = 1627, y1 = 3979, x2 = 1633, y2 = 3985 },
	DOORS = { x = 1630, y = 3965 },
	VIAL_CRATES = { { x = 1626, y = 3982 }, { x = 1634, y = 3982 } } :: { Tile },
	SPROUTING_ROOTS = { { x = 1635, y = 3978 }, { x = 1625, y = 3978 } } :: { Tile },
	BREWMA = { x = 1635, y = 3986 },
	TOOL_CRATES = {
		axe = { x = 1626, y = 3984 },
		tinderbox = { x = 1634, y = 3984 },
		hammer = { x = 1626, y = 3980 },
		knife = { x = 1634, y = 3980 },
	} :: { [Tool]: Tile },
	TOOL_ORDER = { "axe", "tinderbox", "knife", "hammer" } :: { Tool },
	VIAL_OPTION = "Take-5 concoctions",
	FIND_RANGE = 3,
	NEAR_BRAZIER = 2,
	HOVER_RANGE = 15,
	BREWMA_RANGE = 10,
	HERBS_NEEDED = 5,
	SPACE_NEEDED = 5,
	KEEP_ITEMS = 10,
	TOOL_ATTEMPTS = 5,
	POLL_MS = 50,
	TINY_ANTIBAN_CHANCE = 0.4,
	ACTIVITY_WAITS = {
		WAIT_PICKING = true,
		WAIT_MIXING = true,
		WAIT_CUTTING = true,
		WAIT_FLETCHING = true,
		WAIT_BURNING = true,
		WAIT_BOSS = true,
		SOLO_IDLE = true,
	} :: { [string]: boolean },
	REPORT = { counters_key = "" },
}

local ITEMS = {
	ROOT = "Bruma root",
	KINDLING = "Bruma kindling",
	HERB = "Bruma herb",
	UNF = "Rejuvenation potion (unf)",
	POTION = "Rejuvenation potion (1..4)",
	POTION_1 = "Rejuvenation potion (1)",
	KNIVES = { "Knife", "Fletching knife" },
}

local TOOL_NAMES: { [Tool]: { [string]: boolean } } = {
	axe = {},
	tinderbox = { ["tinderbox"] = true, ["bruma torch"] = true, ["bruma torch (off-hand)"] = true },
	knife = { ["knife"] = true, ["fletching knife"] = true },
	hammer = { ["hammer"] = true, ["imcando hammer"] = true, ["imcando hammer (off-hand)"] = true },
}

local Read, Wait, Task, Game, Loop, Solo, Handler = {}, {}, {}, {}, {}, {}, {}

local CONFIG = {
	mode = "group" :: Mode,
	solo_goal = "points" :: SoloGoal,
	solo_potions = 8,
	solo_points = 5000,
	side = "west" :: Side,
	alternate = true,
	prioritize_brazier = false,
	help_pyromancers = true,
	wintertodt_worlds = true,
	stop_fletch_energy = 20,
	max_kills = 0,
	max_minutes = 0,
	max_firemaking = 0,
	timeouts = { idle_minutes = 5 },
	antiban = true,
}

local stats = { kills = 0, rewarded = 0, rewards = 0, points = 0, owed = 0 }

type SoloRound = {
	started: boolean,
	opened: boolean,
	lit: { [Corner]: boolean },
	open_until: number,
	ending: boolean,
	end_corner: Corner,
	points_bonus: number,
	visited: { [Corner]: number },
	visit_every: number,
	checked_at: number,
	at: Corner?,
	turn_back: boolean,
}

local function new_round(): SoloRound
	return {
		started = false,
		opened = false,
		lit = {},
		open_until = Random.int(CONST.SOLO.OPEN_UNTIL[1], CONST.SOLO.OPEN_UNTIL[2]),
		ending = false,
		end_corner = CONST.SOLO.FOCUS,
		points_bonus = Random.int(0, CONST.SOLO.POINTS_SPREAD),
		visited = {},
		visit_every = Random.int(CONST.SOLO.VISIT_MS[1], CONST.SOLO.VISIT_MS[2]),
		checked_at = 0,
		at = nil,
		turn_back = false,
	}
end

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	started_at: number,
	last_progress_at: number,
	last_xp: number,
	current: Side,
	corner: Corner,
	round: SoloRound,
	worlds: { number }?,
	herbs_wanted: number,
	has_herblore: boolean,
	warmth: number,
	boss: number,
	min_warmth: number,
	chat_uid: number,
	round_points: number,
	stale_points: number?,
	subdued: number?,
	picking: boolean,
	mixing: boolean,
	cutting: boolean,
	fletching: boolean,
	burning: boolean,
	hovering: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	started_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	current = "west",
	corner = CONST.SOLO.FOCUS,
	round = new_round(),
	herbs_wanted = CONST.HERBS_NEEDED,
	has_herblore = false,
	warmth = 100,
	boss = 0,
	min_warmth = 50,
	chat_uid = -1,
	round_points = 0,
	picking = false,
	mixing = false,
	cutting = false,
	fletching = false,
	burning = false,
	hovering = false,
}

type State =
	"LOADING"
	| "LOGIN"
	| "LEVEL_UP"
	| "ENTER_ROOM"
	| "DROP_ITEMS"
	| "MAKE_SPACE"
	| "GET_VIALS"
	| "PICK_HERBS"
	| "MIX_POTIONS"
	| "TALK_TO_BREWMA"
	| "SWITCH_SIDES"
	| "WARM_UP"
	| "WALK_ROOT"
	| "WALK_BRAZIER"
	| "USE_SPEC"
	| "CUT_ROOTS"
	| "FLETCH_LOGS"
	| "BURN_FUEL"
	| "HOVER_BRAZIER"
	| "FIX_BRAZIER"
	| "HELP_PYRO"
	| "WAIT_PICKING"
	| "WAIT_MIXING"
	| "WAIT_CUTTING"
	| "WAIT_FLETCHING"
	| "WAIT_BURNING"
	| "WAIT_BOSS"
	| "HOP_WORLD"
	| "DODGE"
	| "SOLO_IDLE"
	| "STOP"

local report = StatsReport.new()

function Read.me(): Tile?
	return Walker.position()
end

function Read.distance(a: Tile, b: Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function Read.any_in_range(from: Tile, tiles: { Tile }, range: number): boolean
	for _, t in ipairs(tiles) do
		if Read.distance(from, t) <= range then
			return true
		end
	end
	return false
end

function Read.in_hall(at: Tile): boolean
	local h = CONST.HALL
	return at.x >= h.x1 and at.x <= h.x2 and at.y >= h.y1 and at.y <= h.y2
end

function Read.outside(at: Tile): boolean
	return at.y < CONST.DOORS.y
end

function Read.spots(): SideSpots
	if CONFIG.mode == "solo" then
		return CONST.SOLO.CORNERS[S.corner]
	end
	return CONST.SIDES[S.current]
end

function Read.total_xp(): number
	return Stats.total_experience(game_state().skills) or 0
end

function Read.hud_text(child: number): string?
	local w = widget(CONST.HUD.GROUP, child)
	if w == nil or w.hidden or w.text == nil then
		return nil
	end
	return w.text
end

function Read.hud_percent(child: number): number?
	local text = Read.hud_text(child)
	if text == nil then
		return nil
	end
	local n = string.match(text, "(%d+)%%")
	return if n then tonumber(n) else 0
end

function Task.stop_actions_except_cutting(stop_hovering: boolean)
	S.picking, S.mixing, S.fletching, S.burning = false, false, false, false
	if stop_hovering then
		S.hovering = false
	end
end

function Task.stop_actions(stop_hovering: boolean)
	Task.stop_actions_except_cutting(stop_hovering)
	S.cutting = false
end

function Read.warmth(): number?
	local value = Read.hud_percent(CONST.HUD.WARMTH)
	if value == nil then
		return nil
	end
	if value < S.warmth then
		Task.stop_actions_except_cutting(false)
	end
	S.warmth = value
	return value
end

function Read.got_hit(): boolean
	local before = S.warmth
	local now = Read.warmth()
	return now ~= nil and now < before
end

function Read.boss_energy(): number
	local value = Read.hud_percent(CONST.HUD.ENERGY) or 0
	if value <= 0 then
		Task.stop_actions(false)
	end
	S.boss = value
	return value
end

function Read.hud_points(): number?
	local text = Read.hud_text(CONST.HUD.POINTS)
	local n = text and string.match((string.gsub(text, ",", "")), "(%d+)")
	return if n then tonumber(n) else nil
end

function Read.track_points()
	local points = Read.hud_points()
	if points == nil then
		return
	end
	if S.stale_points ~= nil then
		if points == S.stale_points then
			return
		end
		S.stale_points = nil
	end
	S.round_points = math.max(S.round_points, points)
end

function Read.number(text: string, pattern: string): number?
	local n = string.match((string.gsub(text, ",", "")), pattern)
	return if n then tonumber(n) else nil
end

function Read.on_kill(total: number?)
	local points = math.max(S.round_points, Read.hud_points() or 0)
	stats.kills += 1
	stats.points += points
	S.stale_points, S.round_points = Read.hud_points(), 0
	S.subdued = total or S.subdued
	if not CONFIG.alternate then
		S.current = CONFIG.side
	end
	Log.log(NAME, `Wintertodt subdued with {points} points, {stats.kills} kills ({S.subdued or "?"} in all)`)
end

function Read.on_rewards(gained: number, owed: number?)
	stats.rewarded += 1
	stats.rewards += gained
	stats.owed = owed or stats.owed
	Log.log(NAME, `{gained} rewards from the cart, {stats.owed} owed`)
end

function Read.read_chat()
	for _, m in ipairs(Chat.new_messages(S.chat_uid, { Chat.MessageType.GAME }) or {}) do
		S.chat_uid = math.max(S.chat_uid, m.uid)
		local text = m.text
		if string.find(text, "Your subdued Wintertodt count is", 1, true) then
			Read.on_kill(Read.number(text, "count is:%s*(%d+)"))
		elseif string.find(text, "from the reward cart", 1, true) then
			Read.on_rewards(
				Read.number(text, "additional (%d+) reward") or 0,
				Read.number(text, "now owed (%d+) reward")
			)
		end
	end
end

function Read.skip_old_chat()
	local last = Chat.last_message()
	S.chat_uid = if last then last.uid else -1
end

function Read.count(items: Item.Item | { Item.Item }): number
	return Inventory.count(items) or 0
end

function Read.used(): number
	return Inventory.count_used() or 0
end

function Read.free(): number
	return Inventory.free_slots() or 0
end

function Read.doses(): number
	local total = 0
	for dose = 1, 4 do
		total += Read.count(`Rejuvenation potion ({dose})`) * dose
	end
	return total
end

function Read.fuel(factor: number): number
	return Read.count({ ITEMS.ROOT, ITEMS.KINDLING }) * factor
end

function Read.loc_view(loc: Loc): Host.LocView?
	local views = loc_shown({ loc.id })
	return views and views[1]
end

function Read.has_action(loc: Loc, wanted: string): boolean
	local view = Read.loc_view(loc)
	if view == nil then
		return false
	end
	for _, action in ipairs(view.actions) do
		if action == wanted then
			return true
		end
	end
	return false
end

function Read.loc_near(anchor: Tile, accept: (Loc) -> boolean): Loc?
	local best, best_d = nil, math.huge
	for _, l in ipairs(Objects.find() or {}) do
		local d = Objects.distance(l, anchor)
		if d <= CONST.FIND_RANGE and d < best_d and accept(l) then
			best, best_d = l, d
		end
	end
	return best
end

function Read.named(part: string): (Loc) -> boolean
	return function(l: Loc): boolean
		return l.name ~= nil and string.find(string.lower(l.name), part, 1, true) ~= nil
	end
end

function Read.offers(option: string): (Loc) -> boolean
	return function(l: Loc): boolean
		return Read.has_action(l, option)
	end
end

function Read.brazier(spots: SideSpots?): Loc?
	return Read.loc_near((spots or Read.spots()).brazier, function(l: Loc): boolean
		return CONST.BRAZIER_STATES[l.id] ~= nil
	end)
end

function Read.root(): Loc?
	return Read.loc_near(Read.spots().root, Read.named("bruma roots"))
end

function Read.pyromancer(spots: SideSpots?): Npc?
	local anchor = (spots or Read.spots()).pyromancer
	local best, best_d = nil, math.huge
	for _, n in ipairs(Npcs.find() or {}) do
		local d = Read.distance(n, anchor)
		if d <= CONST.FIND_RANGE and d < best_d and string.find(string.lower(n.name), "pyromancer", 1, true) then
			best, best_d = n, d
		end
	end
	return best
end

function Read.incapacitated(pyro: Npc): boolean
	return string.find(string.lower(Npcs.clean_name(pyro.name)), "incapacitated", 1, true) ~= nil
end

function Read.brazier_state(spots: SideSpots?): BrazierState
	local pyro = Read.pyromancer(spots)
	if pyro and Read.incapacitated(pyro) then
		return "DEAD"
	end
	local loc = Read.brazier(spots)
	return if loc then CONST.BRAZIER_STATES[loc.id] else "UNLIT"
end

function Read.near_brazier(at: Tile): boolean
	return Read.any_in_range(at, Read.spots().stand, CONST.NEAR_BRAZIER)
end

function Read.is_axe(name: string): boolean
	local base = string.gsub(name, "%s*%b()$", "")
	return string.match(base, " axe$") ~= nil
end

function Read.carried_names(): { string }
	local ids: { number } = {}
	for _, s in ipairs(Inventory.items() or {}) do
		table.insert(ids, s.id)
	end
	for _, s in pairs(Wornitems.worn() or {}) do
		table.insert(ids, s.id)
	end
	local names: { string } = {}
	for _, name in ipairs(Item.names(ids) or {}) do
		if name then
			table.insert(names, string.lower(name))
		end
	end
	return names
end

function Read.has_tool(tool: Tool, names: { string }): boolean
	for _, name in ipairs(names) do
		if tool == "axe" and Read.is_axe(name) or TOOL_NAMES[tool][name] then
			return true
		end
	end
	return false
end

function Read.axe_wielded(): boolean
	local weapon = SpecialAttack.weapon()
	local name = weapon and Item.name(weapon)
	return name ~= nil and Read.is_axe(string.lower(name))
end

function Wait.until_true(timeout_ms: number, check: () -> boolean): boolean
	local deadline = time() + timeout_ms
	while true do
		if Read.threat() then
			return false
		end
		if check() then
			return true
		end
		if time() >= deadline then
			return false
		end
		sleep(math.floor(math.max(1, math.min(CONST.POLL_MS, deadline - time()))))
	end
end

function Wait.sleep(ms: number): boolean
	local deadline = time() + ms
	while time() < deadline do
		if Read.threat() then
			return true
		end
		sleep(math.floor(math.max(1, math.min(CONST.POLL_MS, deadline - time()))))
	end
	return false
end

function Wait.moving()
	Wait.until_true(10 * TICK, function()
		return game_state().destination == nil
	end)
end

function Wait.picking(): boolean
	local count = Read.used()
	local hit = false
	local ok = Wait.until_true(5 * TICK, function()
		hit = Read.got_hit()
		return hit or Read.used() > count
	end)
	S.picking = ok and not hit and Read.count(ITEMS.HERB) < S.herbs_wanted
	return S.picking
end

function Wait.mixing(): boolean
	local count, xp = Read.used(), Read.total_xp()
	local hit = false
	local ok = Wait.until_true(5 * TICK, function()
		hit = Read.got_hit()
		return hit or Read.total_xp() > xp or Read.used() < count
	end)
	S.mixing = ok and not hit
	return S.mixing
end

function Wait.cutting(): boolean
	local count, xp = Read.used(), Read.total_xp()
	local brazier = if CONFIG.prioritize_brazier then Read.brazier_state() else nil
	local boss_low = false
	local ok = Wait.until_true(7 * TICK, function()
		boss_low = CONFIG.mode == "group" and Read.boss_energy() < count - 4
		return boss_low
			or Read.total_xp() > xp
			or Read.used() > count
			or (brazier ~= nil and Read.brazier_state() ~= brazier)
	end)
	S.cutting = ok and not Inventory.is_full() and not boss_low
	return S.cutting
end

function Wait.fletching(): boolean
	local count, xp = Read.count(ITEMS.KINDLING), Read.total_xp()
	local brazier = Read.brazier_state()
	local hit, boss_low = false, false
	local ok = Wait.until_true(5 * TICK, function()
		hit = Read.got_hit()
		boss_low = CONFIG.mode == "group" and Read.boss_energy() < Read.fuel(0.9)
		return hit
			or boss_low
			or Read.total_xp() > xp
			or Read.count(ITEMS.KINDLING) > count
			or Read.brazier_state() ~= brazier
	end)
	S.fletching = ok and not hit and not boss_low and Read.count(ITEMS.ROOT) > 0
	return S.fletching
end

function Wait.burning(): boolean
	local count, xp = Read.used(), Read.total_xp()
	local brazier = Read.brazier_state()
	local hit, ran_out = false, false
	local ok = Wait.until_true(5 * TICK, function()
		hit = Read.got_hit()
		ran_out = Read.count({ ITEMS.ROOT, ITEMS.KINDLING }) == 0
		return hit or ran_out or Read.total_xp() > xp or Read.used() < count or Read.brazier_state() ~= brazier
	end)
	S.burning = ok and not hit and not ran_out
	return S.burning
end

function Wait.boss()
	Wait.until_true(6 * TICK, function()
		return Read.boss_energy() ~= 0
	end)
end

function Task.walk(tile: Tile, near: number): boolean
	return Walker.walk(tile, { near = near }) == true
end

function Task.walk_to_hall(): boolean
	local me = Read.me()
	if me and Read.in_hall(me) then
		return true
	end
	local h = CONST.HALL
	return Task.walk(Random.tile_in_box(h.x1, h.y1, h.x2, h.y2), 2)
end

function Task.enter_room(): boolean
	local me = Read.me()
	local doors = me and Objects.nearest("Doors of Dinh", me)
	if doors == nil then
		Task.walk(CONST.DOORS, 4)
		return false
	end
	if not Objects.approach(doors, { "Enter" }) then
		return false
	end
	return Wait.until_true(12 * TICK, function()
		local now = Read.me()
		return now ~= nil and now.y > CONST.DOORS.y
	end)
end

function Task.take_tool(tool: Tool): boolean
	local option = `Take-{tool}`
	local crate = Read.loc_near(CONST.TOOL_CRATES[tool], Read.offers(option))
	if crate == nil then
		Task.walk(CONST.TOOL_CRATES[tool], 2)
		return false
	end
	Log.log(NAME, `Taking a {tool}`)
	if not Objects.approach(crate, { option }) then
		return false
	end
	Wait.moving()
	return Wait.until_true(4 * TICK, function()
		return Read.has_tool(tool, Read.carried_names())
	end)
end

function Read.missing_tools(): { Tool }
	local names = Read.carried_names()
	local missing: { Tool } = {}
	for _, tool in ipairs(CONST.TOOL_ORDER) do
		if not Read.has_tool(tool, names) then
			table.insert(missing, tool)
		end
	end
	return missing
end

function Task.get_tools()
	for _ = 1, CONST.TOOL_ATTEMPTS do
		local missing = Read.missing_tools()
		if #missing == 0 then
			return
		end
		for _, tool in ipairs(missing) do
			if not Task.take_tool(tool) then
				break
			end
		end
	end
	if #Read.missing_tools() > 0 then
		error("Failed to get tools from the Wintertodt crates.")
	end
end

function Task.pick_herbs(wanted: number): boolean
	S.herbs_wanted = wanted
	local me = Read.me()
	if me == nil then
		return false
	end
	local best, best_d = nil, math.huge
	for _, anchor in ipairs(CONST.SPROUTING_ROOTS) do
		local loc = Read.loc_near(anchor, Read.named("sprouting"))
		if loc and Objects.distance(loc, me) < best_d then
			best, best_d = loc, Objects.distance(loc, me)
		end
	end
	if best == nil then
		Task.walk(CONST.SPROUTING_ROOTS[1], 3)
		return false
	end
	if not Objects.approach(best, { "Pick" }) then
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.picking()
end

function Task.get_vials(option: string): boolean
	local me = Read.me()
	if me == nil then
		return false
	end
	local best, best_d = nil, math.huge
	for _, anchor in ipairs(CONST.VIAL_CRATES) do
		local loc = Read.loc_near(anchor, Read.offers(option))
		if loc and Objects.distance(loc, me) < best_d then
			best, best_d = loc, Objects.distance(loc, me)
		end
	end
	if best == nil then
		Task.walk(CONST.VIAL_CRATES[1], 3)
		return false
	end
	local count = Read.used()
	if not Objects.approach(best, { option }) then
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.until_true(4 * TICK, function()
		return Read.used() > count
	end)
end

function Task.mix_potions(): boolean
	local ok = false
	if Inventory.combine(ITEMS.UNF, ITEMS.HERB) then
		Task.stop_actions(true)
		ok = Wait.mixing()
	end
	Wait.sleep(Random.int(100, 300))
	return ok
end

function Task.talk_to_brewma(): boolean
	local me = Read.me()
	if me == nil then
		return false
	end
	if Read.distance(me, CONST.BREWMA) > CONST.BREWMA_RANGE then
		local b = CONST.BREWMA
		if not Task.walk(Random.tile_in_box(b.x - 4, b.y - 4, b.x + 4, b.y + 4), 3) then
			return false
		end
		Task.stop_actions(true)
		me = Read.me() or me
	end
	local brewma = Npcs.nearest("Brew'ma", me)
	if brewma == nil then
		return false
	end
	if not Inventory.select({ ITEMS.UNF, ITEMS.HERB }) then
		return false
	end
	local count = Read.used()
	if not Npcs.interact(brewma, "Use") then
		Inventory.deselect()
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.until_true(4 * TICK, function()
		return Read.used() < count
	end)
end

function Task.click_brazier(on_step: ((Tile) -> boolean)?): boolean
	local loc = Read.brazier()
	if loc == nil then
		return Task.walk(Read.spots().brazier, 3)
	end
	local xp = Read.total_xp()
	if not Objects.approach(loc, { "Fix", "Light" }, { walk = { on_step = on_step } }) then
		return false
	end
	Task.stop_actions(true)
	local switched = false
	Wait.until_true(10 * TICK, function()
		local here = Read.me()
		switched = on_step ~= nil and here ~= nil and not on_step(here)
		return switched or game_state().destination == nil
	end)
	if switched then
		return false
	end
	return Wait.until_true(4 * TICK, function()
		return Read.total_xp() > xp
	end)
end

function Task.hover_brazier(): boolean
	local me = Read.me()
	if me == nil then
		return false
	end
	local spots = Read.spots()
	if not Read.any_in_range(me, spots.stand, CONST.HOVER_RANGE) then
		if not Task.walk(spots.stand[Random.int(1, #spots.stand)], 2) then
			return false
		end
	end
	local loc = Read.brazier()
	S.hovering = loc ~= nil and Objects.hover(loc)
	return S.hovering
end

function Task.help_pyromancer(): boolean
	local pyro = Read.pyromancer()
	if pyro == nil then
		return false
	end
	local count = Read.doses()
	if not Npcs.approach(pyro, { "Help" }) then
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.until_true(4 * TICK, function()
		return Read.doses() < count
	end)
end

function Task.cut_roots(): boolean
	local root = Read.root()
	if root == nil then
		return Task.walk(Read.spots().root_stand, 1)
	end
	if not Objects.approach(root, { "Chop" }) then
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.cutting()
end

function Task.burn_fuel(): boolean
	local loc = Read.brazier()
	if loc == nil then
		return Task.walk(Read.spots().brazier, 3)
	end
	if not Objects.approach(loc, { "Feed" }) then
		return false
	end
	Task.stop_actions(true)
	Wait.moving()
	return Wait.burning()
end

function Task.fletch_logs(): boolean
	Inventory.combine(ITEMS.KNIVES, ITEMS.ROOT)
	Task.stop_actions(true)
	local ok = Wait.fletching()
	Wait.sleep(Random.int(600, 800))
	return ok
end

function Task.warm_up(): boolean
	local target = Random.int(math.max(85, S.min_warmth), 100)
	Task.stop_actions(true)
	local warm = false
	while not warm do
		local potion = if CONFIG.mode == "solo" then Read.lowest_potion() else ITEMS.POTION
		if potion == nil or not Inventory.interact(potion, "Drink") then
			return false
		end
		if Wait.sleep(Random.int(TICK + 10, 2 * TICK)) then
			return false
		end
		local now = Read.warmth()
		warm = now == nil or now >= target
	end
	S.min_warmth = Biometrics.random_mode_integer(50, 35, 70)
	return true
end

function Task.drop_items(supplies: { Item.Item }): boolean
	local drop: { number } = {}
	for _, slot in ipairs(Inventory.indices_of(supplies) or {}) do
		table.insert(drop, slot)
	end
	local used = Read.used()
	for _, item in ipairs({ ITEMS.ROOT, ITEMS.KINDLING }) do
		for _, slot in ipairs(Inventory.indices_of(item) or {}) do
			if used - #drop <= CONST.KEEP_ITEMS then
				break
			end
			table.insert(drop, slot)
		end
	end
	if #drop == 0 then
		return true
	end
	local ordered = Inventory.pattern(drop)
	return Inventory.shift_drop_slots(ordered)
end

function Task.switch_sides()
	if Biometrics.random_boolean() then
		S.current = if S.current == "west" then "east" else "west"
		Log.log(NAME, `Switching to the {S.current} brazier`)
	end
end

function Game.sign_in(): boolean
	Log.log(NAME, "Logging in")
	if not Login.sign_in() then
		Log.log(NAME, "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.logged_in(s: ClientState): boolean
	return s.game_state == GameState.LOGGED_IN and s.position ~= nil
end

function Game.setup_antiban()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 35)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Firemaking", "Woodcutting", "Fletching", "Construction", "Total" }
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
	if CONFIG.mode == "group" and CONFIG.alternate then
		Antiban.add_task(Task.switch_sides, Biometrics.random_mode_integer(20, 10, 30) * MINUTE, 0.33)
	end

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

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.check_world()
	if not CONFIG.wintertodt_worlds then
		Log.warn(NAME, "For guaranteed results use a Wintertodt world.")
		return
	end
	if not WorldSwitcher.open(true) then
		error("Failed to open the world switcher.")
	end
	local worlds: { number } = {}
	for _, row in ipairs(WorldSwitcher.rows() or {}) do
		if row.available and row.activity and string.find(string.lower(row.activity), "wintertodt", 1, true) then
			table.insert(worlds, row.world)
		end
	end
	if #worlds == 0 then
		error("The world list has no Wintertodt worlds.")
	end
	local world = WorldSwitcher.current()
	if world and table.find(worlds, world) then
		Log.log(NAME, `On Wintertodt world {world}`)
		WorldSwitcher.close()
		return
	end
	Log.log(NAME, `World {world or "?"} isn't a Wintertodt world (those are {table.concat(worlds, ", ")}), hopping`)
	if not WorldSwitcher.random(worlds) then
		error("Failed to hop to a Wintertodt world.")
	end
end

function Game.setup()
	while true do
		local s = game_state()
		if Read.logged_in(s) then
			break
		end
		if Read.scene_loading(s) then
			sleep(100)
		else
			Game.sign_in()
		end
	end

	Biometrics.setup_player()
	S.has_herblore = (Stats.real_level("Herblore") or 0) >= 3
	S.min_warmth = Biometrics.random_mode_integer(50, 35, 70)
	S.current = CONFIG.side
	S.corner = CONST.SOLO.FOCUS

	local me = Read.me()
	if me and Read.outside(me) and not Task.enter_room() then
		error("Failed to enter the Wintertodt room. Please start inside of the Wintertodt room.")
	end
	Task.get_tools()
	if CONFIG.mode == "group" then
		Game.check_world()
	end

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
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
	local key = `{stats.kills}/{stats.rewarded}/{stats.rewards}/{stats.points}/{stats.owed}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "kills", label = "Wintertodt kills", value = stats.kills },
		{ id = "rewarded", label = "Kills with rewards", value = stats.rewarded, percent_of = "kills" },
		{ id = "rewards", label = "Rewards", value = stats.rewards, per = "kills" },
		{ id = "points", label = "Points", value = stats.points, per = "kills" },
		{ id = "owed", label = "Rewards owed at the cart", value = stats.owed, hourly = false },
	})
	Log.log(
		"Progress",
		`Kills: {stats.kills}, with rewards: {stats.rewarded}, rewards: {stats.rewards}, points: {stats.points}, owed: {stats.owed}`
	)
end

function Loop.goal_reached(): string?
	if CONFIG.max_kills > 0 and stats.kills >= CONFIG.max_kills then
		return `Reached {CONFIG.max_kills} kills`
	end
	if CONFIG.max_minutes > 0 and time() - S.started_at >= CONFIG.max_minutes * 60000 then
		return `Ran for {CONFIG.max_minutes} minutes`
	end
	if CONFIG.max_firemaking > 0 and (Stats.real_level("Firemaking") or 0) >= CONFIG.max_firemaking then
		return `Reached Firemaking level {CONFIG.max_firemaking}`
	end
	if time() - S.last_progress_at >= CONFIG.timeouts.idle_minutes * 60000 then
		return `No xp for {CONFIG.timeouts.idle_minutes} minutes`
	end
	return nil
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	S.last_progress_at += time() - S.antiban_began_at
end

function Loop.before_break()
	Loop.antiban_began()
	if Read.logged_in(game_state()) then
		Task.walk_to_hall()
	end
end

function Loop.hook_antiban()
	Antiban.on_start_task = function()
		S.hovering = false
		Loop.antiban_began()
	end
	Antiban.on_finish_task = Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.before_break, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.before_break, Loop.antiban_ended
end

function Loop.supply_state(): State
	local need_vials = Read.count(ITEMS.UNF) == 0
	local need_herbs = Read.count(ITEMS.HERB) < CONST.HERBS_NEEDED
	local low_space = Read.free() < CONST.SPACE_NEEDED
	local vials_first = Biometrics.random_boolean()
	if need_vials and (vials_first or not need_herbs) then
		return if low_space then "MAKE_SPACE" else "GET_VIALS"
	end
	return if low_space then "MAKE_SPACE" else "PICK_HERBS"
end

function Loop.common_state(): (State?, Tile?)
	local reason = Loop.goal_reached()
	if reason then
		Log.log(NAME, `{reason}, stopping the script`)
		return "STOP", nil
	end

	local s = game_state()
	if not Read.logged_in(s) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN", nil
	end
	Loop.watch_progress(s)
	Read.track_points()
	Read.read_chat()
	Loop.report_counters()
	if ChatOptions.leveled_up() then
		return "LEVEL_UP", nil
	end

	if S.picking then
		return "WAIT_PICKING", nil
	end
	if S.mixing then
		return "WAIT_MIXING", nil
	end

	local me = Read.me()
	if me == nil then
		return "LOADING", nil
	end
	if Read.outside(me) then
		return "ENTER_ROOM", nil
	end
	return nil, me
end

function Loop.get_state(): State
	local common, me = Loop.common_state()
	if common or me == nil then
		return common or "LOADING"
	end
	if Read.threat() then
		return "DODGE"
	end

	if Read.count(ITEMS.UNF) > 0 and Read.count(ITEMS.HERB) >= CONST.HERBS_NEEDED then
		return if S.has_herblore then "MIX_POTIONS" else "TALK_TO_BREWMA"
	end

	if Read.count(ITEMS.POTION) == 0 then
		return Loop.supply_state()
	end

	local warmth = Read.warmth()
	if warmth ~= nil and warmth <= S.min_warmth then
		return "WARM_UP"
	end

	local near_brazier = Read.near_brazier(me)

	if Read.boss_energy() == 0 then
		if S.warmth <= 50 then
			return "WARM_UP"
		end
		if Read.count(ITEMS.POTION) <= 2 then
			return Loop.supply_state()
		end
		if not near_brazier then
			return "WALK_BRAZIER"
		end
		if not S.hovering then
			return "HOVER_BRAZIER"
		end
		return "WAIT_BOSS"
	end

	if Read.count({ ITEMS.HERB, ITEMS.UNF }) > 0 then
		return "DROP_ITEMS"
	end

	local brazier = Read.brazier_state()
	if brazier == "BROKEN" or brazier == "UNLIT" then
		return "FIX_BRAZIER"
	end
	if brazier == "DEAD" then
		return if CONFIG.help_pyromancers then "HELP_PYRO" else "SWITCH_SIDES"
	end

	local waiting: State? = if S.cutting
		then "WAIT_CUTTING"
		elseif S.fletching then "WAIT_FLETCHING"
		elseif S.burning then "WAIT_BURNING"
		else nil
	if waiting then
		return if S.hovering then waiting else "HOVER_BRAZIER"
	end

	local has_root, has_kindling = Read.count(ITEMS.ROOT) > 0, Read.count(ITEMS.KINDLING) > 0
	if S.boss < Read.fuel(1.3) or Inventory.is_full() or has_kindling or near_brazier then
		if not near_brazier then
			return "WALK_BRAZIER"
		end
		if has_root and S.boss > CONFIG.stop_fletch_energy then
			return "FLETCH_LOGS"
		end
		if has_root or has_kindling then
			return "BURN_FUEL"
		end
	end

	if Read.distance(me, Read.spots().root_stand) > 0 then
		return "WALK_ROOT"
	end

	local spec_cost = if Read.axe_wielded() then SpecialAttack.cost() else nil
	if spec_cost ~= nil and not SpecialAttack.is_enabled() and (SpecialAttack.energy() or 0) >= spec_cost then
		return "USE_SPEC"
	end
	return "CUT_ROOTS"
end

function Read.breaks_brazier(spot: Host.SpotAnim): boolean
	for _, spots in pairs(CONST.SOLO.CORNERS) do
		if spots.brazier.x - 1 == spot.x and spots.brazier.y - 1 == spot.y then
			return spot.z <= spots.break_z + CONST.SOLO.SNOW.Z_SLACK
		end
	end
	return false
end

function Read.dangers(): { Danger }
	local snow = CONST.SOLO.SNOW
	local spots = SpotAnims.find({ snow.CENTRE, snow.CORNER }) or {}
	local dangers: { Danger } = {}
	for _, c in ipairs(spots) do
		if c.id == snow.CENTRE and c.cycle < c.start_cycle + snow.LANDED_CYCLES then
			local cornered = false
			for _, k in ipairs(spots) do
				local diagonal = math.abs(k.x - c.x) == 1 and math.abs(k.y - c.y) == 1
				if k.id == snow.CORNER and k.start_cycle == c.start_cycle and diagonal then
					cornered = true
					break
				end
			end
			if cornered then
				table.insert(dangers, { x = c.x, y = c.y, radius = snow.AREA })
			elseif Read.breaks_brazier(c) then
				table.insert(dangers, { x = c.x + 1, y = c.y + 1, radius = snow.BLAST })
			end
		end
	end
	return dangers
end

function Read.in_danger(at: Tile, dangers: { Danger }): boolean
	for _, d in ipairs(dangers) do
		if Read.distance(at, { x = d.x, y = d.y }) <= d.radius then
			return true
		end
	end
	return false
end

function Read.threat(): boolean
	local me = Read.me()
	return me ~= nil and Read.in_danger(me, Read.dangers())
end

function Read.lowest_potion(): string?
	for dose = 1, CONST.SOLO.DOSES_PER_POTION do
		local name = `Rejuvenation potion ({dose})`
		if Read.count(name) > 0 then
			return name
		end
	end
	return nil
end

function Read.surplus(): { Item.Item }
	if CONFIG.mode == "solo" then
		return { ITEMS.HERB, ITEMS.UNF }
	end
	return { ITEMS.HERB, ITEMS.UNF, ITEMS.POTION_1 }
end

function Read.herbs_wanted(): number
	return if CONFIG.mode == "solo" then Solo.missing_potions() else CONST.HERBS_NEEDED
end

function Read.vial_option(): string
	if CONFIG.mode == "group" then
		return CONST.VIAL_OPTION
	end
	local need = Solo.missing_potions() - Read.count(ITEMS.UNF)
	local vials = CONST.SOLO.VIALS
	for _, v in ipairs(vials) do
		if need >= v.count then
			return v.option
		end
	end
	return vials[#vials].option
end

function Read.others_here(): boolean
	local me = Players.me()
	for _, p in ipairs(Host.players() or {}) do
		if (me == nil or p.index ~= me.index) and not Read.outside({ x = p.x, y = p.y }) then
			return true
		end
	end
	return false
end

function Read.corner(corner: Corner): SideSpots
	return CONST.SOLO.CORNERS[corner]
end

function Read.needs_light(corner: Corner): boolean
	return Read.brazier_state(Read.corner(corner)) ~= "LIT"
end

function Solo.missing_potions(): number
	local per = CONST.SOLO.DOSES_PER_POTION
	return math.max(0, math.ceil((CONFIG.solo_potions * per - Read.doses()) / per))
end

function Solo.route(): { Corner }
	for _, climb in ipairs(Transports.allowed_climbs()) do
		if string.find(climb, CONST.SOLO.GAP, 1, true) then
			return CONST.SOLO.ROUTE_GAP
		end
	end
	return CONST.SOLO.ROUTE_AROUND
end

function Solo.nearest(me: Tile, corners: { Corner }, wanted: (Corner) -> boolean): Corner?
	local best, best_d = nil, math.huge
	for _, corner in ipairs(corners) do
		local d = Read.distance(me, Read.corner(corner).brazier)
		if d < best_d and wanted(corner) then
			best, best_d = corner, d
		end
	end
	return best
end

function Solo.supply_state(): State?
	local missing = Solo.missing_potions()
	if missing == 0 then
		return if Read.count(Read.surplus()) > 0 then "DROP_ITEMS" else nil
	end
	local need_vials = math.max(0, missing - Read.count(ITEMS.UNF))
	local need_herbs = math.max(0, missing - Read.count(ITEMS.HERB))
	if need_vials == 0 and need_herbs == 0 then
		return if S.has_herblore then "MIX_POTIONS" else "TALK_TO_BREWMA"
	end
	if Read.free() < need_vials + need_herbs then
		return "MAKE_SPACE"
	end
	return if need_vials > 0 then "GET_VIALS" else "PICK_HERBS"
end

function Solo.make_space(): boolean
	local missing = Solo.missing_potions()
	local wanted = math.max(0, missing - Read.count(ITEMS.UNF)) + math.max(0, missing - Read.count(ITEMS.HERB))
	local short = wanted - Read.free()
	local drop: { number } = {}
	for _, item in ipairs({ ITEMS.ROOT, ITEMS.KINDLING }) do
		for _, slot in ipairs(Inventory.indices_of(item) or {}) do
			if #drop >= short then
				break
			end
			table.insert(drop, slot)
		end
	end
	if #drop < short then
		error(`Not enough inventory space for {CONFIG.solo_potions} rejuvenation potions.`)
	end
	local ordered = Inventory.pattern(drop)
	return Inventory.shift_drop_slots(ordered)
end

function Solo.hop(): boolean
	if S.worlds == nil then
		if not WorldSwitcher.open(true) then
			return false
		end
		local worlds: { number } = {}
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.members and row.available and row.activity == "-" then
				table.insert(worlds, row.world)
			end
		end
		if #worlds == 0 then
			error("The world list has no plain members worlds to hop to.")
		end
		Log.log(NAME, `{#worlds} plain members worlds to hop between`)
		S.worlds = worlds
	end
	Log.log(NAME, "Someone else is in the Wintertodt room, hopping")
	Task.stop_actions(true)
	if not WorldSwitcher.random(S.worlds :: { number }) then
		return false
	end
	S.round, S.round_points, S.stale_points = new_round(), 0, nil
	return true
end

function Task.dodge(): boolean
	local me = Read.me()
	local dangers = Read.dangers()
	if me == nil or not Read.in_danger(me, dangers) then
		return true
	end
	local reach = CONST.SOLO.SNOW.REACH
	local anchor = Read.spots().brazier
	local ours = Read.blast_at(dangers, anchor)
	local best, best_cost = nil, math.huge
	for dx = -reach, reach do
		for dy = -reach, reach do
			local tile = { x = me.x + dx, y = me.y + dy }
			if not Read.in_danger(tile, dangers) then
				local path = Walker.path(tile, me)
				local last = path and path[#path]
				if path and last and last.x == tile.x and last.y == tile.y and #path <= reach + 1 then
					local cost = #path * 10 + Read.distance(tile, anchor)
					if cost < best_cost then
						best, best_cost = tile, cost
					end
				end
			end
		end
	end
	if best == nil then
		return false
	end
	Log.log(NAME, `Dodging to {best.x}, {best.y}`)
	Task.stop_actions(true)
	if not Walker.click_tile(best) then
		return false
	end
	local deadline = time() + 4 * TICK
	local safe = false
	while not safe and time() < deadline do
		local now = Read.me()
		safe = now ~= nil and not Read.in_danger(now, Read.dangers())
		if not safe then
			sleep(Random.int(60, 120))
		end
	end
	local relight = if CONFIG.mode == "solo" then Solo.keeps_lit() else true
	if not safe or not ours or not relight then
		return safe
	end
	local landed = time() + 6 * TICK
	while Read.blast_at(Read.dangers(), anchor) and time() < landed do
		sleep(Random.int(60, 120))
	end
	local state = Read.brazier_state()
	if state == "BROKEN" or state == "UNLIT" then
		return if CONFIG.mode == "solo" then Solo.light() else Task.click_brazier()
	end
	return true
end

function Read.blast_at(dangers: { Danger }, brazier: Tile): boolean
	for _, d in ipairs(dangers) do
		if d.radius == CONST.SOLO.SNOW.BLAST and d.x == brazier.x and d.y == brazier.y then
			return true
		end
	end
	return false
end

function Solo.keeps_lit(): boolean
	return S.round.ending or CONFIG.solo_goal == "xp" or S.boss > CONST.SOLO.LOW_ENERGY
end

function Wait.idle()
	local range = CONST.SOLO.IDLE_MS
	Wait.sleep(Random.int(range[1], range[2]))
end

function Solo.light_state(turn_back: boolean): State
	S.round.turn_back = turn_back
	if Read.brazier_state() == "DEAD" then
		return "HELP_PYRO"
	end
	return "FIX_BRAZIER"
end

function Solo.keep_walking(here: Tile, left: Corner?): boolean
	local r = S.round
	if left == nil or left == S.corner or time() - r.checked_at < CONST.SOLO.CHECK_MS then
		return true
	end
	r.checked_at = time()
	if not Read.needs_light(left) then
		return true
	end
	local back = Read.distance(here, Read.corner(left).brazier)
	if back < Read.distance(here, Read.spots().brazier) then
		Log.log(NAME, `The {left} brazier went out and is closer, turning back`)
		return false
	end
	return true
end

function Solo.light(): boolean
	local left = if S.round.turn_back then S.round.at else nil
	local ok = Task.click_brazier(function(here: Tile): boolean
		return Solo.keep_walking(here, left)
	end)
	if ok then
		S.round.at = S.corner
	end
	return ok
end

function Solo.work_state(me: Tile, can_feed: boolean): State
	if S.cutting then
		return "WAIT_CUTTING"
	end
	if S.fletching then
		return "WAIT_FLETCHING"
	end
	if S.burning then
		return "WAIT_BURNING"
	end
	local roots, kindling = Read.count(ITEMS.ROOT), Read.count(ITEMS.KINDLING)
	local near = Read.near_brazier(me)
	if roots + kindling > 0 and (Inventory.is_full() or near or roots == 0) then
		if CONFIG.solo_goal == "points" and roots > 0 then
			return if near then "FLETCH_LOGS" else "WALK_BRAZIER"
		end
		return if can_feed then "BURN_FUEL" else "SOLO_IDLE"
	end
	return "CUT_ROOTS"
end

function Solo.focus_state(me: Tile, light: boolean): State
	local state = Read.brazier_state()
	if state == "DEAD" then
		return "HELP_PYRO"
	end
	if light and (state == "BROKEN" or state == "UNLIT") then
		return Solo.light_state(false)
	end
	return Solo.work_state(me, state == "LIT")
end

function Solo.next_to_open(): Corner?
	local r = S.round
	for _, corner in ipairs(Solo.route()) do
		if not r.lit[corner] then
			if Read.brazier_state(Read.corner(corner)) ~= "LIT" then
				return corner
			end
			r.lit[corner] = true
		end
	end
	return nil
end

function Solo.visit_due(): Corner?
	local r = S.round
	local route = Solo.route()
	for i = #route, 1, -1 do
		local corner = route[i]
		if corner ~= CONST.SOLO.FOCUS and time() - (r.visited[corner] or 0) > r.visit_every then
			return corner
		end
	end
	return nil
end

function Solo.visit_state(me: Tile, corner: Corner): State
	S.corner = corner
	local spots = Read.spots()
	local pyro = Read.pyromancer()
	if pyro == nil or Read.distance(me, spots.pyromancer) > CONST.FIND_RANGE + 2 then
		return "WALK_BRAZIER"
	end
	if Read.incapacitated(pyro) then
		return "HELP_PYRO"
	end
	S.round.visited[corner] = time()
	S.corner = CONST.SOLO.FOCUS
	return "SOLO_IDLE"
end

function Solo.low_state(me: Tile): State
	S.corner = CONST.SOLO.FOCUS
	if Read.brazier_state() == "DEAD" then
		return "HELP_PYRO"
	end
	if S.cutting then
		return "WAIT_CUTTING"
	end
	if S.fletching then
		return "WAIT_FLETCHING"
	end
	if not Inventory.is_full() then
		return "CUT_ROOTS"
	end
	if Read.count(ITEMS.ROOT) > 0 then
		return "FLETCH_LOGS"
	end
	local due = Solo.visit_due()
	if due then
		return Solo.visit_state(me, due)
	end
	if not Read.near_brazier(me) then
		return "WALK_BRAZIER"
	end
	return "SOLO_IDLE"
end

function Solo.end_state(me: Tile): State
	S.corner = S.round.end_corner
	return Solo.focus_state(me, true)
end

function Solo.between_rounds(me: Tile): State
	if S.round.started then
		S.round = new_round()
	end
	if S.warmth <= 50 and Read.doses() > 0 then
		return "WARM_UP"
	end
	S.corner = Solo.route()[1]
	if not Read.near_brazier(me) then
		return "WALK_BRAZIER"
	end
	if not S.hovering then
		return "HOVER_BRAZIER"
	end
	return "WAIT_BOSS"
end

function Solo.round_state(me: Tile, energy: number): State
	local r = S.round
	r.started = true
	if not r.ending and CONFIG.solo_goal == "points" and S.round_points >= CONFIG.solo_points + r.points_bonus then
		r.ending = true
		r.end_corner = Solo.nearest(me, CONST.SOLO.END_CORNERS, function()
			return true
		end) or CONST.SOLO.FOCUS
		Log.log(NAME, `{S.round_points} points, ending the round at the {r.end_corner} brazier`)
	end
	if r.ending then
		return Solo.end_state(me)
	end
	if not r.opened then
		local corner = Solo.next_to_open()
		if corner then
			S.corner = corner
			return Solo.light_state(false)
		end
		r.opened = true
		Log.log(NAME, "All four braziers lit")
	end
	if energy > r.open_until then
		local all: { Corner } = { "sw", "se", "nw", "ne" }
		local out = Solo.nearest(me, all, Read.needs_light)
		if out then
			S.corner = out
			return Solo.light_state(true)
		end
	end
	S.corner = CONST.SOLO.FOCUS
	if CONFIG.solo_goal == "xp" or energy > CONST.SOLO.LOW_ENERGY then
		return Solo.focus_state(me, true)
	end
	return Solo.low_state(me)
end

function Solo.get_state(): State
	local common, me = Loop.common_state()
	if common or me == nil then
		return common or "LOADING"
	end
	if Read.others_here() and S.round_points < CONST.SOLO.REWARD_POINTS then
		return "HOP_WORLD"
	end
	if Read.threat() then
		return "DODGE"
	end
	local doses = Read.doses()
	local warmth = Read.warmth()
	if warmth ~= nil and warmth <= S.min_warmth and doses > 0 then
		return "WARM_UP"
	end
	local energy = Read.boss_energy()
	if doses == 0 or energy == 0 then
		local supply = Solo.supply_state()
		if supply then
			return supply
		end
	end
	if energy == 0 then
		return Solo.between_rounds(me)
	end
	return Solo.round_state(me, energy)
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = Game.sign_in,
	LEVEL_UP = function()
		ChatOptions.handle_level_up()
	end,
	ENTER_ROOM = Task.enter_room,
	WAIT_BOSS = Wait.boss,
	WAIT_PICKING = Wait.picking,
	WAIT_MIXING = Wait.mixing,
	WAIT_CUTTING = Wait.cutting,
	WAIT_FLETCHING = Wait.fletching,
	WAIT_BURNING = Wait.burning,
	SWITCH_SIDES = Task.switch_sides,
	DROP_ITEMS = function()
		Task.drop_items(Read.surplus())
	end,
	MAKE_SPACE = function()
		if CONFIG.mode == "solo" then
			Solo.make_space()
		else
			Task.drop_items(Read.surplus())
		end
	end,
	PICK_HERBS = function()
		Task.pick_herbs(Read.herbs_wanted())
	end,
	GET_VIALS = function()
		Task.get_vials(Read.vial_option())
	end,
	MIX_POTIONS = Task.mix_potions,
	TALK_TO_BREWMA = Task.talk_to_brewma,
	CUT_ROOTS = Task.cut_roots,
	FLETCH_LOGS = Task.fletch_logs,
	BURN_FUEL = Task.burn_fuel,
	USE_SPEC = function()
		SpecialAttack.enable()
	end,
	WARM_UP = Task.warm_up,
	HOVER_BRAZIER = Task.hover_brazier,
	FIX_BRAZIER = function()
		if CONFIG.mode == "solo" then
			Solo.light()
		else
			Task.click_brazier()
		end
	end,
	HELP_PYRO = Task.help_pyromancer,
	HOP_WORLD = Solo.hop,
	DODGE = Task.dodge,
	SOLO_IDLE = Wait.idle,
	WALK_ROOT = function()
		Task.walk(Read.spots().root_stand, 0)
	end,
	WALK_BRAZIER = function()
		local stand = Read.spots().stand
		Task.walk(stand[Random.int(1, #stand)], 1)
	end,
	STOP = function()
		S.finished = true
	end,
}

local GROUP_ONLY = { id = "mode", equals = "Group" }
local SOLO_ONLY = { id = "mode", equals = "Solo" }

local function integer_field(
	id: string,
	label: string,
	default: number,
	min: number,
	max: number,
	visible_when: any?
): any
	return {
		id = id,
		kind = "number",
		label = label,
		default = default,
		min = min,
		max = max,
		integer = true,
		box_first = true,
		visible_when = visible_when,
	}
end

function Game.apply_settings(values: { [string]: any })
	CONFIG.mode = if values.mode == "Solo" then "solo" else "group"
	CONFIG.solo_goal = if values.solo_goal == "Experience" then "xp" else "points"
	CONFIG.solo_potions = values.solo_potions
	CONFIG.solo_points = values.solo_points
	CONFIG.side = if values.side == "East" then "east" else "west"
	CONFIG.alternate = values.alternate == true
	CONFIG.prioritize_brazier = values.prioritize_brazier == true
	CONFIG.help_pyromancers = values.help_pyromancers == true
	CONFIG.wintertodt_worlds = values.wintertodt_worlds == true
	CONFIG.stop_fletch_energy = values.stop_fletch_energy
	CONFIG.max_kills = values.max_kills
	CONFIG.max_minutes = values.max_minutes
	CONFIG.max_firemaking = values.max_firemaking
end

function Game.ask(): boolean
	local values = Host.form({
		title = "Wintertodt",
		submit = "Start",
		fields = {
			{ id = "mode", kind = "choice", label = "Mode", options = { "Group", "Solo" }, default = "Group" },
			{
				id = "side",
				kind = "choice",
				label = "Favorite side",
				options = { "West", "East" },
				default = "West",
				visible_when = GROUP_ONLY,
			},
			{
				id = "alternate",
				kind = "check",
				label = "Alternate sides as antiban",
				default = CONFIG.alternate,
				visible_when = GROUP_ONLY,
			},
			{
				id = "prioritize_brazier",
				kind = "check",
				label = "Prioritize lighting and fixing the brazier",
				default = CONFIG.prioritize_brazier,
				visible_when = GROUP_ONLY,
			},
			{
				id = "help_pyromancers",
				kind = "check",
				label = "Help pyromancers",
				default = CONFIG.help_pyromancers,
				visible_when = GROUP_ONLY,
			},
			{
				id = "wintertodt_worlds",
				kind = "check",
				label = "Wintertodt worlds only",
				default = CONFIG.wintertodt_worlds,
				visible_when = GROUP_ONLY,
			},
			integer_field(
				"stop_fletch_energy",
				"Stop fletching at Wintertodt energy",
				CONFIG.stop_fletch_energy,
				0,
				100,
				GROUP_ONLY
			),
			{
				id = "solo_goal",
				kind = "choice",
				label = "Goal",
				options = { "Points", "Experience" },
				default = "Points",
				visible_when = SOLO_ONLY,
			},
			integer_field("solo_potions", "Rejuvenation potions to keep", CONFIG.solo_potions, 1, 20, SOLO_ONLY),
			integer_field(
				"solo_points",
				"Points before ending a round",
				CONFIG.solo_points,
				CONST.SOLO.REWARD_POINTS,
				100000,
				{ SOLO_ONLY, { id = "solo_goal", equals = "Points" } }
			),
			{ kind = "label", text = "Stop conditions", heading = 2 },
			integer_field("max_kills", "Maximum kills (0 for no limit)", CONFIG.max_kills, 0, 100000),
			integer_field("max_minutes", "Maximum minutes (0 for no limit)", CONFIG.max_minutes, 0, 100000),
			integer_field("max_firemaking", "Stop at Firemaking level (0 for never)", CONFIG.max_firemaking, 0, 99),
		},
	})
	if values == nil then
		return false
	end
	Game.apply_settings(values)
	return true
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		local mode = CONFIG.mode
		Game.apply_settings(values)
		if CONFIG.mode ~= mode then
			CONFIG.mode = mode
			Log.warn(NAME, "The mode changes on the next start")
		end
		Log.log(NAME, "Settings updated")
	end
end

local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.play(get_state: () -> State)
	local last_state: State? = nil
	while not S.finished do
		Game.poll_settings()
		local state = get_state()
		if state ~= last_state then
			Log.log(NAME, state)
			last_state = state
		end
		close_stray()
		Handler.states[state]()
		local dodging = Read.threat()
		if CONFIG.antiban and S.antiban_ready and not S.finished and not dodging then
			local waiting = state == "WAIT_BOSS" or state == "SOLO_IDLE"
			Antiban.do_antiban(true, waiting, waiting)
			if S.boss == 0 then
				Antiban.do_async_tasks("outside")
			elseif CONST.ACTIVITY_WAITS[state] and Biometrics.random_boolean(CONST.TINY_ANTIBAN_CHANCE) then
				Antiban.do_async_tasks("game")
			end
		end
	end
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	Log.log(NAME, `{NAME} started`)
	S.started_at = time()
	Read.skip_old_chat()
	Game.setup()
	S.last_progress_at = time()
	Loop.hook_antiban()

	Loop.play(if CONFIG.mode == "solo" then Solo.get_state else Loop.get_state)

	if Read.logged_in(game_state()) then
		Task.walk_to_hall()
	end
	Log.log(NAME, "Done")
end

Loop.run()
