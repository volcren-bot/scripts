--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local Biometrics = require("@volcren/biometrics")
local ChatTabs = require("@volcren/chat_tabs")
local DebugDraw = require("@volcren/debug_draw")
local Diaries = require("@volcren/diaries")
local Draw = require("@volcren/draw")
local EquipmentLayout = require("@volcren/equipment_layout")
local GameState = require("@volcren/game_state")
local Handoff = require("@volcren/handoff")
local Inventory = require("@volcren/inventory")
local InventoryLayout = require("@volcren/inventory_layout")
local ItemData = require("@volcren/item_data")
local Journal = require("@volcren/journal")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Magic = require("@volcren/magic")
local Mouse = require("@volcren/mouse")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Position = require("@volcren/position")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Walker = require("@volcren/walker")

local NAME = "Varlamore Thieving"

local houses = false
local houses_only = false
local max_pouches: number? = nil

type Tile = { x: number, y: number }
type House = {
	name: string,
	owner: number,
	door: Tile,
	outside: Tile,
	window: Tile,
	searchables: { Tile },
}

local HOUSES: { House } = {
	{
		name = "Lavinia",
		owner = 13312,
		door = { x = 1668, y = 3094 },
		outside = { x = 1668, y = 3095 },
		window = { x = 1670, y = 3088 },
		searchables = { { x = 1666, y = 3093 }, { x = 1669, y = 3089 }, { x = 1675, y = 3088 }, { x = 1676, y = 3091 } },
	},
	{
		name = "Victor",
		owner = 13313,
		door = { x = 1636, y = 3103 },
		outside = { x = 1636, y = 3104 },
		window = { x = 1637, y = 3094 },
		searchables = { { x = 1631, y = 3101 }, { x = 1633, y = 3103 }, { x = 1635, y = 3099 }, { x = 1640, y = 3094 } },
	},
	{
		name = "Caius",
		owner = 13314,
		door = { x = 1631, y = 3121 },
		outside = { x = 1630, y = 3121 },
		window = { x = 1638, y = 3124 },
		searchables = { { x = 1632, y = 3117 }, { x = 1635, y = 3124 }, { x = 1636, y = 3123 }, { x = 1640, y = 3122 } },
	},
}

local CONST = {
	REPORT = { counters_key = "" },
	QUEST = "Children of the Sun",
	MODE_HOUSES = "Pickpocket + Houses",
	MODE_HOUSES_ONLY = "Houses",
	MAPSQUARE = { THIEVING = 6704, BANK = 6448 },
	TILE = {
		THIEVING = { x = 1679, y = 3106 },
		BANK = { x = 1647, y = 3117 },
		SPOT = { x = 1681, y = 3106 },
		HOUSE_WAIT = { x = 1652, y = 3106 },
	},
	HOUSE_WAIT_RADIUS = 4,
	SPOT_RADIUS = 7,
	SPOT_PICKS = 20,
	PLANE = { GROUND = 0 },
	CITIZEN = "Wealthy citizen",
	DISTRACTORS = { Leo = true, Julia = true, Aurelia = true },
	NO_ANIMATION = -1,
	DISTRACTED_HOLD_MS = 3000,
	COIN_POUCH = "Coin pouch",
	POUCH_DIARY = "Ardougne",
	POUCH_LIMITS = { { tier = "elite", limit = 140 }, { tier = "hard", limit = 84 }, { tier = "medium", limit = 56 } },
	POUCH_LIMIT_BASE = 28,
	POUCH_ROOM = 18,
	OPEN_POUCHES_OPTION = "Open-all",
	OPEN_POUCHES_TIMEOUT_MS = 3000,
	PICKPOCKET_OPTION = "Pickpocket",
	HALF_TICK_MS = 300,
	ROUND_START_GRACE_MS = 3000,
	ROUND_END_IDLE_MS = 6000,
	DEBUG_THICK_PX = 4,
	PANEL_RETURN_MS = { MIN = 1000, MAX = 5000 },
	CHAT_TAB = "game",
	DEBUG_LAYER = "citizens",
	HOUSE_LAYER = "houses",
	HOUSE_KEYS = "House keys",
	VALUABLES = "Valuables",
	CHISEL = "Chisel",
	NATURE_RUNE = "Nature rune",
	LOCKED_DOOR = 51998,
	WINDOW = 52998,
	OPEN_OPTION = "Open",
	SEARCH_OPTION = "Search",
	EXIT_OPTION = "Exit",
	BREAK_OPTION = "Break-down",
	HINT_PACKET_LENGTH = 6,
	MAX_OPCODE = 255,
	HIGH_ALCH = "High Level Alchemy",
	OWNER_CLEAR_TILES = 5,
	HOUSE_OPEN_MS = 150000,
	ENTER_TIMEOUT_MS = 8000,
	EXIT_TIMEOUT_MS = 6000,
	SEARCH_IDLE_MS = 3000,
	ENTER_PAUSE_MS = { MIN = 400, MAX = 1100 },
	LOOT_TIMEOUT_MS = 3000,
	LOOT_PER_WALK = 3,
	CLOSE_IN_TILES = 3,
	DOOR_REACH = 3,
	INPUT_IDLE_MS = 2000,
	INPUT_POLL_MS = 50,
	LOOT_ALCH = "alch",
	LOOT_DROP = "drop",
	LOOT_VERBS = {
		alch = { done = "Alched", try = "alch" },
		["break"] = { done = "Broke down", try = "break down" },
		drop = { done = "Dropped", try = "drop" },
	},
	BANK_AT_SLOTS = { MIN = 14, MAX = 20 },
	MESSAGE = {
		COMING_BACK = "spot the homeowner coming back",
		EMPTY = "can't spot anything else worth taking",
		OWNER_NEAR = "owner is still near the door",
		ESCORTED = "escorted out of the house",
		FULL = "need at least one free inventory space",
	},
	STATUETTES = { 29338, 29340, 29342 },
	JEWELLERY = {
		"Gold necklace",
		"Gold amulet",
		"Gold ring",
		"Sapphire amulet",
		"Sapphire necklace",
		"Sapphire ring",
		"Emerald amulet",
		"Emerald necklace",
		"Emerald ring",
		"Ruby amulet",
		"Ruby necklace",
		"Ruby ring",
		"Diamond amulet",
		"Diamond necklace",
		"Diamond ring",
	},
	SHARDS = "Blessed bone shards",
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	equipment = nil :: EquipmentLayout.Layout?,
	inventory = nil :: InventoryLayout.Layout?,
	keys = { min = 30, max = 50 },
	jewellery = {} :: { [string]: string },
	max_runs = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
}

