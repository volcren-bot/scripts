--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local BankpinKeypad = require("@lib/main/interfaces/mainscreen/bankpin_keypad")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local Diaries = require("@lib/main/diaries")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Item = require("@lib/utils/item")
local ItemData = require("@lib/utils/item_data")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Make = require("@lib/main/interfaces/chatbox/make")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Transports = require("@lib/main/transports")
local Walker = require("@lib/main/walker")
local Widgets = require("@lib/main/interfaces/widgets")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Cooker"

type Food = { id: string, raw: string, cooked: string, level: number }

local FOODS: { Food } = {
	{ id = "beef", raw = "Raw beef", cooked = "Cooked meat", level = 1 },
	{ id = "shrimps", raw = "Raw shrimps", cooked = "Shrimps", level = 1 },
	{ id = "chicken", raw = "Raw chicken", cooked = "Cooked chicken", level = 1 },
	{ id = "rabbit", raw = "Raw rabbit", cooked = "Cooked rabbit", level = 1 },
	{ id = "anchovies", raw = "Raw anchovies", cooked = "Anchovies", level = 1 },
	{ id = "sardine", raw = "Raw sardine", cooked = "Sardine", level = 1 },
	{ id = "herring", raw = "Raw herring", cooked = "Herring", level = 5 },
	{ id = "mackerel", raw = "Raw mackerel", cooked = "Mackerel", level = 10 },
	{ id = "thin_snail", raw = "Thin snail", cooked = "Thin snail meat", level = 12 },
	{ id = "trout", raw = "Raw trout", cooked = "Trout", level = 15 },
	{ id = "lean_snail", raw = "Lean snail", cooked = "Lean snail meat", level = 17 },
	{ id = "cod", raw = "Raw cod", cooked = "Cod", level = 18 },
	{ id = "pike", raw = "Raw pike", cooked = "Pike", level = 20 },
	{ id = "fat_snail", raw = "Fat snail", cooked = "Fat snail meat", level = 22 },
	{ id = "salmon", raw = "Raw salmon", cooked = "Salmon", level = 25 },
	{ id = "tuna", raw = "Raw tuna", cooked = "Tuna", level = 30 },
	{ id = "karambwan", raw = "Raw karambwan", cooked = "Cooked karambwan", level = 30 },
	{ id = "larupia", raw = "Raw larupia", cooked = "Cooked larupia", level = 31 },
	{ id = "rainbow_fish", raw = "Raw rainbow fish", cooked = "Rainbow fish", level = 35 },
	{ id = "cave_eel", raw = "Raw cave eel", cooked = "Cave eel", level = 38 },
	{ id = "lobster", raw = "Raw lobster", cooked = "Lobster", level = 40 },
	{ id = "graahk", raw = "Raw graahk", cooked = "Cooked graahk", level = 41 },
	{ id = "bass", raw = "Raw bass", cooked = "Bass", level = 43 },
	{ id = "swordfish", raw = "Raw swordfish", cooked = "Swordfish", level = 45 },
	{ id = "kyatt", raw = "Raw kyatt", cooked = "Cooked kyatt", level = 51 },
	{ id = "pyre_fox", raw = "Raw pyre fox", cooked = "Cooked pyre fox", level = 59 },
	{ id = "monkfish", raw = "Raw monkfish", cooked = "Monkfish", level = 62 },
	{ id = "sunlight_antelope", raw = "Raw sunlight antelope", cooked = "Cooked sunlight antelope", level = 68 },
	{ id = "shark", raw = "Raw shark", cooked = "Shark", level = 80 },
	{ id = "sea_turtle", raw = "Raw sea turtle", cooked = "Sea turtle", level = 82 },
	{ id = "dashing_kebbit", raw = "Raw dashing kebbit", cooked = "Cooked dashing kebbit", level = 82 },
	{ id = "anglerfish", raw = "Raw anglerfish", cooked = "Anglerfish", level = 84 },
	{ id = "dark_crab", raw = "Raw dark crab", cooked = "Dark crab", level = 90 },
	{ id = "manta_ray", raw = "Raw manta ray", cooked = "Manta ray", level = 91 },
	{ id = "moonlight_antelope", raw = "Raw moonlight antelope", cooked = "Cooked moonlight antelope", level = 92 },
}

type Destination = { name: string, walk_to: Host.Tile, plane: number, landing: Host.Tile }

