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
local Chat = require("@lib/main/interfaces/chatbox/chat")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Consumables = require("@lib/main/consumables")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Item = require("@lib/utils/item")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Make = require("@lib/main/interfaces/chatbox/make")
local Minimap = require("@lib/main/interfaces/minimap")
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
	ICE_GLOVES = { "Ice gloves", "Smiths gloves (i)" },
	GAUNTLETS = "Goldsmith gauntlets",
	COAL_BAG = { "Coal bag", "Open coal bag" },
	BIG_BAG_CAPES = { "Smithing cape", "Smithing cape(t)", "Max cape" },
	BAG_SIZE = 27,
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
	},
	BARS_DUE_MS = 9000,
	BELT_MS = 3600,
	LOAD_MS = 4000,
	TAKE_MS = 3000,
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	bar = "Gold bar",
	coal_bag = true,
	stamina = false,
	stamina_below = 40,
	coffer_min = 5000,
	coffer_deposit = 72000,
	max_bars = 0,
	timeouts = { idle_minutes = 5, max_failures = 6 },
	antiban = true,
}

local stats = { bars = 0, trips = 0, failures = 0 }

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
		if string.find(text, CONST.TEXT.paid, 1, true) then
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

function Read.wearing_ice(): boolean
	return Wornitems.contains_any(CONST.ICE_GLOVES)
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
	Antiban.set_zoom_range(0, 30)
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

function Game.tiny_antiban()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_async_tasks("game")
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
		S.bag_size = if Wornitems.contains_any(CONST.BIG_BAG_CAPES) then CONST.BIG_BAG_SIZE else CONST.BAG_SIZE
	end
	if Read.pays_foreman() then
		Log.log(
			NAME,
			`Smithing is under {CONST.FOREMAN.free_level}, the foreman will be paid {CONST.FOREMAN.fee} coins every ten minutes`
		)
	end
	Minimap.set_run(true)

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
	if ChatOptions.contains_continue() or #(ChatOptions.get() or {}) > 0 then
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
		return if f.dispensed > 0 and snap.free_slots > 0 then "COLLECT" else "BANK"
	end
	if snap.ore > 0 or snap.secondary > 0 then
		return "LOAD"
	end
	if (S.bag_coal or 0) > 0 and snap.free_slots > 0 then
		return "EMPTY_BAG"
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

function Handler.prepare_gloves(): boolean
	if not Read.has_ice() then
		if not Bankmain.contains_any(CONST.ICE_GLOVES) then
			Game.stop("No ice gloves (or smiths gloves (i)) to take the bars with")
			return false
		end
		if not Bankmain.withdraw(CONST.ICE_GLOVES, 1, false) then
			return false
		end
	end
	if S.gauntlets and not Wornitems.contains(CONST.GAUNTLETS) and not Bankmain.inventory.contains(CONST.GAUNTLETS) then
		if not Bankmain.contains(CONST.GAUNTLETS) then
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

function Handler.coal_moved(action: string): number?
	local before_bank = Bankmain.count_ex("Coal") or 0
	local before_inv = Bankmain.inventory.count_ex("Coal") or 0
	if not Bankmain.inventory.interact(CONST.COAL_BAG, action) then
		return nil
	end
	local moved = 0
	Handler.wait(function()
		local bank = Bankmain.count_ex("Coal") or before_bank
		local inv = Bankmain.inventory.count_ex("Coal") or before_inv
		moved = (before_bank - bank) + (before_inv - inv)
		return moved ~= 0
	end, 1800)
	return moved
end

function Handler.prepare_bag(): boolean
	if not Read.uses_bag() then
		return true
	end
	if not Bankmain.inventory.contains_any(CONST.COAL_BAG) then
		if not Bankmain.contains_any(CONST.COAL_BAG) then
			Log.log(NAME, "No coal bag, carrying coal in the inventory only")
			S.bag_size, S.bag_coal = 0, nil
			return true
		end
		if not Bankmain.withdraw(CONST.COAL_BAG, 1, false) then
			return false
		end
		S.bag_coal = nil
	end
	if S.bag_coal == nil then
		local moved = Handler.coal_moved("Empty")
		if moved == nil then
			return false
		end
		S.bag_coal = 0
		Log.log(NAME, `Emptied the coal bag ({-moved} coal)`)
		return Handler.deposit_unwanted()
	end
	return true
end