local stats = { runs = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	skip: { [string]: boolean },
	pickpocketing: boolean,
	clicked_at: number,
	pickpocket_seen_at: number?,
	away_since: { [string]: number },
	return_after: { [string]: number },
	distracted_at: { [number]: number },
	debug_drawn: boolean,
	last_pouches: number?,
	phase: "pickpocket" | "houses",
	key_target: number,
	last_chat_uid: number,
	open_since: { [string]: number },
	burgled: { [string]: boolean },
	inside: string?,
	leaving: boolean,
	searching: Tile?,
	searched_before: Tile?,
	search_idle_since: number,
	emptied: { [string]: boolean },
	close_in: { [string]: boolean },
	awkward: { [string]: boolean },
	houses_done: number,
	houses_drawn: boolean,
	prices_missing_logged: boolean,
	was_inside: boolean,
	window_failed: boolean,
	window_unread_logged: boolean,
	bank_at: number,
	hint_opcode: number?,
	hint_listener: number?,
	arrow: Tile?,
}

function Game.apply_settings(values: { [string]: any })
	houses = values.mode == CONST.MODE_HOUSES or values.mode == CONST.MODE_HOUSES_ONLY
	houses_only = values.mode == CONST.MODE_HOUSES_ONLY
	CONFIG.equipment = values.equipment
	CONFIG.inventory = values.inventory
	CONFIG.keys.min = values.keys_min or CONFIG.keys.min
	CONFIG.jewellery = values.jewellery or CONFIG.jewellery
	CONFIG.keys.max = values.keys_max or CONFIG.keys.max
	CONFIG.max_runs = values.max_runs or CONFIG.max_runs
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	skip = {},
	pickpocketing = false,
	clicked_at = -math.huge,
	pickpocket_seen_at = nil,
	away_since = {},
	return_after = {},
	distracted_at = {},
	debug_drawn = false,
	last_pouches = nil,
	phase = "pickpocket",
	key_target = 0,
	last_chat_uid = 0,
	open_since = {},
	burgled = {},
	inside = nil,
	leaving = false,
	searching = nil,
	searched_before = nil,
	search_idle_since = 0,
	emptied = {},
	close_in = {},
	awkward = {},
	houses_done = 0,
	houses_drawn = false,
	prices_missing_logged = false,
	was_inside = false,
	window_failed = false,
	window_unread_logged = false,
	bank_at = CONST.BANK_AT_SLOTS.MAX,
	hint_opcode = nil,
	hint_listener = nil,
	arrow = nil,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	pouches: number,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "WAIT"
	| "OPEN_INVENTORY"
	| "OPEN_CHAT_TAB"
	| "OPEN_POUCHES"
	| "PICKPOCKET"
	| "PICKPOCKETING"
	| "WALK_TO_HOUSE"
	| "WAIT_OWNER"
	| "ENTER_HOUSE"
	| "SEARCH"
	| "SEARCHING"
	| "LEAVE_HOUSE"
	| "LOOT"
	| "BANK"
	| "WALK_TO_SPOT"
	| "WALK_TO_WAIT"

type Citizen = { npc: Host.Npc, distracted: boolean }

type LootAction = { kind: "alch" | "break" | "drop", item: number }

type Plan = {
	citizens: { Citizen },
	distractors: { Host.Npc },
	target: Host.Npc?,
	locs: { [string]: Host.Loc }?,
	house: House?,
	object: Tile?,
	loot: LootAction?,
}

local plan: Plan = { citizens = {}, distractors = {} }

local report = StatsReport.new()

function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.mapsquare(state: ClientState): number?
	local p = state.position
	if p == nil then
		return nil
	end
	return Position.new(p.local_x, p.local_y, p.x, p.y, p.plane):chunk():id()
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	snap = {
		state = state,
		tick = Read.current_tick(state),
		pouches = Inventory.count_ex(CONST.COIN_POUCH) or 0,
	}
	return true
end

function Read.max_pouches(): number
	if max_pouches then
		return max_pouches
	end
	local limit = CONST.POUCH_LIMIT_BASE
	for _, step in CONST.POUCH_LIMITS do
		local done = Diaries.tier(CONST.POUCH_DIARY, step.tier)
		if done == nil then
			error(`Couldn't read the {CONST.POUCH_DIARY} diary`, 0)
		end
		if done then
			limit = step.limit
			break
		end
	end
	max_pouches = limit
	return limit
