--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
local varbit = Host.varbit
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local Chat = require("@lib/main/interfaces/chatbox/chat")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Chatbox = require("@lib/main/interfaces/chatbox/chatbox")
local Clickbox = require("@lib/main/clickbox")
local Consumables = require("@lib/main/consumables")
local GameState = require("@lib/main/game_state")
local Geometry = require("@lib/utils/math/geometry")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Item = require("@lib/utils/item")
local Keyboard = require("@lib/utils/input/keyboard")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Make = require("@lib/main/interfaces/chatbox/make")
local Minimap = require("@lib/main/interfaces/minimap")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Walker = require("@lib/main/walker")
local Widgets = require("@lib/main/interfaces/widgets")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local Triangle = Geometry.Triangle

local NAME = "Blast Furnace"

type Bar = {
	name: string,
	level: number,
	ore: string,
	ore_varbit: number,
	secondary: string?,
	secondary_varbit: number?,
	ratio: number,
	bar_varbit: number,
	gauntlets: boolean,
	ore_smelts_alone: boolean?,
}

local BARS: { Bar } = {
	{
		name = "Bronze bar",
		level = 1,
		ore = "Copper ore",
		ore_varbit = 959,
		secondary = "Tin ore",
		secondary_varbit = 950,
		ratio = 1,
		bar_varbit = 941,
		gauntlets = false,
	},
	{
		name = "Iron bar",
		level = 15,
		ore = "Iron ore",
		ore_varbit = 951,
		ratio = 0,
		bar_varbit = 942,
		gauntlets = false,
	},
	{
		name = "Silver bar",
		level = 20,
		ore = "Silver ore",
		ore_varbit = 956,
		ratio = 0,
		bar_varbit = 948,
		gauntlets = false,
	},
	{
		name = "Steel bar",
		level = 30,
		ore = "Iron ore",
		ore_varbit = 951,
		secondary = "Coal",
		secondary_varbit = 949,
		ratio = 1,
		bar_varbit = 943,
		gauntlets = false,
		ore_smelts_alone = true,
	},
	{
		name = "Gold bar",
		level = 40,
		ore = "Gold ore",
		ore_varbit = 955,
		ratio = 0,
		bar_varbit = 947,
		gauntlets = true,
	},
	{
		name = "Mithril bar",
		level = 50,
		ore = "Mithril ore",
		ore_varbit = 952,
		secondary = "Coal",
		secondary_varbit = 949,
		ratio = 2,
		bar_varbit = 944,
		gauntlets = false,
	},
	{
		name = "Adamantite bar",
		level = 70,
		ore = "Adamantite ore",
		ore_varbit = 953,
		secondary = "Coal",
		secondary_varbit = 949,
		ratio = 3,
		bar_varbit = 945,
		gauntlets = false,
	},
	{
		name = "Runite bar",
		level = 85,
		ore = "Runite ore",
		ore_varbit = 954,
		secondary = "Coal",
		secondary_varbit = 949,
		ratio = 4,
		bar_varbit = 946,
		gauntlets = false,
	},
}

local CONST = {
	REPORT = { counters_key = "" },
	DISPENSED = {
		{ name = "Bronze bar", varbit = 941 },
		{ name = "Iron bar", varbit = 942 },
		{ name = "Steel bar", varbit = 943 },
		{ name = "Mithril bar", varbit = 944 },
		{ name = "Adamantite bar", varbit = 945 },
		{ name = "Runite bar", varbit = 946 },
		{ name = "Gold bar", varbit = 947 },
		{ name = "Silver bar", varbit = 948 },
		{ name = "Lead bar", varbit = 18169 },
		{ name = "Cupronickel bar", varbit = 18170 },
	},
	COFFER_VARBIT = 5357,
	DISPENSER_VARBIT = 936,
	DISPENSER_HOT = 1,
	DISPENSER_REACH = 3,
	ICE_GLOVES = { "Ice gloves", "Smiths gloves (i)" },
	GAUNTLETS = "Goldsmith gauntlets",
	COAL_BAG = { "Coal bag", "Open coal bag" },
	BIG_BAG_CAPES = { "Smithing cape", "Smithing cape(t)", "Max cape" },
	BAG_SIZE = 27,
	ORE_PER_TRIP = 27,
	BIG_BAG_SIZE = 36,
	STAMINA = "Stamina potion(1..4)",
	COINS = "Coins",
	BELT = 9100,
	DISPENSER = "Bar dispenser",
	COFFER = "Coffer",
	FOREMAN = {
		name = "Blast Furnace Foreman",
		option = "Pay",
		fee = 2500,
		free_level = 60,
		paid_ms = 600000,
		renew_ms = 60000,
	},
	TEXT = {
		paid = "you can use the furnace for ten minutes",
		permission = "permission",
		coffer_query = "Deposit how much",
		bag_count = "the coal bag.- contains (%d+) piece",
		bag_empty = "^the coal bag is.-empty",
		took_bars = "from the dispenser",
		pot_full = "make sure all your ore smelts",
	},
	BARS_DUE_MS = 9000,
	BELT_MS = 3600,
	LOAD_MS = 15000,
	ARRIVE_SETTLE_MS = 1200,
	BANK_OPEN_MS = 10000,
	BANK_CONFIRM_MS = 3000,
	BANK_PANEL_MS = 1200,
	FIDGET_MS = 1500,
	WEAR_MS = 1800,
	NEAR_TILES = 2,
	CROWD_TILES = 1,
	INVENTORY_SLOTS = 28,
	TAKE_MS = 3000,
	BELT_FROM_BANK = 0.7,
	BANK_OPTIONS = { "Bank", "Use" },
	BELT_TILE = { x = 1942, y = 4967 },
	MAKE_SPACE = 0.95,
	BELT_SHOWN = 0.35,
	YAW_RANGE = { 55, 90 },
	ZOOM_RANGE = { 128, 145 },
	ZOOM_LIMIT = 155,
	ZOOM_PERCENT = { 0, 3 },
	BAG_MS = 2400,
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	bar = "Gold bar",
	coal_bag = true,
	cape = true,
	stamina = false,
	stamina_below = 40,
	coffer_min = 5000,
	coffer_deposit = 72000,
	max_bars = 0,
	timeouts = { idle_minutes = 5, max_failures = 6 },
	antiban = true,
}

