--!strict
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
local Camera = require("@lib/main/camera")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local DepositBox = require("@lib/main/interfaces/mainscreen/depositbox")
local Diaries = require("@lib/main/diaries")
local GameState = require("@lib/main/game_state")
local GroundItems = require("@lib/main/entities/ground_items")
local Inv = require("@lib/main/interfaces/inv")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Journal = require("@lib/main/interfaces/gametabs/journal")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Projection = require("@lib/main/projection/projection")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Walker = require("@lib/main/walker")
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Collector"

type Spot = { x: number, y: number, plane: number }

type Climb = {
	id: number,
	at: Spot,
	option: string,
	lands: Spot,
}

type Route = {
	down: { Climb },
	chest: { id: number, at: Spot },
	up: { Climb },
}

type Potion = {
	name: string,
	doses: number,
}

type Far = {
	chest: { id: number?, at: Spot },
	ring: boolean?,
}

type Booth = { x: number, y: number, seal: boolean?, dream: boolean? }

type Tele = {
	to: { string },
	bank: { string },
	lyre: boolean?,
	box: boolean?,
	booths: { Booth }?,
}

type Boat = {
	island_npc: number,
	to_town: string,
	town_npc: number,
	to_island: string,
	island_at: Host.Tile,
	town_at: Host.Tile,
	seer: string,
	seer_option: string,
	seer_at: Host.Tile,
}

type Cave = {
	exit: string,
	exit_option: string,
	enter: string,
	enter_option: string,
	bank: string,
}

type Collectable = {
	item: string,
	option: string,
	plane: number,
	members: boolean?,
	tiles: { Host.Tile },
	route: Route?,
	potion: Potion?,
	far: Far?,
	contested: boolean?,
	tele: Tele?,
	boat: Boat?,
	cave: Cave?,
	order: { Host.Tile }?,
}

