--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local BankpinKeypad = require("@volcren/bankpin_keypad")
local Biometrics = require("@volcren/biometrics")
local ChatOptions = require("@volcren/chat_options")
local GameState = require("@volcren/game_state")
local Handoff = require("@volcren/handoff")
local Inventory = require("@volcren/inventory")
local Item = require("@volcren/item")
local ItemData = require("@volcren/item_data")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Make = require("@volcren/make")
local Mouse = require("@volcren/mouse")
local Player = require("@volcren/player")
local Random = require("@volcren/random")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Widgets = require("@volcren/widgets")

local NAME = "Gem cutter"

type Gem = {
	name: string,
	uncut: string,
	cut: string,
	tips: string,
	tips_per_gem: number,
	crafting: number,
	fletching: number,
}

local GEMS: { Gem } = {
	{
		name = "Opal",
		uncut = "Uncut opal",
		cut = "Opal",
		tips = "Opal bolt tips",
		tips_per_gem = 12,
		crafting = 1,
		fletching = 11,
	},
	{
		name = "Jade",
		uncut = "Uncut jade",
		cut = "Jade",
		tips = "Jade bolt tips",
		tips_per_gem = 12,
		crafting = 13,
		fletching = 26,
	},
	{
		name = "Red topaz",
		uncut = "Uncut red topaz",
		cut = "Red topaz",
		tips = "Topaz bolt tips",
		tips_per_gem = 12,
		crafting = 16,
		fletching = 48,
	},
	{
		name = "Sapphire",
		uncut = "Uncut sapphire",
		cut = "Sapphire",
		tips = "Sapphire bolt tips",
		tips_per_gem = 12,
		crafting = 20,
		fletching = 56,
	},
	{
		name = "Emerald",
		uncut = "Uncut emerald",
		cut = "Emerald",
		tips = "Emerald bolt tips",
		tips_per_gem = 12,
		crafting = 27,
		fletching = 58,
	},
	{
		name = "Ruby",
		uncut = "Uncut ruby",
		cut = "Ruby",
		tips = "Ruby bolt tips",
		tips_per_gem = 12,
		crafting = 34,
		fletching = 63,
	},
	{
		name = "Diamond",
		uncut = "Uncut diamond",
		cut = "Diamond",
		tips = "Diamond bolt tips",
		tips_per_gem = 12,
		crafting = 43,
		fletching = 65,
	},
	{
		name = "Dragonstone",
		uncut = "Uncut dragonstone",
		cut = "Dragonstone",
		tips = "Dragonstone bolt tips",
		tips_per_gem = 12,
		crafting = 55,
		fletching = 71,
	},
	{
		name = "Onyx",
		uncut = "Uncut onyx",
		cut = "Onyx",
		tips = "Onyx bolt tips",
		tips_per_gem = 24,
		crafting = 67,
		fletching = 73,
	},
}

type Mode = "Uncut to cut" | "Uncut to bolt tips" | "Cut to bolt tips"

type Stage = { skill: string, level: number, input: string, option: string? }

local CONST = {
	REPORT = { counters_key = "" },
	CHISEL = "Chisel",
	START_MS = 4000,
	MENU_MS = 2400,
	WORK_IDLE_MS = 6000,
	BANK_CONFIRM_MS = 2400,
	HOVER_BANK_LEFT = 1,
	INVENTORY_REOPEN_MS = { 800, 4000 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	gem = "Sapphire",
	mode = "Uncut to cut" :: Mode,
	max_gems = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
}

local stats = { gems = 0, trips = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	gem: Gem,
	working: boolean,
	work_progress_at: number,
	hovered_bank: boolean,
	inventory_due_at: number?,
	last_uncut: number?,
	last_cut: number?,
	profit_per_gem: number,
}

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	gem = GEMS[4],
	working = false,
	work_progress_at = 0,
	hovered_bank = false,
	inventory_due_at = nil,
	last_uncut = nil,
	last_cut = nil,
	profit_per_gem = 0,
}