end

function Read.citizens(now: number): ({ Citizen }, { Host.Npc })
	local npcs = Npcs.find() or {}
	local by_index: { [number]: Host.Npc } = {}
	for _, npc in npcs do
		by_index[npc.index] = npc
	end
	local citizens: { Citizen } = {}
	local distractors: { Host.Npc } = {}
	for _, npc in npcs do
		if CONST.DISTRACTORS[npc.name] then
			table.insert(distractors, npc)
		elseif npc.name == CONST.CITIZEN then
			local target = by_index[npc.interacting_npc]
			local watching = target ~= nil and CONST.DISTRACTORS[target.name] == true
			if watching and npc.animation ~= CONST.NO_ANIMATION then
				S.distracted_at[npc.index] = now
			end
			local since = now - (S.distracted_at[npc.index] or -math.huge)
			table.insert(citizens, { npc = npc, distracted = watching and since < CONST.DISTRACTED_HOLD_MS })
		end
	end
	return citizens, distractors
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

	AntibanTasks.skills = { "Total" }
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

function Game.check_requirements()
	if not Journal.is_quest_complete(CONST.QUEST) then
		error(`{CONST.QUEST} isn't complete`, 0)
	end
end

function Game.walk_to(mapsquare: number, tile: { x: number, y: number }, place: string)
	local state = game_state()
	local p = state.position
	if p and p.plane == CONST.PLANE.GROUND and Read.mapsquare(state) == mapsquare then
		return
	end
	Log.log(NAME, `Walking to the {place}`)
	if not Walker.walk(tile, { plane = CONST.PLANE.GROUND, near = 3 }) then
		error(`Couldn't walk to the {place}`, 0)
	end
end

function Game.open_bank()
	Game.walk_to(CONST.MAPSQUARE.BANK, CONST.TILE.BANK, "bank")
	if not Bankmain.open() then
		error("Couldn't open the bank", 0)
	end
end

function Game.restock(inventory: InventoryLayout.Layout): boolean
	for _, entry in InventoryLayout.entries(inventory) do
		if entry.stackable then
			local have = Inventory.count_ex(entry.items) or 0
			if have < math.max(entry.min, 1) then
				local amount = if entry.max > 0 then entry.max - have else 0
				if not Bankmain.withdraw(entry.items, amount, false) then
					return false
				end
			end
		else
			local missing = entry.copies - (Inventory.count(entry.items) or 0)
			if missing > 0 and not Bankmain.withdraw(entry.items, missing, false) then
				return false
			end
		end
	end
	return InventoryLayout.matches(inventory) == true
end

function Game.prepare_layouts()
	local equipment, inventory = CONFIG.equipment, CONFIG.inventory
	local dress = equipment ~= nil and EquipmentLayout.matches(equipment) == false
	local pack = inventory ~= nil and InventoryLayout.matches(inventory) == false
	if not dress and not pack then
		return
	end
	Log.log(NAME, "Getting the layouts from the bank")
	Game.open_bank()
	if equipment and not EquipmentLayout.prepare(equipment) then
		error("Couldn't put on the equipment layout", 0)
	end
	if inventory then
		if not Bankmain.is_open() then
			Game.open_bank()
		end
		if not Game.restock(inventory) then
			error("The bank is missing items for the inventory layout", 0)
		end
	end
	if Bankmain.is_open() then
		Bankmain.close()
	end
end

function Read.tile_near(c: Tile, r: number): Tile?
	for _ = 1, CONST.SPOT_PICKS do
		local tile = Random.tile_in_box(c.x - r, c.y - r, c.x + r, c.y + r)
		local route = Walker.route(tile)
		if route and route.reached then
			return tile
		end
	end
	return nil
end

function Game.adopt_round()
	local animation = Player.animation()
	if animation == nil or animation == CONST.NO_ANIMATION then
		return
	end
	Log.log(NAME, "Already pickpocketing, waiting for the round to end")
	S.pickpocketing, S.clicked_at, S.pickpocket_seen_at = true, time(), time()
end

function Game.step_next_to(loc: Host.Loc)
	local me = Walker.position()
	if me == nil then
		return
	end
	local best: Tile? = nil
	local best_distance = math.huge
	for _, stand in Objects.stand_tiles(loc) or {} do
		local d = Walker.distance(stand, me)
		if d < best_distance then
			best, best_distance = stand, d
		end
	end
	if best and best_distance > 0 then
		Walker.walk(best, { plane = CONST.PLANE.GROUND, near = 0 })
	end
end

function Game.walk_near(center: Tile, radius: number, place: string)
	local me = Walker.here()
	if me and me.plane == CONST.PLANE.GROUND and Walker.distance(me, center) <= radius then
		return
	end
	local tile = Read.tile_near(center, radius)
	if tile == nil then
		error(`No reachable tile near the {place}`, 0)
	end
	Log.log(NAME, `Walking to {tile.x}, {tile.y}`)
	Game.loot_while_walking(tile)
	if not Walker.walk(tile, { plane = CONST.PLANE.GROUND, near = 0 }) then
		error(`Couldn't walk to the {place}`, 0)
	end
end

