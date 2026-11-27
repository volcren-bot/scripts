--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local BankpinKeypad = require("@volcren/bankpin_keypad")
local Biometrics = require("@volcren/biometrics")
local ChatOptions = require("@volcren/chat_options")
local Clickbox = require("@volcren/clickbox")
local GameState = require("@volcren/game_state")
local Handoff = require("@volcren/handoff")
local Inventory = require("@volcren/inventory")
local Item = require("@volcren/item")
local ItemData = require("@volcren/item_data")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Make = require("@volcren/make")
local Mouse = require("@volcren/mouse")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Transports = require("@volcren/transports")
local Walker = require("@volcren/walker")
local Widgets = require("@volcren/widgets")

local NAME = "Smelter"

type Ore = { name: string, per: number, take: number }
type Recipe = { skill: string, ores: { Ore } }

local RECIPES: { [string]: Recipe } = {
	["Bronze bar"] = {
		skill = "Smithing",
		ores = { { name = "Copper ore", per = 1, take = 14 }, { name = "Tin ore", per = 1, take = 14 } },
	},
	["Iron bar"] = { skill = "Smithing", ores = { { name = "Iron ore", per = 1, take = 0 } } },
	["Silver bar"] = { skill = "Smithing", ores = { { name = "Silver ore", per = 1, take = 0 } } },
	["Steel bar"] = {
		skill = "Smithing",
		ores = { { name = "Iron ore", per = 1, take = 9 }, { name = "Coal", per = 2, take = 18 } },
	},
	["Gold bar"] = { skill = "Smithing", ores = { { name = "Gold ore", per = 1, take = 0 } } },
	["Mithril bar"] = {
		skill = "Smithing",
		ores = { { name = "Mithril ore", per = 1, take = 5 }, { name = "Coal", per = 4, take = 20 } },
	},
	["Adamantite bar"] = {
		skill = "Smithing",
		ores = { { name = "Adamantite ore", per = 1, take = 4 }, { name = "Coal", per = 6, take = 24 } },
	},
	["Runite bar"] = {
		skill = "Smithing",
		ores = { { name = "Runite ore", per = 1, take = 3 }, { name = "Coal", per = 8, take = 24 } },
	},
	["Molten glass"] = {
		skill = "Crafting",
		ores = { { name = "Soda ash", per = 1, take = 14 }, { name = "Bucket of sand", per = 1, take = 14 } },
	},
}

local FURNACES: { [string]: Host.Corners } = {
	["Al Kharid"] = { x1 = 3250, y1 = 3160, x2 = 3300, y2 = 3210 },
	["Edgeville"] = { x1 = 3085, y1 = 3475, x2 = 3130, y2 = 3520 },
	["Falador"] = { x1 = 2950, y1 = 3345, x2 = 3000, y2 = 3395 },
	["Prifddinas"] = { x1 = 3200, y1 = 5990, x2 = 3340, y2 = 6130 },
}

local FASTEST = "Fastest"
local FASTEST_OF = { "Edgeville", "Al Kharid", "Falador" }
local COST_SHARE: { [string]: number } = { ["Edgeville"] = 0.75 }

local CONST = {
	REPORT = { counters_key = "" },
	FURNACE = { name = "Furnace", action = "Smelt" },
	NEAR_TILES = 40,
	WALK_NEAR = 6,
	OPEN_MS = 8000,
	START_MS = 4000,
	SMELT_IDLE_MS = 6000,
	BANK_CONFIRM_MS = 2400,
	HOVER_BANK_LEFT = 1,
	INVENTORY_REOPEN_MS = { 800, 4000 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	bar = "Gold bar",
	furnace = FASTEST,
	max_made = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
}

local stats = { made = 0, trips = 0, failures = 0 }

type Furnace = { name: string, x: number, y: number, plane: number, bank: Host.Tile }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	recipe: Recipe,
	furnace: Furnace?,
	smelting: boolean,
	smelt_progress_at: number,
	hovered_bank: boolean,
	inventory_due_at: number?,
	last_made: number?,
	last_first_ore: number?,
	profit_each: number,
}

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	recipe = RECIPES[CONFIG.bar],
	furnace = nil,
	smelting = false,
	smelt_progress_at = 0,
	hovered_bank = false,
	inventory_due_at = nil,
	last_made = nil,
	last_first_ore = nil,
	profit_each = 0,
}