type Snapshot = {
	state: ClientState,
	chisel: number,
	uncut: number,
	cut: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LEVEL_UP" | "BANK" | "CHISEL" | "MAKE" | "WAIT"

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	local chisel = Inventory.count_ex(CONST.CHISEL)
	local uncut = Inventory.count_ex(S.gem.uncut)
	local cut = Inventory.count_ex(S.gem.cut)
	if chisel == nil or uncut == nil or cut == nil then
		return false
	end
	snap = { state = state, chisel = chisel, uncut = uncut, cut = cut }
	return true
end

function Read.gem_named(name: string): Gem?
	for _, gem in ipairs(GEMS) do
		if gem.name == name then
			return gem
		end
	end
	return nil
end

function Read.cuts_uncut(): boolean
	return CONFIG.mode ~= "Cut to bolt tips"
end

function Read.makes_tips(): boolean
	return CONFIG.mode ~= "Uncut to cut"
end

function Read.source(): string
	return if Read.cuts_uncut() then S.gem.uncut else S.gem.cut
end

function Read.work_items(): { Item.Item }
	if CONFIG.mode == "Uncut to bolt tips" then
		return { S.gem.uncut, S.gem.cut }
	end
	return { Read.source() }
end

function Read.keep(): { Item.Item }
	local keep: { Item.Item } = { CONST.CHISEL }
	for _, item in ipairs(Read.work_items()) do
		table.insert(keep, item)
	end
	return keep
end

function Read.left(uncut: number, cut: number): number
	if CONFIG.mode == "Uncut to cut" then
		return uncut
	elseif CONFIG.mode == "Cut to bolt tips" then
		return cut
	end
	return uncut + cut
end

function Read.stage(uncut: number, cut: number): Stage?
	local gem = S.gem
	if Read.cuts_uncut() and uncut > 0 then
		return { skill = "Crafting", level = gem.crafting, input = gem.uncut, option = gem.uncut }
	end
	if Read.makes_tips() and cut > 0 then
		return { skill = "Fletching", level = gem.fletching, input = gem.cut, option = nil }
	end
	return nil
end

function Read.only_option(): string?
	local options = Make.options()
	if options == nil or #options ~= 1 then
		return nil
	end
	return options[1].name
end

function Read.amount(stage: Stage): Make.AmountArg
	if CONFIG.max_gems <= 0 or stage.input ~= Read.source() then
		return "All"
	end
	local left = math.max(1, CONFIG.max_gems - stats.gems)
	return if left < (Inventory.count_ex(stage.input) or 0) then left else "All"
end

function Read.missing_level(): string?
	local gem = S.gem
	local crafting, fletching = Stats.level("Crafting"), Stats.level("Fletching")
	if crafting == nil or fletching == nil then
		return "Couldn't read the skill levels"
	end
	if Read.cuts_uncut() and crafting < gem.crafting then
		return `Cutting {gem.cut} needs Crafting {gem.crafting}`
	end
	if Read.makes_tips() and fletching < gem.fletching then
		return `{gem.tips} need Fletching {gem.fletching}`
	end
	return nil
end

function Read.working(): boolean
	if not S.working then
		return false
	end
	if Player.is_animating() then
		S.work_progress_at = time()
	end
	return time() - S.work_progress_at < CONST.WORK_IDLE_MS
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
	CONFIG.gem = values.gem or CONFIG.gem
	CONFIG.mode = values.mode or CONFIG.mode
	CONFIG.max_gems = values.max_gems or CONFIG.max_gems
end

function Game.choose_gem(): boolean
	local gem = Read.gem_named(CONFIG.gem)
	if gem == nil then
		Game.block(`Unknown gem {CONFIG.gem}`)
		return false
	end
	S.gem = gem
	local missing = Read.missing_level()
	if missing then
		Game.block(missing)
		return false
	end
	S.last_uncut, S.last_cut = nil, nil
	Log.log(NAME, `{CONFIG.mode}: {gem.name}`)
	return true
end

function Game.load_prices()
	local gem = S.gem
	local prices = ItemData.prices({ gem.uncut, gem.cut, gem.tips })
	if prices == nil then
		S.profit_per_gem = 0
		return
	end
	local uncut, cut, tips = prices[1] or 0, prices[2] or 0, (prices[3] or 0) * gem.tips_per_gem
	if CONFIG.mode == "Uncut to cut" then
		S.profit_per_gem = cut - uncut
	elseif CONFIG.mode == "Uncut to bolt tips" then
		S.profit_per_gem = tips - uncut
	else
		S.profit_per_gem = tips - cut
	end
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		if Game.choose_gem() then
			Game.load_prices()
		end
		Log.log(NAME, "Settings updated")
	end
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 40)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = if Read.makes_tips() then { "Crafting", "Fletching", "Total" } else { "Crafting", "Total" }
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

	if not Game.choose_gem() then
		return
	end
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

function Loop.watch_work()
	local uncut_before, cut_before = S.last_uncut, S.last_cut
	S.last_uncut, S.last_cut = snap.uncut, snap.cut
	if uncut_before == nil or cut_before == nil or Bankmain.is_open() then
		return
	end
	local uncut_used = math.max(0, uncut_before - snap.uncut)
	local cut_used = math.max(0, cut_before - snap.cut)
	if uncut_used + cut_used == 0 then
		return
	end
	stats.gems += if Read.cuts_uncut() then uncut_used else cut_used
	S.failures_in_row = 0
	S.work_progress_at = time()