local CONST = {
	REPORT = { counters_key = "" },
	COOK_ACTION = "Cook",
	BANK_NAMES = { "Bank booth", "Bank chest" },
	BANK_ACTIONS = { "Bank", "Use" },
	SITE = { start_tiles = 25, landing_tiles = 15, pair_tiles = 20, near_tiles = 25 },
	GAUNTLETS = "Cooking gauntlets",
	COOK_IDLE_MS = 4200,
	CAST_READY_MS = 1200,
	BANK_CONFIRM_MS = 2400,
	WALK_IN_MS = 9000,
	DEPOSIT_BUTTON_CHANCE = 0.5,
	INVENTORY_REOPEN_MS = { 800, 4000 },
	VIEW = { check_ms = 1500, spread_degrees = 8, zoom_step = 40 },
	NECKLACES = { 3867, 3865, 3863, 3861, 3859, 3857, 3855, 3853 } :: { Item.Item },
	NECKLACE_ROW = "Games necklace: Burthorpe",
	SPELL = "Kourend Castle Teleport",
	RUNES = {
		{ item = 563, amount = 2 },
		{ item = 554, amount = 1 },
		{ item = 555, amount = 1 },
	},
	TRAVEL_EXCLUDE = { spells = true, items = true, minigames = true, house = true } :: { [string]: boolean },
	DEN = {
		name = "Rogues' Den",
		walk_to = { x = 3041, y = 4971 },
		plane = 1,
		landing = { x = 2899, y = 3553 },
	} :: Destination,
	KITCHEN = {
		name = "Hosidius kitchen",
		walk_to = { x = 1677, y = 3617 },
		plane = 0,
		landing = { x = 1641, y = 3673 },
	} :: Destination,
	LANDING_NEAR = 40,
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	foods = {} :: { Food },
	max_cooked = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local stats = { cooked = 0, burnt = 0, trips = 0, failures = 0 }

type Site = {
	cook: Host.Tile,
	cook_name: string,
	bank: Host.Tile,
	bank_name: string,
	bank_npc: number?,
	plane: number,
}

type View = { yaw: number, pitch: number, zoom: number }

type Travel = "necklace" | "spell"

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	site: Site?,
	food_index: number,
	cooking: boolean,
	cook_progress_at: number,
	last_raw: number?,
	last_cooked: number?,
	cooked_price: number,
	raw_price: number,
	cook_stand: Host.Tile?,
	bank_stand: Host.Tile?,
	view_checked_at: number,
	view: View?,
	no_view: boolean,
	inventory_due_at: number?,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	site = nil,
	food_index = 1,
	cooking = false,
	cook_progress_at = 0,
	last_raw = nil,
	last_cooked = nil,
	cooked_price = 0,
	raw_price = 0,
	cook_stand = nil,
	bank_stand = nil,
	view_checked_at = 0,
	view = nil,
	no_view = false,
	inventory_due_at = nil,
}