function Game.walk_to_spot()
	Game.walk_near(CONST.TILE.SPOT, CONST.SPOT_RADIUS, "thieving spot")
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	Game.check_requirements()
	Log.log(NAME, `Coin pouch limit: {Read.max_pouches()}`)
	if not S.antiban_ready then
		Game.setup_antiban()
	end
	Read.roll_key_target()
	Read.roll_bank_at()
	if houses then
		Game.listen_for_hints()
	end
	if not Read.inside_any() then
		local pickpocketing = not houses or (not houses_only and Read.keys() < S.key_target)
		if pickpocketing then
			Game.walk_to(CONST.MAPSQUARE.THIEVING, CONST.TILE.THIEVING, "thieving area")
		end
		Game.prepare_layouts()
		if pickpocketing then
			Game.walk_to_spot()
		end
		Game.adopt_round()
	end
	Read.skip_old_messages()
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
	local key = `{stats.runs}/{stats.failures}/{S.houses_done}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "runs", label = "Runs", value = stats.runs },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "runs" },
		{ id = "houses", label = "Houses", value = S.houses_done },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_runs > 0 and stats.runs >= CONFIG.max_runs then
		Log.log(NAME, `Reached {CONFIG.max_runs} runs, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.blocked = reason
		S.finished = true
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

function Loop.draw_citizens()
	if not DebugDraw.on() then
		if S.debug_drawn then
			DebugDraw.set(CONST.DEBUG_LAYER, nil)
			S.debug_drawn = false
		end
		return
	end
	local plain: { Host.Tile } = {}
	local thick: { { tile: Host.Tile, color: Draw.Color } } = {}
	for _, npc in plan.distractors do
		table.insert(thick, { tile = { x = npc.x, y = npc.y }, color = Draw.CYAN })
	end
	for _, c in plan.citizens do
		local tile = { x = c.npc.x, y = c.npc.y }
		if c.distracted then
			table.insert(thick, { tile = tile, color = Draw.GREEN })
		else
			table.insert(plain, tile)
		end
	end
	DebugDraw.set(CONST.DEBUG_LAYER, function()
		for _, tile in plain do
			DebugDraw.outline({ tile }, Draw.YELLOW)
		end
		for _, mark in thick do
			DebugDraw.outline({ mark.tile }, mark.color, CONST.DEBUG_THICK_PX)
		end
	end)
	S.debug_drawn = true
end

function Game.fail(why: string)
	Log.log(NAME, why)
	stats.failures += 1
	S.failures_in_row += 1
end

function Loop.draw_houses()
	if not DebugDraw.on() then
		if S.houses_drawn then
			DebugDraw.set(CONST.HOUSE_LAYER, nil)
			S.houses_drawn = false
		end
		return
	end
	local marks: { { tile: Tile, color: Draw.Color } } = {}
	for _, house in HOUSES do
		if Read.door_locked(house) then
			table.insert(marks, { tile = house.door, color = Draw.GREEN })
			table.insert(marks, { tile = house.window, color = Draw.CYAN })
			for _, tile in house.searchables do
				local shining = S.arrow ~= nil and Read.key(S.arrow :: Tile) == Read.key(tile)
				local color = if shining then Draw.GREEN elseif S.emptied[Read.key(tile)] then Draw.RED else Draw.YELLOW
				table.insert(marks, { tile = tile, color = color })
			end
		end
		local owner = Read.owner(house)
		if owner then
			table.insert(marks, { tile = { x = owner.x, y = owner.y }, color = Draw.MAGENTA })
		end
	end
	DebugDraw.set(CONST.HOUSE_LAYER, function()
		for _, mark in marks do
			DebugDraw.outline({ mark.tile }, mark.color, CONST.DEBUG_THICK_PX)
		end
	end)
	S.houses_drawn = true
end

function Read.round_over(now: number): boolean
	local animation = Player.animation()
	if animation and animation ~= CONST.NO_ANIMATION then
		S.pickpocket_seen_at = now
	end
	local seen = S.pickpocket_seen_at
	if seen == nil then
		return now - S.clicked_at >= CONST.ROUND_START_GRACE_MS
	end
	return now - seen >= CONST.ROUND_END_IDLE_MS
end

function Read.nearest_distracted(): Host.Npc?
	local me = snap.state.position :: Host.PositionData
	local best: Host.Npc? = nil
	local best_distance = math.huge
	for _, c in plan.citizens do
		local d = Walker.distance(c.npc, me)
		if c.distracted and d < best_distance then
			best, best_distance = c.npc, d
		end
	end
	return best
end

function Read.return_due(panel: string, open: boolean, now: number): boolean
	if open then
		S.away_since[panel] = nil
		return false
	end
	local since = S.away_since[panel]
	if since == nil then
		S.away_since[panel] = now
		S.return_after[panel] = Random.int(CONST.PANEL_RETURN_MS.MIN, CONST.PANEL_RETURN_MS.MAX)
		return false
	end
	return now - since >= S.return_after[panel]
end

function Loop.panel_state(now: number): State?
	if Read.return_due("inventory", Inventory.is_open(), now) then
		return "OPEN_INVENTORY"
	end
	if Read.return_due("chat", ChatTabs.is_active(CONST.CHAT_TAB), now) then
		return "OPEN_CHAT_TAB"
	end
	return nil
end

