--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
type Tile = Host.Tile
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local Clickbox = require("@lib/main/clickbox")
local GameState = require("@lib/main/game_state")
local Interact = require("@lib/main/interact")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Logout = require("@lib/main/interfaces/gametabs/logout")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Players = require("@lib/main/entities/players")
local Random = require("@lib/utils/math/random")
local SidePanels = require("@lib/main/interfaces/gametabs/side_panels")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Walker = require("@lib/main/walker")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

-- the stall being worked, set once chosen (see Loop.choose_stall)
local NAME = "Stall thiever"

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
	BAKER = {
		STALL = {
			NAME = "Baker's stall",
			-- any other id is the stall after it was stolen from
			READY_ID = 11730,
			OPTION = "Steal-from",
			-- the stall covers 1638..1639, 3683..3684
			TILE = { x = 1638, y = 3683 },
			RESULT_MS = 2400,
			WALK_MS = 3000,
			POLL_MS = 70,
		},
		-- the only tile we steal from: the guards roaming the market can't see it
		SAFE = { x = 1638, y = 3685 },
		-- where to go to pull a guard away, south of the stall
		LURE = { x = 1638, y = 3679 },
		GUARD = "Guard",
		-- what the game says when a steal is refused because a guard is fighting us
		COMBAT_TEXT = "during combat",
		-- how long to wait for the guard to follow us south, and how close it has to be
		LURE_WAIT_MS = 6000,
		LURE_CLOSE = 4,
		-- the booths on the 2nd floor of the building to the west
		BANK = { name = "Bank booth", options = { "Bank", "Use" }, stand = { x = 1611, y = 3681 }, plane = 2 },
		THIEVING = 5,
		JUNK = { "Bread", "Chocolate slice" },
		-- what we eat when the hitpoints are low, best first (item names, not case sensitive)
		FOOD = { "Slice of cake", "2/3 cake", "Chocolate slice", "Bread", "Cake" },
		FOOD_OPTION = "Eat",
		EAT_MS = 1800,
	},
	TEA = {
		STALL = {
			NAME = "Tea stall",
			-- any other id is the stall after it was stolen from
			READY_ID = 635,
			-- the stall covers 3269..3270, 3410..3411
			TILE = { x = 3269, y = 3410 },
			OPTION = "Steal-from",
			RESULT_MS = 2400,
			WALK_MS = 3000,
			POLL_MS = 70,
		},
		-- the tile we steal from
		STAND = { x = 3268, y = 3410 },
		THIEVING = 5,
		JUNK = { "Cup of tea" },
	},
	PORT_ROBERTS = {
		-- best first: the stall after the one worked is where to go while a guard is at it
		STALLS = {
			"Cannonball stall",
			"Ore stall",
			"Gem stall",
			"Spice stall",
			"Silver stall",
			"Fish stall",
			"Fur stall",
			"Silk stall",
			"Veg stall",
		},
		OPTION = "Steal-from",
		GUARD = "Market Guard",
		-- the tile a guard stands on in front of each stall, and we stand on to steal from it
		STOPS = {
			["Cannonball stall"] = { x = 1867, y = 3295 },
			["Ore stall"] = { x = 1863, y = 3294 },
			["Gem stall"] = { x = 1869, y = 3290 },
			["Spice stall"] = { x = 1864, y = 3290 },
			["Silver stall"] = { x = 1866, y = 3290 },
			["Fish stall"] = { x = 1863, y = 3292 },
			["Fur stall"] = { x = 1869, y = 3292 },
			["Silk stall"] = { x = 1869, y = 3295 },
			["Veg stall"] = { x = 1865, y = 3295 },
		},
		-- the guards walk round the edge of this rectangle, east along the top first from `start`
		LOOP = { x1 = 1863, y1 = 3290, x2 = 1869, y2 = 3295, start = { x = 1867, y = 3295 } },
		PLAZA = { x1 = 1858, y1 = 3284, x2 = 1874, y2 = 3299 },
		-- the amulet that teleports out of the cell, worn or in the inventory (item names, not case sensitive)
		AMULET = { name = "sailors' amulet", option = "Port Roberts", TELEPORT_MS = 8000 },
		-- locked in: fewer than this many tiles reachable around us, none on the area's edge
		JAIL_SCAN = 14,
		JAIL_MAX_TILES = 60,
		DOOR = { name = "Cell door", option = "Picklock", TRY_MS = 5000, TRIES = 8, OUT = { x = 1886, y = 3273 } },
		CAUGHT_TEXT = "under arrest",
		PICKED_TEXT = "succeed",
		STEAL_TEXT = "you steal",
		-- ticks a guard stays at a stall
		DWELL = 8,
		-- leave a stall this many ticks before the guard before it would move on to it
		LEAD = 2,
		-- no xp for this long while stealing: the steal stopped, click again
		STALE_MS = 12000,
		-- bank when the inventory is nearly full: the booths northeast of the plaza are at 1881..1884,3316
		BANK = { name = "Bank booth", options = { "Bank", "Use" }, stand = { x = 1882, y = 3315 } },
		FULL_FREE = 1,
		-- how long the lock picking animation can take
		PICK_MS = 5000,
		POLL_MS = 100,
	},
	-- item names (not case sensitive)
	BASKET = "Basket",
	STRAWBERRY = "Strawberry",
	-- Strawberries(5) is a full basket
	BASKET_PARTIAL = "Strawberries(1..4)",
	BASKET_FULL = 5,
	-- how long "Fill" can take to show in the inventory
	BASKET_FILL_MS = 2400,
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