end

function Loop.report_counters()
	local key = `{stats.gems}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "gems", label = "Gems", value = stats.gems },
		{ id = "profit", label = "Profit (gp)", value = stats.gems * S.profit_per_gem },
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
	elseif CONFIG.max_gems > 0 and stats.gems >= CONFIG.max_gems then
		Log.log(NAME, `Did {stats.gems} gems, stopping the script`)
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
	local held = Bankmain.inventory
	if held.contains_different(Read.keep()) or (held.count_ex(CONST.CHISEL) or 0) == 0 then
		return "BANK"
	end
	local uncut, cut = held.count_ex(S.gem.uncut) or 0, held.count_ex(S.gem.cut) or 0
	return if Read.stage(uncut, cut) then "CHISEL" else "BANK"
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
	Loop.watch_work()
	Loop.report_counters()

	if ChatOptions.leveled_up() then
		S.working = false
		return "LEVEL_UP"
	end
	if Bankmain.is_open() then
		return Loop.bank_state()
	end
	if Make.is_open() then
		return "MAKE"
	end
	if snap.chisel > 0 and Read.stage(snap.uncut, snap.cut) then
		return if Read.working() then "WAIT" else "CHISEL"
	end
	return "BANK"
end

function Handler.open_bank()
	S.working, S.hovered_bank = false, false
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

function Handler.withdraw(item: string, amount: number): boolean
	local before = Bankmain.inventory.count_ex(item) or 0
	if not Bankmain.withdraw(item, amount, false) then
		return false
	end
	return Widgets.wait_for(function(): boolean
		return (Bankmain.inventory.count_ex(item) or 0) > before
	end, CONST.BANK_CONFIRM_MS, 50)
end

function Handler.take(item: string, amount: number): boolean
	if (Bankmain.inventory.count_ex(item) or 0) > 0 then
		return true
	end
	if (Bankmain.count_ex(item) or 0) == 0 then
		Game.block(`Out of {item}`)
		return false
	end
	if not Handler.withdraw(item, amount) then
		Game.fail(`Couldn't withdraw {item}`)
		return false
	end
	return true
end

function Handler.bank()
	if not Bankmain.is_open() then
		Handler.open_bank()
		return
	end
	local keep = Read.keep()
	if Bankmain.inventory.contains_different(keep) and not Handler.deposit(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if Handler.take(CONST.CHISEL, 1) then
		Handler.take(Read.source(), 0)
	end
end

function Handler.chisel()
	if Bankmain.is_open() then
		if not Bankmain.close() then
			Game.fail("Couldn't close the bank")
		end
		return
	end
	local stage = Read.stage(snap.uncut, snap.cut)
	if stage == nil then
		return
	end
	if not Inventory.combine(CONST.CHISEL, stage.input) then
		Game.fail(`Couldn't use the {CONST.CHISEL} on the {stage.input}`)
		return
	end
	local opened = Widgets.wait_for(function(): boolean
		return Make.is_open() or Player.is_animating()
	end, CONST.MENU_MS, 50)
	if not opened then
		Game.fail("The make menu didn't open")
	elseif not Make.is_open() then
		S.working, S.work_progress_at, S.hovered_bank = true, time(), false
	end
end

function Handler.make()
	local stage = Read.stage(snap.uncut, snap.cut)
	if stage == nil then
		Make.wait_closed()
		return
	end
	local option = stage.option or Read.only_option()
	if option == nil or not Make.make(option, Read.amount(stage)) then
		Game.fail(`Couldn't pick {option or stage.input} in the make menu`)
		return
	end
	local before = Inventory.count_ex(stage.input) or 0
	local started = Widgets.wait_for(function(): boolean
		return (Inventory.count_ex(stage.input) or before) < before or Player.is_animating()
	end, CONST.START_MS, 100)
	if not started then
		Game.fail(`{option} didn't start`)
		return
	end
	S.working, S.work_progress_at, S.hovered_bank = true, time(), false
end

function Handler.hover_bank()
	if S.hovered_bank or Mouse.busy() or Read.left(snap.uncut, snap.cut) > CONST.HOVER_BANK_LEFT then
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
	BANK = Handler.bank,
	CHISEL = Handler.chisel,
	MAKE = Handler.make,
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

local KEEPS_INVENTORY: { [State]: boolean } = { BANK = true, CHISEL = true, WAIT = true }

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
	Log.log(NAME, `{NAME} started: {CONFIG.mode}, {CONFIG.gem}`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() and not Read.working() then
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
