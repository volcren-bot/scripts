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

local NAME = "Glassblower"

type Product = { item: string, option: string, level: number }

local PRODUCTS: { Product } = {
	{ item = "Beer glass", option = "Beer glass", level = 1 },
	{ item = "Empty candle lantern", option = "Candle lantern", level = 4 },
	{ item = "Empty oil lamp", option = "Oil lamp", level = 12 },
	{ item = "Vial", option = "Vial", level = 33 },
	{ item = "Empty fishbowl", option = "Fishbowl", level = 42 },
	{ item = "Unpowered orb", option = "Unpowered staff orb", level = 46 },
	{ item = "Lantern lens", option = "Lantern lens", level = 49 },
	{ item = "Empty light orb", option = "Light orb", level = 87 },
}

local BEST = "Best available"

local CONST = {
	REPORT = { counters_key = "" },
	PIPE = "Glassblowing pipe",
	GLASS = "Molten glass",
	SKILL = "Crafting",
	START_MS = 4000,
	BLOW_IDLE_MS = 6000,
	BANK_CONFIRM_MS = 2400,
	HOVER_BANK_LEFT = 1,
	INVENTORY_REOPEN_MS = { 800, 4000 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	product = BEST,
	max_made = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
}

local stats = { made = 0, trips = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	product: Product,
	blowing: boolean,
	blow_progress_at: number,
	hovered_bank: boolean,
	inventory_due_at: number?,
	last_glass: number?,
	profits: { [string]: number },
}

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	product = PRODUCTS[1],
	blowing = false,
	blow_progress_at = 0,
	hovered_bank = false,
	inventory_due_at = nil,
	last_glass = nil,
	profits = {},
}

type Snapshot = {
	state: ClientState,
	pipe: number,
	glass: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LEVEL_UP" | "BANK" | "BLOW" | "MAKE" | "WAIT"

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	local pipe = Inventory.count_ex(CONST.PIPE)
	local glass = Inventory.count_ex(CONST.GLASS)
	if pipe == nil or glass == nil then
		return false
	end
	snap = { state = state, pipe = pipe, glass = glass }
	return true
end

function Read.product_named(name: string): Product?
	for _, product in ipairs(PRODUCTS) do
		if product.item == name then
			return product
		end
	end
	return nil
end

function Read.pick_product(): Product?
	local level = Stats.level(CONST.SKILL)
	if level == nil then
		return nil
	end
	if CONFIG.product ~= BEST then
		local product = Read.product_named(CONFIG.product)
		return if product and product.level <= level then product else nil
	end
	local best: Product? = nil
	for _, product in ipairs(PRODUCTS) do
		if product.level <= level then
			best = product
		end
	end
	return best
end

function Read.keep(): { Item.Item }
	return { CONST.PIPE, CONST.GLASS }
end

function Read.blowing(): boolean
	if not S.blowing then
		return false
	end
	if Player.is_animating() then
		S.blow_progress_at = time()
	end
	return time() - S.blow_progress_at < CONST.BLOW_IDLE_MS
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
	CONFIG.product = values.product or CONFIG.product
	CONFIG.max_made = values.max_made or CONFIG.max_made
end

function Game.load_prices()
	local items: { Item.Item } = { CONST.GLASS }
	for _, product in ipairs(PRODUCTS) do
		table.insert(items, product.item)
	end
	local prices = ItemData.prices(items)
	S.profits = {}
	if prices == nil then
		return
	end
	for i, product in ipairs(PRODUCTS) do
		S.profits[product.item] = (prices[i + 1] or 0) - (prices[1] or 0)
	end
end

function Game.choose_product(): boolean
	local product = Read.pick_product()
	if product == nil then
		Game.block(`{CONFIG.product} needs a higher {CONST.SKILL} level`)
		return false
	end
	if product ~= S.product then
		S.product = product
		Log.log(NAME, `Making {product.item}`)
	end
	return true
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Game.choose_product()
		Log.log(NAME, "Settings updated")
	end
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 40)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { CONST.SKILL, "Total" }
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

	if not Game.choose_product() then
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

function Loop.watch_blowing()
	local before = S.last_glass
	S.last_glass = snap.glass
	if before == nil or Bankmain.is_open() or snap.glass >= before then
		return
	end
	stats.made += before - snap.glass
	S.failures_in_row = 0
	S.blow_progress_at = time()
end

function Loop.report_counters()
	local key = `{stats.made}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "made", label = "Made", value = stats.made },
		{ id = "profit", label = "Profit (gp)", value = stats.made * (S.profits[S.product.item] or 0) },
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
		Log.log(NAME, `Made {stats.made} items, stopping the script`)
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
	if held.contains_different(Read.keep()) then
		return "BANK"
	end
	if (held.count_ex(CONST.PIPE) or 0) == 0 or (held.count_ex(CONST.GLASS) or 0) == 0 then
		return "BANK"
	end
	return "BLOW"
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
	Loop.watch_blowing()
	Loop.report_counters()

	if ChatOptions.leveled_up() then
		S.blowing = false
		return "LEVEL_UP"
	end
	if Bankmain.is_open() then
		return Loop.bank_state()
	end
	if Make.is_open() then
		return "MAKE"
	end
	if snap.pipe > 0 and snap.glass > 0 then
		return if Read.blowing() then "WAIT" else "BLOW"
	end
	return "BANK"
end

function Handler.open_bank()
	S.blowing, S.hovered_bank = false, false
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
	if Handler.take(CONST.PIPE, 1) then
		Handler.take(CONST.GLASS, 0)
	end
end

function Handler.blow()
	if Bankmain.is_open() then
		if not Bankmain.close() then
			Game.fail("Couldn't close the bank")
		end
		return
	end
	if not Game.choose_product() then
		return
	end
	if not Inventory.combine(CONST.PIPE, CONST.GLASS) then
		Game.fail(`Couldn't use the {CONST.PIPE} on the {CONST.GLASS}`)
		return
	end
	if not Make.wait_open() then
		Game.fail("The make menu didn't open")
	end
end

function Handler.make()
	if not Game.choose_product() then
		return
	end
	local product = S.product
	if not Make.make(product.option, "All") then
		Game.fail(`Couldn't pick {product.option} in the make menu`)
		return
	end
	local glass_before = snap.glass
	local started = Widgets.wait_for(function(): boolean
		return (Inventory.count_ex(CONST.GLASS) or glass_before) < glass_before or Player.is_animating()
	end, CONST.START_MS, 100)
	if not started then
		Game.fail(`{product.item} didn't start`)
		return
	end
	S.blowing, S.blow_progress_at, S.hovered_bank = true, time(), false
end

function Handler.hover_bank()
	if S.hovered_bank or Mouse.busy() or snap.glass > CONST.HOVER_BANK_LEFT then
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
	BLOW = Handler.blow,
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

local KEEPS_INVENTORY: { [State]: boolean } = { BANK = true, BLOW = true, WAIT = true }

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
	Log.log(NAME, `{NAME} started: {CONFIG.product}`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() and not Read.blowing() then
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