type Snapshot = {
	state: ClientState,
	me: Host.PositionData,
	raw: number,
	cooked: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LEVEL_UP" | "TRAVEL" | "WALK" | "BANK" | "RANGE" | "MAKE" | "WAIT"

local report = StatsReport.new()

function Read.food(): Food?
	return CONFIG.foods[S.food_index]
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	local me = state.position
	local food = Read.food()
	if me == nil or food == nil then
		return false
	end
	local raw = Inventory.count_ex(food.raw)
	local cooked = Inventory.count_ex(food.cooked)
	if raw == nil or cooked == nil then
		return false
	end
	snap = { state = state, me = me, raw = raw, cooked = cooked }
	return true
end

function Read.gap(a: Host.Tile, b: Host.Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

type BankSpot = { x: number, y: number, name: string, npc: number? }

function Read.closest(locs: { BankSpot }, from: Host.Tile): BankSpot?
	local best: BankSpot? = nil
	local best_gap = math.huge
	for _, loc in ipairs(locs) do
		local d = Read.gap(loc, from)
		if d < best_gap then
			best, best_gap = loc, d
		end
	end
	return best
end

function Read.area(center: Host.Tile, reach: number): Host.Corners
	return { x1 = center.x - reach, y1 = center.y - reach, x2 = center.x + reach, y2 = center.y + reach }
end

function Read.offers(view: Host.LocView, names: { string }?, actions: { string }): boolean
	if names then
		local name = string.lower(view.name)
		local named = false
		for _, wanted in ipairs(names) do
			named = named or string.find(name, string.lower(wanted), 1, true) ~= nil
		end
		if not named then
			return false
		end
	end
	for _, action in ipairs(view.actions) do
		if table.find(actions, action) then
			return true
		end
	end
	return false
end

type Shown = { loc: Host.CacheLoc, name: string }

function Read.shown_locs(area: Host.Corners, plane: number, names: { string }?, actions: { string }): { Shown }
	local placed = Host.cache_locs(area, { plane = plane }) or {}
	local ids: { number } = {}
	local index: { [number]: number } = {}
	for _, loc in ipairs(placed) do
		if index[loc.id] == nil then
			table.insert(ids, loc.id)
			index[loc.id] = #ids
		end
	end
	local views = if #ids > 0 then Host.loc_shown(ids) else nil
	local found: { Shown } = {}
	if views == nil then
		return found
	end
	for _, loc in ipairs(placed) do
		local view = views[index[loc.id]]
		if view and Read.offers(view, names, actions) then
			table.insert(found, { loc = loc, name = view.name })
		end
	end
	return found
end

function Read.find_site(center: Host.Tile, plane: number, reach: number): Site?
	local cooks = Read.shown_locs(Read.area(center, reach), plane, nil, { CONST.COOK_ACTION })
	local banks =
		Read.shown_locs(Read.area(center, reach + CONST.SITE.pair_tiles), plane, CONST.BANK_NAMES, CONST.BANK_ACTIONS)
	local bank_spots: { BankSpot } = {}
	for _, bank in ipairs(banks) do
		table.insert(bank_spots, { x = bank.loc.x, y = bank.loc.y, name = bank.name, npc = nil })
	end
	for _, npc in ipairs(Npcs.find() or {}) do
		if Bankmain.is_banker(npc) then
			table.insert(bank_spots, { x = npc.x, y = npc.y, name = npc.name, npc = npc.id })
		end
	end
	local best: Site? = nil
	local best_trip, best_walk = math.huge, math.huge
	for _, cook in ipairs(cooks) do
		local bank = Read.closest(bank_spots, cook.loc)
		local trip = if bank then Read.gap(bank, cook.loc) else math.huge
		local walk = Read.gap(cook.loc, center)
		if
			bank ~= nil
			and trip <= CONST.SITE.pair_tiles
			and (trip < best_trip or (trip == best_trip and walk < best_walk))
		then
			best = {
				cook = { x = cook.loc.x, y = cook.loc.y },
				cook_name = cook.name,
				bank = { x = bank.x, y = bank.y },
				bank_name = bank.name,
				bank_npc = bank.npc,
				plane = plane,
			}
			best_trip, best_walk = trip, walk
		end
	end
	return best
end

function Read.scene_loc(tile: Host.Tile, name: string): Loc?
	local wanted = string.lower(name)
	local locs: { Loc } = Objects.find() or {}
	for _, loc in ipairs(locs) do
		if loc.name ~= nil and string.lower(loc.name) == wanted and Objects.distance(loc, tile) == 0 then
			return loc
		end
	end
	return nil
end

function Read.cook_loc(): Loc?
	local site = S.site :: Site
	return Read.scene_loc(site.cook, site.cook_name)
end

function Read.bank(): Bankmain.Source?
	local site = S.site :: Site
	if site.bank_npc then
		local npc = Npcs.nearest(site.bank_npc, site.bank)
		return if npc then { npc = npc } else nil
	end
	local loc = Read.scene_loc(site.bank, site.bank_name)
	return if loc then { loc = loc } else nil
end

function Read.bank_box(bank: Bankmain.Source, from: Host.Tile?): Clickbox.Clickbox?
	if bank.npc then
		return if from then Npcs.projected(bank.npc, from) else Npcs.clickbox(bank.npc)
	end
	local loc = bank.loc :: Loc
	return if from then Objects.projected(loc, from) else Objects.clickbox(loc)
end

function Read.bank_plain(bank: Bankmain.Source): boolean
	if bank.npc then
		return Walker.plain_walk({ x = bank.npc.x, y = bank.npc.y }, 1)
	end
	return Objects.plain_walk(bank.loc :: Loc)
end

function Read.bank_hovered(bank: Bankmain.Source): boolean
	return if bank.npc then Npcs.hovered(bank.npc) else Objects.hovered(bank.loc :: Loc)
end

function Read.at_site(site: Site): boolean
	return (snap.me.plane or 0) == site.plane and Read.gap(snap.me, site.cook) <= CONST.SITE.near_tiles
end

function Read.shown(box: Clickbox.Clickbox?): boolean
	local cuboid = if box then box.box else nil
	if cuboid == nil then
		return false
	end
	local view, blockers = Toplevel.viewport(), Toplevel.panel_blockers()
	local base = cuboid.bottom
	for _, corner in ipairs({ base.top, base.right, base.bottom, base.left }) do
		if not Toplevel.is_visible(corner, view, blockers) then
			return false
		end
	end
	return true
end

function Read.site_in_view(): boolean
	local bank, cook = Read.bank(), Read.cook_loc()
	local bank_shown = bank == nil or S.cook_stand == nil or Read.shown(Read.bank_box(bank, S.cook_stand))
	local cook_shown = cook == nil
		or S.bank_stand == nil
		or Read.shown(Objects.projected(cook, S.bank_stand :: Host.Tile))
	return bank_shown and cook_shown
end

function Read.off_by(a: number, b: number): number
	return math.abs((a - b + 180) % 360 - 180)
end

function Read.view_yaws(site: Site): { number }
	local bearing = math.deg(math.atan2(site.bank.x - site.cook.x, site.bank.y - site.cook.y))
	local facing = Camera.yaw_degrees() or bearing
	local yaws = { bearing, bearing + 90, bearing + 180, bearing - 90 }
	table.sort(yaws, function(a: number, b: number): boolean
		return Read.off_by(facing, a) < Read.off_by(facing, b)
	end)
	return yaws
end

function Read.in_view(loc: Loc): boolean
	local box = Objects.clickbox(loc)
	return box ~= nil and Clickbox.target(box, loc.name or "object") ~= nil
end

function Read.bank_in_view(bank: Bankmain.Source): boolean
	local box = Read.bank_box(bank)
	local name = if bank.npc then bank.npc.name else (bank.loc :: Loc).name or "bank"
	return box ~= nil and Clickbox.target(box, name) ~= nil
end

function Read.unwanted(keep: { string | number }): { number }
	local matcher = Item.matcher(keep)
	local ids: { number } = {}
	for _, s in ipairs(Bankmain.inventory.items() or {}) do
		if not Item.matches(matcher, s.id, s.name) and not table.find(ids, s.id) then
			table.insert(ids, s.id)
		end
	end
	return ids
end

function Read.travel_keep(): { string | number }
	local keep: { string | number } = {}
	for _, necklace in ipairs(CONST.NECKLACES) do
		table.insert(keep, necklace)
	end
	for _, rune in ipairs(CONST.RUNES) do
		table.insert(keep, rune.item)
	end
	return keep
end

function Read.nearby_destination(): Destination?
	for _, dest in ipairs({ CONST.DEN, CONST.KITCHEN }) do
		if (snap.me.plane or 0) == 0 and Read.gap(snap.me, dest.landing) <= CONST.LANDING_NEAR then
			return dest
		end
	end
	return nil
end

function Read.held_travel(): Travel?
	if Read.wearing_necklace() or Inventory.contains_any(CONST.NECKLACES) then
		return "necklace"
	end
	if not Diaries.tier("kourend", "easy") then
		return nil
	end
	for _, rune in ipairs(CONST.RUNES) do
		if (Inventory.count_ex(rune.item) or 0) < rune.amount then
			return nil
		end
	end
	return "spell"
end

function Read.wearing_necklace(): boolean
	for _, necklace in ipairs(CONST.NECKLACES) do
		if Wornitems.is_wearing(necklace) then
			return true
		end
	end
	return false
end

function Read.runes_available(): boolean
	for _, rune in ipairs(CONST.RUNES) do
		local held = Bankmain.inventory.count_ex(rune.item) or 0
		if held + (Bankmain.count_ex(rune.item) or 0) < rune.amount then
			return false
		end
	end
	return true
end

function Read.can_cast(): boolean
	return Magic.can_cast(CONST.SPELL)
end

function Read.menu_lacks(name: string): boolean
	local options = Make.options()
	if options == nil or #options == 0 then
		return false
	end
	local wanted = string.lower(name)
	for _, option in ipairs(options) do
		if string.lower(option.name) == wanted then
			return false
		end
	end
	return true
end

function Read.cooking(): boolean
	if not S.cooking then
		return false
	end
	if Player.is_animating() then
		S.cook_progress_at = time()
	end
	return time() - S.cook_progress_at < CONST.COOK_IDLE_MS
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

function Game.stop(reason: string)
	Log.log(NAME, `{reason}, stopping the script`)
	S.finished = true
end

function Game.fail(reason: string)
	Log.log(NAME, reason)
	S.failures_in_row += 1
	stats.failures += 1
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Cooking", "Total" }
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
	Antiban.add_async_task(AntibanTasks.small_camera_rotation, 70 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_player, 120 * SECOND, 0.4, "game")

	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.load_prices()
	local food = Read.food()
	if food == nil then
		return
	end
	local prices = ItemData.prices({ food.cooked, food.raw })
	S.cooked_price = if prices then prices[1] or 0 else 0
	S.raw_price = if prices then prices[2] or 0 else 0
end

function Game.select_food(index: number)
	local level = Stats.level("Cooking") or 0
	while CONFIG.foods[index] and CONFIG.foods[index].level > level do
		Log.log(NAME, `Skipping {CONFIG.foods[index].raw}: it needs {CONFIG.foods[index].level} Cooking`)
		index += 1
	end
	S.food_index = index
	S.cooking = false
	S.last_raw, S.last_cooked = nil, nil
	local food = Read.food()
	if food == nil then
		return
	end
	Game.load_prices()
	Log.log(NAME, `Cooking {food.raw}`)
end

function Game.next_food(reason: string)
	local food = Read.food()
	Log.log(NAME, `{reason}, done with {if food then food.raw else "this food"}`)
	Game.select_food(S.food_index + 1)
	if Read.food() == nil then
		Game.stop("No more food to cook")
	end
end

function Game.first_food()
	local level = Stats.level("Cooking") or 0
	for index, food in ipairs(CONFIG.foods) do
		if food.level <= level and Inventory.contains(food.raw) then
			Game.select_food(index)
			return
		end
	end
	Game.select_food(1)
	if Read.food() == nil then
		Game.stop("No ticked food that the Cooking level allows")
	end
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and state.position ~= nil then
			break
		end
		sleep(100)
	end
	Game.first_food()
	local me = Player.position()
	if me then
		S.site = Read.find_site(me, me.plane or 0, CONST.SITE.start_tiles)
	end
	if S.site then
		Log.log(NAME, `Cooking here: {S.site.cook_name} and {S.site.bank_name}`)
	else
		Log.log(NAME, "No permanent fire or range with a bank here, travelling to one")
	end

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

function Loop.watch_food()
	local raw_before, cooked_before = S.last_raw, S.last_cooked
	S.last_raw, S.last_cooked = snap.raw, snap.cooked
	if raw_before == nil or cooked_before == nil or snap.raw >= raw_before or Bankmain.is_open() then
		return
	end
	local used = raw_before - snap.raw
	local cooked = math.clamp(snap.cooked - cooked_before, 0, used)
	stats.cooked += cooked
	stats.burnt += used - cooked
	S.cook_progress_at = time()
	S.failures_in_row = 0
end

function Loop.report_counters()
	local key = `{stats.cooked}/{stats.burnt}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "cooked", label = "Cooked", value = stats.cooked },
		{ id = "burnt", label = "Burnt", value = stats.burnt, percent_of = "cooked" },
		{
			id = "profit",
			label = "Profit (gp)",
			value = stats.cooked * S.cooked_price - (stats.cooked + stats.burnt) * S.raw_price,
		},
		{ id = "trips", label = "Bank trips", value = stats.trips },
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
	elseif CONFIG.max_cooked > 0 and stats.cooked >= CONFIG.max_cooked then
		Game.stop(`Cooked {stats.cooked} food`)
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
	local food = Read.food() :: Food
	if Bankmain.inventory.contains_different({ food.raw }) then
		return "BANK"
	end
	if (Bankmain.inventory.count_empty() or 0) > 0 and (Bankmain.count_ex(food.raw) or 0) > 0 then
		return "BANK"
	end
	return if snap.raw > 0 then "RANGE" else "BANK"
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
	Loop.watch_food()
	Loop.report_counters()

	if ChatOptions.leveled_up() then
		return "LEVEL_UP"
	end
	local site = S.site
	if site == nil then
		return "TRAVEL"
	end
	local here = Read.at_site(site)
	Camera.face_enabled = not here
	if not here then
		return "WALK"
	end
	if Bankmain.is_open() then
		return Loop.bank_state()
	end
	if Make.is_open() then
		return "MAKE"
	end
	if snap.raw > 0 then
		return if Read.cooking() then "WAIT" else "RANGE"
	end
	return "BANK"
end

function Handler.hold_view(view: View)
	Antiban.zoom.max = math.max(Antiban.zoom.min, view.zoom)
	Antiban.pitch.min = math.min(Antiban.pitch.max, view.pitch)
end

function Handler.restore_view(view: View): boolean
	local spread = CONST.VIEW.spread_degrees
	local yaw = Camera.degrees_to_yaw(view.yaw + Random.mean(-spread, spread))
	Camera.set_angles(yaw, view.pitch)
	if (Camera.zoom() or view.zoom) > view.zoom then
		Camera.set_zoom(view.zoom)
	end
	return Read.site_in_view()
end

function Handler.find_view(site: Site): View?
	local pitch = Antiban.pitch.max
	for _, yaw in ipairs(Read.view_yaws(site)) do
		Camera.set_angles(Camera.degrees_to_yaw(yaw), pitch)
		local zoom = Camera.zoom()
		while zoom ~= nil do
			if Read.site_in_view() then
				return { yaw = yaw, pitch = pitch, zoom = zoom }
			end
			if zoom <= Camera.ZOOM_MIN then
				break
			end
			Camera.set_zoom(math.max(Camera.ZOOM_MIN, zoom - CONST.VIEW.zoom_step))
			local now = Camera.zoom()
			if now == nil or now >= zoom then
				break
			end
			zoom = now
		end
	end
	return nil
end

function Handler.keep_view()
	local site = S.site :: Site
	local cook = string.lower(site.cook_name)
	S.view_checked_at = time()
	if S.no_view or Read.site_in_view() then
		return
	end
	local view = S.view
	if view then
		Log.log(NAME, `Turning the camera back to the bank and the {cook}`)
		if Handler.restore_view(view) then
			return
		end
	end
	Log.log(NAME, `Looking for a camera angle that shows both the bank and the {cook}`)
	local found = Handler.find_view(site)
	if found == nil then
		S.no_view = true
		Log.log(NAME, `No camera angle shows both the bank and the {cook}, leaving the camera alone`)
		return
	end
	S.view = found
	Handler.hold_view(found)
end

function Handler.hover_deposit()
	local food = Read.food() :: Food
	local matcher = Item.matcher({ food.raw })
	for _, item in ipairs(Inventory.items() or {}) do
		if not Item.matches(matcher, item.id, item.name) then
			local w = Inventory.box(item.slot)
			if w then
				Mouse.move_async({ x1 = w.x, y1 = w.y, x2 = w.x + w.width - 1, y2 = w.y + w.height - 1 })
			end
			return
		end
	end
end

function Handler.click_bank(bank: Bankmain.Source): boolean
	if not Read.bank_in_view(bank) or not Read.bank_plain(bank) or not Toplevel.escape_clear() then
		return false
	end
	local clicked = if bank.npc
		then Npcs.interact(bank.npc, CONST.BANK_ACTIONS, false)
		else Objects.interact(bank.loc :: Loc, CONST.BANK_ACTIONS, false)
	if not clicked then
		return false
	end
	Handler.hover_deposit()
	return Bankmain.wait_open(CONST.WALK_IN_MS)
end

function Handler.approach_bank(bank: Bankmain.Source): boolean
	local opts: Clickbox.Approach = { arrive_ms = false }
	local picked = if bank.npc
		then Npcs.approach(bank.npc, CONST.BANK_ACTIONS, opts)
		else Objects.approach(bank.loc :: Loc, CONST.BANK_ACTIONS, opts)
	if not picked then
		return false
	end
	Handler.hover_deposit()
	return Bankmain.wait_open(CONST.WALK_IN_MS)
end

function Handler.open_bank(): boolean
	Handler.keep_view()
	local bank = Read.bank()
	if bank == nil then
		Game.fail("The bank isn't in the scene")
		return false
	end
	if not Handler.click_bank(bank) and not Handler.approach_bank(bank) then
		Game.fail("Couldn't open the bank")
		return false
	end
	stats.trips += 1
	S.cooking = false
	return true
end

function Handler.deposit(keep: { string | number }): boolean
	local unwanted = Read.unwanted(keep)
	if #unwanted == 0 then
		return true
	end
	if not Bankmain.inventory.contains_any(keep) and Biometrics.random_boolean(CONST.DEPOSIT_BUTTON_CHANCE) then
		return Bankmain.deposit_inventory()
	end
	for _, id in ipairs(unwanted) do
		if not Bankmain.inventory.interact(id, "Deposit-All") then
			return false
		end
	end
	return true
end

function Handler.wear_gauntlets(): boolean
	if Wornitems.is_wearing(CONST.GAUNTLETS) then
		return true
	end
	if not Bankmain.inventory.contains(CONST.GAUNTLETS) then
		if (Bankmain.count_ex(CONST.GAUNTLETS) or 0) == 0 then
			return true
		end
		local room = Widgets.wait_for(function(): boolean
			return (Bankmain.inventory.count_empty() or 0) > 0
		end, CONST.BANK_CONFIRM_MS, 50)
		if not room then
			return true
		end
		if not Bankmain.withdraw(CONST.GAUNTLETS, 1, false) then
			return false
		end
	end
	if not Bankmain.inventory.interact(CONST.GAUNTLETS, "Wear") then
		return false
	end
	return Widgets.wait_for(function(): boolean
		return Wornitems.is_wearing(CONST.GAUNTLETS)
	end, CONST.BANK_CONFIRM_MS, 50)
end

function Handler.queue_raw(food: Food): boolean?
	local room = (Bankmain.inventory.count_empty() or 0) > 0 or #Read.unwanted({ food.raw }) > 0
	if not room or (Bankmain.count_ex(food.raw) or 0) == 0 then
		return false
	end
	if not Bankmain.set_quantity(0) or not Bankmain.withdraw_selected(food.raw, false) then
		return nil
	end
	return true
end

function Handler.hover_cook(): Loc?
	local loc = Read.cook_loc()
	if loc == nil or not Read.in_view(loc) then
		return nil
	end
	Objects.hover_async(loc)
	return loc
end

function Handler.bank()
	if not Bankmain.is_open() then
		Handler.open_bank()
		return
	end
	S.bank_stand = { x = snap.me.x, y = snap.me.y }
	local food = Read.food() :: Food
	if snap.raw == 0 and (Bankmain.count_ex(food.raw) or 0) == 0 then
		Game.next_food(`Out of {food.raw}`)
		return
	end
	local keep: { string | number } = { food.raw }
	local raw_before = Bankmain.inventory.count_ex(food.raw) or 0
	if not Handler.deposit(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if not Handler.wear_gauntlets() then
		Game.fail("Couldn't put the cooking gauntlets on")
		return
	end
	local withdrew = Handler.queue_raw(food)
	if withdrew == nil then
		Game.fail(`Couldn't withdraw {food.raw}`)
		return
	end
	local cook = Handler.hover_cook()
	local banked = Widgets.wait_for(function(): boolean
		return not Bankmain.inventory.contains_different(keep)
			and (not withdrew or (Bankmain.inventory.count_ex(food.raw) or 0) > raw_before)
	end, CONST.BANK_CONFIRM_MS, 50)
	if not banked then
		Game.fail("The bank didn't swap the items")
		return
	end
	Handler.leave_bank(cook)
end

function Handler.cook_started(): boolean
	local started = Widgets.wait_for(function(): boolean
		return Make.is_open() or Player.is_animating()
	end, CONST.WALK_IN_MS, 50)
	if started and not Make.is_open() then
		S.cooking, S.cook_progress_at = true, time()
	end
	return started
end

function Handler.click_cook(loc: Loc): boolean
	return Objects.interact(loc, CONST.COOK_ACTION, false) and Handler.cook_started()
end

function Handler.approach_cook(loc: Loc): boolean
	return Objects.approach(loc, CONST.COOK_ACTION, { arrive_ms = false }) and Handler.cook_started()
end

function Handler.leave_bank(cook: Loc?)
	if cook and Objects.plain_walk(cook) and Handler.click_cook(cook) then
		return
	end
	if not Bankmain.close(1) then
		Game.fail("Couldn't close the bank")
		return
	end
	local loc = Read.cook_loc()
	if loc then
		Handler.approach_cook(loc)
	end
end

function Handler.range()
	if Bankmain.is_open() then
		Handler.leave_bank(Handler.hover_cook())
		return
	end
	Handler.keep_view()
	local loc = Read.cook_loc()
	if loc == nil then
		Game.fail(`The {(S.site :: Site).cook_name} isn't in the scene`)
		return
	end
	if not Handler.approach_cook(loc) then
		Game.fail(`Couldn't use the {loc.name or "range"}`)
	end
end

function Handler.make()
	S.cook_stand = { x = snap.me.x, y = snap.me.y }
	local food = Read.food() :: Food
	if not Make.wait_open() then
		Game.fail("The cooking menu didn't finish opening")
		return
	end
	if Make.make(food.raw, "All") then
		S.cooking, S.cook_progress_at = true, time()
		S.failures_in_row = 0
		Make.wait_closed()
		return
	end
	S.cooking = false
	if Read.menu_lacks(food.raw) then
		Toplevel.escape_clear()
		Game.next_food(`The cooking menu doesn't offer {food.raw}`)
		return
	end
	Game.fail(`Couldn't cook {food.raw}`)
end

function Handler.hover_bank()
	if snap.raw > 2 or Mouse.busy() then
		return
	end
	local bank = Read.bank()
	if bank == nil or Read.bank_hovered(bank) or not Read.bank_in_view(bank) then
		return
	end
	if bank.npc then
		Npcs.hover_async(bank.npc)
	else
		Objects.hover_async(bank.loc :: Loc)
	end
end

function Handler.wait()
	if CONFIG.antiban and S.antiban_ready then
		if not Antiban.do_async_tasks("game") then
			Antiban.do_async_tasks("outside")
		end
		Antiban.do_antiban()
	end
	if time() - S.view_checked_at >= CONST.VIEW.check_ms then
		Handler.keep_view()
	end
	Handler.hover_bank()
	sleep(Random.int(200, 400))
end

function Handler.walk()
	local site = S.site :: Site
	Log.log(NAME, `Walking to the bank at {site.bank.x}, {site.bank.y}`)
	local ok = Walker.walk({ x = site.bank.x, y = site.bank.y }, { near = 4, plane = site.plane, transports = false })
	if not ok then
		Game.fail("Couldn't walk to the bank")
	end
end

function Handler.withdraw_runes(): boolean
	for _, rune in ipairs(CONST.RUNES) do
		local missing = rune.amount - (Bankmain.inventory.count_ex(rune.item) or 0)
		local banked = Bankmain.count_ex(rune.item) or 0
		if missing > 0 and banked >= missing and not Bankmain.withdraw(rune.item, missing, false) then
			Game.fail(`Couldn't withdraw the runes for {CONST.SPELL}`)
			return false
		end
	end
	return true
end

function Handler.cast_ready(): boolean
	if not Magic.is_open() and not Magic.open() then
		Game.fail("Couldn't open the spellbook")
		return false
	end
	if Widgets.wait_for(Read.can_cast, CONST.CAST_READY_MS, 100) then
		return true
	end
	Game.stop(`Can't cast {CONST.SPELL}: it needs 48 Magic, Client of Kourend, its runes and the standard spellbook`)
	return false
end

function Handler.prepare_travel(): Travel?
	if Read.wearing_necklace() or Bankmain.inventory.contains_any(CONST.NECKLACES) then
		return "necklace"
	end
	if Bankmain.contains_any(CONST.NECKLACES) then
		if Bankmain.withdraw(CONST.NECKLACES, 1, false) then
			return "necklace"
		end
		Game.fail("Couldn't withdraw a games necklace")
		return nil
	end
	if Diaries.tier("kourend", "easy") and (Read.runes_available() or Read.can_cast()) then
		return if Handler.withdraw_runes() then "spell" else nil
	end
	Game.stop(
		`No games necklace for {CONST.DEN.name}, and no {CONST.SPELL} with the Kourend & Kebos easy diary for {CONST.KITCHEN.name}`
	)
	return nil
end

function Handler.teleport(how: Travel): boolean
	if how == "necklace" then
		Log.log(NAME, "Teleporting to Burthorpe")
		return (Transports.teleport_item(CONST.NECKLACE_ROW))
	end
	Log.log(NAME, "Teleporting to Kourend Castle")
	return Handler.cast_ready() and (Transports.teleport_spell(CONST.SPELL))
end

function Handler.walk_to(dest: Destination): boolean
	Log.log(NAME, `Walking to {dest.name}`)
	local ok, walked = pcall(function(): boolean
		return Walker.walk(dest.walk_to, {
			near = 3,
			plane = dest.plane,
			transports = { exclude = CONST.TRAVEL_EXCLUDE },
		})
	end)
	return ok and walked == true
end

function Handler.fetch_travel(): Travel?
	if not Bankmain.is_open() then
		if not Bankmain.open() then
			Game.fail("Couldn't open the nearest bank")
		end
		return nil
	end
	local keep = Read.travel_keep()
	if Bankmain.inventory.contains_different(keep) and not Bankmain.deposit_different(keep) then
		Game.fail("Couldn't deposit the inventory")
		return nil
	end
	return Handler.prepare_travel()
end

function Handler.travel()
	local nearby = Read.nearby_destination()
	local how: Travel? = nil
	if nearby == nil then
		how = if Bankmain.is_open() then nil else Read.held_travel()
		how = how or Handler.fetch_travel()
		if how == nil then
			return
		end
	end
	if Bankmain.is_open() and not Bankmain.close() then
		Game.fail("Couldn't close the bank")
		return
	end
	if how ~= nil and not Handler.teleport(how :: Travel) then
		Game.fail("The teleport didn't work")
		return
	end
	local dest = nearby or (if how == "necklace" then CONST.DEN else CONST.KITCHEN)
	Handler.arrive(dest)
end

function Handler.arrive(dest: Destination)
	if not Handler.walk_to(dest) then
		Game.fail(`Couldn't walk to {dest.name}`)
		return
	end
	local me = Player.position()
	if me == nil then
		return
	end
	S.site = Read.find_site(me, me.plane or 0, CONST.SITE.landing_tiles)
	S.cook_stand, S.bank_stand, S.view, S.no_view = nil, nil, nil, false
	if S.site == nil then
		Game.stop(`No fire or range with a bank near {me.x}, {me.y}`)
		return
	end
	S.failures_in_row = 0
	Log.log(NAME, `Cooking on the {S.site.cook_name} at {S.site.cook.x}, {S.site.cook.y}`)
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	LEVEL_UP = function()
		S.cooking = false
		ChatOptions.handle_level_up()
	end,
	TRAVEL = Handler.travel,
	WALK = Handler.walk,
	BANK = Handler.bank,
	RANGE = Handler.range,
	MAKE = Handler.make,
	WAIT = Handler.wait,
}

function Game.apply_settings(values: { [string]: any })
	local picked = (values.foods or {}) :: { [string]: boolean }
	CONFIG.foods = {}
	for _, food in ipairs(FOODS) do
		if picked[food.id] then
			table.insert(CONFIG.foods, food)
		end
	end
	CONFIG.max_cooked = values.max_cooked or 0
end

function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	Game.apply_settings(values)
	Game.first_food()
end

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

local KEEPS_INVENTORY: { [State]: boolean } = { WALK = true, BANK = true, RANGE = true, WAIT = true }

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

function Loop.run()
	Game.apply_settings(Host.settings())
	if #CONFIG.foods == 0 then
		Log.log(NAME, "No food ticked")
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
		Game.poll_settings()
		close_stray()
		Loop.keep_inventory(state)
		Handler.states[state]()
		sleep(Random.int(60, 140))
	end
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

Loop.run()