local Read, Game, Loop, Handler, Bakers, Port = {}, {}, {}, {}, {}, {}

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
	-- keep to that stall until the house has been empty of others this many seconds
	crowd_linger_s = 30,
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 12 },
	antiban = true,
	-- Baker's stalls: lure a guard away at most this many times in a row before giving up
	max_lures_in_row = 5,
	-- Baker's stalls: stop when the hitpoints fall to this (a guard we can't shake off)
	min_hitpoints = 12,
	-- Baker's stalls: eat what we carry once the hitpoints fall to this
	eat_at_hitpoints = 20,
}

-- the stall being worked: "fruit", "bakers", "tea" or "port_roberts", chosen at the start
local PROFILE = "fruit"
-- the stall's own values (ids, option, timings) and the items to drop
local STALL = CONST.STALL
local JUNK: { string } = CONST.JUNK
-- Port Roberts: the stall picked on the second form
local PORT_STALL = ""

-- counters shown next to the skills in the loader's XP tracker
local stats = { trips = 0, steals = 0, failures = 0, lures = 0, arrests = 0 }

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
	-- when we last saw another player in the house
	crowded_at: number,
	-- states to ignore for one loop
	skip: { [string]: boolean },
	-- Baker's stalls: our hitpoints when last looked at, and the last chat message looked at
	hitpoints: number,
	chat_uid: number,
	lures_in_row: number,
	steals_since_lure: number,
	-- Port Roberts: the stall being stolen from (nil when standing), when it was clicked, and whether we are in jail
	port_at: string?,
	port_clicked_at: number,
	in_jail: boolean,
	-- Port Roberts: whether the amulet was tried since we were put in the cell
	amulet_tried: boolean,
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
	crowded_at = 0,
	skip = {},
	hitpoints = 0,
	chat_uid = 0,
	lures_in_row = 0,
	steals_since_lure = 0,
	port_at = nil,
	port_clicked_at = 0,
	in_jail = false,
	amulet_tried = false,
}

type Stall = { loc: Loc?, ready: boolean }

type Guard = { index: number, x: number, y: number, animation: number }

type Slot = { slot: number, id: number, quantity: number, name: string? }