function Loop.pickpocket_state(skipped: { [string]: boolean }): State
	plan.citizens, plan.distractors = Read.citizens(time())
	Loop.draw_citizens()
	if snap.pouches ~= S.last_pouches then
		S.last_pouches = snap.pouches
		Log.log(NAME, `Coin pouches: {snap.pouches}/{Read.max_pouches()}`)
	end
	local now = time()
	if S.pickpocketing then
		if not Read.round_over(now) then
			return "PICKPOCKETING"
		end
		if S.pickpocket_seen_at then
			Log.log(NAME, "Stopped pickpocketing")
		else
			Log.log(NAME, "The pickpocket didn't start")
			stats.failures += 1
			S.failures_in_row += 1
		end
		S.pickpocketing = false
		S.distracted_at = {}
	end
	if snap.pouches > Read.max_pouches() - CONST.POUCH_ROOM then
		return "OPEN_POUCHES"
	end
	plan.target = Read.nearest_distracted()
	if plan.target then
		return "PICKPOCKET"
	end
	local panel = Loop.panel_state(now)
	if panel then
		return panel
	end
	if skipped["WAIT"] then
		return "LOADING"
	end
	return "WAIT"
end

function Read.key(t: Tile): string
	return `{t.x},{t.y}`
end

function Read.keys(): number
	return Inventory.count_ex(CONST.HOUSE_KEYS) or 0
end

function Read.roll_bank_at()
	S.bank_at = Random.int(CONST.BANK_AT_SLOTS.MIN, CONST.BANK_AT_SLOTS.MAX)
end

function Read.roll_key_target()
	S.key_target = Random.int(CONFIG.keys.min, CONFIG.keys.max)
	Log.log(NAME, `Next house trip at {S.key_target} house keys`)
end

function Read.loc_at(tile: Tile): Host.Loc?
	local locs = plan.locs
	if locs == nil then
		local found: { [string]: Host.Loc } = {}
		for _, loc in Host.locs(CONST.PLANE.GROUND) or {} do
			if loc.clickable then
				found[Read.key(loc)] = loc
			end
		end
		plan.locs, locs = found, found
	end
	return (locs :: { [string]: Host.Loc })[Read.key(tile)]
end

function Read.door_locked(house: House): boolean
	local loc = Read.loc_at(house.door)
	return loc ~= nil and loc.id == CONST.LOCKED_DOOR
end

function Read.inside_any(): boolean
	local views = Host.loc_shown({ CONST.WINDOW })
	local view = views and views[1]
	if view == nil then
		if not S.window_unread_logged then
			S.window_unread_logged = true
			Log.log(NAME, "Couldn't read the house window, keeping the last known inside state")
		end
		return S.was_inside
	end
	S.was_inside = table.find(view.actions, CONST.EXIT_OPTION) ~= nil
	return S.was_inside
end

function Read.nearest_house(): House
	local me = snap.state.position :: Host.PositionData
	local best, best_distance = HOUSES[1], math.huge
	for _, house in HOUSES do
		local d = Walker.distance(house.window, me)
		if d < best_distance then
			best, best_distance = house, d
		end
	end
	return best
end

function Read.owner(house: House): Host.Npc?
	for _, npc in Npcs.find() or {} do
		if npc.id == house.owner then
			return npc
		end
	end
	return nil
end

function Read.watch_doors(now: number)
	for _, house in HOUSES do
		if Read.door_locked(house) then
			if S.open_since[house.name] == nil then
				S.open_since[house.name] = now
				Log.log(NAME, `{house.name}'s house is empty`)
			end
		elseif S.open_since[house.name] then
			S.open_since[house.name], S.burgled[house.name] = nil, nil
		end
	end
end

function Read.open_house(now: number): House?
	for _, house in HOUSES do
		local since = S.open_since[house.name]
		if since and not S.burgled[house.name] and now - since < CONST.HOUSE_OPEN_MS then
			return house
		end
	end
	return nil
end

function Read.new_messages(): { string }
	local out = {}
	for _, m in Host.chat_messages() or {} do
		if m.uid > S.last_chat_uid then
			S.last_chat_uid = m.uid
			table.insert(out, m.text)
		end
	end
	return out
end

function Read.skip_old_messages()
	for _, m in Host.chat_messages() or {} do
		S.last_chat_uid = math.max(S.last_chat_uid, m.uid)
	end
end

function Read.next_object(house: House): Tile?
	local current = S.searching
	if current and not S.emptied[Read.key(current)] then
		return current
	end
	local me = snap.state.position :: Host.PositionData
	local best: Tile? = nil
	local best_distance = math.huge
	for _, tile in house.searchables do
		local d = Walker.distance(tile, me)
		if not S.emptied[Read.key(tile)] and d < best_distance then
			best, best_distance = tile, d
		end
	end
	return best
end

function Read.loot_item(names: { string } | { number }): number?
	for _, item in Inventory.items() or {} do
		for _, wanted in names do
			if item.id == wanted or Host.item_name(item.id) == wanted then
				return item.id
			end
		end
	end
	return nil
end

function Read.loot_items(): { Bankmain.Entry }
	local loot: { Bankmain.Entry } = {}
	local seen: { [number]: boolean } = {}
	for _, item in Inventory.items() or {} do
		local name = Host.item_name(item.id)
		local is_loot = name == CONST.VALUABLES
			or name == CONST.SHARDS
			or table.find(CONST.JEWELLERY, name or "") ~= nil
			or table.find(CONST.STATUETTES, item.id) ~= nil
		if is_loot and not seen[item.id] then
			seen[item.id] = true
			table.insert(loot, item.id)
		end
	end
	return loot
end

