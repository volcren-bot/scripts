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
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Volcanic ash miner"

-- fixed values: ids, tiles, thresholds
local CONST = {
	REPORT = { counters_key = "" },
	ASH = "Volcanic ash",
	MIN_MINING = 22,
	PILE = { name = "Ash pile", option = "Mine" },
	-- game ticks a pile takes to come back; a timer more than LATE_TICKS past due means someone else took it again
	RESPAWN = { TICKS = 50, LATE_TICKS = 4 },
	-- we stay on a pile until it is gone (it comes back after about half a minute). RESULT_MS: how long
	-- without any ash before the pile counts as a failure; STALL_MS: how long without more ash
	-- before we give up on a pile that has given some
	MINE = { RESULT_MS = 6000, STALL_MS = 15000, POLL_MS = 100, TAB_CHECK_MS = 1000, TINY_ANTIBAN = 0.4 },
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

local Read, Route, Game, Loop, Handler = {}, {}, {}, {}, {}

-- what the user can change
local CONFIG = {
	max_ashes = 0, -- ash mined before stopping, 0 is unlimited
	-- the only piles ever mined, as { x = , y = } tiles (the pile's south-west tile), in the order they
	-- are walked: from the top of the volcano (next to the chest) down. Mined in this order going down
	-- and in reverse coming back up
	piles = {
		{ x = 3820, y = 3804 },
		{ x = 3818, y = 3791 },
		{ x = 3821, y = 3779 },
		{ x = 3810, y = 3772 },
		{ x = 3800, y = 3767 },
		{ x = 3794, y = 3773 },
		{ x = 3789, y = 3769 },
		{ x = 3781, y = 3774 },
	} :: { { x: number, y: number } },
	-- the worse route (fewer piles), same order: taken now and then instead of the main one
	secondary_piles = {
		{ x = 3812, y = 3818 },
		{ x = 3804, y = 3826 },
		{ x = 3794, y = 3818 },
		{ x = 3785, y = 3823 },
	} :: { { x: number, y: number } },
	-- chance (biometric) of taking the secondary route each time we are back at the top
	secondary_chance = 0.07,
	-- a pile we depleted that is back within this many ticks is worth waiting for; others are skipped
	wait_ticks = 8,
	-- hop worlds when this many piles in a row are depleted by someone else (no respawn timer of ours)
	hop = true,
	hop_after = 3,
	-- the worlds to hop between; empty picks a random members world with no activity from the world list
	hop_worlds = {} :: { number },
	-- bank at the chest when the inventory is full
	bank = true,
	-- back at the top, bank when the inventory is at least this full (a full inventory banks anywhere)
	bank_at = 0.7,
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { ashes = 0, failures = 0, banked = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	-- the route being walked, the next pile in its list and which way we go
	-- (1 is down the volcano, in list order; -1 is back up)
	route: string,
	idx: number,
	dir: number,
	-- set when a trip ends at the top: bank there if the inventory is filling up
	top_check: boolean,
	-- the tick each pile we depleted comes back at, by "x,y"
	respawn: { [string]: number },
	-- other players are mining the piles: hop (retry_at: not before)
	hop_wanted: boolean,
	hop_retry_at: number,
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
	route = "main",
	idx = 1,
	dir = 1,
	top_check = false,
	respawn = {},
	hop_wanted = false,
	hop_retry_at = 0,
	skip = {},
}

type Snapshot = {
	state: ClientState,
	tick: number,
	me: Host.Tile,
	free_slots: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "BANK" | "MINE" | "AWAIT" | "HOP" | "WAIT"

-- what get_state found that its handler needs
type Plan = { pile: Host.Loc?, wait: Host.Tile? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

---------------------------------------------------------------------------------------------------
-- Reading the client

-- falls back to wall clock ticks
function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.tick(): number
	return Read.current_tick(game_state())
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

-- the pile standing on the tile, nil when it is depleted
function Read.pile_at(x: number, y: number): Host.Loc?
	for _, loc in ipairs(Objects.find(CONST.PILE.name) or {}) do
		if loc.x == x and loc.y == y then
			return loc
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Route

function Route.list(): { { x: number, y: number } }
	return if S.route == "secondary" then CONFIG.secondary_piles else CONFIG.piles
end

-- starts on the main route from the pile nearest to us, going the way with the most piles left
function Route.start()
	local k, best = 1, math.huge
	for i, tile in ipairs(CONFIG.piles) do
		local d = math.max(math.abs(tile.x - snap.me.x), math.abs(tile.y - snap.me.y))
		if d < best then
			k, best = i, d
		end
	end
	local down, up = #CONFIG.piles - k + 1, k
	S.route, S.idx = "main", k
	if down == up then
		S.dir = if Random.int(1, 2) == 1 then 1 else -1
	else
		S.dir = if down > up then 1 else -1
	end
	Log.log(NAME, `Starting at pile {k}, going {if S.dir > 0 then "down" else "up"}`)
end

-- the end of a pass: turn round at the bottom, at the top pick the route for the next trip
function Route.turn()
	if S.dir == 1 then
		-- the last pile was just mined: come back from the one before it
		S.dir, S.idx = -1, math.max(#Route.list() - 1, 1)
		Log.log(NAME, "At the bottom, going back up")
		return
	end
	S.top_check = true
	local second = #CONFIG.secondary_piles > 0 and Biometrics.random_boolean(CONFIG.secondary_chance)
	S.route, S.dir, S.idx = if second then "secondary" else "main", 1, 1
	Log.log(NAME, `At the top, going down the {S.route} route`)
end

-- the pile to mine next on the route, or the tile of one we depleted that is about to come back.
-- Depleted piles are skipped for good; skipping several in a row that we have no timer for means
-- someone else is mining them, and asks for a hop
function Route.target(): (Host.Loc?, Host.Tile?)
	local unknown, streak_start = 0, S.idx
	for _ = 1, 4 * (#CONFIG.piles + #CONFIG.secondary_piles) + 4 do
		local tile = Route.list()[S.idx]
		if tile == nil then
			Route.turn()
			unknown = 0
		else
			local key = `{tile.x},{tile.y}`
			local loc = Read.pile_at(tile.x, tile.y)
			if loc then
				S.respawn[key] = nil
				return loc, nil
			end
			local left = if S.respawn[key] then S.respawn[key] - snap.tick else nil
			if left and left >= -CONST.RESPAWN.LATE_TICKS then
				if left <= CONFIG.wait_ticks then
					return nil, tile
				end
			else
				-- not ours (or taken again since): someone else is on the piles
				S.respawn[key] = nil
				if unknown == 0 then
					streak_start = S.idx
				end
				unknown += 1
				if CONFIG.hop and unknown >= CONFIG.hop_after then
					S.idx, S.hop_wanted = streak_start, true
					return nil, nil
				end
			end
			S.idx += S.dir
		end
	end
	return nil, nil
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

-- the small async antiban tasks (camera, mouse, hover) while we wait on a pile
function Game.tiny_antiban()
	if not CONFIG.antiban or not S.antiban_ready then
		return
	end
	if Biometrics.random_boolean(CONST.MINE.TINY_ANTIBAN) then
		Antiban.do_async_tasks("game")
	end
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
	local key = `{stats.ashes}/{stats.failures}/{stats.banked}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "ashes", label = "Ash mined", value = stats.ashes },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "ashes" },
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
	elseif CONFIG.max_ashes > 0 and stats.ashes >= CONFIG.max_ashes then
		Log.log(NAME, `Mined {CONFIG.max_ashes} ash, stopping the script`)
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

	if CONFIG.bank and snap.free_slots == 0 and not skipped["BANK"] then
		return "BANK"
	end
	if skipped["MINE"] then
		return "LOADING"
	end
	plan.pile, plan.wait = Route.target()
	if S.hop_wanted then
		S.hop_wanted = false
		if time() >= S.hop_retry_at and not skipped["HOP"] then
			return "HOP"
		end
	end
	-- back at the top, next to the chest: bank before the trip if the inventory is filling up
	if S.top_check then
		S.top_check = false
		if CONFIG.bank and not skipped["BANK"] and 28 - snap.free_slots >= math.ceil(28 * CONFIG.bank_at) then
			return "BANK"
		end
	end
	return if plan.pile then "MINE" elseif plan.wait then "AWAIT" else "WAIT"
end

---------------------------------------------------------------------------------------------------
-- Handlers

-- walks to the pile, mines it and waits for the ash
function Handler.mine(pile: Host.Loc)
	local before = Read.ash()
	if not Objects.approach(pile, { CONST.PILE.option }) then
		-- someone else may have taken it as we got there
		if Read.pile_at(pile.x, pile.y) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't mine the pile at {pile.x}, {pile.y}`)
		end
		return
	end
	-- stay on the pile until it is depleted, with the inventory open to watch the ash come in
	Inventory.open()
	local ash = before
	local mined = 0
	local last_gain, last_tab_check = time(), time()
	while true do
		local now = Read.ash()
		if now > ash then
			mined += now - ash
			stats.ashes += now - ash
			ash = now
			S.failures_in_row = 0
			S.last_progress_at = time()
			last_gain = time()
		end
		-- gone: depleted, or someone else was quicker
		if not Read.pile_at(pile.x, pile.y) then
			-- we took its ash, so it was us: it is back in RESPAWN.TICKS
			if mined > 0 then
				S.respawn[`{pile.x},{pile.y}`] = Read.tick() + CONST.RESPAWN.TICKS
			end
			return
		end
		-- no room for more: the bank is next
		if CONFIG.bank and Inventory.free_slots() == 0 then
			return
		end
		local idle = time() - last_gain
		if mined == 0 and idle >= CONST.MINE.RESULT_MS then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `No ash from the pile at {pile.x}, {pile.y}`)
			return
		elseif idle >= CONST.MINE.STALL_MS then
			Log.log(NAME, `The pile at {pile.x}, {pile.y} stopped giving ash, moving on`)
			return
		end
		if time() - last_tab_check >= CONST.MINE.TAB_CHECK_MS then
			last_tab_check = time()
			Inventory.open()
		end
		Game.tiny_antiban()
		sleep(CONST.MINE.POLL_MS)
	end
end

-- walks to a random tile near a pile that is about to come back and waits for it; the pile once it is back
function Handler.await(tile: Host.Tile): Host.Loc?
	local key = `{tile.x},{tile.y}`
	local due = S.respawn[key]
	Log.log(NAME, `Waiting for the pile at {tile.x}, {tile.y} ({due - Read.tick()} ticks)`)
	if math.max(math.abs(tile.x - snap.me.x), math.abs(tile.y - snap.me.y)) > 2 then
		local dx, dy = Random.int(-2, 2), Random.int(-2, 2)
		if dx == 0 and dy == 0 then
			dx = 1
		end
		Walker.walk({ x = tile.x + dx, y = tile.y + dy }, { near = 1 })
	end
	Inventory.open()
	local deadline = time() + math.max(due - Read.tick(), 0) * 600 + CONST.RESPAWN.LATE_TICKS * 600
	local last_tab_check = time()
	while time() < deadline do
		local loc = Read.pile_at(tile.x, tile.y)
		if loc then
			return loc
		end
		if time() - last_tab_check >= CONST.MINE.TAB_CHECK_MS then
			last_tab_check = time()
			Inventory.open()
		end
		Game.tiny_antiban()
		sleep(CONST.MINE.POLL_MS)
	end
	S.respawn[key] = nil
	return nil
end

-- hops to another world; the piles there are all fresh and our timers don't apply
function Handler.hop()
	Log.log(NAME, "Other players are mining the piles, hopping worlds")
	local worlds = CONFIG.hop_worlds
	if #worlds == 0 then
		worlds = {}
		if WorldSwitcher.open(true) then
			for _, row in ipairs(WorldSwitcher.rows() or {}) do
				if row.members and row.available and (row.activity == nil or row.activity == "-") then
					table.insert(worlds, row.world)
				end
			end
		end
	end
	if WorldSwitcher.random(worlds) then
		S.respawn = {}
		return
	end
	Log.log(NAME, "Couldn't hop, trying again in a bit")
	S.hop_retry_at = time() + 20000
	S.skip["HOP"] = true
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

-- done with this pile, mined or not: never go back to it
function Handler.done_with_pile()
	S.idx += S.dir
	if CONFIG.antiban and S.antiban_ready then
		if not Antiban.do_antiban() then
			S.skip["MINE"] = true
		end
	end
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
		Handler.done_with_pile()
	end,
	-- a pile we depleted is about to come back: wait for it, then mine it
	AWAIT = function()
		local pile = Handler.await(assert(plan.wait))
		if pile then
			Handler.mine(pile)
		end
		Handler.done_with_pile()
	end,
	HOP = Handler.hop,
	-- every pile is gone: they come back after about half a minute
	WAIT = function()
		sleep(Random.int(600, 1200))
		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_antiban()
		end
	end,
}

-- asks for the settings that were hard coded in CONFIG, which stay as their defaults; false when the form is closed
function Game.ask(): boolean
	local values = Host.form({
		title = NAME,
		submit = "Start",
		fields = {
			{
				id = "max_ashes",
				kind = "number",
				label = "Max ashes (0 is unlimited)",
				default = CONFIG.max_ashes,
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

-- puts the form's values in CONFIG; they are read where they are used, so it works while the script runs too
function Game.apply_settings(values: { [string]: any })
	CONFIG.max_ashes = values.max_ashes
end

-- takes the settings the user sent with Update in the loader, if there are any
function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	if not S.finished then
		Route.start()
	end
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

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