type Snapshot = {
	state: ClientState,
	me: Host.PositionData,
	made: number,
	ores: { number },
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LEVEL_UP" | "WALK" | "BANK" | "FURNACE" | "SMELT" | "WAIT"

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.ore_names(): { Item.Item }
	local names: { Item.Item } = {}
	for _, ore in ipairs(S.recipe.ores) do
		table.insert(names, ore.name)
	end
	return names
end

function Read.refresh_snapshot(state: ClientState): boolean
	local me = state.position
	if me == nil then
		return false
	end
	local made = Inventory.count_ex(CONFIG.bar)
	if made == nil then
		return false
	end
	local ores: { number } = {}
	for _, ore in ipairs(S.recipe.ores) do
		local held = Inventory.count_ex(ore.name)
		if held == nil then
			return false
		end
		table.insert(ores, held)
	end
	snap = { state = state, me = me, made = made, ores = ores }
	return true
end

function Read.gap(a: Host.Tile, b: Host.Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function Read.smeltable(held: { number }): number
	local count = math.huge
	for i, ore in ipairs(S.recipe.ores) do
		count = math.min(count, held[i] // ore.per)
	end
	return count
end

function Read.closest_bank(tile: Host.Tile, plane: number): (Bankmain.Bank?, number)
	local best: Bankmain.Bank? = nil
	local best_gap = math.huge
	for _, bank in ipairs(Bankmain.BANKS) do
		local gap = Read.gap(bank, tile)
		if bank.plane == plane and gap < best_gap then
			best, best_gap = bank, gap
		end
	end
	return best, best_gap
end

function Read.find_furnace(name: string): Furnace?
	local placed = Host.cache_locs(
		FURNACES[name],
		{ names = { CONST.FURNACE.name }, actions = { CONST.FURNACE.action } }
	) or {}
	local best: Furnace? = nil
	local best_gap = math.huge
	for _, loc in ipairs(placed) do
		local bank, gap = Read.closest_bank(loc, loc.plane)
		if bank and gap < best_gap then
			best = { name = name, x = loc.x, y = loc.y, plane = loc.plane, bank = { x = bank.x, y = bank.y } }
			best_gap = gap
		end
	end
	return best
end

function Read.fastest_furnace(): Furnace?
	local found: { Furnace } = {}
	local goals: { { read x: number, read y: number, read plane: number? } } = {}
	for _, name in ipairs(FASTEST_OF) do
		local furnace = Read.find_furnace(name)
		if furnace then
			table.insert(found, furnace)
			table.insert(goals, { x = furnace.bank.x, y = furnace.bank.y, plane = furnace.plane })
		end
	end
	if #found == 0 then
		return nil
	end
	local costs = Transports.costs({ x = snap.me.x, y = snap.me.y, plane = snap.me.plane or 0 }, goals)
	local best: Furnace? = nil
	local best_cost = math.huge
	for i, furnace in ipairs(found) do
		local cost = costs[i] * (COST_SHARE[furnace.name] or 1)
		Log.log(NAME, `{furnace.name} bank is {math.floor(costs[i])} ticks away, weighed as {math.floor(cost)}`)
		if cost < best_cost then
			best, best_cost = furnace, cost
		end
	end
	return best
end

function Read.at_furnace(furnace: Furnace): boolean
	return (snap.me.plane or 0) == furnace.plane and Read.gap(snap.me, furnace) <= CONST.NEAR_TILES
end

function Read.furnace_loc(): Loc?
	local furnace = S.furnace :: Furnace
	for _, loc in ipairs(Objects.find(CONST.FURNACE.name) or {}) do
		if Objects.distance(loc, furnace) == 0 then
			return loc
		end
	end
	return nil
end

function Read.in_view(loc: Loc): boolean
	local box = Objects.clickbox(loc)
	return box ~= nil and Clickbox.target(box, loc.name or "object") ~= nil
end

function Read.smelting(): boolean
	if not S.smelting then
		return false
	end
	if Player.is_animating() then
		S.smelt_progress_at = time()
	end
	return time() - S.smelt_progress_at < CONST.SMELT_IDLE_MS
end

function Read.banked_ores(): { number }
	local held: { number } = {}
	for _, ore in ipairs(S.recipe.ores) do
		table.insert(held, Bankmain.inventory.count_ex(ore.name) or 0)
	end
	return held
end

function Read.wants(ore: Ore, held: number): number?
	if (Bankmain.count_ex(ore.name) or 0) == 0 then
		return nil
	end
	if ore.take == 0 then
		return if (Bankmain.inventory.count_empty() or 0) > 0 then 0 else nil
	end
	return if held < ore.take then ore.take - held else nil
end

function Read.withdraw_order(): { number }
	local ores = S.recipe.ores
	local order: { number } = {}
	for i = 1, #ores do
		table.insert(order, i)
	end
	local flip = Random.chance()
	table.sort(order, function(a: number, b: number): boolean
		if ores[a].take ~= ores[b].take then
			return ores[a].take > ores[b].take
		end
		return if flip then a > b else a < b
	end)
	return order
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

function Game.block(reason: string)
	Log.log(NAME, `{reason}, stopping the script`)
	S.blocked = reason
	S.finished = true
end

function Game.fail(reason: string)
	Log.log(NAME, reason)
	S.failures_in_row += 1
	stats.failures += 1
end

function Game.apply_settings(values: { [string]: any })
	CONFIG.bar = values.bar or CONFIG.bar
	CONFIG.furnace = values.furnace or CONFIG.furnace
	CONFIG.max_made = values.max_made or CONFIG.max_made
	S.recipe = RECIPES[CONFIG.bar]
	S.furnace = nil
	S.smelting = false
	S.last_made, S.last_first_ore = nil, nil
end

function Game.load_prices()
	local items: { Item.Item } = { CONFIG.bar }
	for _, ore in ipairs(S.recipe.ores) do
		table.insert(items, ore.name)
	end
	local prices = ItemData.prices(items)
	if prices == nil then
		S.profit_each = 0
		return
	end
	local profit = prices[1] or 0
	for i, ore in ipairs(S.recipe.ores) do
		profit -= (prices[i + 1] or 0) * ore.per
	end
	S.profit_each = profit
end

function Game.find_furnace()
	local furnace = if CONFIG.furnace == FASTEST then Read.fastest_furnace() else Read.find_furnace(CONFIG.furnace)
	S.furnace = furnace
	if furnace == nil then
		Game.block(`No reachable furnace for {CONFIG.furnace}`)
		return
	end
	Log.log(NAME, `Smelting {CONFIG.bar} at the {furnace.name} furnace`)
end

function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	Game.apply_settings(values)
	Game.load_prices()
	Game.find_furnace()
	AntibanTasks.skills = { S.recipe.skill, "Total" }
	Log.log(NAME, "Settings updated")
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 40)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { S.recipe.skill, "Total" }
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
	Log.log(NAME, "Antiban set up")
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	Game.find_furnace()
	Game.load_prices()
	Game.setup_antiban()
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

function Loop.watch_smelting()
	local made_before, ore_before = S.last_made, S.last_first_ore
	S.last_made, S.last_first_ore = snap.made, snap.ores[1]
	if made_before == nil or ore_before == nil or Bankmain.is_open() then
		return
	end
	if snap.made > made_before then
		stats.made += snap.made - made_before
		S.failures_in_row = 0
		S.smelt_progress_at = time()
	end
	if snap.ores[1] < ore_before then
		S.smelt_progress_at = time()
	end
end

function Loop.report_counters()
	local key = `{stats.made}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "made", label = "Made", value = stats.made },
		{ id = "profit", label = "Profit (gp)", value = stats.made * S.profit_each },
		{ id = "trips", label = "Bank trips", value = stats.trips },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "trips" },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	if idle >= t.idle_minutes * 60000 then
		Game.block(`Stuck: no xp for {t.idle_minutes} minutes`)
	elseif S.failures_in_row >= t.max_failures then
		Game.block(`Stuck: {S.failures_in_row} failures in a row`)
	elseif CONFIG.max_made > 0 and stats.made >= CONFIG.max_made then
		Log.log(NAME, `Made {stats.made} {CONFIG.bar}, stopping the script`)
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

function Loop.bank_state(): State
	if Bankmain.inventory.contains_different(Read.ore_names()) then
		return "BANK"
	end
	local held = Read.banked_ores()
	for i, ore in ipairs(S.recipe.ores) do
		if Read.wants(ore, held[i]) ~= nil then
			return "BANK"
		end
	end
	return if Read.smeltable(held) > 0 then "FURNACE" else "BANK"
end

function Loop.get_state(): State
	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.watch_smelting()
	Loop.report_counters()

	if ChatOptions.leveled_up() then
		S.smelting = false
		return "LEVEL_UP"
	end
	local furnace = S.furnace
	if furnace == nil then
		return "LOADING"
	end
	if not Read.at_furnace(furnace) then
		return "WALK"
	end
	if Bankmain.is_open() then
		return Loop.bank_state()
	end
	if Make.is_open() then
		return "SMELT"
	end
	if Read.smeltable(snap.ores) > 0 then
		return if Read.smelting() then "WAIT" else "FURNACE"
	end
	return "BANK"
end

function Handler.walk()
	local furnace = S.furnace :: Furnace
	Log.log(NAME, `Walking to the {furnace.name} bank at {furnace.bank.x}, {furnace.bank.y}`)
	local ran, walked = pcall(function(): boolean
		return Walker.walk(furnace.bank, { near = CONST.WALK_NEAR, plane = furnace.plane })
	end)
	if not ran then
		Game.block(`No way to the {furnace.name} bank: {walked}`)
	elseif not walked then
		Game.fail(`Couldn't walk to the {furnace.name} bank`)
	end
end

function Handler.open_bank()
	S.smelting, S.hovered_bank = false, false
	if not Bankmain.open() then
		Game.fail("Couldn't open the bank")
		return
	end
	stats.trips += 1
end

function Handler.deposit(keep: { Item.Item }): boolean
	local ok = if Bankmain.inventory.contains_any(keep)
		then Bankmain.deposit_different(keep)
		else Bankmain.deposit_inventory()
	if not ok then
		return false
	end
	return Widgets.wait_for(function(): boolean
		return not Bankmain.inventory.contains_different(keep)
	end, CONST.BANK_CONFIRM_MS, 50)
end

function Handler.withdraw(ore: Ore, amount: number): boolean
	local before = Bankmain.inventory.count_ex(ore.name) or 0
	if not Bankmain.withdraw(ore.name, amount, false) then
		return false
	end
	return Widgets.wait_for(function(): boolean
		return (Bankmain.inventory.count_ex(ore.name) or 0) > before
	end, CONST.BANK_CONFIRM_MS, 50)
end

function Handler.bank()
	if not Bankmain.is_open() then
		Handler.open_bank()
		return
	end
	local keep = Read.ore_names()
	if Bankmain.inventory.contains_different(keep) and not Handler.deposit(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	local ores = S.recipe.ores
	for _, i in ipairs(Read.withdraw_order()) do
		local held = Bankmain.inventory.count_ex(ores[i].name) or 0
		local amount = Read.wants(ores[i], held)
		if amount ~= nil and not Handler.withdraw(ores[i], amount) then
			Game.fail(`Couldn't withdraw {ores[i].name}`)
			return
		end
	end
	if Read.smeltable(Read.banked_ores()) > 0 then
		return
	end
	for i, ore in ipairs(ores) do
		if Read.banked_ores()[i] < ore.per then
			Game.block(`Out of {ore.name}`)
			return
		end
	end
end

function Handler.click_furnace(loc: Loc): boolean
	if not Objects.interact(loc, CONST.FURNACE.action) then
		return false
	end
	return Make.wait_open(CONST.OPEN_MS)
end

function Handler.leave_bank()
	local loc = Read.furnace_loc()
	if loc and Read.in_view(loc) and Handler.click_furnace(loc) then
		return
	end
	if Bankmain.is_open() and not Bankmain.close() then
		Game.fail("Couldn't close the bank")
	end
end

function Handler.furnace()
	if Bankmain.is_open() then
		Handler.leave_bank()
		return
	end
	local loc = Read.furnace_loc()
	if loc == nil then
		Game.fail("The furnace isn't in the scene")
		return
	end
	if not Handler.click_furnace(loc) then
		Game.fail("Couldn't open the furnace")
	end
end

function Handler.smelt()
	if not Make.make(CONFIG.bar, "All") then
		Game.fail(`Couldn't pick {CONFIG.bar} in the furnace menu`)
		return
	end
	local ore_before = snap.ores[1]
	local started = Widgets.wait_for(function(): boolean
		return (Inventory.count_ex(S.recipe.ores[1].name) or ore_before) < ore_before or Player.is_animating()
	end, CONST.START_MS, 100)
	if not started then
		Game.fail(`{CONFIG.bar} didn't start smelting`)
		return
	end
	S.smelting, S.smelt_progress_at, S.hovered_bank = true, time(), false
end

function Handler.hover_bank()
	if S.hovered_bank or Mouse.busy() or Read.smeltable(snap.ores) > CONST.HOVER_BANK_LEFT then
		return
	end
	S.hovered_bank = true
	Bankmain.hover(nil, false)
end

function Handler.wait()
	if not Antiban.do_async_tasks("game") then
		Antiban.do_async_tasks("outside")
	end
	Antiban.do_antiban()
	Handler.hover_bank()
	sleep(Random.int(200, 400))
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	LEVEL_UP = function()
		ChatOptions.handle_level_up()
	end,
	WALK = Handler.walk,
	BANK = Handler.bank,
	FURNACE = Handler.furnace,
	SMELT = Handler.smelt,
	WAIT = Handler.wait,
}

local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	if Bankmain.is_open() or Make.is_open() or BankpinKeypad.is_open() then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

local KEEPS_INVENTORY: { [State]: boolean } = { WALK = true, BANK = true, FURNACE = true, WAIT = true }

function Loop.keep_inventory(state: State)
	if not KEEPS_INVENTORY[state] or Inventory.is_open() or Bankmain.is_open() or Make.is_open() then
		S.inventory_due_at = nil
		return
	end
	local due = S.inventory_due_at
	if due == nil then
		S.inventory_due_at = time() + Random.int(CONST.INVENTORY_REOPEN_MS[1], CONST.INVENTORY_REOPEN_MS[2])
		return
	end
	if time() < due or Mouse.busy() then
		return
	end
	S.inventory_due_at = nil
	if not Inventory.open() then
		Log.log(NAME, "Couldn't open the inventory")
	end
end

function Loop.wrap_up()
	StatsReport.flush(report)
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
	Log.log(NAME, `{NAME} started: {CONFIG.bar} at {CONFIG.furnace}`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() and not Read.smelting() then
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
		Loop.keep_inventory(state)
		Handler.states[state]()
		sleep(Random.int(60, 140))
	end
	Loop.wrap_up()
	Log.log(NAME, "Done")
end

Loop.run()