function Read.loot_action(): LootAction?
	local statuette = Read.loot_item(CONST.STATUETTES)
	if statuette and Inventory.contains(CONST.CHISEL) then
		return { kind = "break", item = statuette }
	end
	for _, item in Inventory.items() or {} do
		local id = item.id :: number
		local name = Host.item_name(id) or ""
		if table.find(CONST.JEWELLERY, name) then
			if CONFIG.jewellery[name] == CONST.LOOT_DROP then
				return { kind = "drop", item = id }
			elseif Read.worth_alching(id) then
				return { kind = "alch", item = id }
			end
		end
	end
	return nil
end

function Read.minimap_step(tile: Tile): Tile?
	local route = Walker.route(tile)
	if route == nil then
		return nil
	end
	for i = #route.tiles, 2, -1 do
		local step = route.tiles[i]
		if Walker.on_minimap(step) then
			return step
		end
	end
	return nil
end

function Game.wait_input_idle()
	local deadline = time() + CONST.INPUT_IDLE_MS
	while Mouse.busy() and time() < deadline do
		sleep(CONST.INPUT_POLL_MS)
	end
end

function Game.do_loot(action: LootAction)
	Game.wait_input_idle()
	local item = action.item
	local name = Host.item_name(item) or tostring(item)
	local before = Inventory.count(item) or 0
	local done: boolean
	if action.kind == "break" then
		done = Inventory.interact(item, CONST.BREAK_OPTION)
	elseif action.kind == "drop" then
		done, before = Inventory.drop(item), 1
	else
		done = Magic.cast(CONST.HIGH_ALCH) and Inventory.click(item)
	end
	local verb = CONST.LOOT_VERBS[action.kind]
	if done and Inventory.wait_count(item, before - 1, CONST.LOOT_TIMEOUT_MS) then
		Log.log(NAME, `{verb.done} {name}`)
	else
		Game.fail(`Couldn't {verb.try} {name}`)
	end
end

function Game.loot_while_walking(tile: Tile)
	if Read.loot_action() == nil then
		return
	end
	local step = Read.minimap_step(tile)
	if step == nil or not Walker.click_minimap(step) then
		return
	end
	for _ = 1, CONST.LOOT_PER_WALK do
		local action = Read.loot_action()
		if action == nil then
			return
		end
		Game.do_loot(action)
	end
end

function Read.worth_alching(id: number): boolean
	if CONFIG.jewellery[Host.item_name(id) or ""] ~= CONST.LOOT_ALCH then
		return false
	end
	local value, why = ItemData.high_alch(id)
	local rune, rune_why = ItemData.price(CONST.NATURE_RUNE)
	if value == nil or rune == nil then
		if not S.prices_missing_logged then
			S.prices_missing_logged = true
			Log.log(NAME, `No prices ({why or rune_why}), banking jewellery instead of alching it`)
		end
		return false
	end
	return value > rune and Magic.can_cast(CONST.HIGH_ALCH)
end

function Read.searchable(tile: Tile): House?
	for _, house in HOUSES do
		for _, t in house.searchables do
			if t.x == tile.x and t.y == tile.y then
				return house
			end
		end
	end
	return nil
end

function Read.hint_arrow(payload: string): (number, Tile?)
	local kind = string.byte(payload, 1) or 0
	if #payload < CONST.HINT_PACKET_LENGTH or kind == 0 then
		return kind, nil
	end
	local x = (string.byte(payload, 2) or 0) * 256 + (string.byte(payload, 3) or 0)
	local y = (string.byte(payload, 4) or 0) * 256 + (string.byte(payload, 5) or 0)
	return kind, { x = x, y = y }
end

function Game.on_hint_packet(packet: Host.Packet)
	if packet.length ~= CONST.HINT_PACKET_LENGTH then
		return
	end
	local kind, tile = Read.hint_arrow(packet.payload)
	if S.hint_opcode == nil then
		if tile == nil or Read.searchable(tile) == nil then
			return
		end
		S.hint_opcode = packet.opcode
		Host.off_packet(S.hint_listener :: number)
		S.hint_listener = Host.on_packet({ packet.opcode }, Game.on_hint_packet)
		Log.log(NAME, `The hint arrow packet is opcode {packet.opcode}`)
	end
	if kind == 0 then
		S.arrow = nil
	elseif tile and Read.searchable(tile) then
		S.arrow = tile
	end
end

function Game.listen_for_hints()
	local all: { number | Host.PacketName } = {}
	for opcode = 0, CONST.MAX_OPCODE do
		table.insert(all, opcode)
	end
	S.hint_listener = Host.on_packet(all, Game.on_hint_packet)
end

function Read.named_in(text: string, tiles: { Tile? }): Tile?
	local lower = string.lower(text)
	for i = 1, 2 do
		local tile = tiles[i]
		local loc = tile and Read.loc_at(tile)
		if tile and loc and loc.name and string.find(lower, string.lower(loc.name), 1, true) then
			return tile
		end
	end
	return nil
end

function Loop.read_house_messages()
	for _, text in Read.new_messages() do
		if string.find(text, CONST.MESSAGE.COMING_BACK, 1, true) then
			Log.log(NAME, "The owner is coming back")
			S.leaving = true
		elseif string.find(text, CONST.MESSAGE.EMPTY, 1, true) then
			local tile = Read.named_in(text, { S.searching, S.searched_before })
			if tile then
				local emptied = Read.key(tile)
				S.emptied[emptied] = true
				if S.arrow and Read.key(S.arrow :: Tile) == emptied then
					S.arrow = nil
				end
				if S.searching and Read.key(S.searching :: Tile) == emptied then
					S.searching = nil
				end
			end
		elseif string.find(text, CONST.MESSAGE.FULL, 1, true) then
			Log.log(NAME, "The inventory is full, leaving")
			S.leaving = true
		end
	end