function Handler.fill_bag(): boolean
	if not Read.uses_bag() or (S.bag_coal or 0) >= S.bag_size then
		return true
	end
	if not Bankmain.contains("Coal") then
		return true
	end
	local moved = Handler.coal_moved("Fill")
	if moved == nil or moved <= 0 then
		Log.log(NAME, "The coal bag didn't fill")
		return false
	end
	S.bag_coal = math.min((S.bag_coal or 0) + moved, S.bag_size)
	return true
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
	if not Bankmain.contains(CONST.STAMINA) then
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
	local wait = S.belt_clear_at - time()
	if wait > 0 then
		sleep(wait)
	end
	local f = Read.furnace()
	local slots = Bankmain.inventory.count_empty() or 0
	local carried = f.secondary + (if secondary == "Coal" then S.bag_size else 0)
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
	if not Bankmain.contains(item) then
		if item == "Coal" and (S.bag_coal or 0) > 0 then
			return true
		end
		Game.stop(`Out of {item}`)
		return false
	end
	if (Bankmain.inventory.count_empty() or 0) == 0 then
		return true
	end
	if not Bankmain.withdraw(item, 0, false) then
		return false
	end
	return Handler.wait(function()
		return Bankmain.inventory.contains(item)
	end, 2000)
end

function Handler.bank()
	if not Bankmain.is_open() then
		if not Bankmain.open() then
			Game.fail("The bank didn't open")
			S.skip["BANK"] = true
			return
		end
	end
	local before_bars = Bankmain.inventory.count_ex(ALL_BARS) or 0
	if not Handler.deposit_unwanted() then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if before_bars > 0 then
		stats.trips += 1
	end
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
	if not Handler.withdraw_trip() then
		if not S.finished then
			Game.fail("Couldn't withdraw the trip")
		end
		return
	end
	S.failures_in_row = 0
	Bankmain.close()
end

function Handler.take()
	local before = Inventory.count_ex(ALL_BARS) or 0
	for _, d in ipairs(CONST.DISPENSED) do
		if (varbit(d.varbit) or 0) > 0 then
			if not Make.make(d.name, "All") then
				Game.fail(`Couldn't take the {d.name}s`)
				return
			end
			break
		end
	end
	if Handler.wait(function()
		return (Inventory.count_ex(ALL_BARS) or 0) > before
	end, CONST.TAKE_MS) then
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
	Log.log(NAME, `Closing the dialogue: {ChatOptions.title() or "?"}`)
	Toplevel.escape_clear()
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

function Handler.load()
	local bar = S.bar
	local ore_before = snap.ore
	local carried = snap.ore + snap.secondary
	Handler.warn_iron(snap.furnace)
	local belt = Objects.nearest(CONST.BELT, snap.me)
	if belt == nil then
		Game.fail("The conveyor belt isn't here")
		return
	end
	if not Objects.interact(belt, "Put-ore-on") then
		Game.fail("Couldn't use the conveyor belt")
		return
	end
	local loaded = Handler.wait(function()
		local left = (Inventory.count_ex(bar.ore) or 0)
			+ (if bar.secondary then Inventory.count_ex(bar.secondary) or 0 else 0)
		return left < carried or ChatOptions.contains_continue() or #(ChatOptions.get() or {}) > 0
	end, CONST.LOAD_MS)
	local ore_after = Inventory.count_ex(bar.ore) or 0
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

function Handler.empty_bag()
	local before = Inventory.count_ex("Coal") or 0
	if not Inventory.interact(CONST.COAL_BAG, "Empty") then
		Game.fail("Couldn't empty the coal bag")
		return
	end
	local moved = 0
	local ok = Handler.wait(function()
		moved = (Inventory.count_ex("Coal") or 0) - before
		return moved > 0
	end, 2400)
	if ok and moved > 0 then
		S.bag_coal = math.max((S.bag_coal or 0) - moved, 0)
	else
		S.bag_coal = 0
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

function Handler.collect()
	local f = snap.furnace
	if S.gauntlets and f.ore > 0 then
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
	if Objects.distance(dispenser, snap.me) > 3 then
		Walker.walk({ x = dispenser.x + Random.int(0, 1), y = dispenser.y + 1 }, { near = 2 })
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
		if f.dispensed > 0 and not (S.gauntlets and f.ore > 0) then
			return
		end
		if f.ore == 0 and time() >= S.bars_due_until then
			S.skip["WAIT_BARS"] = true
			return
		end
		Game.tiny_antiban()
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