local COLLECTABLE_NAMES = {
	"Lumbridge Logs",
	"Barbarian outpost planks",
	"Eclipse red",
	"Observatory superantipoison",
	"Snape grass",
	"Red spider eggs",
}
local SNAPE_ROUTES = {
	"The Dibber (Hosidius)",
	"Waterbirth (Enchanted lyre)",
	"Waterbirth (teleport)",
	"Waterbirth (Peer the Seer)",
}
local SNAPE_TODO: { string } = {}
local FAR_BANK_NAMES = { "Observatory superantipoison" }
local COLLECTABLES: { [string]: Collectable } = {
	["Lumbridge Logs"] = {
		item = "Logs",
		option = "Take",
		plane = 2,
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
	["Observatory superantipoison"] = {
		item = "Superantipoison(1)",
		option = "Take",
		plane = 0,
		members = true,
		tiles = {
			{ x = 2467, y = 3176 },
		},
		potion = { name = "Superantipoison", doses = 4 },
		far = { chest = { id = 4483, at = { x = 2444, y = 3083, plane = 0 } }, ring = true },
	},
	["Snape grass"] = {
		item = "Snape grass",
		option = "Take",
		plane = 0,
		members = true,
		tiles = {
			{ x = 1835, y = 3638 },
			{ x = 1835, y = 3640 },
			{ x = 1836, y = 3638 },
			{ x = 1836, y = 3643 },
			{ x = 1837, y = 3642 },
			{ x = 1838, y = 3644 },
			{ x = 1840, y = 3644 },
			{ x = 1840, y = 3645 },
			{ x = 1842, y = 3644 },
			{ x = 1843, y = 3643 },
		},
		far = { chest = { id = 21301, at = { x = 1809, y = 3567, plane = 0 } } },
		contested = true,
	},
	["Red spider eggs"] = {
		item = "Red spiders' eggs",
		option = "Take",
		plane = 0,
		members = true,
		tiles = {
			{ x = 3030, y = 9382 },
			{ x = 3031, y = 9370 },
			{ x = 3035, y = 9376 },
		},
		cave = {
			exit = "Opening",
			exit_option = "Exit",
			enter = "Cave entrance",
			enter_option = "Enter",
			bank = "Bank Crab",
		},
	},
}

local WATERBIRTH_TILES: { Host.Tile } = {
	{ x = 2540, y = 3765 },
	{ x = 2542, y = 3765 },
	{ x = 2546, y = 3763 },
	{ x = 2552, y = 3757 },
	{ x = 2553, y = 3754 },
	{ x = 2553, y = 3751 },
}
local WATERBIRTH_ORDER: { Host.Tile } = {
	{ x = 2553, y = 3751 },
	{ x = 2553, y = 3754 },
	{ x = 2552, y = 3757 },
	{ x = 2546, y = 3763 },
	{ x = 2542, y = 3765 },
	{ x = 2540, y = 3765 },
}

local SNAPE_ROUTE_DATA: { [string]: Collectable } = {
	[SNAPE_ROUTES[3]] = {
		item = "Snape grass",
		option = "Take",
		plane = 0,
		members = true,
		tiles = WATERBIRTH_TILES,
		contested = true,
		order = WATERBIRTH_ORDER,
		tele = {
			to = { "Waterbirth Teleport", "Tele Group Waterbirth" },
			bank = { "Moonclan Teleport", "Tele Group Moonclan" },
			booths = {
				{ x = 2097, y = 3920, seal = true },
				{ x = 2098, y = 3920, seal = true },
				{ x = 2099, y = 3920, dream = true },
			},
		},
	},
	[SNAPE_ROUTES[2]] = {
		item = "Snape grass",
		option = "Take",
		plane = 0,
		members = true,
		tiles = WATERBIRTH_TILES,
		contested = true,
		order = WATERBIRTH_ORDER,
		tele = { to = { "Waterbirth Island" }, bank = { "Neitiznot" }, lyre = true, box = false },
	},
	[SNAPE_ROUTES[4]] = {
		item = "Snape grass",
		option = "Take",
		plane = 0,
		members = true,
		tiles = WATERBIRTH_TILES,
		contested = true,
		order = WATERBIRTH_ORDER,
		boat = {
			island_npc = 10407,
			to_town = "Rellekka",
			town_npc = 6535,
			to_island = "Waterbirth Island",
			island_at = { x = 2545, y = 3761 },
			town_at = { x = 2622, y = 3683 },
			seer = "Peer the Seer",
			seer_option = "Deposit-items",
			seer_at = { x = 2634, y = 3673 },
		},
	},
}

local CONST = {
	REPORT = { counters_key = "" },
	PICK = {
		WALK_FROM = 6,
		WALK_NEAR = 2,
		RESULT_MS = 7000,
		POLL_MS = 100,
		SKIP_PREHOVER = 0.03,
		TINY_ANTIBAN = 0.4,
		NEAR_TIE = 2,
		TIE_CLOSEST = 0.7,
		QUICK_POLL_MS = 40,
	},
	HOP = { SETTLE_MIN_MS = 1500, SETTLE_MAX_MS = 2600, RETRY_MS = 15000 },
	BANK = { OPEN_ATTEMPTS = 2, DEPOSIT_MS = 3000 },
	ROUTE = { CLIMB_MS = 12000 },
	RING = {
		ANY = "Ring of dueling(1..8)",
		TELEPORT = "Castle Wars",
		MAX_CHARGES = 8,
		ARRIVE_MS = 9000,
		ARRIVE_NEAR = 30,
	},
	POTION = {
		TRIP_MIN = 24,
		TRIP_MAX = 27,
		TRIP_MODE = 25,
		VIAL = "Vial",
		BATCH_MIN = 4,
		POUR_MIN_MS = 500,
		POUR_MODE_MS = 600,
		POUR_MAX_MS = 800,
		POUR_WAIT_MS = 2000,
	},
	FAR = { NEAR = 4 },
	AIM = { TILES = 3, ERROR = 0.1 },
	CAVE = { PASS_MS = 12000, SCENE_MS = 4000 },
	BOAT = { JOURNEY = "misc_shipjourney", START_MS = 15000, END_MS = 20000, WALK_MS = 8000, CLOSE = 7 },
	TELE = {
		MOVED = 20,
		ARRIVE_MS = 10000,
		BOX_CHANCE = 0.2,
		FAR_FROM = 60,
		SPAWN_WAIT_MS = 12000,
		WAIT_SPREAD = 2,
		RESPAWN_CHECK_MS = 120,
	},
	RIVAL = { NEAR = 20, CLICK_MS = 4000 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	collect = COLLECTABLE_NAMES[1],
	max_items = 0,
	deposit_box_chance = 0.05,
	hop_worlds = {} :: { number },
	ring = false,
	snape_route = SNAPE_ROUTES[1],
	timeouts = { idle_minutes = 8, max_failures = 4 },
	antiban = true,
}

local stats = { collected = 0, trips = 0, hops = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	settle_until: number,
	hop_retry_at: number,
	skip: { [string]: boolean },
	chosen: Host.GroundItem?,
	trip_target: number,
	batch_size: number,
	pouring: boolean,
	no_ring: boolean,
	seen: { [string]: boolean },
	clicked: { [string]: number },
	rivals: boolean,
	visited: { [string]: boolean },
	step: number,
	reverse: boolean,
	waiting_since: number?,
	wait_target: Host.Tile?,
	booths: { Booth }?,
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
	trip_target = 0,
	batch_size = 0,
	pouring = false,
	no_ring = false,
	seen = {},
	clicked = {},
	rivals = false,
	visited = {},
	step = 1,
	reverse = false,
	waiting_since = nil,
	wait_target = nil,
	booths = nil,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	me: Host.Tile,
	free_slots: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "SETTLE" | "BANK" | "RETURN" | "COMBINE" | "DROP" | "PICK" | "HOP" | "WAIT"

type Plan = { item: Host.GroundItem? }

local plan: Plan = {}

local report = StatsReport.new()

local backpack = Inv.new(93, 28)

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
	if CONFIG.collect == "Snape grass" and SNAPE_ROUTE_DATA[CONFIG.snape_route] then
		return SNAPE_ROUTE_DATA[CONFIG.snape_route]
	end
	return COLLECTABLES[CONFIG.collect]
end

type PotionSlot = { slot: number, dose: number }

type Potions = {
	partial: { PotionSlot },
	full: number,
	doses: number,
	vials: number,
}

function Read.potions(): Potions?
	local potion = Read.collectable().potion
	if potion == nil then
		return nil
	end
	local found: Potions = { partial = {}, full = 0, doses = 0, vials = 0 }
	for _, held in ipairs(backpack.items() or {}) do
		local base, dose = string.match(held.name or "", "^(.-)%((%d)%)$")
		if base == potion.name and dose then
			local n = tonumber(dose) or 0
			found.doses += n
			if n >= potion.doses then
				found.full += 1
			else
				table.insert(found.partial, { slot = held.slot, dose = n })
			end
		elseif held.name == CONST.POTION.VIAL then
			found.vials += 1
		end
	end
	return found
end

function Read.held(): number
	local potions = Read.potions()
	if potions then
		return potions.doses
	end
	return backpack.count_ex(Read.collectable().item) or 0
end

function Read.ring(): ("worn" | "pack")?
	if Wornitems.contains(CONST.RING.ANY) then
		return "worn"
	end
	if Inventory.contains(CONST.RING.ANY) then
		return "pack"
	end
	return nil
end

function Read.use_ring(): boolean
	local far = Read.collectable().far
	if far == nil or far.ring ~= true then
		return false
	end
	return CONFIG.ring and not S.no_ring
end

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

function Read.player_near_spawns(): boolean
	local c = Read.collectable()
	local name = game_state().player_name
	for _, p in ipairs(Host.players() or {}) do
		if p.name ~= name then
			for _, tile in ipairs(c.tiles) do
				if math.max(math.abs(p.x - tile.x), math.abs(p.y - tile.y)) <= CONST.RIVAL.NEAR then
					return true
				end
			end
		end
	end
	return false
end

function Read.watch_rivals(spawns: { Host.GroundItem })
	local now: { [string]: boolean } = {}
	for _, item in ipairs(spawns) do
		now[`{item.x},{item.y}`] = true
	end
	local near: boolean? = nil
	for key in pairs(S.seen) do
		if not now[key] then
			local at = S.clicked[key]
			if at == nil or time() - at > CONST.RIVAL.CLICK_MS then
				if near == nil then
					near = Read.player_near_spawns()
				end
			end
			if (at == nil or time() - at > CONST.RIVAL.CLICK_MS) and near then
				if not S.rivals then
					Log.log(NAME, `Someone else took the spawn at {key}`)
				end
				S.rivals = true
			end
		end
	end
	S.seen = now
end

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

function Read.ranked(items: { Host.GroundItem }, from: Host.Tile): { { item: Host.GroundItem, cost: number } }
	local ranked = {}
	for _, item in ipairs(items) do
		local cost = if item.x == from.x and item.y == from.y then 0 else Read.path_cost(from, item)
		table.insert(ranked, { item = item, cost = cost })
	end
	table.sort(ranked, function(a, b)
		return a.cost < b.cost
	end)
	return ranked
end

function Read.cheapest(items: { Host.GroundItem }, from: Host.Tile): Host.GroundItem?
	local ranked = Read.ranked(items, from)
	return if ranked[1] then ranked[1].item else nil
end

function Read.step_tile(): Host.Tile?
	local order = Read.collectable().order
	if order == nil then
		return nil
	end
	return order[if S.reverse then #order + 1 - S.step else S.step]
end

function Read.next_tiles(count: number): { Host.Tile }
	local order = Read.collectable().order
	local tiles: { Host.Tile } = {}
	if order == nil then
		return tiles
	end
	for step = S.step, math.min(S.step + count - 1, #order) do
		table.insert(tiles, order[if S.reverse then #order + 1 - step else step])
	end
	return tiles
end

function Read.new_rotation()
	local c = Read.collectable()
	if c.order == nil then
		return
	end
	S.step, S.waiting_since, S.wait_target = 1, nil, nil
	S.reverse = Biometrics.random_boolean(0.5)
	Log.log(NAME, if S.reverse then "Rotation in reverse" else "Rotation forward")
end

function Read.candidates(reset: boolean, known: { Host.GroundItem }?): { Host.GroundItem }
	local c = Read.collectable()
	local spawns = known or Read.spawns()
	if c.order then
		local tile = Read.step_tile()
		local at_step: { Host.GroundItem } = {}
		for _, item in ipairs(spawns) do
			if tile and item.x == tile.x and item.y == tile.y then
				table.insert(at_step, item)
			end
		end
		return at_step
	end
	if not c.contested then
		return spawns
	end
	local left: { Host.GroundItem } = {}
	for _, item in ipairs(spawns) do
		if not S.visited[`{item.x},{item.y}`] then
			table.insert(left, item)
		end
	end
	if #left == 0 and reset and #spawns > 0 then
		S.visited = {}
		return spawns
	end
	return left
end

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

function Read.next_after(item: Host.GroundItem): Host.GroundItem?
	local rest: { Host.GroundItem } = {}
	local skipped = false
	for _, other in ipairs(Read.candidates(false)) do
		if not skipped and other.id == item.id and other.x == item.x and other.y == item.y then
			skipped = true
		else
			table.insert(rest, other)
		end
	end
	if Read.collectable().order then
		return Read.cheapest(rest, item)
	end
	return Read.pick_from(rest, item)
end

function Read.loc_at(id: number, at: Spot): Host.Loc?
	for _, loc in ipairs(Host.locs(at.plane) or {}) do
		if loc.id == id and loc.x == at.x and loc.y == at.y then
			return loc
		end
	end
	return nil
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

	AntibanTasks.skills = { "Total" }
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

	if Bankmain.is_open() then
		Bankmain.close()
	elseif DepositBox.is_open() then
		DepositBox.close()
	end

	local c = Read.collectable()
	local near = c.tiles[1]
	if snap.state.position and (snap.state.position.plane ~= c.plane or Walker.distance(snap.me, near) > 25) then
		if
			c.tele and (snap.state.position.plane ~= c.plane or Walker.distance(snap.me, near) > CONST.TELE.FAR_FROM)
		then
			Log.log(NAME, `Teleporting to the {CONFIG.collect} spawns`)
			local ready = if c.tele.lyre then Game.check_lyre() else Game.check_spellbook()
			if not ready or not Handler.teleport_with(c.tele.to, c.tele.lyre) then
				Log.log(NAME, "Couldn't teleport to the spawns, stopping the script")
				S.finished = true
				return
			end
		elseif c.cave and Walker.distance(snap.me, near) > CONST.TELE.FAR_FROM then
			Log.log(NAME, `Going into the cave of the {CONFIG.collect} spawns`)
			if not Handler.pass_through(c.cave.enter, c.cave.enter_option) then
				Log.log(NAME, "Couldn't get into the cave (start outside it or inside), stopping the script")
				S.finished = true
				return
			end
		elseif c.boat and Walker.distance(snap.me, near) > CONST.TELE.FAR_FROM then
			Log.log(NAME, `Sailing to the {CONFIG.collect} spawns`)
			if not Handler.sail(c.boat.town_npc, c.boat.to_island, c.boat.town_at) then
				Log.log(NAME, "Couldn't sail to the spawns (start in Rellekka or on the island), stopping the script")
				S.finished = true
				return
			end
		elseif not Walker.walk(near, { near = 3, plane = c.plane }) then
			Log.log(NAME, `Couldn't walk to the {CONFIG.collect} spawns, stopping the script`)
			S.finished = true
			return
		end
	end

	Read.new_rotation()
	if Read.collectable().order then
		Handler.walk_to_step(false)
		Handler.aim_camera()
	end

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

local LUNAR_ISLE = { x1 = 2040, y1 = 3840, x2 = 2200, y2 = 3960 }

function Read.on_lunar_isle(): boolean
	local at = Walker.position()
	return at ~= nil
		and at.x >= LUNAR_ISLE.x1
		and at.x <= LUNAR_ISLE.x2
		and at.y >= LUNAR_ISLE.y1
		and at.y <= LUNAR_ISLE.y2
end

function Game.check_spellbook(): boolean
	if not Magic.open() then
		Log.log(NAME, "Error: couldn't open the spellbook to check it, stopping the script")
		return false
	end
	local book = Magic.spellbook()
	if book == "lunar" then
		return true
	end
	if Read.on_lunar_isle() then
		Log.log(NAME, `The {book} spellbook is on, switching to lunar at the altar is TODO, stopping the script`)
	else
		Log.log(NAME, `Error: the {book} spellbook is on, the lunar spellbook is needed, stopping the script`)
	end
	return false
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
	plan = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Inventory.is_open() then
		Inventory.open()
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	local trip = Read.collectable()
	if (trip.boat or trip.tele or trip.cave) and Read.away_from_spawns() then
		return if snap.free_slots == 0 and not skipped["BANK"] then "BANK" else "RETURN"
	end

	local potions = Read.potions()
	if potions then
		if S.trip_target == 0 then
			Loop.next_trip_target()
		end
		if S.batch_size == 0 then
			Loop.next_batch(potions)
		end
		local partial = #potions.partial
		if not S.pouring and partial >= 2 and (partial >= S.batch_size or snap.free_slots == 0) then
			S.pouring = true
		end
		if S.pouring then
			if partial >= 2 and not skipped["COMBINE"] then
				return "COMBINE"
			elseif potions.vials > 0 and not skipped["DROP"] then
				return "DROP"
			end
			S.pouring, S.batch_size = false, 0
		end
		if potions.full >= S.trip_target and not skipped["BANK"] then
			return "BANK"
		elseif snap.free_slots == 0 and not skipped["BANK"] then
			return "BANK"
		end
	elseif snap.free_slots == 0 and not skipped["BANK"] then
		return "BANK"
	end
	if time() < S.settle_until then
		return "SETTLE"
	end
	local spawns = Read.spawns()
	if Read.collectable().contested then
		Read.watch_rivals(spawns)
		if S.rivals and time() >= S.hop_retry_at and not skipped["HOP"] then
			return "HOP"
		end
	end
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
	plan.item = plan.item or Read.cheapest(Read.candidates(true, spawns), snap.me)
	if plan.item and not skipped["PICK"] then
		return "PICK"
	end
	if plan.item == nil and Read.collectable().order then
		return "WAIT"
	end
	if plan.item == nil and time() >= S.hop_retry_at and not skipped["HOP"] then
		return "HOP"
	end
	return "LOADING"
end

local function antiban()
	if CONFIG.antiban and S.antiban_ready then
		Antiban.do_antiban()
	end
end

function Handler.tiny_antiban()
	if CONFIG.antiban and S.antiban_ready and Biometrics.random_boolean(CONST.PICK.TINY_ANTIBAN) then
		Antiban.do_async_tasks("game")
	end
end

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

function Handler.prehover_loc(loc: Host.Loc, landing: Spot)
	local function aim(): Clickbox.Clickbox?
		return Objects.projected(loc, landing)
	end
	Clickbox.hover_async(aim, loc.name or tostring(loc.id))
end

function Handler.prehover_spawn(tile: Host.Tile, plane: number, landing: Spot)
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

function Read.plane(): number?
	local p = game_state().position
	return if p then p.plane else nil
end

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

function Handler.open_chest(route: Route): boolean
	for i, step in ipairs(route.down) do
		local nxt = route.down[i + 1]
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

function Handler.return_up(c: Collectable)
	local route = assert(c.route)
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
			return
		end
	end
end

function Handler.pick(item: Host.GroundItem)
	local before = Read.held()
	S.clicked[`{item.x},{item.y}`] = time()
	S.visited[`{item.x},{item.y}`] = true
	local here = Walker.position() or snap.me
	if GroundItems.distance(item, here) > CONST.PICK.WALK_FROM then
		if not Walker.walk({ x = item.x, y = item.y }, { near = CONST.PICK.WALK_NEAR, plane = item.plane }) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't walk to the {item.name} at {item.x}, {item.y}`)
			return
		end
	end
	if not GroundItems.interact(item, Read.collectable().option, false) then
		if GroundItems.refresh(item) then
			S.failures_in_row += 1
			stats.failures += 1
			Log.log(NAME, `Couldn't take the {item.name} at {item.x}, {item.y}`)
		elseif Read.collectable().order then
			S.step = S.step % #(Read.collectable().order :: { Host.Tile }) + 1
			S.waiting_since, S.wait_target = nil, nil
		end
		return
	end
	if Read.collectable().order then
		S.step = S.step % #(Read.collectable().order :: { Host.Tile }) + 1
		S.waiting_since, S.wait_target = nil, nil
	end
	local quick = Read.collectable().order ~= nil
	if quick then
		Handler.aim_camera()
	else
		Handler.tiny_antiban()
	end
	local route = Read.collectable().route
	if route and snap.free_slots <= 1 then
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
		if GroundItems.refresh(item) == nil and Read.held() == before then
			return
		end
		sleep(if quick then CONST.PICK.QUICK_POLL_MS else CONST.PICK.POLL_MS)
	end
	S.failures_in_row += 1
	stats.failures += 1
	Log.log(NAME, `The {item.name} at {item.x}, {item.y} didn't reach the inventory`)
end

function Handler.worlds(): { number }
	local worlds: { number } = {}
	if #CONFIG.hop_worlds > 0 then
		for _, world in ipairs(CONFIG.hop_worlds) do
			if not WorldSwitcher.is_blocked(world) then
				table.insert(worlds, world)
			end
		end
		return worlds
	end
	if WorldSwitcher.open(true) then
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.available and (row.members or not Read.collectable().members) then
				table.insert(worlds, row.world)
			end
		end
	end
	table.sort(worlds)
	return worlds
end

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
		S.rivals, S.seen, S.clicked, S.visited = false, {}, {}, {}
		S.settle_until = time() + Random.int(CONST.HOP.SETTLE_MIN_MS, CONST.HOP.SETTLE_MAX_MS)
		return
	end
	Log.log(NAME, "Couldn't hop, trying again in a bit")
	S.hop_retry_at = time() + CONST.HOP.RETRY_MS
	S.failures_in_row += 1
	stats.failures += 1
	S.skip["HOP"] = true
end

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

function Loop.next_trip_target()
	local p = CONST.POTION
	S.trip_target = Biometrics.random_mode_integer(p.TRIP_MODE, p.TRIP_MIN, p.TRIP_MAX)
end

function Loop.next_batch(potions: Potions)
	local room = math.min(28, snap.free_slots + #potions.partial)
	local most = math.max(2, room)
	local least = math.min(CONST.POTION.BATCH_MIN, most)
	S.batch_size = math.floor(Random.left(least, most + 1))
end

function Handler.combine()
	local potions = assert(Read.potions())
	local partial = potions.partial
	if #partial < 2 then
		return
	end
	local lowest, highest = math.huge, 0
	for _, p in ipairs(partial) do
		lowest, highest = math.min(lowest, p.dose), math.max(highest, p.dose)
	end
	local from: { PotionSlot } = {}
	for _, p in ipairs(partial) do
		if p.dose == lowest then
			table.insert(from, p)
		end
	end
	local source = from[Random.int(1, #from)]
	local into: { PotionSlot } = {}
	for _, p in ipairs(partial) do
		if p.dose == highest and p.slot ~= source.slot then
			table.insert(into, p)
		end
	end
	if #into == 0 then
		for _, p in ipairs(partial) do
			if p.slot ~= source.slot then
				table.insert(into, p)
			end
		end
	end
	local target = into[Random.int(1, #into)]
	local before = backpack.item(source.slot)
	if Inventory.combine_slots(source.slot, target.slot) then
		sleep(
			Biometrics.random_mode_integer(
				CONST.POTION.POUR_MODE_MS,
				CONST.POTION.POUR_MIN_MS,
				CONST.POTION.POUR_MAX_MS
			)
		)
		local deadline = time() + CONST.POTION.POUR_WAIT_MS
		while time() < deadline do
			local now = backpack.item(source.slot)
			if now == nil or before == nil or now.id ~= before.id then
				break
			end
			sleep(CONST.PICK.POLL_MS)
		end
	else
		Log.log(NAME, `Couldn't pour the potion in slot {source.slot} into slot {target.slot}`)
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["COMBINE"] = true
	end
end

function Handler.drop_vials()
	if not Inventory.shift_drop(CONST.POTION.VIAL) then
		Log.log(NAME, "Couldn't drop the empty vials")
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["DROP"] = true
	end
end

function Handler.teleport(far: Far): boolean
	local ring = CONST.RING
	local where = Read.ring()
	local ok = false
	if where == "worn" then
		ok = Wornitems.interact(ring.ANY, ring.TELEPORT)
	elseif where == "pack" then
		ok = Inventory.interact(ring.ANY, "Rub")
			and ChatOptions.wait_option(ring.TELEPORT)
			and ChatOptions.select(ring.TELEPORT)
	end
	if not ok then
		Log.log(NAME, "Couldn't use the ring of dueling")
		return false
	end
	local deadline = time() + ring.ARRIVE_MS
	while time() < deadline do
		local here = Walker.position()
		if here and Walker.distance(here, far.chest.at) <= ring.ARRIVE_NEAR then
			sleep(Random.int(300, 700))
			return true
		end
		sleep(CONST.PICK.POLL_MS)
	end
	Log.log(NAME, "The ring of dueling didn't take us to Castle Wars")
	return false
end

function Handler.reach_far(far: Far): boolean
	local here = Walker.position()
	if here and Walker.distance(here, far.chest.at) <= CONST.RING.ARRIVE_NEAR then
		return true
	end
	if Read.use_ring() and Read.ring() then
		Log.log(NAME, "Teleporting to Castle Wars")
		if Handler.teleport(far) then
			return true
		end
	end
	Log.log(NAME, "Walking to the bank")
	return Walker.walk(far.chest.at, { near = CONST.FAR.NEAR, plane = far.chest.at.plane })
end

function Handler.open_far(far: Far): boolean
	if far.chest.id == nil then
		return Bankmain.open()
	end
	local chest = Read.loc_at(far.chest.id, far.chest.at)
	if chest == nil then
		Log.log(NAME, "The bank chest wasn't found")
		return false
	end
	return Bankmain.open({ loc = chest, npc = nil })
end

function Handler.restock_ring(): boolean
	if not Read.use_ring() or Read.ring() then
		return false
	end
	for charges = 1, CONST.RING.MAX_CHARGES do
		local name = `Ring of dueling({charges})`
		if Bankmain.contains(name) and Bankmain.withdraw(name, 1, false) then
			Log.log(NAME, `Took a {name} out of the bank`)
			return true
		end
	end
	Log.log(NAME, "No ring of dueling in the bank, walking from now on")
	S.no_ring = true
	return false
end

function Handler.wear_ring()
	if Inventory.contains(CONST.RING.ANY) and Inventory.interact(CONST.RING.ANY, "Wear") then
		Wornitems.wait_count(CONST.RING.ANY, 1, 2000)
	end
end

function Handler.open_bank(box: boolean): boolean
	local c = Read.collectable()
	local route = c.route
	for attempt = 1, CONST.BANK.OPEN_ATTEMPTS do
		if c.far then
			if Handler.open_far(c.far) or Handler.enter_pin() then
				return true
			end
		elseif route then
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

function Handler.bank()
	local c = Read.collectable()
	if c.tele then
		return Handler.bank_by_teleport(c)
	elseif c.boat then
		return Handler.bank_by_boat(c)
	elseif c.cave then
		return Handler.bank_by_cave(c)
	end
	local route = c.route
	local box = route == nil and c.far == nil and Biometrics.random_boolean(CONFIG.deposit_box_chance)
	if c.far then
		local potions = Read.potions()
		Log.log(
			NAME,
			if potions
				then `Going to the bank with {potions.full} full potions`
				else "Inventory full, going to the bank"
		)
		if not Handler.reach_far(c.far) then
			S.failures_in_row += 1
			stats.failures += 1
			S.skip["BANK"] = true
			return
		end
	else
		Log.log(NAME, `Inventory full, using the {if box then "deposit box" else "bank"}`)
	end
	if not Handler.open_bank(box) then
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["BANK"] = true
		return
	end
	local keep = if c.far and Read.ring() == "pack" then 1 else 0
	local clicked
	if box then
		clicked = DepositBox.deposit_inventory()
	elseif keep > 0 then
		clicked = Bankmain.deposit_different(CONST.RING.ANY)
	else
		clicked = Bankmain.deposit_inventory()
	end
	if clicked and Inventory.wait_used(keep, CONST.BANK.DEPOSIT_MS) then
		stats.trips += 1
		S.failures_in_row = 0
		if c.potion then
			Loop.next_trip_target()
		end
	else
		Log.log(NAME, "The inventory wasn't deposited")
		S.failures_in_row += 1
		stats.failures += 1
	end
	local took_ring = c.far ~= nil and Handler.restock_ring()
	if box then
		DepositBox.close()
	else
		Bankmain.close()
	end
	Inventory.open()
	if took_ring then
		Handler.wear_ring()
	end
	if route then
		Handler.return_up(c)
	end
	if c.far then
		Log.log(NAME, "Walking back to the spawn")
		local spawn = c.tiles[1]
		if not Walker.walk(spawn, { near = CONST.PICK.WALK_NEAR, plane = c.plane }) then
			Log.log(NAME, "Couldn't walk back to the spawn")
			S.failures_in_row += 1
			stats.failures += 1
		end
	end
	S.last_progress_at = time()
end

function Read.in_view(tiles: { Host.Tile }): boolean
	for _, tile in ipairs(tiles) do
		local quad = Projection.tile({ x = tile.x, y = tile.y, plane = Read.collectable().plane })
		if quad == nil or not Projection.on_screen(quad) then
			return false
		end
	end
	return true
end

function Handler.aim_camera()
	local me = Walker.position()
	local facing = Camera.yaw_degrees()
	local tiles = Read.next_tiles(CONST.AIM.TILES)
	if me == nil or facing == nil or #tiles == 0 or Read.in_view(tiles) then
		return
	end
	local sin, cos = 0, 0
	for _, tile in ipairs(tiles) do
		if tile.x ~= me.x or tile.y ~= me.y then
			local bearing = math.atan2(tile.x - me.x, tile.y - me.y)
			sin, cos = sin + math.sin(bearing), cos + math.cos(bearing)
		end
	end
	if sin == 0 and cos == 0 then
		return
	end
	local target = math.deg(math.atan2(sin, cos))
	local diff = (target - facing + 180) % 360 - 180
	local aimed = target + diff * (Random.int(-100, 100) / 100) * CONST.AIM.ERROR
	Log.log(
		NAME,
		`Turning the camera {math.round(diff)} degrees (facing {math.round(facing)}, target {math.round(target)}) from {me.x}, {me.y} toward {tiles[1].x}, {tiles[1].y}`
	)
	Camera.set_yaw_degrees(aimed)
end

function Read.near_tile(tile: Host.Tile): Host.Tile
	local spread = CONST.TELE.WAIT_SPREAD
	return { x = tile.x + Random.int(-spread, spread), y = tile.y + Random.int(-spread, spread) }
end

function Handler.walk_to_step(until_respawn: boolean)
	local tile = Read.step_tile()
	local here = Walker.position()
	if tile == nil or here == nil or Walker.distance(here, tile) <= CONST.TELE.WAIT_SPREAD then
		return
	end
	local checked = 0
	Walker.walk(S.wait_target or Read.near_tile(tile), {
		near = 1,
		plane = Read.collectable().plane,
		on_step = function(): boolean?
			if not until_respawn or time() - checked < CONST.TELE.RESPAWN_CHECK_MS then
				return nil
			end
			checked = time()
			return #Read.candidates(false) == 0
		end,
	})
end

function Handler.wait_for_spawn()
	local tile = Read.step_tile()
	local since: number = S.waiting_since or time()
	if S.waiting_since == nil then
		S.wait_target = if tile then Read.near_tile(tile) else nil
	end
	S.waiting_since = since
	if tile == nil or time() - since > CONST.TELE.SPAWN_WAIT_MS then
		S.step = S.step % #(Read.collectable().order :: { Host.Tile }) + 1
		S.waiting_since, S.wait_target = nil, nil
		return
	end
	Handler.aim_camera()
	Handler.walk_to_step(true)
	sleep(Random.int(150, 300))
	antiban()
end

local LYRE_NAMES = {
	"Enchanted lyre(i)",
	"Enchanted lyre(5)",
	"Enchanted lyre(4)",
	"Enchanted lyre(3)",
	"Enchanted lyre(2)",
	"Enchanted lyre(1)",
	"Enchanted lyre",
}

function Read.has_lyre(): boolean
	local worn = Wornitems.indices_of(LYRE_NAMES)
	local carried = Inventory.indices_of(LYRE_NAMES)
	return (worn ~= nil and #worn > 0) or (carried ~= nil and #carried > 0)
end

function Game.check_lyre(): boolean
	if Read.has_lyre() then
		return true
	end
	Log.log(NAME, "Error: no enchanted lyre worn or in the inventory, stopping the script")
	return false
end

function Game.check_lyre_diary(): boolean
	local done = Diaries.tier("Fremennik", "elite")
	if done then
		return true
	end
	if done == nil then
		Log.log(NAME, "Error: couldn't read the Fremennik diary, stopping the script")
	else
		Log.log(
			NAME,
			"Error: the Fremennik elite diary must be completed to use the enchanted lyre, stopping the script"
		)
	end
	return false
end

local SEAL_NAMES = { "Seal of passage" }

function Game.pick_booths(c: Collectable): { Booth }?
	local booths = c.tele and c.tele.booths
	if booths == nil or Diaries.tier("Fremennik", "elite") == true then
		return nil
	end
	local worn, carried = Wornitems.indices_of(SEAL_NAMES), Inventory.indices_of(SEAL_NAMES)
	local seal = (worn ~= nil and #worn > 0) or (carried ~= nil and #carried > 0)
	local dream = Journal.is_quest_complete("Dream Mentor")
	local allowed: { Booth } = {}
	for _, booth in ipairs(booths) do
		if (booth.seal and seal) or (booth.dream and dream) then
			table.insert(allowed, booth)
		end
	end
	local where = if #allowed > 0
		then `banking at {#allowed} of {#booths} booths`
		else "banking at the deposit box only"
	Log.log(NAME, `Fremennik elite diary not done (seal of passage: {seal}, Dream Mentor: {dream}), {where}`)
	return allowed
end

function Read.allowed_booth(booths: { Booth }): Bankmain.Source?
	local at = Walker.position()
	local best: Host.Loc? = nil
	local best_d = math.huge
	for _, loc in ipairs(Objects.find("Bank booth") or {}) do
		for _, booth in ipairs(booths) do
			if loc.x == booth.x and loc.y == booth.y then
				local d = if at then Walker.distance(at, loc) else 0
				if d < best_d then
					best, best_d = loc, d
				end
			end
		end
	end
	return if best then { loc = best, npc = nil } else nil
end

function Handler.play_lyre(destination: string): boolean
	local worn = Wornitems.indices_of(LYRE_NAMES)
	if worn and #worn > 0 then
		return Wornitems.open() and Wornitems.interact_slot(worn[1], destination)
	end
	local carried = Inventory.indices_of(LYRE_NAMES)
	if carried and #carried > 0 then
		return Inventory.open()
			and Inventory.hover_slot(carried[1])
			and Minimenu.open()
			and Minimenu.select_submenu(destination, nil, "Play")
	end
	return false
end

function Handler.teleport_with(spells: { string }, lyre: boolean?): boolean
	if not lyre and not Magic.open() then
		Log.log(NAME, "Couldn't open the spellbook")
		return false
	end
	local usable: { string } = {}
	for _, spell in ipairs(spells) do
		if if lyre then Read.has_lyre() else Magic.can_cast(spell) then
			table.insert(usable, spell)
		end
	end
	if #usable == 0 then
		Log.log(
			NAME,
			`Error: none of {table.concat(spells, ", ")} can be cast (out of runes, or no lyre?), stopping the script`
		)
		S.finished = true
		return false
	end
	local spell = usable[if #usable > 1 and Biometrics.random_boolean(0.5) then 2 else 1]
	local from = Walker.position()
	Log.log(NAME, if lyre then `Playing the lyre to {spell}` else `Casting {spell}`)
	if not (if lyre then Handler.play_lyre(spell) else Magic.cast(spell)) then
		Log.log(NAME, `Couldn't {if lyre then "play the lyre to" else "cast"} {spell}`)
		return false
	end
	local deadline = time() + CONST.TELE.ARRIVE_MS
	while time() < deadline do
		local here = Walker.position()
		if from and here and Walker.distance(here, from) >= CONST.TELE.MOVED then
			sleep(Random.int(500, 1100))
			return true
		end
		sleep(CONST.PICK.POLL_MS)
	end
	Log.log(NAME, `{spell} didn't take us anywhere`)
	return false
end

function Handler.bank_by_teleport(c: Collectable)
	local tele = assert(c.tele)
	local function failed()
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["BANK"] = true
	end
	if not Read.away_from_spawns() then
		Log.log(NAME, "Inventory full, teleporting to the bank")
		if not Handler.teleport_with(tele.bank, tele.lyre) then
			return failed()
		end
	end
	local booths = S.booths
	local box = tele.box ~= false
		and ((booths ~= nil and #booths == 0) or Biometrics.random_boolean(CONST.TELE.BOX_CHANCE))
	local opened = false
	for attempt = 1, CONST.BANK.OPEN_ATTEMPTS do
		if box then
			opened = DepositBox.open() and DepositBox.wait_open()
		else
			local source = if booths then Read.allowed_booth(booths) else nil
			opened = Bankmain.open(source) or Handler.enter_pin()
		end
		if opened or S.finished then
			break
		end
		Log.log(NAME, `The {if box then "deposit box" else "bank"} didn't open (attempt {attempt})`)
		sleep(Random.int(400, 900))
	end
	if not opened then
		return failed()
	end
	local clicked = if box then DepositBox.deposit(c.item, nil, true) else Bankmain.deposit(c.item, nil, true)
	if clicked and Inventory.wait_count(c.item, 0, CONST.BANK.DEPOSIT_MS) then
		stats.trips += 1
		S.failures_in_row = 0
	else
		Log.log(NAME, `The {c.item} wasn't deposited`)
		S.failures_in_row += 1
		stats.failures += 1
	end
	if box then
		DepositBox.close()
	else
		Bankmain.close()
	end
	Inventory.open()
	Handler.return_to_spawns(c)
end

function Read.away_from_spawns(): boolean
	local c = Read.collectable()
	local at = Walker.position()
	return at ~= nil and Walker.distance(at, c.tiles[1]) > CONST.TELE.FAR_FROM
end

function Handler.sail(npc_id: number, option: string, at: Host.Tile): boolean
	local from = Walker.position()
	local started = false
	local jarvald: Host.Npc? = nil
	local reason = ""
	for attempt = 1, 3 do
		local here = Walker.position()
		if here and Walker.distance(here, jarvald or at) > CONST.BOAT.CLOSE then
			Walker.walk(at, { near = 3 })
		end
		jarvald = (Npcs.find(npc_id) or {})[1]
		reason = if jarvald == nil then "not in sight" else "couldn't click him"
		if jarvald and Npcs.interact(jarvald, option, CONST.BOAT.WALK_MS) then
			reason = "no journey"
			local deadline = time() + CONST.BOAT.START_MS
			while time() < deadline and Toplevel.interface_name() ~= CONST.BOAT.JOURNEY do
				sleep(CONST.PICK.POLL_MS)
			end
			started = Toplevel.interface_name() == CONST.BOAT.JOURNEY
			if started then
				break
			end
		end
		Log.log(NAME, `Jarvald didn't take us ({option}, attempt {attempt}: {reason})`)
		sleep(Random.int(400, 900))
	end
	if not started then
		return false
	end
	local deadline = time() + CONST.BOAT.END_MS
	while time() < deadline and Toplevel.interface_name() == CONST.BOAT.JOURNEY do
		sleep(CONST.PICK.POLL_MS)
	end
	sleep(Random.int(500, 1100))
	local here = Walker.position()
	return from ~= nil and here ~= nil and Walker.distance(here, from) >= CONST.TELE.MOVED
end

function Handler.pass_through(name: string, option: string): boolean
	local from = Walker.position()
	for attempt = 1, 3 do
		local loc = if from then Objects.nearest(name, from) else nil
		if loc and Objects.approach(loc, option) then
			local deadline = time() + CONST.CAVE.PASS_MS
			while time() < deadline do
				local here = Walker.position()
				if here and from and Walker.distance(here, from) >= CONST.TELE.MOVED then
					sleep(Random.int(500, 1100))
					return true
				end
				sleep(CONST.PICK.POLL_MS)
			end
		end
		Log.log(NAME, `Couldn't go through the {name} ({option}, attempt {attempt})`)
		sleep(Random.int(400, 900))
		from = Walker.position()
	end
	return false
end

function Handler.bank_by_cave(c: Collectable)
	local cave = assert(c.cave)
	local function failed()
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["BANK"] = true
	end
	if not Read.away_from_spawns() then
		Log.log(NAME, "Inventory full, leaving the cave")
		if not Handler.pass_through(cave.exit, cave.exit_option) then
			return failed()
		end
	end
	local opened = false
	for attempt = 1, CONST.BANK.OPEN_ATTEMPTS do
		local bank: Host.Loc? = nil
		local deadline = time() + CONST.CAVE.SCENE_MS
		repeat
			local here = Walker.position()
			bank = if here then Objects.nearest(cave.bank, here) else nil
			if bank == nil then
				sleep(CONST.PICK.POLL_MS)
			end
		until bank ~= nil or time() >= deadline
		opened = bank ~= nil and (Bankmain.open({ loc = bank, npc = nil }) or Handler.enter_pin())
		if opened or S.finished then
			break
		end
		Log.log(NAME, `The {cave.bank} didn't open (attempt {attempt})`)
		sleep(Random.int(400, 900))
	end
	if opened then
		if Bankmain.deposit(c.item, nil, true) and Inventory.wait_count(c.item, 0, CONST.BANK.DEPOSIT_MS) then
			stats.trips += 1
			S.failures_in_row = 0
		else
			Log.log(NAME, `The {c.item} wasn't deposited`)
			S.failures_in_row += 1
			stats.failures += 1
		end
		Bankmain.close()
		Inventory.open()
	else
		S.failures_in_row += 1
		stats.failures += 1
	end
	Handler.return_to_spawns(c)
end

function Handler.bank_by_boat(c: Collectable)
	local boat = assert(c.boat)
	local function failed()
		S.failures_in_row += 1
		stats.failures += 1
		S.skip["BANK"] = true
	end
	if not Read.away_from_spawns() then
		Log.log(NAME, `Inventory full, sailing to {boat.to_town}`)
		if not Handler.sail(boat.island_npc, boat.to_town, boat.island_at) then
			return failed()
		end
	end
	if not Walker.walk(boat.seer_at, { near = 3 }) then
		Log.log(NAME, `Couldn't walk to {boat.seer}`)
	end
	local opened = false
	for attempt = 1, CONST.BANK.OPEN_ATTEMPTS do
		local seer = (Npcs.find(boat.seer) or {})[1]
		opened = seer ~= nil and Npcs.interact(seer, boat.seer_option, CONST.BOAT.WALK_MS) and DepositBox.wait_open()
		if opened or S.finished then
			break
		end
		Log.log(NAME, `{boat.seer}'s deposit box didn't open (attempt {attempt})`)
		sleep(Random.int(400, 900))
	end
	if opened then
		if DepositBox.deposit(c.item, nil, true) and Inventory.wait_count(c.item, 0, CONST.BANK.DEPOSIT_MS) then
			stats.trips += 1
			S.failures_in_row = 0
		else
			Log.log(NAME, `The {c.item} wasn't deposited`)
			S.failures_in_row += 1
			stats.failures += 1
		end
		DepositBox.close()
		Inventory.open()
	else
		S.failures_in_row += 1
		stats.failures += 1
	end
	Handler.return_to_spawns(c)
end

function Handler.return_to_spawns(c: Collectable)
	S.visited = {}
	local back
	if c.boat then
		back = Handler.sail(c.boat.town_npc, c.boat.to_island, c.boat.town_at)
	elseif c.cave then
		back = Handler.pass_through(c.cave.enter, c.cave.enter_option)
	else
		back = Handler.teleport_with(assert(c.tele).to, c.tele.lyre)
	end
	if back then
		Read.new_rotation()
		Handler.walk_to_step(false)
		Handler.aim_camera()
	elseif not S.finished then
		S.failures_in_row += 1
		stats.failures += 1
		sleep(Random.int(800, 1600))
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
	RETURN = function()
		Handler.return_to_spawns(Read.collectable())
	end,
	COMBINE = Handler.combine,
	DROP = Handler.drop_vials,
	PICK = function()
		Handler.pick(assert(plan.item))
		if not Read.collectable().order then
			antiban()
		end
	end,
	HOP = Handler.hop,
	WAIT = Handler.wait_for_spawn,
}

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
				id = "snape_route",
				kind = "choice",
				label = "Snape grass route",
				options = SNAPE_ROUTES,
				default = CONFIG.snape_route,
				visible_when = { id = "collect", equals = "Snape grass" },
			},
			{
				id = "snape_todo",
				kind = "label",
				label = "TODO",
				visible_when = { id = "snape_route", equals = SNAPE_TODO },
			},
			{
				id = "spider_note",
				kind = "label",
				label = "Only picks the eggs at the Pandemonium",
				visible_when = { id = "collect", equals = "Red spider eggs" },
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
			{
				id = "ring",
				kind = "check",
				label = "Ring of dueling",
				default = CONFIG.ring,
				visible_when = { id = "collect", equals = FAR_BANK_NAMES },
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
	if COLLECTABLES[values.collect] then
		CONFIG.collect = values.collect
	end
	CONFIG.max_items = values.max_items
	if table.find(SNAPE_ROUTES, values.snape_route) then
		CONFIG.snape_route = values.snape_route
	end
	CONFIG.ring = values.ring == true
end

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
local last_stray_at = 0
local function close_stray(banking: boolean)
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	if banking and (Bankmain.is_open() or DepositBox.is_open() or BankpinKeypad.is_open()) then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
	if CONFIG.collect == "Snape grass" and CONFIG.snape_route == SNAPE_ROUTES[3] and not Game.check_spellbook() then
		return
	end
	if
		CONFIG.collect == "Snape grass"
		and CONFIG.snape_route == SNAPE_ROUTES[2]
		and not (Game.check_lyre_diary() and Game.check_lyre())
	then
		return
	end
	if CONFIG.collect == "Snape grass" and table.find(SNAPE_TODO, CONFIG.snape_route) then
		Log.log(NAME, `{CONFIG.snape_route} isn't done yet (TODO), stopping the script`)
		return
	end
	Log.log(NAME, `{NAME} started: {CONFIG.collect}`)
	Game.setup()
	S.booths = Game.pick_booths(Read.collectable())
	if S.booths then
		Inventory.open()
	end
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		close_stray(state == "BANK")
		Game.poll_settings()
		Handler.states[state]()

		if not (state == "PICK" and S.chosen and Read.collectable().order) then
			if CONFIG.antiban and S.antiban_ready then
				Antiban.do_async_tasks("outside")
			end
			sleep(Random.int(60, 140))
		end
	end
	Log.log(NAME, "Done")
end

Loop.run()