end

function Loop.inside_state(now: number): State
	local house = Read.nearest_house()
	plan.house = house
	if S.inside ~= house.name then
		S.inside, S.leaving, S.searching, S.searched_before, S.emptied = house.name, false, nil, nil, {}
		S.close_in, S.window_failed = {}, false
		S.burgled[house.name] = true
		Log.log(NAME, `Inside {house.name}'s house`)
	end
	Loop.read_house_messages()
	local arrow = S.arrow
	local shining = arrow ~= nil and Read.searchable(arrow) == house and not S.emptied[Read.key(arrow)]
	plan.object = if shining then arrow else Read.next_object(house)
	if S.leaving or plan.object == nil then
		return "LEAVE_HOUSE"
	end
	local target = plan.object :: Tile
	local animation = Player.animation()
	if animation and animation ~= CONST.NO_ANIMATION then
		S.search_idle_since = now
	end
	local same = S.searching ~= nil and Read.key(S.searching :: Tile) == Read.key(target)
	if same and now - S.search_idle_since < CONST.SEARCH_IDLE_MS then
		return Loop.panel_state(now) or "SEARCHING"
	end
	if Mouse.busy() then
		return "SEARCHING"
	end
	return "SEARCH"
end

function Loop.house_state(skipped: { [string]: boolean }): State
	local now = time()
	Read.watch_doors(now)
	Loop.draw_houses()
	if S.phase == "houses" and not S.pickpocketing and S.debug_drawn then
		DebugDraw.set(CONST.DEBUG_LAYER, nil)
		S.debug_drawn = false
	end
	if Read.inside_any() then
		return Loop.inside_state(now)
	end
	if S.inside then
		Log.log(NAME, `Left {S.inside}'s house with {Inventory.count_ex(CONST.VALUABLES) or 0} valuables`)
		S.inside, S.leaving, S.searching = nil, false, nil
		S.houses_done += 1
	end
	if S.phase == "pickpocket" and not houses_only then
		if S.pickpocketing or Read.keys() < S.key_target then
			return Loop.pickpocket_state(skipped)
		end
		Log.log(NAME, `Got {Read.keys()} house keys, burgling houses`)
		S.phase = "houses"
	end
	if (Inventory.count_used() or 0) >= S.bank_at then
		return "BANK"
	end
	if Read.keys() == 0 then
		if #Read.loot_items() > 0 then
			return "BANK"
		end
		if houses_only then
			Log.log(NAME, "Out of house keys, stopping the script")
			S.finished = true
			return "LOADING"
		end
		S.phase = "pickpocket"
		Read.roll_key_target()
		return "WALK_TO_SPOT"
	end
	plan.house = Read.open_house(now)
	local house = plan.house
	if house == nil then
		if S.pickpocketing then
			return Loop.pickpocket_state(skipped)
		end
		local panel = Loop.panel_state(now)
		if panel then
			return panel
		end
		local here = snap.state.position :: Host.PositionData
		if Walker.distance(here, CONST.TILE.HOUSE_WAIT) > CONST.HOUSE_WAIT_RADIUS then
			return "WALK_TO_WAIT"
		end
		plan.loot = Read.loot_action()
		if plan.loot then
			return "LOOT"
		end
		return if skipped["WAIT"] then "LOADING" else "WAIT"
	end
	if S.pickpocketing then
		return Loop.pickpocket_state(skipped)
	end
	local me = snap.state.position :: Host.PositionData
	if Walker.distance(me, house.outside) > CONST.DOOR_REACH then
		return "WALK_TO_HOUSE"
	end
	local owner = Read.owner(house)
	if owner and Walker.distance(owner, house.door) <= CONST.OWNER_CLEAR_TILES then
		plan.loot = Read.loot_action()
		return if plan.loot then "LOOT" else "WAIT_OWNER"
	end
	return "ENTER_HOUSE"
