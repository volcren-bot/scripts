--!strict
-- Collector: picks up items that spawn on the ground, hopping worlds for fresh spawns, and banks them when the inventory is full.
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local BankpinKeypad = require("@lib/main/interfaces/mainscreen/bankpin_keypad")
local Biometrics = require("@lib/main/antiban/biometrics")
local Clickbox = require("@lib/main/clickbox")
local DepositBox = require("@lib/main/interfaces/mainscreen/depositbox")
local GameState = require("@lib/main/game_state")
local GroundItems = require("@lib/main/entities/ground_items")
local Inv = require("@lib/main/interfaces/inv")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Objects = require("@lib/main/entities/objects")
local Projection = require("@lib/main/projection/projection")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Walker = require("@lib/main/walker")
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")

local NAME = "Collector"

type Spot = { x: number, y: number, plane: number }

-- a ladder or stairs taken by hand so the next target can be hovered while the climb happens
type Climb = {
	-- the loc, found by its id on its tile and floor
	id: number,
	at: Spot,
	option: string,
	-- where we stand after taking it
	lands: Spot,
}

-- the way to a bank that is on another floor: the climbs down, then the chest, and the climbs back up
type Route = {
	down: { Climb },
	chest: { id: number, at: Spot },
	up: { Climb },
}

type Collectable = {
	-- the ground item picked up
	item: string,
	option: string,
	plane: number,
	-- only hop between members worlds
	members: boolean?,
	-- the tiles the item spawns on: only items on these tiles are picked up
	tiles: { Host.Tile },
	-- set when the nearest bank is not reached by plain walking: the route to it, and no deposit box
	route: Route?,
}

-- what can be collected, in the order of the settings dropdown
local COLLECTABLE_NAMES = { "Lumbridge Logs", "Barbarian outpost planks", "Eclipse red" }
local COLLECTABLES: { [string]: Collectable } = {
	["Lumbridge Logs"] = {
		item = "Logs",
		option = "Take",
		plane = 2,
		-- the top floor of Lumbridge Castle, next to the bank booths and the deposit box
		tiles = {
			{ x = 3205, y = 3224 },
			{ x = 3205, y = 3226 },
			{ x = 3208, y = 3225 },
			{ x = 3209, y = 3224 },
		},
	},
	["Barbarian outpost planks"] = {
		item = "Plank",
		option = "Take",
		plane = 0,
		members = true,
		-- outside the outpost, with the bank chest and deposit box to the west
		tiles = {
			{ x = 2550, y = 3575 },
			{ x = 2553, y = 3576 },
			{ x = 2554, y = 3575 },
			{ x = 2556, y = 3573 },
		},
	},
	["Eclipse red"] = {
		item = "Eclipse red",
		option = "Take",
		plane = 2,
		members = true,
		-- the top floor of Guildmaster Apatura's quarters in the Hunter Guild; the bank chest is on the ground floor, reached by two ladders
		tiles = {
			{ x = 1555, y = 3035 },
		},
		route = {
			down = {
				{
					id = 52620,
					at = { x = 1557, y = 3034, plane = 2 },
					option = "Climb-down",
					lands = { x = 1557, y = 3033, plane = 1 },
				},
				{
					id = 52620,
					at = { x = 1552, y = 3033, plane = 1 },
					option = "Climb-down",
					lands = { x = 1552, y = 3034, plane = 0 },
				},
			},
			chest = { id = 53015, at = { x = 1542, y = 3039, plane = 0 } },
			up = {
				{
					id = 52614,
					at = { x = 1552, y = 3033, plane = 0 },
					option = "Climb-up",
					lands = { x = 1552, y = 3034, plane = 1 },
				},
				{
					id = 52614,
					at = { x = 1557, y = 3034, plane = 1 },
					option = "Climb-up",
					lands = { x = 1557, y = 3033, plane = 2 },
				},
			},
		},
	},
}

