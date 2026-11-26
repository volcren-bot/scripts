--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Tile = Host.Tile
type Spot = { x: number, y: number, plane: number }
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local Biometrics = require("@volcren/biometrics")
local Boxing = require("./boxing")
local Chat = require("@volcren/chat")
local ChatOptions = require("@volcren/chat_options")
local Deadfall = require("./deadfall")
local Falconry = require("./falconry")
local GameState = require("@volcren/game_state")
local Handoff = require("@volcren/handoff")
local HuntsmansKit = require("@volcren/huntsmans_kit")
local Inventory = require("@volcren/inventory")
local Item = require("@volcren/item")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Netting = require("./netting")
local Npcs = require("@volcren/npcs")
local Pitfall = require("./pitfall")
local Player = require("@volcren/player")
local Position = require("@volcren/position")
local Quetzal = require("@volcren/quetzal")
local Random = require("@volcren/random")
local RumourLocations = require("./rumour_locations")
local Salamanders = require("./salamanders")
local Shopmain = require("@volcren/shopmain")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Travel = require("./travel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Hunter Rumours"

local MEAT_POUCHES = { "Large meat pouch (open)", "Large meat pouch", "Small meat pouch (open)", "Small meat pouch" }
local FUR_POUCHES = {
	"Large fur pouch (open)",
	"Large fur pouch",
	"Medium fur pouch (open)",
	"Medium fur pouch",
	"Small fur pouch (open)",
	"Small fur pouch",
}

local CONST = {
	REPORT = { counters_key = "" },
	ANTIBAN_GAP_MS = { 3000, 9000 },
	MAPSQUARE = { HUNTER_GUILD = 6191, HUNTER_GUILD_BASEMENT = 6291 },
	BURROW_SPREAD = 2,
	BURROW_LOAD_MS = 2500,
	TILE = {
		BURROW = { x = 1558, y = 9457, plane = 0 },
		BANK = { x = 1544, y = 3040, plane = 0 },
		PITRI = { x = 1558, y = 3046, plane = 2 },
		IMIA = { x = 1561, y = 3058, plane = 0 },
	},
	NPC = { PITRI = 13135, IMIA = 13131 },
	OPTION = { RECHARGE = "Recharge-whistle", WEAR = "Wear", OPEN = "Open" },
	OPEN_TIMEOUT_MS = 2400,
	RELEASE = "Release",
	PROGRESS_TILES = 10,
	RELEASE_GAP_MS = { 120, 380 },
	SACK_FREE_SLOTS = 8,
	LOOT_SACKS = {
		"Hunters' loot sack (basic)",
		"Hunters' loot sack (adept)",
		"Hunters' loot sack (expert)",
		"Hunters' loot sack (master)",
	},
	RECHARGE_SETTLE_MS = { 1200, 2000 },
	EQUIP_TIMEOUT_MS = 2400,
	RESTOCK_MS = { 4000, 8000 },
	KIT = "Huntsman's kit",
	COINS = { name = "Coins", amount = 20000 },
	STAFFS = { "Dramen staff", "Lunar staff" },
	OUTFIT = { "Guild hunter headwear", "Guild hunter top", "Guild hunter legs", "Guild hunter boots" },
	WHISTLES = {
		{ name = "Perfected quetzal whistle(i)" },
		{ name = "Perfected quetzal whistle", charges = 50, recharge_at = { 5, 15 } },
		{ name = "Enhanced quetzal whistle", charges = 20, recharge_at = { 3, 8 } },
		{ name = "Basic quetzal whistle", charges = 5, recharge_at = { 1, 3 } },
	} :: { { name: string, charges: number?, recharge_at: { number }? } },
	GEAR = {
		["box trap"] = { { items = { "Box trap" }, want = 50, need = 5, shop = true } },
		["butterfly net"] = { { items = { "Magic insect net", "Insect net" }, want = 1, need = 0, shop = true } },
		["net trap"] = { { items = { "Net trap" }, want = 10, need = 5, shop = true } },
		["deadfall"] = {
			{ items = { "Fletching knife", "Knife" }, want = 1, need = 1, shop = false },
			{ items = MEAT_POUCHES, want = 1, need = 0, shop = false },
			{ items = FUR_POUCHES, want = 1, need = 0, shop = false },
		},
		["pitfall"] = {
			{ items = { "Hunter's spear", "Teasing stick" }, want = 1, need = 1, shop = true },
			{ items = { "Knife", "Fletching knife" }, want = 1, need = 1, shop = false },
			{ items = MEAT_POUCHES, want = 1, need = 0, shop = false },
			{ items = FUR_POUCHES, want = 1, need = 0, shop = false },
		},
		["falconry"] = {
			{ items = MEAT_POUCHES, want = 1, need = 1, shop = false },
			{ items = FUR_POUCHES, want = 1, need = 1, shop = false },
		},
	} :: { [string]: { { items: { string }, want: number, need: number, shop: boolean } } },
	PREY_GEAR = {
		["orange salamander"] = {
			{
				items = { "Waterskin(4)", "Waterskin(3)", "Waterskin(2)", "Waterskin(1)" },
				want = 4,
				need = 2,
				shop = false,
			},
		},
	} :: { [string]: { { items: { string }, want: number, need: number, shop: boolean } } },
	AXES = {
		{ name = "Crystal axe", level = 71 },
		{ name = "3rd age axe", level = 65 },
		{ name = "Infernal axe", level = 61 },
		{ name = "Dragon axe", level = 61 },
		{ name = "Rune axe", level = 41 },
		{ name = "Adamant axe", level = 31 },
		{ name = "Mithril axe", level = 21 },
		{ name = "Black axe", level = 11 },
		{ name = "Steel axe", level = 6 },
		{ name = "Iron axe", level = 1 },
		{ name = "Bronze axe", level = 1 },
	},
	FOOD_TRAPS = { pitfall = true },
	LOOT_SLOTS = {
		deadfall = 3,
		pitfall = 4,
		falconry = 2,
		["box trap"] = 1,
		["net trap"] = 1,
		["butterfly net"] = 0,
	} :: { [string]: number },
	AXE_TRAPS = { pitfall = true, deadfall = true },
	POUCH = { OPEN = "Open", OPENED = "(open)", EMPTY = "Empty" },
	LOOT = { BURY = "Bury", BONES = { "Bones", "Big bones" }, HIDES = { " fur$", " hide$" }, MEAT = { "^Raw " } },
	CHORE_STATES = { WAIT = true, CATCH = true, TEASE = true, CHOP = true },
	MID_CATCH_STATES = { JUMP = true, RETRIEVE = true, LURE = true },
	EAT_AT = { 0.4, 0.55 },
	EAT_OPTION = "Eat",
	RUMOUR = {
		OPTION = "Rumour",
		CURRENT = "^Your current rumour target is an? (.-)%. You'll need to bring back (.-)%. (.-) was the source of the rumour%.",
		ASSIGNED = "rumours of an? rare (.-) coming in%. Once you find it, bring back (.-)%.$",
		ANOTHER = { YES = "Yes.", NO = "No." },
		TIMEOUT_MS = 2400,
		READ_ATTEMPTS = 3,
		DIALOGUE_TIMEOUT_MS = 8000,
		CONTINUES = 3,
	},
	MASTERS = {
		{ npc = 13121, name = "Gilman", tier = "novice" },
		{ npc = 13122, name = "Ornus", tier = "adept" },
		{ npc = 13123, name = "Cervus", tier = "adept" },
		{ npc = 13124, name = "Aco", tier = "expert" },
		{ npc = 13125, name = "Teco", tier = "expert" },
		{ npc = 13126, name = "Wolf", tier = "master" },
	},
	RUMOURS = {
		{ prey = "tropical wagtail", part = 29222, trap = "snare", level = 19 },
		{ prey = "wild kebbit", part = 29223, trap = "deadfall", level = 23 },
		{ prey = "sapphire glacialis", part = 29224, trap = "butterfly net", level = 25 },
		{ prey = "swamp lizard", part = 29225, trap = "net trap", level = 29 },
		{ prey = "spined larupia", part = 29226, trap = "pitfall", level = 31 },
		{ prey = "barb-tailed kebbit", part = 29223, trap = "deadfall", level = 33 },
		{ prey = "snowy knight", part = 29227, trap = "butterfly net", level = 35 },
		{ prey = "prickly kebbit", part = 29223, trap = "deadfall", level = 37 },
		{ prey = "embertailed jerboa", part = 29228, trap = "box trap", level = 39 },
		{ prey = "horned graahk", part = 29229, trap = "pitfall", level = 41 },
		{ prey = "spotted kebbit", part = 29223, trap = "falconry", level = 43 },
		{ prey = "black warlock", part = 29230, trap = "butterfly net", level = 45 },
		{ prey = "orange salamander", part = 29231, trap = "net trap", level = 47 },
		{ prey = "razor-backed kebbit", part = 29223, trap = "noose", level = 49 },
		{ prey = "sabre-toothed kebbit", part = 29223, trap = "deadfall", level = 51 },
		{ prey = "grey chinchompa", part = 29221, trap = "box trap", level = 53 },
		{ prey = "sabre-toothed kyatt", part = 29232, trap = "pitfall", level = 53 },
		{ prey = "dark kebbit", part = 29223, trap = "falconry", level = 57 },
		{ prey = "pyre fox", part = 29233, trap = "deadfall", level = 57 },
		{ prey = "red salamander", part = 29234, trap = "net trap", level = 59 },
		{ prey = "wyrmscraig goat", part = 33835, trap = "goat pit", level = 60 },
		{ prey = "carnivorous chinchompa", part = 29235, trap = "box trap", level = 63 },
		{ prey = "red chinchompa", part = 29235, trap = "box trap", level = 63 },
		{ prey = "sunlight moth", part = 29237, trap = "butterfly net", level = 65 },
		{ prey = "dashing kebbit", part = 29223, trap = "falconry", level = 69 },
		{ prey = "sunlight antelope", part = 29236, trap = "pitfall", level = 72 },
		{ prey = "moonlight moth", part = 29240, trap = "butterfly net", level = 75 },
		{ prey = "tecu salamander", part = 29238, trap = "net trap", level = 79 },
		{ prey = "herbiboar", part = 29239, trap = "herbiboar", level = 80 },
		{ prey = "moonlight antelope", part = 29241, trap = "pitfall", level = 91 },
	},
	RECHARGE_ITEMS = {
		{ name = "Raw dashing kebbit", charges = 3 },
		{ name = "Raw pyre fox", charges = 2 },
		{ name = "Raw kyatt", charges = 2 },
		{ name = "Raw sunlight antelope", charges = 3 },
		{ name = "Raw moonlight antelope", charges = 3 },
		{ name = "Raw graahk", charges = 2 },
		{ name = "Raw barb-tailed kebbit", charges = 1 },
		{ name = "Raw larupia", charges = 1 },
		{ name = "Quetzal feed", charges = 1 },
		{ name = "Raw wild kebbit", charges = 1 },
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	max_rumours = 0,
	stop_level = 0,
	open_sacks = true,
	bury_bones = true,
	hides = "Bank",
	meat = "Bank",
	catches = {
		[10033] = "bank",
		[10034] = "bank",
		[10146] = "release",
		[10147] = "release",
		[10149] = "release",
	} :: { [number]: string },
	food = "Bass",
	food_count = 6,
	timeouts = { idle_minutes = 5, max_failures = 4, max_restarts = 3, restart_window_ms = 600000 },
}

local stats = { rumours = 0, catches = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	progress_tile: Host.Tile?,
	failures_in_row: number,
	restarts: { number },
	rumour: Rumour?,
	task: Task?,
	prep: Prep,
	recharge_at: number?,
	eat_at: number?,
	start_worn: { string },
	skip: { [string]: boolean },
}

function Game.apply_settings(values: { [string]: any })
	CONFIG.max_rumours = values.max_rumours or CONFIG.max_rumours
	CONFIG.stop_level = values.stop_level or CONFIG.stop_level
	CONFIG.open_sacks = values.open_loot_sacks ~= false
	CONFIG.bury_bones = values.bury_bones ~= false
	CONFIG.hides = values.hides or CONFIG.hides
	CONFIG.meat = values.meat or CONFIG.meat
	CONFIG.food = values.food or CONFIG.food
	CONFIG.food_count = values.food_count or CONFIG.food_count
	for id, column in pairs(values.catches or {}) do
		local item = tonumber(id)
		if item and type(column) == "string" then
			CONFIG.catches[item] = column
		end
	end
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

type Prep = {
	forced: boolean,
	banked: boolean,
	rebanked: boolean,
	kit_seen: boolean,
	shopped: boolean,
	recharged: boolean,
	ready: boolean,
	bank: { [string]: number },
}

type Solver = {
	new: (prey: string) -> any,
	state: (task: any) -> string,
	step: (task: any, state: string) -> boolean,
}
type Task = { solver: Solver, job: { catches: number, blocked: string? } }

local SOLVERS: { Solver } =
	{ Netting :: any, Boxing :: any, Falconry :: any, Salamanders :: any, Pitfall :: any, Deadfall :: any }

function Read.new_task(prey: string): Task?
	for _, solver in ipairs(SOLVERS) do
		local job = solver.new(prey)
		if job ~= nil then
			return { solver = solver, job = job }
		end
	end
	return nil
end

type Want = { items: { string }, want: number, need: number, kit: boolean, shop: boolean }

function Read.new_prep(): Prep
	return {
		forced = false,
		banked = false,
		rebanked = false,
		kit_seen = false,
		shopped = false,
		recharged = false,
		ready = false,
		bank = {},
	}
end

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	restarts = {},
	rumour = nil,
	task = nil,
	prep = Read.new_prep(),
	recharge_at = nil,
	eat_at = nil,
	start_worn = {},
	skip = {},
}

type Rumour = {
	prey: string,
	part: number?,
	part_word: string,
	trap: string?,
	level: number?,
	master: string,
	master_npc: number?,
	areas: { RumourLocations.Area }?,
}

type Snapshot = {
	state: ClientState,
	tick: number,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "NO_RUMOUR"
	| "HAND_IN"
	| "BANK"
	| "KIT"
	| "SHOP"
	| "EQUIP"
	| "RECHARGE"
	| "OPEN_SACK"
	| "OPEN_POUCH"
	| "BURY"
	| "RELEASE"
	| "DROP"
	| "BANK_LOOT"
	| "HUNT"
	| "NO_SOLVER"

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
	}
	return true
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
	Log.log(NAME, "Antiban set up")
end

function Read.carried(items: { string }): number
	local n = Inventory.count_ex(items :: { Item.Item }) or 0
	for _, name in ipairs(items) do
		if Wornitems.is_wearing(name) then
			n += 1
		end
	end
	return n
end

function Read.held_whistle(): (number?, number?)
	for rank, whistle in ipairs(CONST.WHISTLES) do
		if Inventory.contains(whistle.name) then
			return rank, whistle.charges
		end
	end
	return nil, nil
end

function Read.missing_charges(): number
	local rank, max = Read.held_whistle()
	if rank == nil or max == nil then
		return 0
	end
	local charges = Quetzal.charges(true) or max
	if S.recharge_at == nil then
		local range = CONST.WHISTLES[rank].recharge_at or { 0, 0 }
		S.recharge_at = Random.int(range[1], range[2])
		Log.log(NAME, `Next whistle recharge at {S.recharge_at} charges or fewer`)
	end
	if charges > (S.recharge_at :: number) then
		return 0
	end
	return math.max(0, max - charges)
end

function Read.unnoted(name: string): number
	local held: { { id: number, quantity: number } } = {}
	local ids: { number } = {}
	for _, item in ipairs(Inventory.items() or {}) do
		if item.name == name then
			table.insert(held, item)
			table.insert(ids, item.id)
		end
	end
	if #held == 0 then
		return 0
	end
	local stacks = Host.item_stackable(ids) or {}
	local count = 0
	for i, item in ipairs(held) do
		if stacks[i] == false then
			count += item.quantity
		end
	end
	return count
end

function Read.has_recharge_items(): boolean
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		if Read.unnoted(item.name) > 0 then
			return true
		end
	end
	return false
end

function Read.wants(): { Want }
	local list: { Want } = {
		{ items = { CONST.KIT }, want = 1, need = 0, kit = false, shop = false },
		{ items = CONST.STAFFS, want = 1, need = 0, kit = false, shop = false },
		{ items = { CONST.COINS.name }, want = CONST.COINS.amount, need = 0, kit = false, shop = false },
	}
	for _, piece in ipairs(CONST.OUTFIT) do
		table.insert(list, { items = { piece }, want = 1, need = 0, kit = true, shop = false })
	end
	for _, gear in ipairs(Read.rumour_gear()) do
		table.insert(list, {
			items = gear.items,
			want = gear.want,
			need = gear.need,
			kit = Read.storable(gear.items),
			shop = gear.shop,
		})
	end
	return list
end

function Read.rumour_gear(): { { items: { string }, want: number, need: number, shop: boolean } }
	local list = {}
	local trap = S.rumour and S.rumour.trap
	local prey = S.rumour and S.rumour.prey
	for _, gear in ipairs(if trap then CONST.GEAR[trap] or {} else {}) do
		table.insert(list, gear)
	end
	for _, gear in ipairs(if prey then CONST.PREY_GEAR[prey] or {} else {}) do
		table.insert(list, gear)
	end
	if trap and CONST.AXE_TRAPS[trap] then
		local woodcutting = Stats.real_level("Woodcutting") or 1
		local axes: { string } = {}
		for _, axe in ipairs(CONST.AXES) do
			if axe.level <= woodcutting then
				table.insert(axes, axe.name)
			end
		end
		table.insert(list, { items = axes, want = 1, need = 1, shop = false })
	end
	if trap and CONST.FOOD_TRAPS[trap] and CONFIG.food_count > 0 then
		table.insert(list, { items = { CONFIG.food }, want = CONFIG.food_count, need = 1, shop = false })
	end
	return list
end

function Read.storable(items: { string }): boolean
	for _, name in ipairs(items) do
		if HuntsmansKit.can_store(name) then
			return true
		end
	end
	return false
end

function Read.short(w: Want): number
	return math.max(0, w.want - Read.carried(w.items))
end

function Read.in_bank(items: { string }): boolean
	for _, name in ipairs(items) do
		if (S.prep.bank[string.lower(name)] or 0) > 0 then
			return true
		end
	end
	return false
end

function Read.kit_short(): boolean
	for _, w in ipairs(Read.wants()) do
		if w.kit and Read.short(w) > 0 then
			return true
		end
	end
	return false
end

function Read.bank_short(): boolean
	for _, w in ipairs(Read.wants()) do
		if Read.short(w) > 0 and Read.in_bank(w.items) then
			return true
		end
	end
	return false
end

function Read.shop_short(): boolean
	for _, w in ipairs(Read.wants()) do
		if w.shop and Read.carried(w.items) < w.need then
			return true
		end
	end
	return false
end

function Read.outfit_to_wear(): string?
	for _, piece in ipairs(CONST.OUTFIT) do
		if Inventory.contains(piece) and not Wornitems.is_wearing(piece) then
			return piece
		end
	end
	return nil
end

function Read.closed_pouch(): string?
	for _, pouches in ipairs({ MEAT_POUCHES, FUR_POUCHES }) do
		for _, name in ipairs(pouches) do
			if not string.find(name, CONST.POUCH.OPENED, 1, true) and Inventory.contains(name) then
				return name
			end
		end
	end
	return nil
end

function Read.loot(patterns: { string }): { string }
	local found: { string } = {}
	for _, item in ipairs(Inventory.items() or {}) do
		local name = item.name or ""
		for _, pattern in ipairs(patterns) do
			if string.find(name, pattern) and not table.find(found, name) then
				table.insert(found, name)
			end
		end
	end
	return found
end

function Read.bones(): string?
	for _, name in ipairs(CONST.LOOT.BONES) do
		if Inventory.contains(name) then
			return name
		end
	end
	return nil
end

function Read.to_drop(): { string }
	local drop: { string } = {}
	local patterns: { string } = {}
	if CONFIG.hides == "Drop" then
		table.move(CONST.LOOT.HIDES, 1, #CONST.LOOT.HIDES, #patterns + 1, patterns)
	end
	if CONFIG.meat == "Drop" then
		table.move(CONST.LOOT.MEAT, 1, #CONST.LOOT.MEAT, #patterns + 1, patterns)
	end
	if #patterns > 0 then
		drop = Read.loot(patterns)
	end
	return drop
end

function Read.to_release(): string?
	for _, item in ipairs(Inventory.items() or {}) do
		if CONFIG.catches[item.id] == "release" and item.name then
			return item.name
		end
	end
	return nil
end

function Read.loot_full(): boolean
	local trap = S.rumour and S.rumour.trap
	local room = if trap then CONST.LOOT_SLOTS[trap] or 1 else 1
	if (Inventory.free_slots() or 0) >= math.max(room, 1) then
		return false
	end
	local keep = Item.matcher(Read.keep_items())
	for _, item in ipairs(Inventory.items() or {}) do
		if not Item.matches(keep, item.id, item.name) then
			return true
		end
	end
	return false
end

function Read.chore(bank: boolean): State?
	if Read.to_release() then
		return "RELEASE"
	end
	if CONFIG.bury_bones and Read.bones() then
		return "BURY"
	end
	if #Read.to_drop() > 0 then
		return "DROP"
	end
	if bank and Read.loot_full() then
		return "BANK_LOOT"
	end
	return nil
end

function Read.should_eat(): boolean
	local hp, max = Player.hitpoints()
	if hp == nil or max == nil or not Inventory.contains(CONFIG.food) then
		return false
	end
	if S.eat_at == nil then
		S.eat_at = Random.float(CONST.EAT_AT[1], CONST.EAT_AT[2])
	end
	return hp <= max * (S.eat_at :: number)
end

function Game.eat(): boolean
	local hp = Player.hitpoints()
	Log.log(NAME, `Eating {CONFIG.food} at {hp or "?"} hitpoints`)
	S.eat_at = nil
	local before = Inventory.count_ex(CONFIG.food) or 0
	if not Inventory.interact(CONFIG.food, CONST.EAT_OPTION) then
		return false
	end
	local deadline = time() + CONST.OPEN_TIMEOUT_MS
	repeat
		if (Inventory.count_ex(CONFIG.food) or 0) < before then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Read.loot_sack(): string?
	for _, sack in ipairs(CONST.LOOT_SACKS) do
		if Inventory.contains(sack) then
			return sack
		end
	end
	return nil
end

function Read.current_gear(): { [string]: boolean }
	local current: { [string]: boolean } = {}
	for _, gear in ipairs(Read.rumour_gear()) do
		for _, name in ipairs(gear.items) do
			current[name] = true
		end
	end
	return current
end

function Read.spare_for_kit(): { string }
	local spare: { string } = {}
	for _, name in ipairs(Read.spare_gear()) do
		if HuntsmansKit.can_store(name) then
			table.insert(spare, name)
		end
	end
	return spare
end

function Read.spare_gear(): { string }
	local current = Read.current_gear()
	local spare: { string } = {}
	for _, table_of in ipairs({ CONST.GEAR, CONST.PREY_GEAR }) do
		for _, gears in pairs(table_of) do
			for _, gear in ipairs(gears) do
				for _, name in ipairs(gear.items) do
					if not current[name] and Inventory.contains(name) and not table.find(spare, name) then
						table.insert(spare, name)
					end
				end
			end
		end
	end
	return spare
end

function Read.keep_items(): { Item.Item }
	local keep: { Item.Item } = { CONST.KIT, CONST.COINS.name }
	for _, name in ipairs(S.start_worn) do
		table.insert(keep, name)
	end
	if CONFIG.open_sacks then
		for _, sack in ipairs(CONST.LOOT_SACKS) do
			table.insert(keep, sack)
		end
	end
	if Read.missing_charges() > 0 then
		for _, item in ipairs(CONST.RECHARGE_ITEMS) do
			table.insert(keep, item.name)
		end
	end
	for _, name in ipairs(CONST.STAFFS) do
		table.insert(keep, name)
	end
	for _, whistle in ipairs(CONST.WHISTLES) do
		table.insert(keep, whistle.name)
	end
	for name in pairs(Read.current_gear()) do
		table.insert(keep, name)
	end
	if not S.prep.kit_seen and (HuntsmansKit.held() or Read.in_bank({ CONST.KIT })) then
		for _, name in ipairs(Read.spare_for_kit()) do
			table.insert(keep, name)
		end
	end
	return keep
end

function Read.at_guild(plane: number): boolean
	local p = snap.state.position
	return p ~= nil and p.plane == plane and Read.mapsquare(snap.state) == CONST.MAPSQUARE.HUNTER_GUILD
end

function Read.in_burrow(): boolean
	local me = Walker.position()
	if me == nil then
		return false
	end
	return (me.x // 64) * 256 + me.y // 64 == CONST.MAPSQUARE.HUNTER_GUILD_BASEMENT
end

function Read.near_guild(): boolean
	local mapsquare = Read.mapsquare(snap.state)
	return mapsquare == CONST.MAPSQUARE.HUNTER_GUILD or mapsquare == CONST.MAPSQUARE.HUNTER_GUILD_BASEMENT
end

function Read.carrying_enough(): boolean
	if Read.held_whistle() == nil then
		return false
	end
	for _, w in ipairs(Read.wants()) do
		if w.need > 0 and Read.carried(w.items) < w.need then
			return false
		end
	end
	return true
end

function Read.prep_state(): State?
	local p = S.prep
	if p.ready then
		return nil
	end
	if not p.forced and not p.banked and not Read.near_guild() and Read.carrying_enough() then
		p.ready = true
		Log.log(NAME, "Already carrying what the rumour needs, skipping the guild")
		return nil
	end
	if CONFIG.open_sacks and Read.loot_sack() and (Inventory.free_slots() or 0) >= CONST.SACK_FREE_SLOTS then
		return "OPEN_SACK"
	end
	if Read.outfit_to_wear() then
		return "EQUIP"
	end
	if Read.closed_pouch() then
		return "OPEN_POUCH"
	end
	if not p.kit_seen and HuntsmansKit.held() then
		if Read.kit_short() or #Read.spare_for_kit() > 0 then
			return "KIT"
		end
		p.kit_seen = true
	end
	if not p.banked then
		return "BANK"
	end
	if not p.rebanked and Read.bank_short() then
		return "BANK"
	end
	if not p.shopped and Read.shop_short() then
		return "SHOP"
	end
	if Read.outfit_to_wear() then
		return "EQUIP"
	end
	if not p.recharged and Read.missing_charges() > 0 and Read.has_recharge_items() then
		return "RECHARGE"
	end
	p.ready = true
	Log.log(NAME, `Ready for the {S.rumour and S.rumour.prey or "rumour"}`)
	return nil
end

function Game.go_to(tile: Spot, what: string): boolean
	Log.log(NAME, `Walking to {what}`)
	local walked, why = Travel.walk(tile, 3)
	if why then
		Log.log(NAME, `No way to {what}: {why}`)
	end
	return walked
end

function Game.withdraw(items: { string }, amount: number): number
	local got = 0
	for _, name in ipairs(items) do
		local stock = S.prep.bank[string.lower(name)] or 0
		if got >= amount then
			break
		elseif stock > 0 then
			local before = Inventory.count_ex(name) or 0
			if Bankmain.withdraw(name, math.min(stock, amount - got), false) then
				local taken = (Inventory.count_ex(name) or before) - before
				S.prep.bank[string.lower(name)] = stock - taken
				got += taken
				Log.log(NAME, `Withdrew {taken} {name}`)
			end
		end
	end
	return got
end

function Game.bank_whistle()
	local held = Read.held_whistle()
	for rank, whistle in ipairs(CONST.WHISTLES) do
		if held ~= nil and rank >= held then
			return
		end
		if Read.in_bank({ whistle.name }) and Game.withdraw({ whistle.name }, 1) > 0 then
			S.recharge_at = nil
			if held ~= nil then
				local old = CONST.WHISTLES[held].name
				Log.log(NAME, `Banking the {old}`)
				Bankmain.deposit(old, 1)
			end
			return
		end
	end
end

function Game.bank_recharge_items()
	local needed = Read.missing_charges()
	if needed == 0 or Read.has_recharge_items() then
		return
	end
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		local take = needed // item.charges
		if take > 0 and Read.in_bank({ item.name }) then
			needed -= Game.withdraw({ item.name }, take) * item.charges
		end
	end
	for i = #CONST.RECHARGE_ITEMS, 1, -1 do
		local item = CONST.RECHARGE_ITEMS[i]
		if needed <= 0 then
			break
		elseif Read.in_bank({ item.name }) then
			needed -= Game.withdraw({ item.name }, 1) * item.charges
		end
	end
	if not Read.has_recharge_items() then
		Log.log(NAME, "No meat or quetzal feed in the bank to recharge the whistle with")
	end
end

function Game.empty_pouches()
	for _, pouches in ipairs({ MEAT_POUCHES, FUR_POUCHES }) do
		for _, name in ipairs(pouches) do
			if Bankmain.inventory.contains(name) then
				local emptied = Bankmain.inventory.interact(name, CONST.POUCH.EMPTY)
				Log.log(NAME, if emptied then `Emptied the {name} into the bank` else `Couldn't empty the {name}`)
				Random.sleep(300, 700)
			end
		end
	end
end

function Game.bank(): boolean
	if not Read.at_guild(0) then
		return Game.go_to(CONST.TILE.BANK, "the guild's bank")
	end
	if not Bankmain.is_open() and not Bankmain.open() then
		return false
	end
	Game.empty_pouches()
	if not Bankmain.deposit_different(Read.keep_items()) then
		Log.log(NAME, "Couldn't bank the loot")
		return false
	end
	for _, item in ipairs(Bankmain.items() or {}) do
		if item.name and item.quantity > 0 then
			S.prep.bank[string.lower(item.name)] = item.quantity
		end
	end
	local kit_too = S.prep.kit_seen or not (HuntsmansKit.held() or Read.in_bank({ CONST.KIT }))
	Game.bank_whistle()
	for _, w in ipairs(Read.wants()) do
		local short = Read.short(w)
		if short > 0 and (kit_too or not w.kit) and Read.in_bank(w.items) then
			Game.withdraw(w.items, short)
		end
	end
	Game.bank_recharge_items()
	S.prep.banked = true
	S.prep.rebanked = S.prep.rebanked or kit_too
	return Bankmain.close()
end

function Game.kit(): boolean
	if not HuntsmansKit.open() then
		return false
	end
	for _, name in ipairs(Read.spare_for_kit()) do
		if HuntsmansKit.deposit(name, "All") then
			Log.log(NAME, `Stored the {name} in the huntsman's kit`)
		end
	end
	for _, w in ipairs(Read.wants()) do
		local short = if w.kit then Read.short(w) else 0
		for _, name in ipairs(w.items) do
			local stored = HuntsmansKit.quantity(name) or 0
			if short > 0 and stored > 0 then
				local take = math.min(short, stored)
				if HuntsmansKit.withdraw(name, take) then
					Log.log(NAME, `Took {take} {name} from the huntsman's kit`)
					short -= take
				end
			end
		end
	end
	S.prep.kit_seen = true
	return HuntsmansKit.close()
end

function Game.shop(): boolean
	if not Read.at_guild(0) then
		return Game.go_to(CONST.TILE.IMIA, "Imia's shop")
	end
	if not Shopmain.is_open() then
		local me = Walker.position()
		local imia = if me then Npcs.nearest(CONST.NPC.IMIA, me) else nil
		if imia == nil then
			return Game.go_to(CONST.TILE.IMIA, "Imia's shop")
		end
		if not Npcs.approach(imia, Shopmain.OPTION) or not Shopmain.wait_open() then
			Log.log(NAME, "Couldn't open Imia's shop")
			return false
		end
	end
	local done = true
	for _, w in ipairs(Read.wants()) do
		local short = Read.short(w)
		if w.shop and Read.carried(w.items) < w.need then
			local name = w.items[#w.items]
			local bought = Shopmain.buy(name, short)
			Log.log(NAME, `Bought {bought} {name}`)
			if Read.carried(w.items) < w.need then
				done = false
			end
		end
	end
	if not done then
		Random.sleep(CONST.RESTOCK_MS[1], CONST.RESTOCK_MS[2])
		return false
	end
	S.prep.shopped = true
	return Shopmain.close()
end

function Game.open_pouch(): boolean
	local pouch = Read.closed_pouch() :: string
	Log.log(NAME, `Opening the {pouch}`)
	if not Inventory.interact(pouch, CONST.POUCH.OPEN) then
		return false
	end
	local deadline = time() + CONST.OPEN_TIMEOUT_MS
	repeat
		if not Inventory.contains(pouch) then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.bury(): boolean
	local bones = Read.bones() :: string
	local before = Inventory.count_ex(bones) or 0
	Log.log(NAME, `Burying {bones}`)
	if not Inventory.interact(bones, CONST.LOOT.BURY) then
		return false
	end
	local deadline = time() + CONST.OPEN_TIMEOUT_MS
	repeat
		if (Inventory.count_ex(bones) or 0) < before then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.release(): boolean
	local slots: { number } = {}
	for _, item in ipairs(Inventory.items() or {}) do
		if CONFIG.catches[item.id] == "release" then
			table.insert(slots, item.slot)
		end
	end
	Log.log(NAME, `Releasing {#slots} caught creatures`)
	local settle = time() + CONST.OPEN_TIMEOUT_MS
	while Player.animation() ~= -1 and time() < settle do
		sleep(100)
	end
	for _, slot in ipairs(slots) do
		if not Inventory.interact_slot(slot, CONST.RELEASE) then
			return false
		end
		Random.sleep(CONST.RELEASE_GAP_MS[1], CONST.RELEASE_GAP_MS[2])
	end
	local deadline = time() + CONST.OPEN_TIMEOUT_MS
	repeat
		local left = 0
		for _, item in ipairs(Inventory.items() or {}) do
			if CONFIG.catches[item.id] == "release" then
				left += 1
			end
		end
		if left == 0 then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.drop(): boolean
	local items = Read.to_drop()
	Log.log(NAME, `Dropping {table.concat(items, ", ")}`)
	return Inventory.shift_drop(items :: { Item.Item })
end

function Game.bank_loot(): boolean
	Log.log(NAME, "The inventory is full, banking the loot")
	S.prep = Read.new_prep()
	S.prep.forced = true
	return true
end

function Game.open_sack(): boolean
	local sack = Read.loot_sack() :: string
	local before = Inventory.count_ex(sack) or 0
	Log.log(NAME, `Opening the {sack}`)
	if not Inventory.interact(sack, CONST.OPTION.OPEN) then
		return false
	end
	local deadline = time() + CONST.OPEN_TIMEOUT_MS
	repeat
		if (Inventory.count_ex(sack) or 0) < before then
			if S.prep.banked then
				S.prep.banked, S.prep.rebanked = false, false
			end
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.equip(): boolean
	local piece = Read.outfit_to_wear() :: string
	Log.log(NAME, `Wearing the {piece}`)
	if not Inventory.interact(piece, CONST.OPTION.WEAR) then
		return false
	end
	local deadline = time() + CONST.EQUIP_TIMEOUT_MS
	repeat
		if Wornitems.is_wearing(piece) then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.recharge(): boolean
	local me = Walker.position()
	local pitri = if me and Read.at_guild(CONST.TILE.PITRI.plane) then Npcs.nearest(CONST.NPC.PITRI, me) else nil
	if pitri == nil then
		return Game.go_to(CONST.TILE.PITRI, "Soar Leader Pitri")
	end
	local before = Quetzal.charges(true) or 0
	local _, max = Read.held_whistle()
	local meat: { [string]: number } = {}
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		meat[item.name] = Read.unnoted(item.name)
	end
	if not Npcs.approach(pitri, CONST.OPTION.RECHARGE) then
		return false
	end
	S.prep.recharged = true
	Random.sleep(CONST.RECHARGE_SETTLE_MS[1], CONST.RECHARGE_SETTLE_MS[2])
	local added = 0
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		added += (meat[item.name] - Read.unnoted(item.name)) * item.charges
	end
	if added <= 0 then
		local checked = Quetzal.charges()
		Log.log(NAME, `Soar Leader Pitri didn't take any meat; the whistle has {checked or "unknown"} charges`)
		if checked == nil then
			Quetzal.set_charges(max or before)
		end
		S.recharge_at = nil
		return true
	end
	local after = math.min(before + added, max or before + added)
	Quetzal.set_charges(after)
	Log.log(NAME, `Whistle recharged: {before} -> {after}`)
	S.recharge_at = nil
	return true
end

function Read.parse_rumour(text: string): Rumour?
	local prey, part_word, master = string.match(text, CONST.RUMOUR.CURRENT)
	if prey == nil or part_word == nil or master == nil then
		return nil
	end
	return Read.make_rumour(prey, part_word, master)
end

function Read.make_rumour(prey: string, part_word: string, master: string): Rumour
	prey = string.lower(prey)
	local rumour: Rumour = { prey = prey, part_word = part_word, master = master, areas = RumourLocations[prey] }
	for _, r in ipairs(CONST.RUMOURS) do
		if r.prey == prey then
			rumour.part, rumour.trap, rumour.level = r.part, r.trap, r.level
			break
		end
	end
	for _, m in ipairs(CONST.MASTERS) do
		if string.lower(m.name) == string.lower(master) then
			rumour.master_npc = m.npc
			break
		end
	end
	return rumour
end

function Game.adopt_rumour(rumour: Rumour, text: string)
	S.rumour = rumour
	S.prep = Read.new_prep()
	Log.log(
		NAME,
		`Rumour: {rumour.prey} ({rumour.trap or "unknown trap"}), bring back {rumour.part_word} to {rumour.master}`
	)
	if rumour.part == nil or rumour.master_npc == nil or rumour.areas == nil then
		Log.log(NAME, `Rumour not fully known: {text}`)
	end
	S.task = Read.new_task(rumour.prey)
	if S.task == nil then
		Log.log(NAME, `No solver for {rumour.prey} yet`)
	end
end

function Game.assigned_rumour(master: string, seen: number): Rumour?
	local deadline = time() + CONST.RUMOUR.TIMEOUT_MS
	repeat
		for _, m in ipairs(Chat.new_messages(seen, { Chat.MessageType.DIALOG }) or {}) do
			local prey, part_word = string.match(m.text, CONST.RUMOUR.ASSIGNED)
			if prey and part_word and string.find(m.name, master, 1, true) then
				local rumour = Read.make_rumour(prey, part_word, master)
				Game.adopt_rumour(rumour, m.text)
				return rumour
			end
		end
		sleep(Quetzal.POLL_MS)
	until time() >= deadline
	return nil
end

function Game.read_rumour(): Rumour?
	local slot = Quetzal.whistle_slot()
	if slot == nil then
		Log.log(NAME, "No quetzal whistle held to read the rumour with")
		return nil
	end
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Inventory.interact_slot(slot, CONST.RUMOUR.OPTION) then
		return nil
	end
	local unknown: { string } = {}
	local deadline = time() + CONST.RUMOUR.TIMEOUT_MS
	repeat
		for _, m in ipairs(Chat.new_messages(seen, { Chat.MessageType.GAME }) or {}) do
			seen = m.uid
			local rumour = Read.parse_rumour(m.text)
			if rumour ~= nil then
				Game.adopt_rumour(rumour :: Rumour, m.text)
				return rumour
			end
			table.insert(unknown, m.text)
		end
		sleep(Quetzal.POLL_MS)
	until time() >= deadline
	Log.log(NAME, `No rumour read from the whistle{if #unknown > 0 then ": " .. table.concat(unknown, " / ") else ""}`)
	return nil
end

function Read.packing(): boolean
	local task = S.task
	return task ~= nil and task.solver.state(task.job) ~= "DONE"
end

function Read.holds_part(): boolean
	local part = S.rumour and S.rumour.part
	return part ~= nil and Inventory.contains(part)
end

function Game.hand_in(): boolean
	local rumour = S.rumour :: Rumour
	local part = rumour.part :: number
	if rumour.master_npc == nil then
		S.blocked = `don't know who {rumour.master} is`
		S.finished = true
		return false
	end
	local inside = Read.in_burrow()
	local master: Host.Npc? = nil
	if inside then
		local deadline = time() + CONST.BURROW_LOAD_MS
		repeat
			local me = Walker.position()
			master = if me then Npcs.nearest(rumour.master_npc, me) else nil
			if master == nil then
				sleep(100)
			end
		until master ~= nil or time() >= deadline
	end
	if master == nil then
		local what = `{rumour.master} with the {Item.name(part) or "rumour part"}`
		if inside then
			local middle = CONST.TILE.BURROW
			local r = CONST.BURROW_SPREAD
			local tile = { x = middle.x + Random.int(-r, r), y = middle.y + Random.int(-r, r), plane = middle.plane }
			Log.log(NAME, `Can't see {rumour.master}, walking into the middle of the room`)
			return (Travel.walk(tile, 1))
		end
		Log.log(NAME, `Walking to {what}`)
		local walked, why = Travel.walk(CONST.TILE.BURROW, 3, Read.in_burrow)
		if why then
			Log.log(NAME, `No way to {what}: {why}`)
		end
		return walked
	end
	if not Npcs.approach(master, CONST.RUMOUR.OPTION) then
		return false
	end
	local more = CONFIG.max_rumours == 0 or stats.rumours + 1 < CONFIG.max_rumours
	local answer = if more then CONST.RUMOUR.ANOTHER.YES else CONST.RUMOUR.ANOTHER.NO
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not ChatOptions.continue_until_option(answer, CONST.RUMOUR.DIALOGUE_TIMEOUT_MS) then
		Log.log(NAME, `{rumour.master} didn't ask about another rumour`)
		return false
	end
	if Inventory.contains(part) then
		Log.log(NAME, `{rumour.master} didn't take the {Item.name(part) or "rumour part"}`)
		return false
	end
	stats.rumours += 1
	Log.log(NAME, `Handed in rumour {stats.rumours}: {rumour.prey}`)
	S.rumour, S.task = nil, nil
	for _ = 1, CONST.RUMOUR.CONTINUES do
		if not ChatOptions.contains_continue() then
			break
		end
		ChatOptions.continue_chat()
	end
	if not more then
		return true
	end
	if Game.assigned_rumour(rumour.master, seen) == nil and Game.read_rumour() == nil then
		S.blocked = `couldn't read the new rumour from {rumour.master}`
		S.finished = true
		return false
	end
	return true
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	Game.setup_antiban()
	Toplevel.escape_clear()
	for _, item in pairs(Wornitems.worn() or {}) do
		local name = Item.name(item.id)
		if name then
			table.insert(S.start_worn, name)
		end
	end

	local charges = Quetzal.charges(true)
	local rank = Read.held_whistle()
	local low = if rank then CONST.WHISTLES[rank].recharge_at else nil
	if charges ~= nil and low ~= nil and charges <= low[2] then
		charges = Quetzal.charges() or charges
	end
	Log.log(NAME, if charges ~= nil then `Quetzal whistle charges: {charges}` else "No quetzal whistle charges read")
	for _ = 1, CONST.RUMOUR.READ_ATTEMPTS do
		if Game.read_rumour() then
			break
		end
		Toplevel.escape_clear()
		Random.sleep(600, 1400)
	end
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
	local me = s.position
	if me and (S.progress_tile == nil or Walker.distance(me, S.progress_tile :: Host.Tile) > CONST.PROGRESS_TILES) then
		S.progress_tile = me
		S.last_progress_at = time()
	end
end

function Loop.report_counters()
	stats.catches = if S.task then S.task.job.catches else stats.catches
	local key = `{stats.rumours}/{stats.catches}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "rumours", label = "Rumours", value = stats.rumours },
		{ id = "catches", label = "Catches", value = stats.catches },
		{ id = "failures", label = "Failures", value = stats.failures },
	})
end

function Loop.restart_hunt(): boolean
	local t = CONFIG.timeouts
	local now = time()
	local recent: { number } = {}
	for _, at in ipairs(S.restarts) do
		if now - at < t.restart_window_ms then
			table.insert(recent, at)
		end
	end
	S.restarts = recent
	if S.rumour == nil or #recent >= t.max_restarts then
		return false
	end
	table.insert(S.restarts, now)
	Log.log(NAME, `{S.failures_in_row} failures in a row, starting the {S.rumour.prey} hunt over`)
	S.task = Read.new_task(S.rumour.prey)
	S.failures_in_row = 0
	return true
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		if Loop.restart_hunt() then
			return
		end
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.stop_level > 0 and (Stats.real_level("Hunter") or 0) >= CONFIG.stop_level then
		Log.log(NAME, `Reached Hunter level {CONFIG.stop_level}, stopping the script`)
		S.finished = true
		return
	elseif CONFIG.max_rumours > 0 and stats.rumours >= CONFIG.max_rumours then
		Log.log(NAME, `Reached {CONFIG.max_rumours} rumours, stopping the script`)
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

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	local state: State = if S.rumour == nil
		then "NO_RUMOUR"
		elseif Read.holds_part() then (if Read.packing() then "HUNT" else Read.chore(false) or "HAND_IN")
		else Read.prep_state() or (if S.task then "HUNT" else "NO_SOLVER")
	if skipped[state] then
		return "LOADING"
	end
	return state
end

function Handler.outcome(ok: boolean)
	if ok then
		S.failures_in_row = 0
	else
		S.failures_in_row += 1
		stats.failures += 1
	end
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	HUNT = function()
		local task = S.task :: Task
		if Read.should_eat() then
			Handler.outcome(Game.eat())
			return
		end
		local state = task.solver.state(task.job)
		local chore: State? = nil
		if CONST.CHORE_STATES[state] then
			chore = Read.chore(true)
		elseif not CONST.MID_CATCH_STATES[state] and not Read.holds_part() and Read.loot_full() then
			chore = Read.chore(true)
		end
		if chore then
			Handler.states[chore]()
			return
		end
		if state == "BLOCKED" then
			Log.log(NAME, `Can't hunt: {task.job.blocked}, stopping the script`)
			S.blocked = task.job.blocked
			S.finished = true
			return
		elseif state == "DONE" then
			return
		end
		local ok = task.solver.step(task.job, state)
		if not ok then
			Log.log(NAME, `{state} didn't work`)
		end
		Handler.outcome(ok)
	end,
	HAND_IN = function()
		Handler.outcome(Game.hand_in())
	end,
	BANK = function()
		Handler.outcome(Game.bank())
	end,
	KIT = function()
		Handler.outcome(Game.kit())
	end,
	SHOP = function()
		Handler.outcome(Game.shop())
	end,
	EQUIP = function()
		Handler.outcome(Game.equip())
	end,
	RECHARGE = function()
		Handler.outcome(Game.recharge())
	end,
	OPEN_SACK = function()
		Handler.outcome(Game.open_sack())
	end,
	OPEN_POUCH = function()
		Handler.outcome(Game.open_pouch())
	end,
	BURY = function()
		Handler.outcome(Game.bury())
	end,
	RELEASE = function()
		Handler.outcome(Game.release())
	end,
	DROP = function()
		Handler.outcome(Game.drop())
	end,
	BANK_LOOT = function()
		Handler.outcome(Game.bank_loot())
	end,
	NO_RUMOUR = function()
		Log.log(NAME, "No rumour to work on, stopping the script")
		S.blocked = "no rumour to work on"
		S.finished = true
	end,
	NO_SOLVER = function()
		local prey = S.rumour and S.rumour.prey or "this rumour"
		Log.log(NAME, `Ready, but there's no solver for {prey} yet, stopping the script`)
		S.blocked = `no solver for {prey} yet`
		S.finished = true
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

Loop.next_antiban = 0

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

		if state ~= "HUNT" and time() >= Loop.next_antiban and Antiban.do_async_tasks("outside") then
			Loop.next_antiban = time() + Random.int(CONST.ANTIBAN_GAP_MS[1], CONST.ANTIBAN_GAP_MS[2])
		end
		sleep(Random.int(60, 140))
	end
	Loop.wrap_up()
	Log.log(NAME, "Done")
end

Loop.run()
