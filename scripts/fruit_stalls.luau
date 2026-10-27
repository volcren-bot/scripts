--!strict
-- Hosidius fruit stalls: steals from the two stalls in the house, keeps the good fruit and banks it.
-- Structure (same as tempoross.luau): get_state() reads the client and picks a state, a handler
-- per state does the work, Loop.run() repeats that until S.finished.
--
-- Start inside the stall house, or anywhere near it. With run energy it steals from whichever stall
-- is ready, walking between the two; without, it sits next to one and waits for it. A full inventory
-- drops the cheap fruit and fills baskets with strawberries; when nothing is left to make room it
-- banks everything, takes 5 empty baskets and walks back.
local Host = require("../../lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
type Tile = Host.Tile
local GameState = require("../../lib/main/game_state")
local Login = require("../../lib/main/interfaces/login/login")
local Biometrics = require("../../lib/main/antiban/biometrics")
local Antiban = require("../../lib/main/antiban/antiban")
local AntibanTasks = require("../../lib/main/antiban/antiban_tasks")
local Interact = require("../../lib/main/interact")
local Clickbox = require("../../lib/main/clickbox")
local Objects = require("../../lib/main/entities/objects")
local Player = require("../../lib/main/player")
local Players = require("../../lib/main/entities/players")
local Walker = require("../../lib/main/walker")
local Bankmain = require("../../lib/main/interfaces/mainscreen/bankmain")
local Inventory = require("../../lib/main/interfaces/gametabs/inventory")
local Stats = require("../../lib/main/interfaces/gametabs/stats")
local Log = require("../../lib/utils/log")
local Mouse = require("../../lib/utils/input/mouse")
local Random = require("../../lib/utils/math/random")
local StatsReport = require("../../lib/utils/stats_report")

local NAME = "Fruit stalls"

-- fixed values: ids, tiles, thresholds
local CONST = {
	REPORT = { counters_key = "" },
	STALL = {
		NAME = "Fruit Stall",
		-- any other id is the stall after it was stolen from (by us or another player)
		READY_ID = 28823,
		OPTION = "Steal-from",
		-- east and west stall, and the tile next to each inside the house
		EAST = { x = 1801, y = 3607 },
		WEST = { x = 1795, y = 3607 },
		EAST_SIDE = { x = 1800, y = 3607 },
		WEST_SIDE = { x = 1796, y = 3607 },
		-- how long a steal can take to show before it counts as missed
		RESULT_MS = 2400,
		-- the longest walk between the stalls to wait for
		WALK_MS = 6000,
		POLL_MS = 70,
	},
	-- the floor of the house
	HOUSE = { x1 = 1795, y1 = 3606, x2 = 1801, y2 = 3610 },
	DOOR = {
		NAME = "Door",
		CLOSED_ID = 7452,
		OPTION = "Open",
		-- the door on the south wall, towards both banks, and the tile just outside it
		SOUTH = { x = 1798, y = 3605 },
		OUTSIDE = { x = 1798, y = 3603 },
		OPEN_MS = 3500,
	},
	BANK = {
		CHEST = { name = "Bank chest", options = { "Use" }, stand = { x = 1809, y = 3569 } },
		BOOTH = { name = "Bank booth", options = { "Bank", "Use" }, stand = { x = 1749, y = 3599 } },
		OPEN_MS = 4000,
		GROUP = 12,
		-- the bank's item grid and its "Deposit inventory" button
		GRID = 12,
		DEPOSIT_INVENTORY = 47,
		BASKETS = 5,
		SCROLL_TRIES = 12,
	},
	RUN = { GROUP = 160, ORBS = { 28, 29, 27, 26 }, OPTION = "Toggle Run" },
	-- item names (not case sensitive)
	BASKET = "Basket",
	STRAWBERRY = "Strawberry",
	-- Strawberries(5) is a full basket
	BASKET_PARTIAL = "Strawberries(1..4)",
	BASKET_FULL = 5,
	JUNK = {
		"Cooking apple",
		"Banana",
		"Jangerberries",
		"Lemon",
		"Lime",
		"Redberries",
		"Pineapple",
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

-- what the user can change
local CONFIG = {
	max_trips = 0, -- bank trips before stopping, 0 is unlimited
	-- "random" picks one per trip, or "chest" / "booth"
	bank = "random",
	-- fill baskets with strawberries once there are this few free slots
	fill_below_free = 4,
	-- steal from both stalls while running with at least this much energy, else sit on one
	min_run_energy = 8,
	-- turn run back on once the energy is back up to a value rolled between these
	run_resume = { 25, 60 },
	-- with another player in the house, stay on one stall instead of running between the two
	stick_when_crowded = true,
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 12 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { trips = 0, steals = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	run_resume_at: number,
	run_checked_at: number,
	-- the stall we stay on while another player is stealing, nil when alone
	sticky: Tile?,
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
	run_resume_at = 0,
	run_checked_at = 0,
	sticky = nil,
	skip = {},
}

type Stall = { loc: Loc?, ready: boolean }

type Slot = { slot: number, id: number, quantity: number, name: string? }

type Snapshot = {
	state: ClientState,
	tick: number,
	pos: Tile,
	inside: boolean,
	items: { Slot },
	free: number,
	-- inventory by kind
	junk: { number },
	loose_strawberries: { number },
	-- slot of the basket a strawberry should go in, the fullest one that isn't full
	fill_target: number?,
	-- everything but baskets
	to_bank: number,
	east: Stall,
	west: Stall,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "STEAL" | "FILL" | "DROP" | "BANK" | "RETURN"

-- what get_state found that its handlers need
type Plan = { fill: { from: number, to: number }? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

local JUNK_SET: { [string]: boolean } = {}
for _, name in ipairs(CONST.JUNK) do
	JUNK_SET[string.lower(name)] = true
end

---------------------------------------------------------------------------------------------------
-- Reading the client

-- falls back to wall clock ticks
function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.in_house(pos: Tile): boolean
	local h = CONST.HOUSE
	return pos.x >= h.x1 and pos.x <= h.x2 and pos.y >= h.y1 and pos.y <= h.y2
end

function Read.stall_at(tile: Tile): Stall
	for _, loc in ipairs(Objects.find(CONST.STALL.NAME) or {}) do
		if loc.x == tile.x and loc.y == tile.y then
			return { loc = loc, ready = loc.id == CONST.STALL.READY_ID }
		end
	end
	return { loc = nil, ready = false }
end

-- the closed door on `tile`, nil when it is open (an open door has another id)
function Read.closed_door(tile: Tile): Loc?
	for _, loc in ipairs(Objects.find(CONST.DOOR.NAME) or {}) do
		if loc.x == tile.x and loc.y == tile.y and loc.id == CONST.DOOR.CLOSED_ID then
			return loc
		end
	end
	return nil
end

-- sorts the inventory into what the handlers work with
function Read.inventory(snapshot: Snapshot)
	local items = Inventory.items() or {}
	snapshot.items = items
	snapshot.free = 28 - #items
	snapshot.junk, snapshot.loose_strawberries, snapshot.fill_target, snapshot.to_bank = {}, {}, nil, 0

	local best_fill, empty_basket = 0, nil
	for _, item in ipairs(items) do
		local name = string.lower(item.name or "")
		if JUNK_SET[name] then
			table.insert(snapshot.junk, item.slot)
		elseif name == "strawberry" then
			table.insert(snapshot.loose_strawberries, item.slot)
		end
		if name == "basket" then
			empty_basket = empty_basket or item.slot
		else
			snapshot.to_bank += 1
			local n = tonumber(string.match(name, "^strawberries%((%d)%)$"))
			if n and n < CONST.BASKET_FULL and n > best_fill then
				best_fill, snapshot.fill_target = n, item.slot
			end
		end
	end
	snapshot.fill_target = snapshot.fill_target or empty_basket
end

function Read.refresh_snapshot(state: ClientState): boolean
	local pos = state.position
	if pos == nil then
		return false
	end
	snap = {
		state = state,
		tick = Read.current_tick(state),
		pos = { x = pos.x, y = pos.y },
		inside = Read.in_house(pos),
		east = Read.stall_at(CONST.STALL.EAST),
		west = Read.stall_at(CONST.STALL.WEST),
	} :: any
	Read.inventory(snap)
	return true
end

-- whether another player is in the stall house with us
function Read.crowded(): boolean
	local me = game_state().player_name
	for _, player in ipairs(Players.find() or {}) do
		if player.name ~= me and Read.in_house(player) then
			return true
		end
	end
	return false
end

-- whether we can run from one stall to the other: running and energy to spare
function Read.can_alternate(): boolean
	return Player.is_running() and (Player.run_energy() or 0) >= CONFIG.min_run_energy
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
	local MINUTE, HOUR, SECOND = Antiban.MINUTE, Antiban.HOUR, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Thieving" }
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

	Antiban.add_break(30 * MINUTE, 2 * MINUTE, 0.33, 0.01)
	Antiban.add_break(45 * MINUTE, 5 * MINUTE, 0.33, 0.02)
	Antiban.add_break(
		60 * MINUTE,
		10 * MINUTE,
		0.33,
		math.floor(0.05 * Biometrics.random_double(1.0) * 100 + 0.5) / 100
	)
	Antiban.add_break(
		250 * MINUTE,
		20 * MINUTE,
		0.33,
		math.floor(0.5 * Biometrics.random_double(1.3) * 100 + 0.5) / 100
	)

	Antiban.add_sleep(
		Biometrics.sleep_hour(),
		Biometrics.sleep_length() * HOUR,
		0.1,
		0.8 * Biometrics.random_double(1.3)
	)
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

-- turns run back on once there is enough energy for it to be worth it
function Game.ensure_run()
	if time() - S.run_checked_at < 5000 or Player.is_running() then
		return
	end
	S.run_checked_at = time()
	if (Player.run_energy() or 0) < S.run_resume_at then
		return
	end
	for _, child in ipairs(CONST.RUN.ORBS) do
		local orb = Host.widget(CONST.RUN.GROUP, child)
		if orb and not orb.hidden and orb.width > 10 then
			if Interact.with(orb, CONST.RUN.OPTION, nil, false) and Player.is_running() then
				S.run_resume_at = Random.int(CONFIG.run_resume[1], CONFIG.run_resume[2])
				Log.log(NAME, "Run turned on")
				return
			end
		end
	end
end

-- clears whatever item is left selected, not only ones the inventory knows about
function Game.deselect()
	local selected = Host.selected_widget()
	if selected == nil then
		return
	end
	Log.log(NAME, "Clearing a selected item")
	-- clicking the selected item again puts it down
	if selected.group == 149 then
		Inventory.click_slot(selected.index)
	else
		Inventory.deselect()
	end
	local waited = 0
	while Host.selected_widget() ~= nil and waited < 1200 do
		sleep(50)
		waited += 50
	end
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	for _, skill in ipairs(snap.state.skills or {}) do
		if skill.name == "Thieving" and skill.real_level < 25 then
			Log.log(NAME, `Thieving {skill.real_level} is below 25, the fruit stalls need 25`)
			S.finished = true
		end
	end

	S.run_resume_at = Random.int(CONFIG.run_resume[1], CONFIG.run_resume[2])
	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

-- opens the door on `tile` if it is closed
function Game.open_door(tile: Tile): boolean
	local door = Read.closed_door(tile)
	if door == nil then
		return true
	end
	Log.log(NAME, "Opening the door")
	if not Objects.approach(door, CONST.DOOR.OPTION) then
		return false
	end
	local waited = 0
	while Read.closed_door(tile) ~= nil do
		if waited >= CONST.DOOR.OPEN_MS then
			return false
		end
		sleep(100)
		waited += 100
	end
	return true
end

-- through the south door, in either direction; `to` is where to end up
function Game.walk_through_door(from: Tile, to: Tile): boolean
	if not Walker.walk(from, { near = 1 }) then
		return false
	end
	if not Game.open_door(CONST.DOOR.SOUTH) then
		return false
	end
	return Walker.walk(to, { near = 0 })
end

---------------------------------------------------------------------------------------------------
-- Banking

function Game.bank_kinds(): { string }
	if CONFIG.bank == "chest" then
		return { "CHEST", "BOOTH" }
	elseif CONFIG.bank == "booth" then
		return { "BOOTH", "CHEST" }
	elseif Random.chance(0.5) then
		return { "CHEST", "BOOTH" }
	end
	return { "BOOTH", "CHEST" }
end

-- walks to the bank of that kind and opens it
function Game.open_bank(kind: string): boolean
	local bank = (CONST.BANK :: any)[kind]
	Log.log(NAME, `Walking to the {string.lower(bank.name)}`)
	if not Walker.walk(bank.stand, { near = 2 }) then
		Log.log(NAME, `Couldn't walk to the {string.lower(bank.name)}`)
		return false
	end
	-- clicking while the scene still slides under the mouse misses
	Player.wait_still(3000)
	for attempt = 1, 2 do
		local me = Walker.position()
		local loc = me and Objects.nearest(bank.name, me)
		if loc == nil then
			Log.log(NAME, `No {bank.name} found`)
			return false
		end
		if Objects.approach(loc, bank.options) then
			local waited = 0
			while waited < CONST.BANK.OPEN_MS do
				if Bankmain.is_open() then
					return true
				end
				sleep(100)
				waited += 100
			end
		end
		Log.log(NAME, `The {string.lower(bank.name)} didn't open (attempt {attempt})`)
		Player.wait_still(3000)
	end
	return false
end

-- the bank's component for the item in that bank slot, scrolled into view
function Game.bank_box(slot: number): Host.Widget?
	for _ = 1, CONST.BANK.SCROLL_TRIES do
		local grid = Host.widget(CONST.BANK.GROUP, CONST.BANK.GRID)
		if grid == nil then
			return nil
		end
		for _, child in ipairs(Host.widget_children(CONST.BANK.GROUP, CONST.BANK.GRID) or {}) do
			if child.index == slot and not child.hidden then
				if child.y < grid.y then
					Mouse.scroll(2, false, grid)
				elseif child.y + child.height > grid.y + grid.height then
					Mouse.scroll(2, true, grid)
				else
					return child
				end
			end
		end
	end
	return nil
end

-- deposits everything and takes the empty baskets
function Game.use_bank(): boolean
	local pack = Inventory
	if pack.count_used() ~= 0 then
		local button = Host.widget(CONST.BANK.GROUP, CONST.BANK.DEPOSIT_INVENTORY)
		if button == nil then
			return false
		end
		Mouse.click(button)
		if not pack.wait_used(0, 3000) then
			Log.log(NAME, "The inventory wasn't deposited")
			return false
		end
	end
	local slot = Bankmain.index_of(CONST.BASKET)
	if slot == nil then
		Log.log(NAME, "No baskets in the bank, going without")
		return true
	end
	local box = Game.bank_box(slot)
	if box == nil then
		Log.log(NAME, "Couldn't find the baskets on screen")
		return false
	end
	local amount = `Withdraw-{CONST.BANK.BASKETS}`
	if
		not Interact.with(box, amount, CONST.BASKET, false)
		and not Interact.with(box, "Withdraw-All", CONST.BASKET, false)
	then
		return false
	end
	return pack.wait_used(CONST.BANK.BASKETS, 3000) or (pack.count_used() or 0) > 0
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
	local key = `{stats.steals}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "steals", label = "Steals", value = stats.steals },
		{ id = "trips", label = "Bank trips", value = stats.trips },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "steals" },
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
	elseif CONFIG.max_trips > 0 and stats.trips >= CONFIG.max_trips then
		Log.log(NAME, `Reached {CONFIG.max_trips} bank trips, stopping the script`)
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

	-- outside the house we are on a bank trip: bank whatever we carry, then go back
	if not snap.inside then
		return if snap.to_bank > 0 then "BANK" else "RETURN"
	end

	local can_fill = #snap.loose_strawberries > 0 and snap.fill_target ~= nil and not skipped["FILL"]
	if can_fill then
		plan.fill = { from = snap.loose_strawberries[1], to = snap.fill_target :: number }
	end
	if snap.free == 0 then
		if #snap.junk > 0 and not skipped["DROP"] then
			return "DROP"
		end
		if can_fill then
			return "FILL"
		end
		return "BANK"
	end

	-- fill the baskets while the stalls are down, or when space runs low
	if can_fill and (snap.free <= CONFIG.fill_below_free or (not snap.east.ready and not snap.west.ready)) then
		return "FILL"
	end
	return "STEAL"
end

---------------------------------------------------------------------------------------------------
-- Handlers

-- the stall to steal from now, nil when there is none ready
function Handler.pick_stall(): Stall?
	local east, west = snap.east, snap.west
	-- with company, keep to one stall: the one we are nearest to when the other player shows up
	if CONFIG.stick_when_crowded and Read.crowded() then
		if S.sticky == nil then
			local function dist(t: Tile): number
				return math.max(math.abs(t.x - snap.pos.x), math.abs(t.y - snap.pos.y))
			end
			local nearest = if dist(CONST.STALL.EAST) <= dist(CONST.STALL.WEST) then CONST.STALL.EAST else CONST.STALL.WEST
			S.sticky = nearest
			Log.log(NAME, `Another player is stealing, staying on the {if nearest == CONST.STALL.EAST then "east" else "west"} stall`)
		end
		local stall = if S.sticky == CONST.STALL.EAST then east else west
		if stall.ready and stall.loc then
			return stall
		end
		return nil
	elseif S.sticky ~= nil then
		S.sticky = nil
		Log.log(NAME, "Alone again, using both stalls")
	end

	local alternate = Read.can_alternate()
	local candidates: { Stall } = {}
	for _, stall in ipairs({ east, west }) do
		if stall.ready and stall.loc then
			table.insert(candidates, stall)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local best: Stall? = nil
	local best_d = math.huge
	for _, stall in ipairs(candidates) do
		local d = Objects.distance(stall.loc :: Loc, snap.pos)
		if d < best_d then
			best, best_d = stall, d
		end
	end
	-- without energy only the stall we stand next to is worth it
	if not alternate and best_d > 2 then
		return nil
	end
	return best
end

-- waits for the steal to show: the stall goes down or the inventory fills
function Handler.wait_stolen(stall: Stall, before: number): boolean
	local tile = { x = (stall.loc :: Loc).x, y = (stall.loc :: Loc).y }
	local start = time()
	while time() - start < CONST.STALL.RESULT_MS do
		sleep(CONST.STALL.POLL_MS)
		if not Read.stall_at(tile).ready or (Inventory.count_used() or before) > before then
			return true
		end
	end
	return false
end

-- moves the mouse onto the stall we are leaving, where the screen will show it once we stand next to
-- the one just clicked: the camera follows the player, so that is not where it is drawn now
function Handler.pre_hover(clicked: Stall, other: Stall)
	if other.loc == nil or S.sticky ~= nil or not Read.can_alternate() then
		return
	end
	local side = if clicked == snap.east then CONST.STALL.EAST_SIDE else CONST.STALL.WEST_SIDE
	local box = Objects.projected(other.loc, side)
	local point = box and Clickbox.target(box, CONST.STALL.NAME)
	if point then
		Mouse.move(point)
	end
end

function Handler.steal(stall: Stall)
	local loc = stall.loc :: Loc
	local before = #snap.items
	-- no waiting for the walk: the mouse goes to the other stall while we are on our way
	if not Objects.interact(loc, CONST.STALL.OPTION, false) then
		stats.failures += 1
		S.failures_in_row += 1
		Log.log(NAME, `Steal at {loc.x},{loc.y} failed ({S.failures_in_row} in a row)`)
		-- a stall that went down under the click, or a misclick on something next to it
		sleep(Random.int(300, 800))
		return
	end
	Handler.pre_hover(stall, if stall == snap.east then snap.west else snap.east)
	Player.wait_walk(CONST.STALL.WALK_MS)
	if Handler.wait_stolen(stall, before) then
		stats.steals += 1
	end
	S.failures_in_row = 0
end

function Handler.idle()
	Game.ensure_run()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_antiban()
	end
	sleep(CONST.STALL.POLL_MS)
end

-- leaves the house, banks and comes back to the stalls
function Handler.bank()
	for _, kind in ipairs(Game.bank_kinds()) do
		if snap.inside and not Game.walk_through_door(CONST.STALL.EAST_SIDE, CONST.DOOR.OUTSIDE) then
			stats.failures += 1
			S.failures_in_row += 1
			return
		end
		snap.inside = false
		if Game.open_bank(kind) then
			local ok = Game.use_bank()
			Bankmain.close()
			if ok then
				stats.trips += 1
				S.failures_in_row = 0
				S.last_progress_at = time()
				Log.log(NAME, `Banked ({stats.trips} trips)`)
				return
			end
		end
		Log.log(NAME, `Banking at the {string.lower(kind)} failed, trying the other one`)
		Bankmain.close()
	end
	S.failures_in_row += 1
	stats.failures += 1
end

function Handler.return_to_house()
	local side = if Random.chance(0.5) then CONST.STALL.EAST_SIDE else CONST.STALL.WEST_SIDE
	if Game.walk_through_door(CONST.DOOR.OUTSIDE, side) then
		S.failures_in_row = 0
		S.last_progress_at = time()
		return
	end
	stats.failures += 1
	S.failures_in_row += 1
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	STEAL = function()
		-- an item left selected (an interrupted basket fill) turns every click into "use on"
		Game.deselect()
		Game.ensure_run()
		local stall = Handler.pick_stall()
		if stall then
			Handler.steal(stall)
		else
			Handler.idle()
		end
	end,
	FILL = function()
		local fill = plan.fill :: { from: number, to: number }
		if not Inventory.combine_slots(fill.from, fill.to) then
			S.skip["FILL"] = true
			Game.deselect()
		else
			Log.log(NAME, "Strawberry put in a basket")
			Game.deselect()
		end
	end,
	DROP = function()
		Log.log(NAME, `Dropping {#snap.junk} cheap fruit`)
		if not Inventory.shift_drop(CONST.JUNK :: { string | number }) then
			S.skip["DROP"] = true
		end
	end,
	BANK = Handler.bank,
	RETURN = Handler.return_to_house,
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
		-- the steal loop has its own pace
		if state ~= "STEAL" then
			sleep(Random.int(60, 140))
		end
	end
	Log.log(NAME, "Done")
end

Loop.run()