-- fixed values: ids, tiles, thresholds
local CONST = {
	REPORT = { counters_key = "" },
	-- how long we wait for a picked item to reach the inventory
	PICK = {
		WALK_FROM = 6,
		WALK_NEAR = 2,
		RESULT_MS = 7000,
		POLL_MS = 100,
		SKIP_PREHOVER = 0.03,
		TINY_ANTIBAN = 0.4,
		NEAR_TIE = 2,
		TIE_CLOSEST = 0.7,
	},
	-- after arriving on a world the spawns take a moment to show: no decisions before then
	HOP = { SETTLE_MIN_MS = 1500, SETTLE_MAX_MS = 2600, RETRY_MS = 15000 },
	BANK = { OPEN_ATTEMPTS = 2, DEPOSIT_MS = 3000 },
	-- how long one ladder may take, walking to it included
	ROUTE = { CLIMB_MS = 12000 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

-- what the user can change
local CONFIG = {
	collect = COLLECTABLE_NAMES[1],
	max_items = 0, -- items collected before stopping, 0 is unlimited
	-- chance (biometric) of using the deposit box instead of the bank on a trip
	deposit_box_chance = 0.05,
	-- the worlds to hop between, in order; empty takes every safe world from the world list
	hop_worlds = {} :: { number },
	-- the script stops when stuck: nothing collected for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 8, max_failures = 4 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { collected = 0, trips = 0, hops = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	-- no decisions before this time (ms): a world was just entered
	settle_until: number,
	-- no hopping before this time (ms): the last hop failed
	hop_retry_at: number,
	-- states to ignore for one loop
	skip: { [string]: boolean },
	-- the item pre-hovered after the last click: the next one taken, when it is still there
	chosen: Host.GroundItem?,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	settle_until = 0,
	hop_retry_at = 0,
	skip = {},
	chosen = nil,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	me: Host.Tile,
	free_slots: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "SETTLE" | "BANK" | "PICK" | "HOP"

-- what get_state found that its handler needs
type Plan = { item: Host.GroundItem? }

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

local backpack = Inv.new(93, 28)

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

function Read.collectable(): Collectable
	return COLLECTABLES[CONFIG.collect]
end

-- how many of the collected item the inventory holds
function Read.held(): number
	return backpack.count_ex(Read.collectable().item) or 0
end

-- every item of the collectable lying on one of its spawn tiles
function Read.spawns(): { Host.GroundItem }
	local c = Read.collectable()
	local found: { Host.GroundItem } = {}
	for _, item in ipairs(GroundItems.find(c.item) or {}) do
		if item.plane == c.plane then
			for _, tile in ipairs(c.tiles) do
				if tile.x == item.x and tile.y == item.y then
					table.insert(found, item)
					break
				end
			end
		end
	end
	return found
end

-- how many steps walking from a tile to the item takes (doors and stairs planned), a straight distance when no way is found
function Read.path_cost(from: Host.Tile, item: Host.GroundItem): number
	local plan = Host.nav_plan(
		{ x = from.x, y = from.y, plane = item.plane },
		{ x = item.x, y = item.y, plane = item.plane },
		{ rnd = 0 }
	)
	if plan == nil then
		return 1000 + GroundItems.distance(item, from)
	end
	local cost = #plan.tiles
	if not plan.reached then
		cost += 1000
	end
	return cost
end

-- the items with the steps to walk to each from a tile, fewest first
function Read.ranked(items: { Host.GroundItem }, from: Host.Tile): { { item: Host.GroundItem, cost: number } }
	local ranked = {}
	for _, item in ipairs(items) do
		-- the same tile costs nothing, no need to plan
		local cost = if item.x == from.x and item.y == from.y then 0 else Read.path_cost(from, item)
		table.insert(ranked, { item = item, cost = cost })
	end
	table.sort(ranked, function(a, b)
		return a.cost < b.cost
	end)
	return ranked
end

-- the item that is the fewest steps to walk to from a tile
function Read.cheapest(items: { Host.GroundItem }, from: Host.Tile): Host.GroundItem?
	local ranked = Read.ranked(items, from)
	return if ranked[1] then ranked[1].item else nil
end

-- the item to take from a tile: the closest, but when others are at most NEAR_TIE steps further, one of them 30% of the time
function Read.pick_from(items: { Host.GroundItem }, from: Host.Tile): Host.GroundItem?
	local ranked = Read.ranked(items, from)
	local closest = ranked[1]
	if closest == nil then
		return nil
	end
	local others = {}
	for i = 2, #ranked do
		if ranked[i].cost - closest.cost <= CONST.PICK.NEAR_TIE then
			table.insert(others, ranked[i].item)
		end
	end
	if #others == 0 or Biometrics.random_boolean(CONST.PICK.TIE_CLOSEST) then
		return closest.item
	end
	return others[Random.int(1, #others)]
end

-- the item to take after `item`, the fewest steps from where `item` is; nil when it was the last
function Read.next_after(item: Host.GroundItem): Host.GroundItem?
	local rest: { Host.GroundItem } = {}
	local skipped = false
	for _, other in ipairs(Read.spawns()) do
		-- one entry on its tile is the one being taken; others stacked there are still to take
		if not skipped and other.id == item.id and other.x == item.x and other.y == item.y then
			skipped = true
		else
			table.insert(rest, other)
		end
	end
	return Read.pick_from(rest, item)
end

-- the loc with an id standing on a tile and floor, even when the floor is not the one we are on
function Read.loc_at(id: number, at: Spot): Host.Loc?
	for _, loc in ipairs(Host.locs(at.plane) or {}) do
		if loc.id == id and loc.x == at.x and loc.y == at.y then
			return loc
		end
	end
	return nil
end

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

	AntibanTasks.skills = { "Total" }
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

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	-- a bank or deposit box left open blocks every click
	if Bankmain.is_open() then
		Bankmain.close()
	elseif DepositBox.is_open() then
		DepositBox.close()
	end

	-- far from the spawns (another floor, another town): walk there first
	local c = Read.collectable()
	local near = c.tiles[1]
	if snap.state.position and (snap.state.position.plane ~= c.plane or Walker.distance(snap.me, near) > 25) then
		Log.log(NAME, `Walking to the {CONFIG.collect} spawns`)
		if not Walker.walk(near, { near = 3, plane = c.plane }) then
			Log.log(NAME, `Couldn't walk to the {CONFIG.collect} spawns, stopping the script`)
			S.finished = true
			return
		end
	end

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

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
	local key = `{stats.collected}/{stats.trips}/{stats.hops}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "collected", label = "Collected", value = stats.collected },
		{ id = "trips", label = "Bank trips", value = stats.trips },
		{ id = "hops", label = "Hops", value = stats.hops },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "collected" },
	})
end

-- stops the script when it hasn't progressed or keeps failing
function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `nothing collected for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_items > 0 and stats.collected >= CONFIG.max_items then
		Log.log(NAME, `Collected {CONFIG.max_items} items, stopping the script`)
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
	-- the inventory is the tab we want open: antiban tasks and hops leave other tabs showing
	if not Inventory.is_open() then
		Inventory.open()
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	if snap.free_slots == 0 and not skipped["BANK"] then
		return "BANK"
	end
	if time() < S.settle_until then
		return "SETTLE"
	end
	local spawns = Read.spawns()
	-- the one we pre-hovered, so the click lands where the mouse already is
	local chosen = S.chosen
	S.chosen = nil
	if chosen then
		for _, spawn in ipairs(spawns) do
			if spawn.id == chosen.id and spawn.x == chosen.x and spawn.y == chosen.y then
				plan.item = spawn
				break
			end
		end
	end
	plan.item = plan.item or Read.cheapest(spawns, snap.me)
	if plan.item and not skipped["PICK"] then
		return "PICK"
	end
	-- every spawn is gone: another world has them again
	if plan.item == nil and time() >= S.hop_retry_at and not skipped["HOP"] then
		return "HOP"
	end
	return "LOADING"
end

-- Handlers

local function antiban()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_antiban()
	end
end

-- the small async antiban tasks (camera, mouse, hover) between the click and the pre-hover
function Handler.tiny_antiban()
	if CONFIG.antiban and S.antiban_ready and Biometrics.random_boolean(CONST.PICK.TINY_ANTIBAN) then
		Antiban.do_async_tasks("game")
	end
end

-- starts the mouse moving to the item we take next, aimed as the screen will look from the tile of the one just clicked
function Handler.prehover(clicked: Host.GroundItem)
	local nxt = Read.next_after(clicked)
	if nxt == nil or Biometrics.random_boolean(CONST.PICK.SKIP_PREHOVER) then
		return
	end
	S.chosen = nxt
	local shift = Projection.arrival({ x = clicked.x, y = clicked.y })
	if shift == nil then
		return
	end
	local fine_x = nxt.scene_x * Projection.TILE + Projection.TILE / 2
	local fine_y = nxt.scene_y * Projection.TILE + Projection.TILE / 2
	local function aim(): Clickbox.Clickbox?
		local cuboid = Projection.cuboid(fine_x, fine_y, nil, GroundItems.PILE_HEIGHT, nil, shift)
		return if cuboid then Clickbox.from_cuboid(cuboid) else nil
	end
	Clickbox.hover_async(aim, nxt.name or tostring(nxt.id))
end

-- starts the mouse moving to a loc, aimed as the screen will look once we stand on `landing` (which may be on another floor)
function Handler.prehover_loc(loc: Host.Loc, landing: Spot)
	local function aim(): Clickbox.Clickbox?
		return Objects.projected(loc, landing)
	end
	Clickbox.hover_async(aim, loc.name or tostring(loc.id))
end

-- starts the mouse moving to the spawn tile of the item, aimed from `landing`; the item may be on a floor we are not on yet
function Handler.prehover_spawn(tile: Host.Tile, plane: number, landing: Spot)
	-- tiles are scene tiles plus the scene's origin, which any loc tells
	local ref = Host.locs(plane) and (Host.locs(plane) :: { Host.Loc })[1]
	if ref == nil then
		return
	end
	local fine_x = (tile.x - (ref.x - ref.scene_x)) * Projection.TILE + Projection.TILE / 2
	local fine_y = (tile.y - (ref.y - ref.scene_y)) * Projection.TILE + Projection.TILE / 2
	local function aim(): Clickbox.Clickbox?
		local cuboid = Projection.cuboid(fine_x, fine_y, nil, GroundItems.PILE_HEIGHT, landing :: any)
		return if cuboid then Clickbox.from_cuboid(cuboid) else nil
	end
	Clickbox.hover_async(aim, Read.collectable().item)
end

-- the floor we stand on
function Read.plane(): number?
	local p = game_state().position
	return if p then p.plane else nil
end

-- takes a ladder and waits until we are on the floor above or below; `ahead` is called once it is clicked, to hover whatever comes next
function Handler.climb(step: Climb, ahead: () -> ()): boolean
	local loc = Read.loc_at(step.id, step.at)
	if loc == nil then
		Log.log(NAME, `Ladder {step.id} at {step.at.x}, {step.at.y} not found`)
		return false
	end
	if Read.plane() ~= step.at.plane then
		return false
	end
	if not Objects.approach(loc, step.option, { walk = {} }) then
		Log.log(NAME, `Couldn't click the ladder at {step.at.x}, {step.at.y}`)
		return false
	end
	ahead()
	local deadline = time() + CONST.ROUTE.CLIMB_MS
	while time() < deadline do
		if Read.plane() == step.lands.plane then
			sleep(Random.int(150, 300))
			return true
		end
		sleep(CONST.PICK.POLL_MS)
	end
	return false
end

-- goes down the ladders, hovering each next ladder (then the chest) as the climb happens, and opens the bank chest
function Handler.open_chest(route: Route): boolean
	for i, step in ipairs(route.down) do
		local nxt = route.down[i + 1]
		-- already below this ladder (a retry)
		local ok = Read.plane() ~= step.at.plane
			or Handler.climb(step, function()
				if nxt then
					local loc = Read.loc_at(nxt.id, nxt.at)
					if loc then
						Handler.prehover_loc(loc, step.lands)
					end
				else
					local chest = Read.loc_at(route.chest.id, route.chest.at)
					if chest then
						Handler.prehover_loc(chest, step.lands)
					end
				end
			end)
		if not ok then
			return false
		end
	end
	local chest = Read.loc_at(route.chest.id, route.chest.at)
	if chest == nil then
		Log.log(NAME, "The bank chest wasn't found")
		return false
	end
	return Bankmain.open({ loc = chest, npc = nil })
end

-- goes up the ladders from the bank, hovering the next ladder and then the spawn as the climbs happen
function Handler.return_up(c: Collectable)
	local route = assert(c.route)
	-- the mouse heads for the first ladder as soon as the bank is closed
	local first = route.up[1]
	local first_loc = Read.loc_at(first.id, first.at)
	local here = Walker.position()
	if first_loc and here then
		Handler.prehover_loc(first_loc, { x = here.x, y = here.y, plane = first.at.plane })
	end
	for i, step in ipairs(route.up) do
		local nxt = route.up[i + 1]
		local ok = Handler.climb(step, function()
			if nxt then
				local loc = Read.loc_at(nxt.id, nxt.at)
				if loc then
					Handler.prehover_loc(loc, step.lands)
				end
			else
				Handler.prehover_spawn(c.tiles[1], c.plane, step.lands)
			end
		end)
		if not ok then
			-- the normal walk back to the spawn takes over
			return
		end
	end
end

-- takes the item off the ground and waits for it to reach the inventory
function Handler.pick(item: Host.GroundItem)
	local before = Read.held()
	-- coming back from the bank the spawns are far off: walk close first, the click doesn't walk that far
	local here = Walker.position() or snap.me
	if GroundItems.distance(item, here) > CONST.PICK.WALK_FROM then
		if not Walker.walk({ x = item.x, y = item.y }, { near = CONST.PICK.WALK_NEAR, plane = item.plane }) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't walk to the {item.name} at {item.x}, {item.y}`)
			return
		end
	end
	-- false: back as soon as it is clicked, so the next one can be hovered while we walk to this one
	if not GroundItems.interact(item, Read.collectable().option, false) then
		-- someone else may have taken it as we got there
		if GroundItems.refresh(item) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't take the {item.name} at {item.x}, {item.y}`)
		end
		return
	end
	Handler.tiny_antiban()
	local route = Read.collectable().route
	if route and snap.free_slots <= 1 then
		-- this one fills the inventory: the bank is next, so the mouse goes to the first ladder
		local ladder = route.down[1]
		local loc = Read.loc_at(ladder.id, ladder.at)
		if loc then
			Handler.prehover_loc(loc, { x = item.x, y = item.y, plane = item.plane })
		end
	else
		Handler.prehover(item)
	end
	local deadline = time() + CONST.PICK.RESULT_MS
	while time() < deadline do
		local now = Read.held()
		if now > before then
			stats.collected += now - before
			S.failures_in_row = 0
			S.last_progress_at = time()
			return
		end
		-- gone without reaching us: taken by someone else
		if GroundItems.refresh(item) == nil and Read.held() == before then
			return
		end
		sleep(CONST.PICK.POLL_MS)
	end
	S.failures_in_row += 1
	stats.failures += 1
	Log.log(NAME, `The {item.name} at {item.x}, {item.y} didn't reach the inventory`)
end

-- the worlds to hop between: the configured ones, else every safe world (members only when the collectable needs it)
function Handler.worlds(): { number }
	if #CONFIG.hop_worlds > 0 then
		return CONFIG.hop_worlds
	end
	local worlds: { number } = {}
	if WorldSwitcher.open(true) then
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.available and (row.members or not Read.collectable().members) then
				table.insert(worlds, row.world)
			end
		end
	end
	-- in order, so next() walks up the list
	table.sort(worlds)
	return worlds
end

-- hops to another world, where the items are all there again
function Handler.hop()
	local wait = WorldSwitcher.cooldown()
	if wait > 0 then
		sleep(math.min(wait, 1000))
		return
	end
	Log.log(NAME, "Nothing left here, hopping worlds")
	local worlds = Handler.worlds()
	local current = WorldSwitcher.current()
	local at = if current then table.find(worlds, current) else nil
	local target = worlds[if at and at < #worlds then at + 1 else 1]
	Log.log(NAME, `Hopping from world {current} to {target}`)
	if target and WorldSwitcher.switch(target) then
		stats.hops += 1
		S.settle_until = time() + Random.int(CONST.HOP.SETTLE_MIN_MS, CONST.HOP.SETTLE_MAX_MS)
		return
	end
	Log.log(NAME, "Couldn't hop, trying again in a bit")
	S.hop_retry_at = time() + CONST.HOP.RETRY_MS
	S.failures_in_row += 1
	stats.failures += 1
	S.skip["HOP"] = true
end

-- types the bank PIN when the keypad is up (the loader holds it); a PIN that is missing, wrong or locked stops the script rather than retrying
function Handler.enter_pin(): boolean
	if not BankpinKeypad.is_open() then
		return false
	end
	local result = BankpinKeypad.enter()
	Log.log(NAME, `Bank PIN: {result}`)
	if result == "no_pin" or result == "wrong" or result == "locked" or result == "unavailable" then
		Log.log(NAME, "The bank PIN can't be entered, set it in the loader, stopping the script")
		S.finished = true
		return false
	end
	return Bankmain.wait_open()
end

-- opens the bank booth or the deposit box and waits for it
function Handler.open_bank(box: boolean): boolean
	local route = Read.collectable().route
	for attempt = 1, CONST.BANK.OPEN_ATTEMPTS do
		if route then
			-- a retry carries on from the floor the first attempt got to
			if Handler.open_chest(route) or Handler.enter_pin() then
				return true
			end
		elseif box then
			if DepositBox.open() and DepositBox.wait_open() then
				return true
			end
		elseif Bankmain.open() or Handler.enter_pin() then
			return true
		end
		if S.finished then
			return false
		end
		Log.log(NAME, `The {if box then "deposit box" else "bank"} didn't open (attempt {attempt})`)
		sleep(Random.int(400, 900))
	end
	return false
end

-- empties the inventory into the bank, or the deposit box on a few trips
function Handler.bank()
	local route = Read.collectable().route
	-- the deposit box is not on the way when there is a route
	local box = route == nil and Biometrics.random_boolean(CONFIG.deposit_box_chance)
	Log.log(NAME, `Inventory full, using the {if box then "deposit box" else "bank"}`)
	if not Handler.open_bank(box) then
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["BANK"] = true
		return
	end
	local clicked = if box then DepositBox.deposit_inventory() else Bankmain.deposit_inventory()
	if clicked and Inventory.wait_used(0, CONST.BANK.DEPOSIT_MS) then
		stats.trips += 1
		S.failures_in_row = 0
	else
		Log.log(NAME, "The inventory wasn't deposited")
		S.failures_in_row += 1
		stats.failures += 1
	end
	if box then
		DepositBox.close()
	else
		Bankmain.close()
	end
	-- the inventory is the tab we want back
	Inventory.open()
	if route then
		Handler.return_up(Read.collectable())
	end
	S.last_progress_at = time()
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	SETTLE = function()
		sleep(100)
	end,
	BANK = Handler.bank,
	PICK = function()
		Handler.pick(assert(plan.item))
		antiban()
	end,
	HOP = Handler.hop,
}

-- asks what to collect, which stays as its default if the form has no handler; false when the form is closed
function Game.ask(): boolean
	local values = Host.form({
		title = NAME,
		submit = "Start",
		fields = {
			{
				id = "collect",
				kind = "choice",
				label = "Collect",
				options = COLLECTABLE_NAMES,
				default = CONFIG.collect,
			},
			{
				id = "max_items",
				kind = "number",
				label = "Max items (0 is unlimited)",
				default = CONFIG.max_items,
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
	if COLLECTABLES[values.collect] then
		CONFIG.collect = values.collect
	end
	CONFIG.max_items = values.max_items
end

-- takes the settings the user sent with Update in the loader, if there are any
function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	local switched = values.collect ~= CONFIG.collect
	Game.apply_settings(values)
	Log.log(NAME, "Settings updated")
	if switched then
		Log.log(NAME, `Now collecting {CONFIG.collect}`)
		S.settle_until, S.skip, S.chosen, plan = 0, {}, nil, {}
	end
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	Log.log(NAME, `{NAME} started: {CONFIG.collect}`)
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

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