end

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}
	plan = { citizens = {}, distractors = {} }

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	if houses then
		return Loop.house_state(skipped)
	end
	return Loop.pickpocket_state(skipped)
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	WAIT = function()
		if S.antiban_ready and not Antiban.do_antiban() then
			S.skip["WAIT"] = true
		end
		sleep(CONST.HALF_TICK_MS)
	end,
	PICKPOCKET = function()
		local npc = plan.target :: Host.Npc
		Log.log(NAME, `Pickpocketing the citizen at {npc.x}, {npc.y}`)
		if Npcs.interact(npc, CONST.PICKPOCKET_OPTION) then
			S.pickpocketing, S.clicked_at, S.pickpocket_seen_at = true, time(), nil
			stats.runs += 1
			S.failures_in_row = 0
		else
			Log.log(NAME, "Couldn't click the citizen")
			stats.failures += 1
			S.failures_in_row += 1
		end
	end,
	OPEN_INVENTORY = function()
		if Inventory.open() then
			S.away_since["inventory"] = nil
		else
			Log.log(NAME, "Couldn't open the inventory")
		end
	end,
	OPEN_CHAT_TAB = function()
		if ChatTabs.open(CONST.CHAT_TAB) then
			S.away_since["chat"] = nil
		else
			Log.log(NAME, `Couldn't open the {CONST.CHAT_TAB} chat tab`)
		end
	end,
	PICKPOCKETING = function()
		if S.antiban_ready then
			Antiban.do_async_tasks("game")
		end
		sleep(CONST.HALF_TICK_MS)
	end,
	OPEN_POUCHES = function()
		Log.log(NAME, `Opening {snap.pouches} coin pouches`)
		local opened = Inventory.interact(CONST.COIN_POUCH, CONST.OPEN_POUCHES_OPTION)
			and Inventory.wait_count(CONST.COIN_POUCH, 0, CONST.OPEN_POUCHES_TIMEOUT_MS)
		if opened then
			S.failures_in_row = 0
		else
			Log.log(NAME, "Couldn't open the coin pouches")
			stats.failures += 1
			S.failures_in_row += 1
		end
	end,
	WALK_TO_HOUSE = function()
		local house = plan.house :: House
		Log.log(NAME, `Walking to {house.name}'s house`)
		Game.loot_while_walking(house.outside)
		if not Walker.walk(house.outside, { plane = CONST.PLANE.GROUND, near = CONST.DOOR_REACH }) then
			Game.fail(`Couldn't walk to {house.name}'s house`)
		end
	end,
	WAIT_OWNER = function()
		sleep(CONST.HALF_TICK_MS * 2)
	end,
	ENTER_HOUSE = function()
		local house = plan.house :: House
		local door = Read.loc_at(house.door)
		local keys = Read.keys()
		Read.skip_old_messages()
		if door == nil or not Objects.interact(door, CONST.OPEN_OPTION) then
			Game.fail(`Couldn't open {house.name}'s door`)
			return
		end
		local deadline = time() + CONST.ENTER_TIMEOUT_MS
		while time() < deadline and not Read.inside_any() do
			sleep(CONST.HALF_TICK_MS)
		end
		if Read.inside_any() then
			Log.log(NAME, `Opened {house.name}'s door, {keys} -> {Read.keys()} house keys`)
			S.failures_in_row = 0
			sleep(Random.int(CONST.ENTER_PAUSE_MS.MIN, CONST.ENTER_PAUSE_MS.MAX))
		else
			Log.log(NAME, `Didn't get into {house.name}'s house`)
		end
	end,
	SEARCH = function()
		local tile = plan.object :: Tile
		local loc = Read.loc_at(tile)
		Log.log(NAME, `Searching the {loc and loc.name or "object"} at {tile.x}, {tile.y}`)
		local me = Walker.position()
		local far = me ~= nil and Walker.distance(me, tile) > CONST.CLOSE_IN_TILES
		local retry = S.close_in[Read.key(tile)] == true or S.awkward[Read.key(tile)] == true
		if loc and (retry or far) then
			Game.step_next_to(loc)
		end
		if loc and Objects.interact(loc, CONST.SEARCH_OPTION, false, nil, nil, retry) then
			local previous = S.searching
			if previous and Read.key(previous) ~= Read.key(tile) then
				S.searched_before = previous
			end
			S.searching, S.search_idle_since = tile, time()
			S.failures_in_row = 0
		else
			S.close_in[Read.key(tile)] = true
			S.awkward[Read.key(tile)] = true
			Game.fail(`Couldn't search the object at {tile.x}, {tile.y}`)
		end
	end,
	SEARCHING = function()
		if S.antiban_ready then
			Antiban.do_async_tasks("game")
		end
		sleep(CONST.HALF_TICK_MS)
	end,
	LEAVE_HOUSE = function()
		local house = plan.house :: House
		local window = Read.loc_at(house.window)
		Log.log(NAME, `Leaving {house.name}'s house through the window`)
		local me = Walker.position()
		if me and Walker.distance(me, house.window) > CONST.CLOSE_IN_TILES then
			Walker.walk(house.window, { plane = CONST.PLANE.GROUND, near = 1 })
		end
		Game.wait_input_idle()
		if window == nil or not Objects.interact(window, CONST.EXIT_OPTION, nil, nil, nil, S.window_failed) then
			S.window_failed = true
			Game.fail("Couldn't climb out of the window")
			return
		end
		local deadline = time() + CONST.EXIT_TIMEOUT_MS
		while time() < deadline and Read.inside_any() do
			sleep(CONST.HALF_TICK_MS)
		end
	end,
	LOOT = function()
		Game.do_loot(plan.loot :: LootAction)
	end,
	BANK = function()
		Game.loot_while_walking(CONST.TILE.BANK)
		Game.walk_to(CONST.MAPSQUARE.BANK, CONST.TILE.BANK, "bank")
		if not Bankmain.open() then
			Game.fail("Couldn't open the bank")
			return
		end
		local loot = Read.loot_items()
		local banked = #loot == 0 or Bankmain.deposit_array(loot)
		local inventory = CONFIG.inventory
		local stocked = inventory == nil or Game.restock(inventory)
		Bankmain.close()
		Read.roll_bank_at()
		if not banked then
			Game.fail("Couldn't deposit the loot")
		elseif not stocked then
			Game.fail("The bank is missing items for the inventory layout")
		end
	end,
	WALK_TO_SPOT = function()
		Game.walk_to_spot()
	end,
	WALK_TO_WAIT = function()
		Game.walk_near(CONST.TILE.HOUSE_WAIT, CONST.HOUSE_WAIT_RADIUS, "houses")
	end,
}
local last_stray_at = 0
local function close_stray()
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
		if Handoff.finishing() then
			Log.log(NAME, "The queue asked to wrap up")
			break
		end
		Game.poll_settings()
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		close_stray()
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