type Snapshot = {
	state: ClientState,
	tick: number,
	pos: Tile,
	inside: boolean,
	plane: number,
	-- Baker's stalls: whether we stand on the safe tile, and the stall
	at_safe: boolean,
	baker: Stall,
	tea: Stall,
	items: { Slot },
	free: number,
	-- inventory by kind
	junk: { number },
	loose_strawberries: { number },
	-- slot of the basket a strawberry should go in, the fullest one that isn't full
	fill_target: number?,
	-- whether that basket already holds a strawberry, so its own "Fill" option only takes strawberries
	fill_started: boolean,
	-- Baker's stalls: slot of the food to eat first, if we carry any
	food: number?,
	-- everything but baskets
	to_bank: number,
	east: Stall,
	west: Stall,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "PORT" | "JAIL" | "STEAL" | "FILL" | "DROP" | "BANK" | "RETURN" | "LURE" | "EAT"

-- what get_state found that its handlers need
type Plan = { fill: { from: number, to: number, direct: boolean }? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

local JUNK_SET: { [string]: boolean } = {}
local function set_junk(names: { string })
	JUNK, JUNK_SET = names, {}
	for _, name in ipairs(names) do
		JUNK_SET[string.lower(name)] = true
	end
end
set_junk(CONST.JUNK)

-- how well a food ranks, 1 is eaten first
local FOOD_RANK: { [string]: number } = {}
for rank, name in ipairs(CONST.BAKER.FOOD) do
	FOOD_RANK[string.lower(name)] = rank
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
	for _, loc in ipairs(Objects.find(STALL.NAME) or {}) do
		if loc.x == tile.x and loc.y == tile.y then
			return { loc = loc, ready = loc.id == STALL.READY_ID }
		end
	end
	return { loc = nil, ready = false }
end

-- slots of the strawberries not in a basket
function Read.loose_strawberries(): { number }
	local slots = {}
	for _, item in ipairs(Inventory.items() or {}) do
		if string.lower(item.name or "") == "strawberry" then
			table.insert(slots, item.slot)
		end
	end
	return slots
end

-- sorts the inventory into what the handlers work with
function Read.inventory(snapshot: Snapshot)
	local items = Inventory.items() or {}
	snapshot.items = items
	snapshot.free = 28 - #items
	snapshot.junk, snapshot.loose_strawberries, snapshot.fill_target, snapshot.to_bank = {}, {}, nil, 0
	snapshot.fill_started = false
	snapshot.food = nil

	local best_fill, empty_basket, best_food = 0, nil, math.huge
	for _, item in ipairs(items) do
		local name = string.lower(item.name or "")
		local rank = FOOD_RANK[name]
		if PROFILE == "bakers" and rank and rank < best_food then
			best_food, snapshot.food = rank, item.slot
		end
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
	snapshot.fill_started = snapshot.fill_target ~= nil
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
		plane = pos.plane,
		at_safe = pos.plane == 0 and pos.x == CONST.BAKER.SAFE.x and pos.y == CONST.BAKER.SAFE.y,
	} :: any
	if PROFILE == "fruit" then
		snap.east, snap.west = Read.stall_at(CONST.STALL.EAST), Read.stall_at(CONST.STALL.WEST)
	elseif PROFILE == "tea" then
		snap.tea = Read.stall_at(CONST.TEA.STALL.TILE)
	elseif PROFILE == "bakers" then
		snap.baker = Read.stall_at(CONST.BAKER.STALL.TILE)
	end
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
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
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

	-- breaks and sleeps come from the loader's Breaks tab
	Antiban.sync_config()
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

	local needed = if PROFILE == "fruit"
		then 25
		elseif PROFILE == "tea" then CONST.TEA.THIEVING
		elseif PROFILE == "port_roberts" then 0
		else CONST.BAKER.THIEVING
	for _, skill in ipairs(snap.state.skills or {}) do
		if skill.name == "Thieving" and skill.real_level < needed then
			Log.log(NAME, `Thieving {skill.real_level} is below {needed}, {NAME} need {needed}`)
			S.finished = true
		end
	end

	if PROFILE == "port_roberts" then
		-- messages from before don't count
		Bakers.combat_message()
	elseif PROFILE == "bakers" then
		-- messages from before we started don't count
		Bakers.combat_message()
		S.hitpoints = Player.hitpoints() or 0
	end

	S.run_resume_at = Random.int(CONFIG.run_resume[1], CONFIG.run_resume[2])
	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

---------------------------------------------------------------------------------------------------
-- Banking

function Game.bank_kinds(): { string }
	if PROFILE == "port_roberts" then
		return { "PORT" }
	elseif PROFILE == "bakers" then
		return { "BAKER" }
	elseif CONFIG.bank == "chest" then
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
	local bank = if kind == "BAKER"
		then CONST.BAKER.BANK
		elseif kind == "PORT" then CONST.PORT_ROBERTS.BANK
		else (CONST.BANK :: any)[kind]
	Log.log(NAME, `Walking to the {string.lower(bank.name)}`)
	-- the booths are on another floor: the walker takes the stairs
	if not Walker.walk(bank.stand, { near = 2, plane = bank.plane }) then
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
	if PROFILE ~= "fruit" then
		return true
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
	local key = `{stats.steals}/{stats.trips}/{stats.failures}/{stats.lures}/{stats.arrests}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	local counters = {
		{ id = "steals", label = "Steals", value = stats.steals },
		{ id = "trips", label = "Bank trips", value = stats.trips },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "steals" },
	}
	if PROFILE == "bakers" then
		table.insert(counters, { id = "lures", label = "Guards lured", value = stats.lures })
	end
	if PROFILE == "port_roberts" then
		table.insert(counters, { id = "arrests", label = "Arrests", value = stats.arrests })
	end
	Host.report_counters(counters)
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

	-- a full inventory is dropped, filled or banked from its tab, which antiban may have switched away from
	if snap.free == 0 and not Inventory.is_open() then
		SidePanels.open("Inventory")
	end

	if PROFILE == "bakers" then
		return Bakers.pick_state(skipped)
	elseif PROFILE == "port_roberts" then
		return Port.pick_state(skipped)
	elseif PROFILE == "tea" then
		return if snap.free == 0 and not skipped["DROP"] then "DROP" else "STEAL"
	end

	-- outside the house we are on a bank trip: bank whatever we carry, then go back
	if not snap.inside then
		return if snap.to_bank > 0 then "BANK" else "RETURN"
	end

	local can_fill = #snap.loose_strawberries > 0 and snap.fill_target ~= nil and not skipped["FILL"]
	if can_fill then
		plan.fill = { from = snap.loose_strawberries[1], to = snap.fill_target :: number, direct = snap.fill_started }
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
	local crowded = CONFIG.stick_when_crowded and Read.crowded()
	if crowded then
		S.crowded_at = time()
	end
	-- someone stepping out for a moment doesn't free the other stall
	if crowded or (S.sticky ~= nil and time() - S.crowded_at < CONFIG.crowd_linger_s * 1000) then
		if S.sticky == nil then
			local function dist(t: Tile): number
				return math.max(math.abs(t.x - snap.pos.x), math.abs(t.y - snap.pos.y))
			end
			local nearest = if dist(CONST.STALL.EAST) <= dist(CONST.STALL.WEST)
				then CONST.STALL.EAST
				else CONST.STALL.WEST
			S.sticky = nearest
			Log.log(
				NAME,
				`Another player is stealing, staying on the {if nearest == CONST.STALL.EAST then "east" else "west"} stall`
			)
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
	while time() - start < STALL.RESULT_MS do
		sleep(STALL.POLL_MS)
		if not Read.stall_at(tile).ready or (Inventory.count_used() or before) > before then
			return true
		end
	end
	return false
end

-- moves the mouse onto the stall we are leaving, where it will be drawn once we stand next to the other
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
	if not Objects.interact(loc, STALL.OPTION, false) then
		stats.failures += 1
		S.failures_in_row += 1
		Log.log(NAME, `Steal at {loc.x},{loc.y} failed ({S.failures_in_row} in a row)`)
		-- a stall that went down under the click, or a misclick on something next to it
		sleep(Random.int(300, 800))
		return
	end
	if PROFILE == "fruit" then
		Handler.pre_hover(stall, if stall == snap.east then snap.west else snap.east)
	end
	Player.wait_walk(STALL.WALK_MS)
	if Handler.wait_stolen(stall, before) then
		stats.steals += 1
	end
	S.failures_in_row = 0
end

-- "Fill" on a basket already holding strawberries; true once strawberries left the inventory
function Handler.fill_basket(slot: number): boolean
	local before = #Read.loose_strawberries()
	if not Inventory.interact_slot(slot, "Fill") then
		return false
	end
	local waited = 0
	while waited < CONST.BASKET_FILL_MS do
		sleep(CONST.STALL.POLL_MS)
		waited += CONST.STALL.POLL_MS
		if #Read.loose_strawberries() < before then
			return true
		end
	end
	return false
end

function Handler.idle()
	Game.ensure_run()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_antiban()
	end
	sleep(STALL.POLL_MS)
end

-- leaves the house, banks and comes back to the stalls
function Handler.bank()
	for _, kind in ipairs(Game.bank_kinds()) do
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
	if Walker.walk(side, { near = 0 }) then
		S.failures_in_row = 0
		S.last_progress_at = time()
		return
	end
	stats.failures += 1
	S.failures_in_row += 1
end

---------------------------------------------------------------------------------------------------
-- Baker's stalls

local function chebyshev(a: Tile, b: Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- the guards around, nearest to a tile first (the safe tile by default)
function Bakers.guards(from: Tile?): { Guard }
	local origin = from or CONST.BAKER.SAFE
	local guards: { Guard } = {}
	for _, npc in ipairs(Npcs.find(CONST.BAKER.GUARD) or {}) do
		table.insert(guards, { index = npc.index, x = npc.x, y = npc.y, animation = npc.animation })
	end
	table.sort(guards, function(a, b)
		return chebyshev(a, origin) < chebyshev(b, origin)
	end)
	return guards
end

-- whether the game told us we are in combat since last looked: it refuses a steal then
function Bakers.combat_message(): boolean
	local found = false
	for _, message in ipairs(Host.chat_messages() or {}) do
		if message.uid > S.chat_uid then
			S.chat_uid = message.uid
			if string.find(string.lower(message.text), CONST.BAKER.COMBAT_TEXT, 1, true) then
				found = true
			end
		end
	end
	return found
end

-- the guard that has seen us, if any: it refuses the steal, drops our hitpoints or swings at us
function Bakers.spotted(): Guard?
	local guards = Bakers.guards()
	local nearest = guards[1]
	local reason: string? = nil

	if Bakers.combat_message() then
		reason = "the game says we are in combat"
	end
	local hitpoints = Player.hitpoints()
	if hitpoints then
		if hitpoints < S.hitpoints then
			reason = reason or `hitpoints {S.hitpoints} -> {hitpoints}`
		end
		S.hitpoints = hitpoints
	end
	if nearest and chebyshev(nearest, CONST.BAKER.SAFE) <= 1 and nearest.animation ~= -1 then
		reason = reason or `guard {nearest.index} next to us is attacking`
	end
	if reason == nil then
		return nil
	end
	Log.log(NAME, `Spotted: {reason}`)
	return nearest or { index = -1, x = CONST.BAKER.SAFE.x, y = CONST.BAKER.SAFE.y, animation = -1 }
end

function Bakers.pick_state(skipped: { [string]: boolean }): State
	-- off the safe tile we are on a bank trip or have been pulled away: bank what we carry, else go back
	if not snap.at_safe then
		return if snap.plane ~= 0 and snap.to_bank > 0 then "BANK" else "RETURN"
	end
	-- before anything else: a guard on us hits hard, and the lure logs out when the hitpoints get too low
	local hitpoints = Player.hitpoints()
	if snap.food and hitpoints and hitpoints <= CONFIG.eat_at_hitpoints and not skipped["EAT"] then
		return "EAT"
	end
	if Bakers.spotted() then
		return "LURE"
	end
	if snap.free == 0 then
		if #snap.junk > 0 and not skipped["DROP"] then
			return "DROP"
		end
		return "BANK"
	end
	return "STEAL"
end

function Handler.bakers_steal()
	-- an item left selected turns every click into "use on"
	Game.deselect()
	Game.ensure_run()
	local stall = snap.baker
	if stall.ready and stall.loc then
		local before = stats.steals
		Handler.steal(stall)
		if stats.steals > before then
			S.steals_since_lure += 1
			if S.steals_since_lure >= 5 then
				S.lures_in_row = 0
			end
		end
	else
		Handler.idle()
	end
end

-- eats the best food we carry, one bite per loop
function Handler.eat()
	local hitpoints = Player.hitpoints() or 0
	local before = #snap.items
	local name = "food"
	for _, item in ipairs(snap.items) do
		if item.slot == snap.food then
			name = item.name or name
		end
	end
	Log.log(NAME, `Hitpoints at {hitpoints}, eating {name}`)
	Game.deselect()
	if not Inventory.interact_slot(snap.food :: number, CONST.BAKER.FOOD_OPTION) then
		S.skip["EAT"] = true
		return
	end
	-- a cake leaves its remainder in the slot: the hitpoints are what tell it was eaten
	local waited = 0
	while waited < CONST.BAKER.EAT_MS do
		sleep(100)
		waited += 100
		local now = Player.hitpoints()
		if (now and now > hitpoints) or (Inventory.count_used() or before) < before then
			break
		end
	end
	-- the hit that took us here is not a new sighting
	S.hitpoints = Player.hitpoints() or S.hitpoints
end

-- pulls the guard that saw us away from the safe tile: south, to where it can reach us, and back
function Handler.lure()
	S.lures_in_row += 1
	S.steals_since_lure = 0
	stats.lures += 1
	if S.lures_in_row > CONFIG.max_lures_in_row then
		Log.log(NAME, `A guard still follows us after {CONFIG.max_lures_in_row} lures, stopping the script`)
		S.finished = true
		return
	end
	local hitpoints = Player.hitpoints() or 99
	if hitpoints <= CONFIG.min_hitpoints then
		-- standing on the tile with a guard on us only gets worse: leave the game (it takes a few tries in combat)
		Log.log(NAME, `Hitpoints down to {hitpoints}, logging out and stopping the script`)
		Logout.logout(6, 20000)
		S.finished = true
		return
	end
	Log.log(NAME, `A guard saw us, luring it south ({stats.lures} lures)`)
	if not Walker.walk(CONST.BAKER.LURE, { near = 1, plane = 0 }) then
		Log.log(NAME, "Couldn't walk south")
	end
	-- go back once the guard is south of the stall and close behind, where it gets stuck
	local south = CONST.BAKER.STALL.TILE.y - 1
	local waited = 0
	Game.ensure_run()
	while waited < CONST.BAKER.LURE_WAIT_MS do
		local me = Walker.position()
		if me == nil then
			break
		end
		local guard = Bakers.guards(me)[1]
		if guard == nil or (guard.y <= south and chebyshev(guard, me) <= CONST.BAKER.LURE_CLOSE) then
			break
		end
		sleep(150)
		waited += 150
	end
	Handler.return_to_safe()
	-- what happened on the way is dealt with: only new hits and messages count from here
	Bakers.combat_message()
	S.hitpoints = Player.hitpoints() or S.hitpoints
end

-- back on the exact tile the guards can't see
function Handler.return_to_safe()
	-- from the bank this is down the stairs: the plane has to be said
	if Walker.walk(CONST.BAKER.SAFE, { near = 0, plane = 0 }) then
		S.failures_in_row = 0
		S.last_progress_at = time()
		return
	end
	stats.failures += 1
	S.failures_in_row += 1
end

---------------------------------------------------------------------------------------------------
-- Port Roberts

-- the tiles the guards walk, in the order they walk them, and where each stall's tile is in it
local LOOP_TILES: { Tile } = {}
local LOOP_INDEX: { [number]: number } = {}
-- per stall: where in the loop its guard stop is, and the stops before it
local STOP_INDEX: { [string]: number } = {}
local STOP_BEFORE: { [string]: { number } } = {}

local function tile_key(x: number, y: number): number
	return x * 10000 + y
end

do
	local r = CONST.PORT_ROBERTS.LOOP
	local function add(x: number, y: number)
		table.insert(LOOP_TILES, { x = x, y = y })
		LOOP_INDEX[tile_key(x, y)] = #LOOP_TILES - 1
	end
	for x = r.start.x, r.x2 do
		add(x, r.y2)
	end
	for y = r.y2 - 1, r.y1, -1 do
		add(r.x2, y)
	end
	for x = r.x2 - 1, r.x1, -1 do
		add(x, r.y1)
	end
	for y = r.y1 + 1, r.y2 do
		add(r.x1, y)
	end
	for x = r.x1 + 1, r.start.x - 1 do
		add(x, r.y2)
	end

	local order: { string } = {}
	for name, stop in pairs(CONST.PORT_ROBERTS.STOPS) do
		STOP_INDEX[name] = LOOP_INDEX[tile_key(stop.x, stop.y)]
		table.insert(order, name)
	end
	table.sort(order, function(a, b)
		return STOP_INDEX[a] < STOP_INDEX[b]
	end)
	-- the indexes of the stops before each stall's, nearest first
	for position, name in ipairs(order) do
		local before = {}
		for back = 1, 2 do
			local other = order[(position - 1 - back) % #order + 1]
			table.insert(before, STOP_INDEX[other])
		end
		STOP_BEFORE[name] = before
	end
end

type GuardTrack = { x: number, y: number, since: number, seen: number }

-- each guard's tile, and the tick it last moved (the earliest it could have when we looked away)
local guards: { [number]: GuardTrack } = {}

local function ahead(from: number, to: number): number
	return (to - from) % #LOOP_TILES
end

-- follows the guards: where they are, and how long each has stood still
function Port.track()
	local tick = Read.current_tick(game_state())
	for _, npc in ipairs(Npcs.find(CONST.PORT_ROBERTS.GUARD) or {}) do
		local seen = guards[npc.index]
		if seen == nil then
			guards[npc.index] = { x = npc.x, y = npc.y, since = tick - CONST.PORT_ROBERTS.DWELL, seen = tick }
		else
			if seen.x ~= npc.x or seen.y ~= npc.y then
				seen.x, seen.y = npc.x, npc.y
				-- if we missed ticks, it moved as early as it could have: it is the safer guess
				seen.since = if tick - seen.seen > 1 then seen.seen + 1 else tick
			end
			seen.seen = tick
		end
	end
end

-- the guards as loop position:ticks stood still, for the log
function Port.guards_text(): string
	local tick = Read.current_tick(game_state())
	local parts: { string } = {}
	for _, guard in pairs(guards) do
		table.insert(parts, `{LOOP_INDEX[tile_key(guard.x, guard.y)] or "?"}:{tick - guard.since}`)
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

-- counts the steals the game reports
function Port.count_steals()
	for _, message in ipairs(Host.chat_messages() or {}) do
		if message.uid > S.chat_uid then
			S.chat_uid = message.uid
			if string.find(string.lower(message.text), CONST.PORT_ROBERTS.STEAL_TEXT, 1, true) then
				stats.steals += 1
			end
		end
	end
end

-- whether a guard is, or is about to be, at the stall; `lead`/`wide` widen that, `eta` is our ticks to get there
function Port.danger(name: string, lead: number, wide: boolean, eta: number?): boolean
	local P = CONST.PORT_ROBERTS
	local here = STOP_INDEX[name]
	local before = STOP_BEFORE[name]
	local tick = Read.current_tick(game_state())
	local near = ahead(before[1], here)
	for _, guard in pairs(guards) do
		local at = LOOP_INDEX[tile_key(guard.x, guard.y)]
		if at ~= nil and tick - guard.seen <= 3 then
			local d = ahead(at, here)
			local stood = tick - guard.since
			if d == 0 then
				-- a guard about to step off is gone by the time we get there
				if eta == nil or stood + eta < P.DWELL + 1 then
					return true
				end
			elseif d < near or (d == near and (wide or stood >= P.DWELL - lead)) then
				-- walking up to it, or standing at the stop before and about to
				return true
			end
		end
	end
	return false
end

-- whether we are walled in: few reachable tiles, the cell with its door shut
function Port.locked_in(): boolean
	local P = CONST.PORT_ROBERTS
	local me = Walker.position()
	if me == nil then
		return false
	end
	local r = P.JAIL_SCAN
	local c = Host.collision({ x1 = me.x - r, y1 = me.y - r, x2 = me.x + r, y2 = me.y + r })
	if c == nil then
		return false
	end
	local function flags(x: number, y: number): number?
		local i, j = x - c.x, y - c.y
		if i < 0 or j < 0 or i >= c.width or j >= c.height then
			return nil
		end
		return c.flags[i * c.height + j + 1]
	end
	local blocked = 0x200000 + 0x100 + 0x40000
	-- {step x, step y, wall flag on the tile we leave, wall flag on the tile we enter}
	local steps = { { 0, 1, 0x2, 0x20 }, { 1, 0, 0x8, 0x80 }, { 0, -1, 0x20, 0x2 }, { -1, 0, 0x80, 0x8 } }
	local seen: { [number]: boolean } = { [tile_key(me.x, me.y)] = true }
	local queue: { Tile } = { me }
	local head = 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		if head > P.JAIL_MAX_TILES then
			return false
		end
		local from = flags(at.x, at.y) or 0
		for _, step in ipairs(steps) do
			local nx, ny = at.x + step[1], at.y + step[2]
			local into = flags(nx, ny)
			if into == nil then
				return false
			end
			if
				bit32.band(from, step[3]) == 0
				and bit32.band(into, step[4]) == 0
				and bit32.band(into, blocked) == 0
				and not seen[tile_key(nx, ny)]
			then
				seen[tile_key(nx, ny)] = true
				table.insert(queue, { x = nx, y = ny })
			end
		end
	end
	return true
end

function Port.in_plaza(pos: Tile, plane: number): boolean
	local a = CONST.PORT_ROBERTS.PLAZA
	return plane == 0 and pos.x >= a.x1 and pos.x <= a.x2 and pos.y >= a.y1 and pos.y <= a.y2
end

function Port.pick_state(skipped: { [string]: boolean }): State
	if Port.locked_in() then
		return "JAIL"
	elseif not Port.in_plaza(snap.pos, snap.plane) then
		return "RETURN"
	end
	if snap.free <= CONST.PORT_ROBERTS.FULL_FREE and not skipped["BANK"] then
		return "BANK"
	end
	return "PORT"
end

-- true once the stall was clicked; the steal then goes on by itself until we click something else
function Port.steal(name: string): boolean
	local P = CONST.PORT_ROBERTS
	if Port.locked_in() then
		return false
	end
	local me = Walker.position()
	local loc = me and Objects.nearest(name, me)
	-- turning the camera first costs ticks we don't have with a guard coming
	if
		loc == nil
		or not (Objects.interact(loc, P.OPTION, false, false) or Objects.interact(loc, P.OPTION, false, true))
	then
		stats.failures += 1
		S.failures_in_row += 1
		Log.log(NAME, `Couldn't click the {string.lower(name)}`)
		return false
	end
	S.port_at, S.port_clicked_at = name, time()
	S.failures_in_row = 0
	Log.log(NAME, `tick {Read.current_tick(game_state())}: clicked the {string.lower(name)} [{Port.guards_text()}]`)
	return true
end

-- stops stealing by clicking the tile we stand on
function Port.stand()
	local me = Walker.position()
	if me and Walker.click_tile(me) then
		S.port_at = nil
	end
end

-- steals from the next stall while a guard is coming to ours and it is clear, else stands still
function Port.leave(main: string)
	Log.log(
		NAME,
		`tick {Read.current_tick(game_state())}: leaving, {stats.steals} steals so far [{Port.guards_text()}]`
	)
	local list = CONST.PORT_ROBERTS.STALLS
	local name = list[(table.find(list, main) or #list) + 1]
	if name ~= nil and S.port_at ~= name and not Port.danger(name, CONST.PORT_ROBERTS.LEAD, true) then
		Log.log(NAME, `A guard is coming to the {string.lower(main)}, stealing from the {string.lower(name)}`)
		if Port.steal(name) then
			return
		end
	end
	Log.log(NAME, `A guard is coming to the {string.lower(main)}, standing still`)
	Port.stand()
end

function Handler.port()
	local P = CONST.PORT_ROBERTS
	Game.deselect()
	Game.ensure_run()
	Port.track()
	Port.count_steals()
	local main = PORT_STALL
	local at = S.port_at
	if at == main then
		-- just clicked, still on our way, with a guard on the stall that is about to step off
		local eta = if time() - S.port_clicked_at < 3000 then 4 else nil
		if Port.danger(main, P.LEAD, false, eta) then
			Port.leave(main)
		elseif time() - math.max(S.last_progress_at, S.port_clicked_at) > P.STALE_MS then
			-- the steal stopped on its own
			S.port_at = nil
		end
	else
		-- going back takes time: the guard must not be on its way by then
		local me = Walker.position()
		local stop = P.STOPS[main]
		local walk = if me then math.ceil(Walker.distance(me, stop) / 2) else 0
		if not Port.danger(main, P.LEAD + walk, false, walk + 1) then
			Port.steal(main)
		elseif at ~= nil and Port.danger(at, P.LEAD, false) then
			-- the stall we went to is getting a guard too
			Port.leave(main)
			return
		elseif at ~= nil and time() - math.max(S.last_progress_at, S.port_clicked_at) > P.STALE_MS then
			S.port_at = nil
		end
	end
	-- the inventory shows what we stole: back to it whenever something (antiban) switched tab, unless a guard is close
	if not Inventory.is_open() and not Port.danger(main, P.LEAD + 3, false) then
		SidePanels.open("Inventory")
	end
	sleep(P.POLL_MS)
end

-- banks what we got and leaves the way back to port_return
function Handler.port_bank()
	if Port.locked_in() then
		Handler.jail()
		return
	end
	S.port_at = nil
	Handler.bank()
	if S.failures_in_row > 0 then
		S.skip["BANK"] = true
	end
end

-- waits for whatever our player is doing to finish, such as picking the lock
function Port.wait_animation()
	local waited = 0
	local idle = 0
	while waited < CONST.PORT_ROBERTS.PICK_MS and idle < 3 do
		sleep(100)
		waited += 100
		local me = Players.me()
		idle = if me == nil or me.animation == -1 then idle + 1 else 0
	end
	sleep(Random.int(300, 600))
end

-- teleports out with the sailors' amulet, worn or in the inventory; true once we are out of the cell
function Port.amulet(): boolean
	local A = CONST.PORT_ROBERTS.AMULET
	local function is_amulet(name: string?): boolean
		return name ~= nil and string.find(string.lower(name), A.name, 1, true) ~= nil
	end
	local clicked = false
	local worn_items = Wornitems.worn()
	local worn = worn_items and worn_items.amulet
	if worn and is_amulet(Host.item_name(worn.id)) then
		Log.log(NAME, "Teleporting out with the worn sailors' amulet")
		clicked = Wornitems.interact_slot(worn.slot, A.option)
		-- back to the tab the rest of the script works from
		SidePanels.open("Inventory")
	else
		for _, item in ipairs(Inventory.items() or {}) do
			if is_amulet(item.name) then
				Log.log(NAME, "Teleporting out with the sailors' amulet in the inventory")
				clicked = Inventory.interact_slot(item.slot, A.option)
				break
			end
		end
	end
	if not clicked then
		return false
	end
	local waited = 0
	while waited < A.TELEPORT_MS do
		sleep(200)
		waited += 200
		if not Port.locked_in() then
			Port.wait_animation()
			return true
		end
	end
	return false
end

-- picks the lock of the cell door
function Handler.jail()
	local P = CONST.PORT_ROBERTS
	if not S.in_jail then
		S.in_jail = true
		S.port_at = nil
		stats.arrests += 1
		S.amulet_tried = false
		Log.log(NAME, `Caught ({stats.arrests} arrests)`)
	end
	-- the amulet is quicker than the lock: tried once, then the lock
	if not S.amulet_tried then
		S.amulet_tried = true
		if Port.amulet() then
			return
		end
		Log.log(NAME, "No sailors' amulet or it didn't work, picking the lock")
	end
	local chat = S.chat_uid
	for _ = 1, P.DOOR.TRIES do
		local me = Walker.position()
		local door = me and Objects.nearest(P.DOOR.name, me)
		if door == nil then
			break
		end
		if Objects.interact(door, P.DOOR.option, false, true) then
			local waited = 0
			while waited < P.DOOR.TRY_MS do
				sleep(100)
				waited += 100
				for _, message in ipairs(Host.chat_messages() or {}) do
					if message.uid > chat then
						chat = message.uid
						if string.find(string.lower(message.text), P.PICKED_TEXT, 1, true) then
							S.chat_uid = chat
							Port.wait_animation()
							return
						end
					end
				end
				if not Port.locked_in() then
					return
				end
			end
		end
	end
	stats.failures += 1
	S.failures_in_row += 1
end

-- back to the stall we work, from the cell or wherever we ended up
function Handler.port_return()
	-- never click to walk out of the cell: the door comes first
	if Port.locked_in() then
		Handler.jail()
		return
	end
	S.in_jail = false
	S.port_at = nil
	local stop = CONST.PORT_ROBERTS.STOPS[PORT_STALL]
	-- next to the cell door we are still locked in, or have just come out of it
	local me = Walker.position()
	local door = me and Objects.nearest(CONST.PORT_ROBERTS.DOOR.name, me)
	if me and door and Objects.distance(door, me) <= 3 then
		local out = CONST.PORT_ROBERTS.DOOR.OUT
		if me.x ~= out.x or me.y ~= out.y then
			-- through the door if it is open: the walker can't start from the door's tile
			Walker.walk_tile(out, 4000)
		end
		local now = Walker.position()
		if now and Objects.distance(door, now) <= 3 and not (now.x == out.x and now.y == out.y) then
			Handler.jail()
			return
		end
	end
	if Walker.walk(stop, { near = 0, plane = 0, timeout_ms = 40000 }) then
		S.failures_in_row = 0
		S.last_progress_at = time()
		return
	end
	stats.failures += 1
	S.failures_in_row += 1
end

local function loading()
	sleep(100)
end

local function login()
	Game.sign_in()
end

local function drop()
	local what = if PROFILE == "fruit"
		then "cheap fruit"
		elseif PROFILE == "tea" then "cups of tea"
		else "bread and chocolate slices"
	Log.log(NAME, `Dropping {#snap.junk} {what}`)
	if not Inventory.shift_drop(JUNK :: { string | number }) then
		S.skip["DROP"] = true
	end
end

Handler.bakers_states = {
	LOADING = loading,
	LOGIN = login,
	STEAL = Handler.bakers_steal,
	DROP = drop,
	BANK = Handler.bank,
	RETURN = Handler.return_to_safe,
	LURE = Handler.lure,
	EAT = Handler.eat,
}

Handler.tea_states = {
	LOADING = loading,
	LOGIN = login,
	STEAL = function()
		Game.deselect()
		Game.ensure_run()
		local stand = CONST.TEA.STAND
		local stall = snap.tea
		if snap.pos.x ~= stand.x or snap.pos.y ~= stand.y then
			if not Walker.walk(stand, { near = 0, plane = 0 }) then
				stats.failures += 1
				S.failures_in_row += 1
			end
		elseif stall.ready and stall.loc then
			Handler.steal(stall)
		else
			Handler.idle()
		end
	end,
	DROP = drop,
}

Handler.port_roberts_states = {
	LOADING = loading,
	LOGIN = login,
	PORT = Handler.port,
	JAIL = Handler.jail,
	BANK = Handler.port_bank,
	RETURN = Handler.port_return,
}

Handler.fruit_states = {
	LOADING = loading,
	LOGIN = login,
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
		local fill = plan.fill :: { from: number, to: number, direct: boolean }
		-- "Fill" on a basket that has a strawberry in it takes up to 4 more in one click
		if fill.direct and Handler.fill_basket(fill.to) then
			Log.log(NAME, "Basket filled")
		elseif not Inventory.combine_slots(fill.from, fill.to) then
			S.skip["FILL"] = true
			Game.deselect()
		else
			Log.log(NAME, "Strawberry put in a basket")
			Game.deselect()
		end
	end,
	DROP = drop,
	BANK = Handler.bank,
	RETURN = Handler.return_to_house,
}

local STALLS = { "Fruit stalls", "Baker's stalls", "Tea stall", "Port Roberts" }

-- the stall being worked and the one the form last named, to tell when the user changes it
local chosen = { stall = STALLS[1], port_stall = CONST.PORT_ROBERTS.STALLS[1] }

-- switches to the stall of the form's values: its profile, values, junk and handlers
function Loop.apply_stall(values: { [string]: any })
	chosen.stall, chosen.port_stall = values.stall, values.port_stall
	if values.stall == STALLS[2] then
		PROFILE, NAME, STALL = "bakers", "Baker's stalls", CONST.BAKER.STALL
		set_junk(CONST.BAKER.JUNK)
		Handler.states = Handler.bakers_states
	elseif values.stall == STALLS[3] then
		PROFILE, NAME, STALL = "tea", "Tea stall", CONST.TEA.STALL
		set_junk(CONST.TEA.JUNK)
		Handler.states = Handler.tea_states
	elseif values.stall == STALLS[4] then
		PROFILE, NAME, PORT_STALL = "port_roberts", "Port Roberts", values.port_stall
		set_junk({})
		Handler.states = Handler.port_roberts_states
	else
		PROFILE, NAME, STALL = "fruit", "Fruit stalls", CONST.STALL
		set_junk(CONST.JUNK)
		Handler.states = Handler.fruit_states
	end
end

-- asks which stall to work and sets up for it; false when the form is closed
function Loop.choose_stall(): boolean
	local values = Host.form({
		title = "Stall thiever",
		submit = "Start",
		fields = {
			{ id = "stall", kind = "choice", label = "Stall", options = STALLS, default = STALLS[1] },
			{ kind = "label", text = "Only for Port Roberts:" },
			{
				id = "port_stall",
				kind = "choice",
				label = "Port Roberts stall",
				options = CONST.PORT_ROBERTS.STALLS,
				default = CONST.PORT_ROBERTS.STALLS[1],
			},
		},
	})
	if values == nil then
		return false
	end
	Loop.apply_stall(values)
	return true
end

-- takes the settings the user sent with Update in the loader. A new stall resets what belongs to the old one and sets up again
function Loop.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	local switched = values.stall ~= chosen.stall
	if not switched and PROFILE == "port_roberts" and values.port_stall ~= PORT_STALL then
		PORT_STALL = values.port_stall
		chosen.port_stall = values.port_stall
		Log.log(NAME, `Port Roberts stall changed to {PORT_STALL}`)
		return
	end
	if not switched then
		return
	end
	Loop.apply_stall(values)
	S.sticky, S.skip, plan = nil, {}, {}
	S.hitpoints, S.lures_in_row, S.steals_since_lure = 0, 0, 0
	S.port_at, S.port_clicked_at, S.in_jail, S.amulet_tried = nil, 0, false, false
	Log.log(NAME, `Switched to {NAME}`)
	Game.setup()
end

function Loop.run()
	if not Loop.choose_stall() then
		Log.log(NAME, "No stall chosen, stopping the script")
		return
	end
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
		Loop.poll_settings()
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		-- the steal loop has its own pace
		if state ~= "STEAL" and state ~= "PORT" then
			sleep(Random.int(60, 140))
		end
	end
	Log.log(NAME, "Done")
end

Loop.run()
