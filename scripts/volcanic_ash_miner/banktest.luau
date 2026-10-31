--!strict
-- Mines volcanic ash on Fossil Island: walks the ash piles up and down the volcano, banks at the chest when the inventory is full.
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local GameState = require("@lib/main/game_state")
local Interact = require("@lib/main/interact")
local Inv = require("@lib/main/interfaces/inv")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Mouse = require("@lib/utils/input/mouse")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Walker = require("@lib/main/walker")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Volcanic ash miner"

-- fixed values: ids, tiles, thresholds
local CONST = {
	REPORT = { counters_key = "" },
	ASH = "Volcanic ash",
	MIN_MINING = 22,
	PILE = { name = "Ash pile", option = "Mine" },
	-- one ash per pile, then it is gone for about half a minute
	MINE = { RESULT_MS = 6000, POLL_MS = 100 },
	-- the chest at the top of the volcano
	BANK = {
		name = "Bank chest",
		options = { "Use" },
		stand = { x = 3820, y = 3807 },
		OPEN_MS = 4000,
		GROUP = 12,
		DEPOSIT_INVENTORY = 47,
		DEPOSIT_OPTION = "Deposit-All",
		-- the inventory as the bank draws it: slot n is the child with index n
		INV_GROUP = 15,
		INV_CHILD = 3,
		DEPOSIT_PASSES = 30,
		-- the frame the close button is in, and its index there
		FRAME = 2,
		CLOSE = 11,
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

-- what the user can change
local CONFIG = {
	max_runs = 1, -- ash mined before stopping, 0 is unlimited
	-- piles not worth the walk, as { x = , y = } tiles (the pile's south-west tile)
	skip_piles = {} :: { { x: number, y: number } },
	-- bank at the chest when the inventory is full
	bank = true,
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { runs = 0, failures = 0, banked = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	-- which way along the volcano we are going: 1 is north (y grows), -1 south
	direction: number,
	-- the pickaxe carried in the inventory at the start: the bank deposit leaves it
	pickaxe: string?,
	-- states to ignore for one loop
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	direction = 1,
	skip = {},
}

type Snapshot = {
	state: ClientState,
	tick: number,
	me: Host.Tile,
	free_slots: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "BANK" | "MINE" | "WAIT"

-- what get_state found that its handler needs
type Plan = { pile: Host.Loc? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

---------------------------------------------------------------------------------------------------
-- Reading the client

-- falls back to wall clock ticks
function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
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
		me = { x = state.position.x, y = state.position.y },
		free_slots = Inventory.free_slots() or 28,
	}
	return true
end

local backpack = Inv.new(93, 28)

-- the pickaxe we wield and the one in the backpack, by name
function Read.pickaxe(): (string?, string?)
	local function find(items: { Inv.Slot }?): string?
		for _, item in ipairs(items or {}) do
			if item.name and string.find(string.lower(item.name), "pickaxe", 1, true) then
				return item.name
			end
		end
		return nil
	end
	return find(Wornitems.items()), find(backpack.items())
end

function Read.ash(): number
	return backpack.count_ex(CONST.ASH) or 0
end

function Read.skipped(loc: Host.Loc): boolean
	for _, tile in ipairs(CONFIG.skip_piles) do
		if tile.x == loc.x and tile.y == loc.y then
			return true
		end
	end
	return false
end

-- the piles that are there to mine, not the ones we skip
function Read.piles(): { Host.Loc }
	local out = {}
	for _, loc in ipairs(Objects.find(CONST.PILE.name) or {}) do
		if not Read.skipped(loc) then
			table.insert(out, loc)
		end
	end
	return out
end

function Read.pile_there(x: number, y: number): boolean
	for _, loc in ipairs(Objects.find(CONST.PILE.name) or {}) do
		if loc.x == x and loc.y == y then
			return true
		end
	end
	return false
end

-- the nearest pile in the direction we are going; at the end of the volcano we turn round
function Read.next_pile(): Host.Loc?
	local piles = Read.piles()
	local me = snap.me
	for _ = 1, 2 do
		local best: Host.Loc? = nil
		local best_distance = math.huge
		for _, loc in ipairs(piles) do
			-- a pile level with us (or a tile behind) still counts as ahead
			if (loc.y - me.y) * S.direction >= -1 then
				local d = Objects.distance(loc, me)
				if d < best_distance then
					best, best_distance = loc, d
				end
			end
		end
		if best then
			return best
		end
		if #piles == 0 then
			return nil
		end
		S.direction = -S.direction
		Log.log(NAME, if S.direction > 0 then "Going north" else "Going south")
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Game setup

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
	-- scene reload while logged in
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

	-- queued without blocking: camera, hover and random tab in the game, tabs and chat outside it
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

	-- breaks and sleeps come from the loader's Breaks tab
	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

-- closes the bank: Escape, else its close button (the lib's check rejects it when the window is big)
function Game.close_bank(): boolean
	if Bankmain.close(1, 1500) then
		return true
	end
	for _ = 1, 3 do
		local kids = Host.widget_children(CONST.BANK.GROUP, CONST.BANK.FRAME) or {}
		for _, kid in ipairs(kids) do
			if kid.index == CONST.BANK.CLOSE and not kid.hidden then
				Mouse.click(kid)
				break
			end
		end
		sleep(600)
		if not Bankmain.is_open() then
			return true
		end
	end
	Log.log(NAME, "The bank didn't close")
	return false
end

-- empties the inventory into the open bank. With a pickaxe carried it stays: the items are deposited
-- one kind at a time (the bank's quantity is All, so one click takes every item of that id)
function Game.deposit(): boolean
	if S.pickaxe == nil then
		local button = Host.widget(CONST.BANK.GROUP, CONST.BANK.DEPOSIT_INVENTORY)
		if button == nil then
			return false
		end
		Mouse.click(button)
		return Inventory.wait_used(0, 3000)
	end
	for _ = 1, CONST.BANK.DEPOSIT_PASSES do
		local slot: number? = nil
		local name: string? = nil
		for _, item in ipairs(backpack.items() or {}) do
			if item.name ~= S.pickaxe then
				slot, name = item.slot, item.name
				break
			end
		end
		if slot == nil then
			return true
		end
		-- with the bank open the inventory is drawn in the bank's side panel, not in the inventory tab
		local box: Host.Widget? = nil
		for _, child in ipairs(Host.widget_children(CONST.BANK.INV_GROUP, CONST.BANK.INV_CHILD) or {}) do
			if child.index == slot and not child.hidden then
				box = child
				break
			end
		end
		if box == nil or not Interact.with(box, CONST.BANK.DEPOSIT_OPTION, name, false) then
			return false
		end
		sleep(Random.int(200, 400))
	end
	return false
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	-- a bank left open blocks every click
	if Bankmain.is_open() then
		Game.close_bank()
	end

	local mining = Stats.get("Mining")
	if mining == nil or mining.real_level < CONST.MIN_MINING then
		Log.log(NAME, `Volcanic ash needs {CONST.MIN_MINING} Mining, you have {mining and mining.real_level or "?"}`)
		S.finished = true
		return
	end

	local equipped, carried = Read.pickaxe()
	if equipped == nil and carried == nil then
		Log.log(NAME, "No pickaxe: equip one or keep it in the inventory")
		S.finished = true
		return
	end
	-- a pickaxe in the inventory is kept out of the bank: remember which
	S.pickaxe = if equipped then nil else carried
	Log.log(NAME, `Pickaxe: {equipped or carried}{if equipped then " (equipped)" else ""}`)

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

---------------------------------------------------------------------------------------------------
-- Loop

-- resets the idle timeout on xp and reports it
function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

-- what the loader's XP tracker shows next to the skills: the totals, it works out the rates itself
function Loop.report_counters()
	local key = `{stats.runs}/{stats.failures}/{stats.banked}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "runs", label = "Ash mined", value = stats.runs },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "runs" },
		{ id = "banked", label = "Bank trips", value = stats.banked },
	})
end

-- stops the script when it hasn't progressed or keeps failing
function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_runs > 0 and stats.runs >= CONFIG.max_runs then
		Log.log(NAME, `Mined {CONFIG.max_runs} ash, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.finished = true
	end
end

-- time spent in antiban doesn't count as idle
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

-- reads the client and decides what to do next; handlers do it
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

	if CONFIG.bank and snap.free_slots <= 27 and not skipped["BANK"] then
		return "BANK"
	end
	if skipped["MINE"] then
		return "LOADING"
	end
	plan.pile = Read.next_pile()
	return if plan.pile then "MINE" else "WAIT"
end

---------------------------------------------------------------------------------------------------
-- Handlers

-- walks to the pile, mines it and waits for the ash
function Handler.mine(pile: Host.Loc)
	local before = Read.ash()
	if not Objects.approach(pile, { CONST.PILE.option }) then
		-- someone else may have taken it as we got there
		if Read.pile_there(pile.x, pile.y) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't mine the pile at {pile.x}, {pile.y}`)
		end
		return
	end
	local waited = 0
	while waited < CONST.MINE.RESULT_MS do
		if Read.ash() > before then
			stats.runs += 1
			S.failures_in_row = 0
			S.last_progress_at = time()
			return
		end
		-- gone without ash: another player was quicker
		if not Read.pile_there(pile.x, pile.y) then
			return
		end
		sleep(CONST.MINE.POLL_MS)
		waited += CONST.MINE.POLL_MS
	end
	S.failures_in_row += 1
	stats.failures += 1
	Log.log(NAME, `No ash from the pile at {pile.x}, {pile.y}`)
end

-- opens the chest, deposits the inventory and closes it
function Handler.bank()
	Log.log(NAME, "Inventory full, banking")
	if not Walker.walk(CONST.BANK.stand, { near = 2 }) then
		Log.log(NAME, "Couldn't walk to the bank chest")
		S.failures_in_row += 1
		S.skip["BANK"] = true
		return
	end
	Player.wait_still(3000)
	local opened = false
	for attempt = 1, 2 do
		local loc = Objects.nearest(CONST.BANK.name, snap.me)
		if loc and Objects.approach(loc, CONST.BANK.options) then
			local waited = 0
			while waited < CONST.BANK.OPEN_MS and not opened do
				opened = Bankmain.is_open()
				if not opened then
					sleep(100)
					waited += 100
				end
			end
		end
		if opened then
			break
		end
		Log.log(NAME, `The bank chest didn't open (attempt {attempt})`)
		Player.wait_still(3000)
	end
	if not opened then
		S.failures_in_row += 1
		S.skip["BANK"] = true
		return
	end
	if Game.deposit() then
		stats.banked += 1
		S.failures_in_row = 0
	else
		Log.log(NAME, "The inventory wasn't deposited")
		S.failures_in_row += 1
	end
	Game.close_bank()
	S.last_progress_at = time()
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	BANK = function()
		Handler.bank()
	end,
	MINE = function()
		Handler.mine(assert(plan.pile))
		if CONFIG.antiban and S.antiban_ready then
			if not Antiban.do_antiban() then
				S.skip["MINE"] = true
			end
		end
	end,
	-- every pile is gone: they come back after about half a minute
	WAIT = function()
		sleep(Random.int(600, 1200))
		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_antiban()
		end
	end,
}

function Loop.run()
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