local stats = { bars = 0, trips = 0, failures = 0 }

type Trip = {
	pot_ore: number,
	pot_coal: number,
	ore: number,
	coal: number,
}

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	bar: Bar,
	gauntlets: boolean,
	bag_size: number,
	bag_coal: number?,
	trip: Trip?,
	pot_full: boolean,
	gold_take: boolean,
	deposited: { Unwanted },
	paid_until: number,
	permission_needed: boolean,
	coffer_coins: number,
	bars_due_until: number,
	belt_clear_at: number,
	seen_uid: number,
	warned_iron: boolean,
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	bar = BARS[5],
	gauntlets = false,
	bag_size = 0,
	bag_coal = nil,
	trip = nil,
	pot_full = false,
	gold_take = false,
	deposited = {},
	paid_until = 0,
	permission_needed = false,
	coffer_coins = 0,
	bars_due_until = 0,
	belt_clear_at = 0,
	seen_uid = -1,
	warned_iron = false,
	skip = {},
}

type Furnace = {
	ore: number,
	secondary: number,
	dispensed: number,
	coffer: number,
	cooled: boolean,
}

type Snapshot = {
	state: ClientState,
	me: Host.Tile,
	smithing: number,
	free_slots: number,
	ore: number,
	secondary: number,
	bars: number,
	coins: number,
	furnace: Furnace,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "BANK"
	| "TAKE"
	| "CHAT"
	| "FOREMAN"
	| "COFFER"
	| "LOAD"
	| "EMPTY_BAG"
	| "COLLECT"
	| "WAIT_BARS"

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.bar_by_name(name: string): Bar
	for _, bar in ipairs(BARS) do
		if bar.name == name then
			return bar
		end
	end
	return BARS[5]
end

function Read.uses_bag(): boolean
	return S.bag_size > 0
end

function Read.dispensed(): number
	local total = 0
	for _, d in ipairs(CONST.DISPENSED) do
		total += varbit(d.varbit) or 0
	end
	return total
end

function Read.furnace(): Furnace
	local bar = S.bar
	return {
		ore = varbit(bar.ore_varbit) or 0,
		secondary = if bar.secondary_varbit then varbit(bar.secondary_varbit) or 0 else 0,
		dispensed = Read.dispensed(),
		coffer = varbit(CONST.COFFER_VARBIT) or 0,
		cooled = varbit(CONST.DISPENSER_VARBIT) ~= CONST.DISPENSER_HOT,
	}
end

function Read.smithing(s: ClientState): number
	for _, skill in ipairs(s.skills or {}) do
		if skill.name == "Smithing" then
			return skill.level
		end
	end
	return 0
end

function Read.bar_names(): { string }
	local names = {}
	for _, d in ipairs(CONST.DISPENSED) do
		table.insert(names, d.name)
	end
	return names
end

local ALL_BARS = Read.bar_names()

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	local bar = S.bar
	snap = {
		state = state,
		me = { x = state.position.x, y = state.position.y },
		smithing = Read.smithing(state),
		free_slots = Inventory.free_slots() or 0,
		ore = Inventory.count_ex(bar.ore) or 0,
		secondary = if bar.secondary then Inventory.count_ex(bar.secondary) or 0 else 0,
		bars = Inventory.count_ex(ALL_BARS) or 0,
		coins = Inventory.count_ex(CONST.COINS) or 0,
		furnace = Read.furnace(),
	}
	return true
end

function Read.pays_foreman(): boolean
	return snap.smithing < CONST.FOREMAN.free_level
end

function Read.foreman_due(): boolean
	if not Read.pays_foreman() then
		return false
	end
	if S.permission_needed then
		return true
	end
	return S.paid_until > 0 and time() >= S.paid_until - CONST.FOREMAN.renew_ms
end

function Read.bars_coming(f: Furnace): boolean
	if f.ore == 0 then
		return time() < S.bars_due_until
	end
	return f.secondary >= S.bar.ratio * f.ore
end

function Read.read_messages()
	for _, m in ipairs(Chat.new_messages(S.seen_uid) or {}) do
		S.seen_uid = m.uid
		local text = string.lower(m.text)
		local game = m.kind == Chat.MessageType.GAME
		local bag_count = if game then string.match(text, CONST.TEXT.bag_count) else nil
		if bag_count then
			S.bag_coal = tonumber(bag_count)
		elseif game and string.find(text, CONST.TEXT.bag_empty) then
			S.bag_coal = 0
		elseif string.find(text, CONST.TEXT.pot_full, 1, true) then
			S.pot_full = true
			Log.log(NAME, "The pot is full of coal, banking the coal")
		elseif string.find(text, CONST.TEXT.paid, 1, true) then
			S.paid_until = time() + CONST.FOREMAN.paid_ms
			S.permission_needed = false
			Log.log(NAME, "The foreman lets us use the furnace for ten minutes")
		elseif string.find(text, CONST.TEXT.permission, 1, true) then
			S.permission_needed = true
			S.bars_due_until = 0
			Log.log(NAME, "The foreman wants paying")
		end
	end
end

function Read.dialog_open(): boolean
	if #(ChatOptions.get() or {}) > 0 then
		return true
	end
	local prompt = ChatOptions.continue_widget()
	if prompt == nil or Chat.clean(prompt.text or "") == ChatOptions.WAIT_TEXT then
		return false
	end
	return not string.find(string.lower(Chatbox.text() or ""), CONST.TEXT.took_bars, 1, true)
end

function Read.belt_walk(): boolean
	local me = Read.position() or snap.me
	local tile = CONST.BELT_TILE
	return math.max(math.abs(me.x - tile.x), math.abs(me.y - tile.y)) > CONST.NEAR_TILES
end

function Read.position(): Host.Tile?
	local p = game_state().position
	return if p then { x = p.x, y = p.y } else nil
end

function Read.in_bank(item: Item.Item | { Item.Item }): boolean
	return (Bankmain.count_ex(item) or 0) > 0
end

function Read.gold_buffer(): boolean
	return S.gauntlets and CONFIG.stamina
end

function Read.wait_tile(dispenser: Host.Loc): Host.Tile
	local x, y = dispenser.x, dispenser.y
	local tiles = { { x = x, y = y - 1 }, { x = x - 1, y = y }, { x = x - 1, y = y - 1 } }
	local liked = tiles[Biometrics.get_biometric(Biometrics.LIKES) % #tiles + 1]
	local pull = 1 + 2 * Biometrics.get_probability(Biometrics.PATTERN)
	return Random.weighted(tiles, function(t: Host.Tile): number
		return if t == liked then pull else 1
	end) or liked
end

function Read.bag_counts(): boolean
	return S.bar.secondary == "Coal" and not S.bar.ore_smelts_alone
end

function Read.bag_needed(): boolean
	local bar, trip = S.bar, S.trip
	if trip == nil or (S.bag_coal or 0) < S.bag_size then
		return true
	end
	local coal_after = trip.pot_coal + trip.coal - bar.ratio * (trip.pot_ore + trip.ore)
	local next_trip = bar.ratio * CONST.ORE_PER_TRIP - (if Read.bag_counts() then S.bag_size else 0)
	return coal_after < next_trip + S.bag_size
end

function Read.wearing_ice(): boolean
	return Wornitems.contains_any(CONST.ICE_GLOVES)
end

function Read.wearing_big_cape(): boolean
	return Wornitems.contains_any(CONST.BIG_BAG_CAPES)
end

function Read.has_ice(): boolean
	return Read.wearing_ice() or Inventory.contains_any(CONST.ICE_GLOVES)
end

function Read.keep(): { Item.Item }
	local keep: { any } = { CONST.ICE_GLOVES[1], CONST.ICE_GLOVES[2] }
	if S.gauntlets then
		table.insert(keep, CONST.GAUNTLETS)
	end
	if Read.uses_bag() then
		table.insert(keep, CONST.COAL_BAG[1])
		table.insert(keep, CONST.COAL_BAG[2])
	end
	return keep
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
	Antiban.set_zoom_range(CONST.ZOOM_PERCENT[1], CONST.ZOOM_PERCENT[2])
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Smithing" }
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
	Antiban.add_walk_task(AntibanTasks.small_camera_rotation, 4 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_tab, 6 * MINUTE, 0.33)

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_pitch_change, 45 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_zoom_change, 60 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_player, 120 * SECOND, 0.4, "game")

	Antiban.add_async_task(AntibanTasks.random_tab, 60 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 80 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.walk_tasks()
	Loop.keep_camera()
	if CONFIG.antiban and S.antiban_ready and Antiban.do_async_tasks("game") then
		Handler.wait(function()
			return not Mouse.busy()
		end, CONST.FIDGET_MS)
	end
end

function Game.stop(reason: string)
	Log.log(NAME, `{reason}, stopping the script`)
	S.finished = true
end

function Game.fail(reason: string)
	Log.log(NAME, reason)
	S.failures_in_row += 1
	stats.failures += 1
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	local last = Chat.last_message()
	S.seen_uid = if last then last.uid else -1

	local smithing = Stats.get("Smithing")
	local level = smithing and smithing.level or 0
	if level < S.bar.level then
		Game.stop(`{S.bar.name} needs {S.bar.level} Smithing, you have {level}`)
		return
	end
	if Objects.nearest(CONST.BELT, snap.me) == nil then
		Game.stop("Start at the Blast Furnace")
		return
	end
	S.bag_size = 0
	if CONFIG.coal_bag and S.bar.secondary == "Coal" then
		S.bag_size = if Read.wearing_big_cape() then CONST.BIG_BAG_SIZE else CONST.BAG_SIZE
	end
	if Read.pays_foreman() then
		Log.log(
			NAME,
			`Smithing is under {CONST.FOREMAN.free_level}, the foreman will be paid {CONST.FOREMAN.fee} coins every ten minutes`
		)
	end
	Minimap.set_run(true)
	Camera.face_enabled = false

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
	local key = `{stats.bars}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "bars", label = "Bars", value = stats.bars, hourly = true },
		{ id = "trips", label = "Bar trips", value = stats.trips },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "trips" },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	if idle >= t.idle_minutes * 60000 then
		Game.stop(`Stuck: no xp for {t.idle_minutes} minutes`)
	elseif S.failures_in_row >= t.max_failures then
		Game.stop(`Stuck: {S.failures_in_row} failures in a row`)
	elseif CONFIG.max_bars > 0 and stats.bars >= CONFIG.max_bars then
		Game.stop(`Made {stats.bars} bars`)
	end
end

function Loop.keep_camera()
	local zoom = Camera.zoom()
	if zoom and zoom > CONST.ZOOM_LIMIT then
		Camera.set_zoom(Random.int(CONST.ZOOM_RANGE[1], CONST.ZOOM_RANGE[2]))
	end
	local yaw = Camera.yaw_degrees()
	local range = CONST.YAW_RANGE
	if yaw == nil or (yaw >= range[1] and yaw <= range[2]) then
		return
	end
	Camera.set_yaw_degrees(Random.int(range[1], range[2]), "keys")
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
	Read.read_messages()
	Loop.watch_progress(s)
	Loop.report_counters()

	local f = snap.furnace
	if Bankmain.is_open() then
		return "BANK"
	end
	if Make.is_open() then
		return "TAKE"
	end
	if Read.dialog_open() and not skipped["CHAT"] then
		return "CHAT"
	end
	if snap.coins > 0 then
		if Read.foreman_due() and snap.coins >= CONST.FOREMAN.fee then
			return "FOREMAN"
		end
		if S.coffer_coins > 0 and not skipped["COFFER"] then
			return "COFFER"
		end
		return "BANK"
	end
	if Read.foreman_due() then
		return "BANK"
	end
	if snap.bars > 0 then
		return if not Read.gold_buffer() and f.dispensed > 0 and snap.free_slots > 0 then "COLLECT" else "BANK"
	end
	if snap.ore > 0 or snap.secondary > 0 then
		return if S.pot_full and snap.ore == 0 then "BANK" else "LOAD"
	end
	if (S.bag_coal or 0) > 0 and snap.free_slots > 0 and Read.bag_needed() then
		return "EMPTY_BAG"
	end
	if Read.gold_buffer() then
		return if S.gold_take and f.dispensed > 0 then "COLLECT" else "BANK"
	end
	if f.dispensed > 0 then
		return "COLLECT"
	end
	if Read.bars_coming(f) and not skipped["WAIT_BARS"] then
		return "WAIT_BARS"
	end
	return "BANK"
end

function Handler.wait(check: () -> boolean, timeout_ms: number): boolean
	return Widgets.wait_until(check, timeout_ms, 50)
end

function Handler.deposit_unwanted(): boolean
	if not Bankmain.inventory.contains_different(Read.keep()) then
		return true
	end
	return Bankmain.deposit_different(Read.keep())
end

type Unwanted = { id: number, name: string? }

function Read.bank_inventory_shown(): boolean
	local first = (Inventory.items() or {})[1]
	return first == nil or Bankmain.inventory.box(first.slot) ~= nil
end

function Read.unwanted(): { Unwanted }
	local keep = Item.matcher(Read.keep())
	local seen: { [number]: boolean } = {}
	local out: { Unwanted } = {}
	for _, s in ipairs(Inventory.items() or {}) do
		if not Item.matches(keep, s.id, s.name) and not seen[s.id] then
			seen[s.id] = true
			table.insert(out, { id = s.id, name = s.name })
		end
	end
	return out
end

function Read.kept_slots(): number
	local keep = Item.matcher(Read.keep())
	local kept = 0
	for _, s in ipairs(Inventory.items() or {}) do
		if Item.matches(keep, s.id, s.name) then
			kept += 1
		end
	end
	return kept
end

function Handler.queue_deposit(): boolean
	S.deposited = Read.unwanted()
	for _, u in ipairs(S.deposited) do
		if not Bankmain.inventory.interact(u.id, "Deposit-All") then
			return false
		end
	end
	return true
end

function Handler.prepare_gloves(): boolean
	if not Read.has_ice() then
		if not Read.in_bank(CONST.ICE_GLOVES) then
			Game.stop("No ice gloves (or smiths gloves (i)) to take the bars with")
			return false
		end
		if not Bankmain.withdraw(CONST.ICE_GLOVES, 1, false) then
			return false
		end
	end
	if S.gauntlets and not Wornitems.contains(CONST.GAUNTLETS) and not Bankmain.inventory.contains(CONST.GAUNTLETS) then
		if not Read.in_bank(CONST.GAUNTLETS) then
			Log.log(NAME, "No goldsmith gauntlets, smelting gold without them")
			S.gauntlets = false
			return Handler.prepare_gloves()
		end
		if not Bankmain.withdraw(CONST.GAUNTLETS, 1, false) then
			return false
		end
	end
	if S.gauntlets and not Wornitems.contains(CONST.GAUNTLETS) then
		if not Bankmain.inventory.interact(CONST.GAUNTLETS, "Wear") then
			return false
		end
		return Handler.wait(function()
			return Wornitems.contains(CONST.GAUNTLETS)
		end, 3000)
	end
	if not S.gauntlets and not Read.wearing_ice() then
		if not Bankmain.inventory.interact(CONST.ICE_GLOVES, "Wear") then
			return false
		end
		return Handler.wait(Read.wearing_ice, 3000)
	end
	return true
end

function Handler.use_bag(interact: (any, string) -> boolean, action: string): boolean
	Read.read_messages()
	if not interact(CONST.COAL_BAG, action) then
		return false
	end
	S.bag_coal = nil
	return Handler.wait(function()
		Read.read_messages()
		return S.bag_coal ~= nil
	end, CONST.BAG_MS)
end

function Handler.prepare_bag(): boolean
	if not Read.uses_bag() then
		return true
	end
	if not Bankmain.inventory.contains_any(CONST.COAL_BAG) then
		if not Read.in_bank(CONST.COAL_BAG) then
			Log.log(NAME, "No coal bag, carrying coal in the inventory only")
			S.bag_size, S.bag_coal = 0, nil
			return true
		end
		if not Bankmain.withdraw(CONST.COAL_BAG, 1, false) then
			return false
		end
		S.bag_coal = nil
	end
	return Handler.prepare_cape()
end

function Handler.prepare_cape(): boolean
	local capes = CONST.BIG_BAG_CAPES
	if not Read.wearing_big_cape() then
		if not CONFIG.cape then
			S.bag_size = CONST.BAG_SIZE
			return true
		end
		if not Bankmain.inventory.contains_any(capes) then
			if not Read.in_bank(capes) then
				S.bag_size = CONST.BAG_SIZE
				return true
			end
			if not Bankmain.withdraw(capes, 1, false) then
				return false
			end
		end
		if not Bankmain.inventory.interact(capes, "Wear") or not Handler.wait(Read.wearing_big_cape, 3000) then
			return false
		end
		Log.log(NAME, `Wearing the cape, the coal bag holds {CONST.BIG_BAG_SIZE} coal`)
		if not Handler.deposit_unwanted() then
			return false
		end
	end
	S.bag_size = CONST.BIG_BAG_SIZE
	return true
end

function Handler.bag_offers(option: string): boolean
	return Minimenu.has(option, "coal bag")
end

function Handler.fill_bag(): boolean
	if not Read.uses_bag() or S.bag_coal == S.bag_size then
		return true
	end
	if not Read.in_bank("Coal") then
		return true
	end
	if S.bag_coal == 0 then
		if not Bankmain.inventory.interact(CONST.COAL_BAG, "Fill") then
			return false
		end
		S.bag_coal = nil
		return true
	end
	if not Handler.use_bag(Bankmain.inventory.interact, "Empty") then
		if not Handler.bag_offers("Fill") then
			Log.log(NAME, "The coal bag didn't empty into the bank")
			return false
		end
		S.bag_coal = 0
	end
	if Handler.use_bag(Bankmain.inventory.interact, "Fill") then
		return true
	end
	Log.log(NAME, "The coal bag didn't fill")
	return false
end

function Handler.coins_needed(): number
	local needed = 0
	if Read.foreman_due() then
		needed += CONST.FOREMAN.fee
	end
	S.coffer_coins = 0
	if snap.furnace.coffer < CONFIG.coffer_min then
		S.coffer_coins = CONFIG.coffer_deposit
		needed += CONFIG.coffer_deposit
	end
	return needed
end

function Handler.withdraw_coins(): boolean?
	local needed = Handler.coins_needed()
	if needed == 0 then
		return false
	end
	local have = Bankmain.count_ex(CONST.COINS) or 0
	if have < needed then
		if Read.foreman_due() and have < CONST.FOREMAN.fee then
			Game.stop("Not enough coins to pay the foreman")
			return nil
		end
		S.coffer_coins = have - (if Read.foreman_due() then CONST.FOREMAN.fee else 0)
		needed = have
		if S.coffer_coins <= 0 then
			Game.stop("Out of coins for the coffer")
			return nil
		end
		Log.log(NAME, "Low on coins, putting the last of them in the coffer")
	end
	if not Bankmain.withdraw(CONST.COINS, needed, false) then
		return nil
	end
	return true
end

function Handler.drink_stamina(): boolean
	if not CONFIG.stamina then
		return true
	end
	if (Player.run_energy() or 100) >= CONFIG.stamina_below or (Consumables.remaining("stamina") or 0) > 0 then
		return true
	end
	if not Read.in_bank(CONST.STAMINA) then
		return true
	end
	if not Bankmain.withdraw(CONST.STAMINA, 1, false) then
		return false
	end
	if not Bankmain.inventory.interact(CONST.STAMINA, "Drink") then
		return false
	end
	Handler.wait(function()
		return (Consumables.remaining("stamina") or 0) > 0
	end, 2400)
	return Handler.deposit_unwanted()
end

function Handler.plan_trip(): string?
	local bar = S.bar
	local secondary = bar.secondary
	if secondary == nil then
		return bar.ore
	end
	local wait = math.ceil(S.belt_clear_at - time())
	if wait > 0 then
		sleep(wait)
	end
	local f = Read.furnace()
	S.trip = { pot_ore = f.ore, pot_coal = f.secondary, ore = 0, coal = 0 }
	local slots = CONST.INVENTORY_SLOTS - Read.kept_slots()
	local carried = f.secondary + (if Read.bag_counts() then S.bag_size else 0)
	if carried >= bar.ratio * (f.ore + slots) then
		return bar.ore
	end
	return secondary
end

function Handler.withdraw_trip(): boolean
	local item = Handler.plan_trip()
	if item == nil then
		return false
	end
	if S.bar.secondary == "Coal" and not Handler.fill_bag() then
		return false
	end
	if not Read.in_bank(item) then
		if item == "Coal" and Read.uses_bag() then
			return Handler.confirm_bank(nil)
		end
		Game.stop(`Out of {item}`)
		return false
	end
	if not Bankmain.set_quantity(0) or not Bankmain.withdraw_selected(item, false) then
		return false
	end
	return Handler.confirm_bank(item)
end

function Handler.confirm_bank(item: string?): boolean
	local function deposited(): boolean
		for _, u in ipairs(S.deposited) do
			if u.name ~= item and Inventory.contains(u.id) then
				return false
			end
		end
		return true
	end
	return Handler.wait(function()
		Read.read_messages()
		return deposited()
			and (item == nil or Bankmain.inventory.contains(item))
			and (not Read.uses_bag() or S.bag_coal ~= nil)
	end, CONST.BANK_CONFIRM_MS)
end

function Handler.hover_deposit()
	local keep = Item.matcher(Read.keep())
	for _, s in ipairs(Inventory.items() or {}) do
		if not Item.matches(keep, s.id, s.name) then
			local w = Inventory.box(s.slot)
			if w then
				Mouse.move_async({ x1 = w.x, y1 = w.y, x2 = w.x + w.width - 1, y2 = w.y + w.height - 1 })
			end
			return
		end
	end
end

function Handler.open_bank(): boolean
	local bank = Bankmain.nearest()
	local chest = if bank then bank.loc else nil
	if chest == nil or not Read.in_view(chest) or not Toplevel.escape_clear() then
		return Bankmain.open(bank)
	end
	if not Objects.interact(chest, CONST.BANK_OPTIONS, false) then
		return false
	end
	Game.walk_tasks()
	Handler.hover_deposit()
	return Handler.arrive(Bankmain.is_open, CONST.BANK_OPEN_MS)
end

function Handler.arrive(done: () -> boolean, timeout_ms: number): boolean
	local still_since: number? = nil
	Handler.wait(function()
		if done() then
			return true
		end
		if Player.in_transit() then
			still_since = nil
		elseif still_since == nil then
			still_since = time()
		end
		return still_since ~= nil and time() - still_since >= CONST.ARRIVE_SETTLE_MS
	end, timeout_ms)
	return done()
end

function Handler.bank()
	if not Bankmain.is_open() then
		if not Handler.open_bank() then
			Game.fail("The bank didn't open")
			S.skip["BANK"] = true
			return
		end
	end
	Handler.wait(Read.bank_inventory_shown, CONST.BANK_PANEL_MS)
	local before_bars = Bankmain.inventory.count_ex(ALL_BARS) or 0
	if not Handler.queue_deposit() then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if before_bars > 0 then
		stats.trips += 1
	end
	S.pot_full = false
	if not Handler.prepare_gloves() or S.finished then
		Game.fail("Couldn't sort out the gloves")
		return
	end
	if not Handler.prepare_bag() then
		Game.fail("Couldn't sort out the coal bag")
		return
	end
	local coins = Handler.withdraw_coins()
	if coins == nil then
		if not S.finished then
			Game.fail("Couldn't withdraw coins")
		end
		return
	end
	if coins then
		Bankmain.close()
		return
	end
	if not Handler.drink_stamina() then
		Game.fail("Couldn't drink a stamina potion")
		return
	end
	if Read.dispensed() > 0 and not Read.gold_buffer() then
		Bankmain.close()
		return
	end
	if Read.gold_buffer() and Read.dispensed() > 0 and not Read.in_bank(S.bar.ore) then
		Log.log(NAME, `Out of {S.bar.ore}, taking the last bars`)
		S.gold_take = true
		Bankmain.close()
		return
	end
	if not Handler.withdraw_trip() then
		if not S.finished then
			Game.fail("Couldn't withdraw the trip")
		end
		return
	end
	if Read.gold_buffer() and not Handler.gold_gloves() then
		Game.fail("Couldn't put on the ice gloves")
		return
	end
	S.failures_in_row = 0
	Handler.leave_bank()
end

function Handler.gold_gloves(): boolean
	S.gold_take = Read.dispensed() > 0
	if not S.gold_take or Read.wearing_ice() then
		return true
	end
	if not Bankmain.inventory.interact(CONST.ICE_GLOVES, "Wear") then
		return false
	end
	return Handler.wait(Read.wearing_ice, CONST.WEAR_MS)
end

function Read.in_view(loc: Host.Loc?): boolean
	if loc == nil then
		return false
	end
	local box = Objects.clickbox(loc)
	return box ~= nil and Clickbox.target(box, loc.name or "object") ~= nil
end

function Read.shown_share(loc: Host.Loc?): number
	local box = if loc then Objects.clickbox(loc) else nil
	local view = Toplevel.viewport()
	if box == nil or box.triangles == nil or view == nil then
		return 0
	end
	local blockers = Toplevel.blockers() or {}
	local total, shown = 0, 0
	for _, t in ipairs(box.triangles) do
		local area = Triangle.area(t)
		local c = Triangle.centroid(t)
		total += area
		if Toplevel.is_visible({ x = math.round(c.x), y = math.round(c.y) }, view, blockers) then
			shown += area
		end
	end
	return if total > 0 then shown / total else 0
end

function Handler.belt(): Host.Loc?
	return Objects.nearest(CONST.BELT, snap.me)
end

function Handler.belt_shown(): boolean
	return Read.shown_share(Handler.belt()) >= CONST.BELT_SHOWN
end

function Handler.leave_bank()
	if Biometrics.random_boolean(CONST.BELT_FROM_BANK) and Handler.belt_shown() then
		Handler.load()
		return
	end
	Bankmain.close()
	Handler.hover_belt()
end

function Handler.take_all(name: string, only: boolean): boolean
	if not Make.set_amount("All") then
		return false
	end
	if only and Biometrics.random_boolean(CONST.MAKE_SPACE) then
		Keyboard.key_press(Keyboard.keys.SPACE)
		return true
	end
	return Make.make(name)
end

function Handler.take()
	local before = Inventory.count_ex(ALL_BARS) or 0
	local kinds: { string } = {}
	for _, d in ipairs(CONST.DISPENSED) do
		if (varbit(d.varbit) or 0) > 0 then
			table.insert(kinds, d.name)
		end
	end
	if #kinds > 0 and not Handler.take_all(kinds[1], #kinds == 1) then
		Game.fail(`Couldn't take the {kinds[1]}s`)
		return
	end
	local gold = Read.gold_buffer() and S.gold_take
	if not gold then
		Handler.hover_bank(nil)
	end
	local taken = Handler.wait(function()
		return (Inventory.count_ex(ALL_BARS) or 0) > before
	end, CONST.TAKE_MS)
	if gold then
		S.gold_take = false
		Handler.wear_gauntlets()
		Handler.hover_bank(nil)
	end
	if taken then
		local got = (Inventory.count_ex(ALL_BARS) or 0) - before
		stats.bars += got
		S.failures_in_row = 0
		S.last_progress_at = time()
		Log.log(NAME, `Took {got} bars ({stats.bars} in all)`)
	end
end

function Handler.chat()
	if ChatOptions.contains_continue() then
		ChatOptions.continue_chat()
		return
	end
	if ChatOptions.find("Yes") then
		ChatOptions.select("Yes")
		return
	end
	for _, o in ipairs(ChatOptions.get() or {}) do
		if string.match(string.lower(o.text), "^no%f[%A]") then
			Log.log(NAME, `Declining the dialogue: {o.text}`)
			ChatOptions.select(o.text)
			return
		end
	end
	Log.log(NAME, `Closing the dialogue: {ChatOptions.title() or "?"}`)
	Toplevel.escape_clear()
	S.skip["CHAT"] = true
end

function Handler.foreman()
	local npc = Npcs.nearest(CONST.FOREMAN.name, snap.me)
	if npc == nil then
		Game.fail("The foreman isn't here")
		return
	end
	if not Npcs.interact(npc, CONST.FOREMAN.option) or not ChatOptions.wait_option("Yes", false, 4000) then
		Game.fail("The foreman didn't ask for the fee")
		return
	end
	ChatOptions.select("Yes")
	Handler.wait(function()
		Read.read_messages()
		return S.paid_until > time()
	end, 3000)
	if S.paid_until > time() then
		S.failures_in_row = 0
	end
end

function Handler.coffer()
	local amount = math.min(S.coffer_coins, snap.coins)
	local loc = Objects.nearest(CONST.COFFER, snap.me)
	if loc == nil then
		Game.fail("The coffer isn't here")
		S.skip["COFFER"] = true
		return
	end
	if not Objects.interact(loc, "Use") or not ChatOptions.wait_option("Deposit", false, 4000) then
		Game.fail("The coffer didn't open")
		S.skip["COFFER"] = true
		return
	end
	local before = varbit(CONST.COFFER_VARBIT) or 0
	if not ChatOptions.select("Deposit") or not Chat.answer_query(CONST.TEXT.coffer_query, tostring(amount), 3000) then
		Game.fail("Couldn't deposit into the coffer")
		S.skip["COFFER"] = true
		return
	end
	if Handler.wait(function()
		return (varbit(CONST.COFFER_VARBIT) or 0) > before
	end, 3000) then
		Log.log(NAME, `Put {amount} coins in the coffer`)
		S.coffer_coins = 0
		S.failures_in_row = 0
	else
		Game.fail("The coffer didn't take the coins")
		S.skip["COFFER"] = true
	end
end

function Handler.warn_iron(f: Furnace)
	if S.bar.name == "Iron bar" and f.secondary == 0 and not S.warned_iron then
		local coal = varbit(949) or 0
		if coal > 0 then
			S.warned_iron = true
			Log.log(NAME, `The furnace holds {coal} coal: that much iron ore will come out as steel`)
		end
	end
end

function Handler.carried(): (number, number)
	local bar = S.bar
	return Inventory.count_ex(bar.ore) or 0, if bar.secondary then Inventory.count_ex(bar.secondary) or 0 else 0
end

function Handler.load()
	local ore_before, secondary_before = Handler.carried()
	local carried = ore_before + secondary_before
	Handler.warn_iron(Read.furnace())
	local belt = Objects.nearest(CONST.BELT, snap.me)
	if belt == nil then
		Game.fail("The conveyor belt isn't here")
		return
	end
	local walking = Read.belt_walk()
	if not Handler.click_belt(belt) then
		Game.fail("Couldn't use the conveyor belt")
		return
	end
	local hovered = false
	local function prehover()
		if not hovered and not Bankmain.is_open() then
			hovered = true
			if walking then
				Game.walk_tasks()
			end
			Handler.prehover_next(ore_before > 0)
		end
	end
	prehover()
	local function went_on(): boolean
		local ore, secondary = Handler.carried()
		return ore + secondary < carried
	end
	local loaded = Handler.arrive(function(): boolean
		prehover()
		return went_on() or Read.dialog_open()
	end, CONST.LOAD_MS) and went_on()
	local ore_after, secondary_after = Handler.carried()
	if S.trip then
		S.trip.ore += ore_before - ore_after
		S.trip.coal += secondary_before - secondary_after
	end
	if ore_after < ore_before then
		S.bars_due_until = time() + CONST.BARS_DUE_MS
	end
	if loaded then
		S.belt_clear_at = time() + CONST.BELT_MS
		S.failures_in_row = 0
	else
		Game.fail("Nothing went on the belt")
	end
end

function Handler.prehover_next(ore_loaded: boolean)
	if (S.bag_coal or 0) > 0 and Read.bag_needed() then
		Handler.hover_bag()
		return
	end
	local at = CONST.BELT_TILE
	local bars_next = if Read.gold_buffer()
		then S.gold_take
		else ore_loaded or time() < S.bars_due_until or Read.furnace().ore > 0
	if not bars_next then
		Handler.hover_bank(at)
		return
	end
	local dispenser = Objects.nearest(CONST.DISPENSER, at)
	if dispenser then
		Objects.hover_async(dispenser, at)
	end
end

function Handler.hover_bag()
	local slot = Inventory.index_of(CONST.COAL_BAG)
	local w = if slot then Inventory.box(slot) else nil
	if w then
		Mouse.move_async({ x1 = w.x, y1 = w.y, x2 = w.x + w.width - 1, y2 = w.y + w.height - 1 })
	end
end

function Handler.hover_belt()
	local belt = Handler.belt()
	if belt then
		Objects.hover_async(belt)
	end
end

function Handler.hover_bank(at: Host.Tile?)
	local bank = Bankmain.nearest()
	if bank and bank.loc then
		Objects.hover_async(bank.loc, at)
	end
end

function Read.crowded(loc: Host.Loc): boolean
	local function near(x: number, y: number): boolean
		return math.abs(x - loc.x) <= CONST.CROWD_TILES and math.abs(y - loc.y) <= CONST.CROWD_TILES
	end
	for _, n in ipairs(Host.npcs() or {}) do
		if string.sub(n.name, 1, 5) ~= "<col=" and near(n.x, n.y) then
			return true
		end
	end
	local me = game_state().player_name
	for _, p in ipairs(Host.players() or {}) do
		if p.name ~= me and near(p.x, p.y) then
			return true
		end
	end
	return false
end

function Handler.click_belt(belt: Host.Loc): boolean
	return Objects.interact(belt, "Put-ore-on", false, nil, nil, Read.crowded(belt))
end

function Handler.empty_bag()
	local coal, room = S.bag_coal or 0, Inventory.free_slots() or 0
	local belt = Handler.belt()
	if belt == nil or room == 0 then
		Game.fail("Can't empty the coal bag here")
		return
	end
	Read.read_messages()
	S.bag_coal = nil
	local first = true
	while coal > 0 do
		if not first then
			Handler.hover_bag()
			Handler.wait(function()
				return (Inventory.count_ex("Coal") or 0) == 0
			end, CONST.BAG_MS)
		end
		first = false
		if not Inventory.interact(CONST.COAL_BAG, "Empty") then
			Game.fail("Couldn't empty the coal bag")
			return
		end
		if not Handler.click_belt(belt) then
			Game.fail("Couldn't use the conveyor belt")
			return
		end
		local moved = math.min(coal, room)
		coal -= moved
		if S.trip then
			S.trip.coal += moved
		end
	end
	Handler.prehover_next(false)
	local done = Handler.wait(function()
		Read.read_messages()
		return S.bag_coal == 0 and (Inventory.count_ex("Coal") or 0) == 0
	end, CONST.BAG_MS)
	S.belt_clear_at = time() + CONST.BELT_MS
	if done then
		S.failures_in_row = 0
	else
		Game.fail("The coal bag's coal didn't all go on the belt")
	end
end

function Handler.swap_to_ice(): boolean
	if Read.wearing_ice() then
		return true
	end
	if not Inventory.interact(CONST.ICE_GLOVES, "Wear") then
		return false
	end
	return Handler.wait(Read.wearing_ice, 2400)
end

function Handler.collect_gold()
	local dispenser = Objects.nearest(CONST.DISPENSER, snap.me)
	if dispenser == nil then
		Game.fail("The bar dispenser isn't here")
		return
	end
	if not Handler.swap_to_ice() then
		Game.fail("Couldn't put on the ice gloves")
		return
	end
	if not Objects.interact(dispenser, "Take", false) then
		sleep(Random.int(300, 600))
		return
	end
	if not Make.wait_open(CONST.TAKE_MS) then
		Game.fail("The dispenser didn't offer the bars")
		return
	end
	Handler.take()
end

function Handler.wear_gauntlets()
	if Wornitems.contains(CONST.GAUNTLETS) then
		return
	end
	if not Inventory.interact(CONST.GAUNTLETS, "Wear") then
		Game.fail("Couldn't put on the goldsmith gauntlets")
		return
	end
	Handler.wait(function()
		return Wornitems.contains(CONST.GAUNTLETS)
	end, CONST.WEAR_MS)
end

function Handler.collect()
	if Read.gold_buffer() then
		Handler.collect_gold()
		return
	end
	local f = snap.furnace
	if not f.cooled or (S.gauntlets and f.ore > 0) then
		Handler.wait_bars()
		return
	end
	if not Handler.swap_to_ice() then
		Game.fail("Couldn't put on the ice gloves")
		return
	end
	local dispenser = Objects.nearest(CONST.DISPENSER, snap.me)
	if dispenser == nil then
		Game.fail("The bar dispenser isn't here")
		return
	end
	if not Objects.interact(dispenser, "Take") then
		sleep(Random.int(300, 600))
		return
	end
	if not Make.wait_open(CONST.TAKE_MS) then
		Game.fail("The dispenser didn't offer the bars")
		return
	end
	Handler.take()
end

function Handler.wait_bars()
	local dispenser = Objects.nearest(CONST.DISPENSER, snap.me)
	if dispenser == nil then
		S.skip["WAIT_BARS"] = true
		return
	end
	if Objects.distance(dispenser, snap.me) > CONST.DISPENSER_REACH then
		Walker.walk(Read.wait_tile(dispenser), { near = 0 })
	end
	if S.gauntlets and snap.furnace.ore == 0 and Read.dispensed() > 0 then
		return
	end
	if not Objects.hovered(dispenser) then
		Objects.hover(dispenser)
	end
	local deadline = math.max(S.bars_due_until, time() + 1200)
	while time() < deadline do
		local f = Read.furnace()
		if f.dispensed > 0 and f.cooled and not (S.gauntlets and f.ore > 0) then
			return
		end
		if f.dispensed == 0 and f.ore == 0 and time() >= S.bars_due_until then
			S.skip["WAIT_BARS"] = true
			return
		end
		sleep(Random.int(80, 160))
	end
	S.bars_due_until = 0
end

function Handler.run_energy()
	if not Player.is_running() and (Player.run_energy() or 0) >= Random.int(15, 40) then
		Minimap.set_run(true)
	end
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	BANK = Handler.bank,
	TAKE = Handler.take,
	CHAT = Handler.chat,
	FOREMAN = Handler.foreman,
	COFFER = Handler.coffer,
	LOAD = Handler.load,
	EMPTY_BAG = Handler.empty_bag,
	COLLECT = Handler.collect,
	WAIT_BARS = Handler.wait_bars,
}

function Game.ask(): boolean
	local names = {}
	for _, bar in ipairs(BARS) do
		table.insert(names, bar.name)
	end
	local values = Host.form({
		title = NAME,
		submit = "Start",
		fields = {
			{ id = "bar", kind = "choice", label = "Bar", options = names, default = CONFIG.bar },
			{
				id = "coal_bag",
				kind = "check",
				label = "Use a coal bag (bars that need coal)",
				default = CONFIG.coal_bag,
			},
			{
				id = "cape",
				kind = "check",
				label = "Wear a smithing or max cape from the bank (the coal bag holds 36)",
				default = CONFIG.cape,
				enabled_by = "coal_bag",
			},
			{ id = "stamina", kind = "check", label = "Drink stamina potions from the bank", default = CONFIG.stamina },
			{
				id = "stamina_below",
				kind = "number",
				label = "Drink below run energy",
				default = CONFIG.stamina_below,
				min = 1,
				max = 100,
				integer = true,
				enabled_by = "stamina",
			},
			{
				id = "coffer_deposit",
				kind = "number",
				label = "Coins to put in the coffer each time (72,000 lasts an hour)",
				default = CONFIG.coffer_deposit,
				min = 1000,
				max = 10000000,
				integer = true,
			},
			{
				id = "max_bars",
				kind = "number",
				label = "Max bars (0 is unlimited)",
				default = CONFIG.max_bars,
				min = 0,
				max = 1000000,
				integer = true,
			},
		},
	})
	if values == nil then
		return false
	end
	Game.apply_settings(values)
	return true
end

function Game.apply_settings(values: { [string]: any })
	CONFIG.bar = values.bar
	CONFIG.coal_bag = values.coal_bag
	CONFIG.cape = values.cape
	CONFIG.stamina = values.stamina
	CONFIG.stamina_below = values.stamina_below
	CONFIG.coffer_deposit = values.coffer_deposit
	CONFIG.max_bars = values.max_bars
	S.bar = Read.bar_by_name(CONFIG.bar)
	S.gauntlets = S.bar.gauntlets
end

function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	local bar = S.bar
	Game.apply_settings(values)
	if bar ~= S.bar then
		Log.log(NAME, `Bar changed to {S.bar.name}`)
		S.bars_due_until = 0
	end
	Log.log(NAME, "Settings updated")
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	Log.log(NAME, `{NAME} started: {S.bar.name}`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		Game.poll_settings()
		Handler.states[state]()
		Handler.run_energy()

		if CONFIG.antiban and S.antiban_ready and state == "BANK" and not Bankmain.is_open() then
			Antiban.do_antiban()
		end
		sleep(Random.int(60, 140))
	end
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

Loop.run()
