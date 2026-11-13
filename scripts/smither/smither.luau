--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Loc = Host.Loc
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Anvil = require("@lib/main/interfaces/mainscreen/anvil")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local BankpinKeypad = require("@lib/main/interfaces/mainscreen/bankpin_keypad")
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Item = require("@lib/utils/item")
local ItemData = require("@lib/utils/item_data")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Mouse = require("@lib/utils/input/mouse")
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

local NAME = "Smither"

local METALS = { "Bronze", "Iron", "Steel", "Mithril", "Adamantite", "Runite" }
local ITEMS = {
	"Dagger",
	"Axe",
	"Mace",
	"Med helm",
	"Bolts (unf)",
	"Sword",
	"Dart tip",
	"Wire",
	"Nails",
	"Scimitar",
	"Spear",
	"Hasta",
	"Arrowtips",
	"Limbs",
	"Longsword",
	"Javelin heads",
	"Full helm",
	"Knife",
	"Sq shield",
	"Warhammer",
	"Battleaxe",
	"Chainbody",
	"Kiteshield",
	"Claws",
	"Platelegs",
	"Plateskirt",
	"2h sword",
	"Platebody",
}

local CONST = {
	REPORT = { counters_key = "" },
	HAMMERS = { "Hammer", "Imcando hammer", "Imcando hammer (off-hand)" },
	BANK_NAMES = { "Bank booth", "Bank chest" },
	BANK_ACTIONS = { "Bank", "Use" },
	SITE = { start_tiles = 25, landing_tiles = 45, pair_tiles = 20, near_tiles = 25 },
	SMITH_IDLE_MS = 4200,
	CAST_READY_MS = 1200,
	BANK_CONFIRM_MS = 2400,
	WALK_IN_MS = 9000,
	VIEW = { check_ms = 1500, spread_degrees = 8, zoom_step = 40 },
	CRYSTAL = { item = 23946, row = "Eternal teleport crystal: Prifddinas" },
	TABLET = { item = 8007, row = "Varrock tablet" },
	SPELL = "Varrock Teleport",
	RUNES = {
		{ item = 563, amount = 1 },
		{ item = 554, amount = 1 },
		{ item = 556, amount = 3 },
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	metal = METALS[1],
	item_type = ITEMS[1],
	max_items = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local stats = { made = 0, bars = 0, trips = 0, failures = 0 }

type Site = { anvil: Host.Tile, bank: Host.Tile, plane: number }

type View = { yaw: number, pitch: number, zoom: number }

type Teleport = "crystal" | "tablet" | "spell"

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	site: Site?,
	bar: string,
	item: string,
	bars_per: number,
	makes: number,
	smithing: boolean,
	smith_progress_at: number,
	last_bars: number?,
	item_price: number,
	bar_price: number,
	no_crystal: boolean,
	anvil_stand: Host.Tile?,
	bank_stand: Host.Tile?,
	view_checked_at: number,
	view: View?,
	no_view: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	site = nil,
	bar = "",
	item = "",
	bars_per = 1,
	makes = 1,
	smithing = false,
	smith_progress_at = 0,
	last_bars = nil,
	item_price = 0,
	bar_price = 0,
	no_crystal = false,
	anvil_stand = nil,
	bank_stand = nil,
	view_checked_at = 0,
	view = nil,
	no_view = false,
}

type Snapshot = {
	state: ClientState,
	me: Host.PositionData,
	bars: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "LEVEL_UP" | "TRAVEL" | "WALK" | "BANK" | "ANVIL" | "SMITH" | "WAIT"

local report = StatsReport.new()

function Read.item_name(metal: string, item_type: string): string
	local kind = string.lower(item_type)
	if kind == "bolts (unf)" then
		return if metal == "Adamantite" then "Adamant bolts(unf)" else `{metal} {kind}`
	elseif kind == "limbs" then
		return `{metal} {kind}`
	elseif kind == "nails" then
		return if metal == "Runite" then "Rune nails" else `{metal} {kind}`
	elseif metal == "Runite" then
		return `Rune {kind}`
	elseif metal == "Adamantite" then
		return `Adamant {kind}`
	end
	return `{metal} {kind}`
end

function Read.bars_per(item_type: string): number
	local kind = string.lower(item_type)
	if kind == "platebody" then
		return 5
	elseif
		table.find({ "warhammer", "battleaxe", "chainbody", "kiteshield", "2h sword", "platelegs", "plateskirt" }, kind)
	then
		return 3
	elseif table.find({ "scimitar", "longsword", "full helm", "sq shield", "claws" }, kind) then
		return 2
	end
	return 1
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	local me = state.position
	if me == nil then
		return false
	end
	local bars = Inventory.count_ex(S.bar)
	if bars == nil then
		return false
	end
	snap = { state = state, me = me, bars = bars }
	return true
end

function Read.gap(a: Host.Tile, b: Host.Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function Read.closest(locs: { Host.CacheLoc }, from: Host.Tile): Host.CacheLoc?
	local best: Host.CacheLoc? = nil
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

function Read.offers(view: Host.LocView, names: { string }, actions: { string }): boolean
	local name = string.lower(view.name)
	local named = false
	for _, wanted in ipairs(names) do
		named = named or string.find(name, string.lower(wanted), 1, true) ~= nil
	end
	if not named then
		return false
	end
	for _, action in ipairs(view.actions) do
		if table.find(actions, action) then
			return true
		end
	end
	return false
end

function Read.shown_locs(area: Host.Corners, plane: number, names: { string }, actions: { string }): { Host.CacheLoc }
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
	local found: { Host.CacheLoc } = {}
	if views == nil then
		return found
	end
	for _, loc in ipairs(placed) do
		local view = views[index[loc.id]]
		if view and Read.offers(view, names, actions) then
			table.insert(found, loc)
		end
	end
	return found
end

function Read.find_site(center: Host.Tile, plane: number, reach: number): Site?
	local anvils = Read.shown_locs(Read.area(center, reach), plane, { Anvil.OBJECT }, { Anvil.OPTION })
	local banks =
		Read.shown_locs(Read.area(center, reach + CONST.SITE.pair_tiles), plane, CONST.BANK_NAMES, CONST.BANK_ACTIONS)
	local best: Site? = nil
	local best_gap = math.huge
	for _, anvil in ipairs(anvils) do
		local bank = Read.closest(banks, anvil)
		local d = Read.gap(anvil, center)
		if bank ~= nil and Read.gap(bank, anvil) <= CONST.SITE.pair_tiles and d < best_gap then
			best = { anvil = { x = anvil.x, y = anvil.y }, bank = { x = bank.x, y = bank.y }, plane = plane }
			best_gap = d
		end
	end
	return best
end

function Read.scene_loc(tile: Host.Tile, names: { string }): Loc?
	local locs: { Loc } = Objects.find() or {}
	for _, loc in ipairs(locs) do
		local name = if loc.name then string.lower(loc.name) else nil
		if name ~= nil and Objects.distance(loc, tile) == 0 then
			for _, wanted in ipairs(names) do
				if string.find(name, string.lower(wanted), 1, true) then
					return loc
				end
			end
		end
	end
	return nil
end

function Read.at_site(site: Site): boolean
	return (snap.me.plane or 0) == site.plane and Read.gap(snap.me, site.anvil) <= CONST.SITE.near_tiles
end

function Read.shown_from(tile: Host.Tile, names: { string }, from: Host.Tile?): boolean
	local loc = Read.scene_loc(tile, names)
	if loc == nil or from == nil then
		return true
	end
	local box = Objects.projected(loc, from)
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

function Read.site_in_view(site: Site): boolean
	return Read.shown_from(site.bank, CONST.BANK_NAMES, S.anvil_stand)
		and Read.shown_from(site.anvil, { Anvil.OBJECT }, S.bank_stand)
end

function Read.view_yaws(site: Site): { number }
	local bearing = math.deg(math.atan2(site.bank.x - site.anvil.x, site.bank.y - site.anvil.y))
	local facing = Camera.yaw_degrees() or bearing
	local yaws = { bearing, bearing + 90, bearing + 180, bearing - 90 }
	table.sort(yaws, function(a: number, b: number): boolean
		return Read.off_by(facing, a) < Read.off_by(facing, b)
	end)
	return yaws
end

function Read.off_by(a: number, b: number): number
	return math.abs((a - b + 180) % 360 - 180)
end

function Read.in_view(loc: Loc): boolean
	local box = Objects.clickbox(loc)
	return box ~= nil and Clickbox.target(box, loc.name or "object") ~= nil
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

function Read.has_hammer(): boolean
	if Inventory.contains_any(CONST.HAMMERS) then
		return true
	end
	for _, hammer in ipairs(CONST.HAMMERS) do
		if Wornitems.is_wearing(hammer) then
			return true
		end
	end
	return false
end

function Read.keep(): { string | number }
	local keep: { string | number } = { S.bar }
	for _, hammer in ipairs(CONST.HAMMERS) do
		table.insert(keep, hammer)
	end
	return keep
end

function Read.travel_keep(): { string | number }
	local keep: { string | number } = { CONST.CRYSTAL.item, CONST.TABLET.item }
	for _, hammer in ipairs(CONST.HAMMERS) do
		table.insert(keep, hammer)
	end
	for _, rune in ipairs(CONST.RUNES) do
		table.insert(keep, rune.item)
	end
	return keep
end

function Read.held_or_banked(item: number): boolean
	return Bankmain.inventory.contains(item) or (Bankmain.count_ex(item) or 0) > 0
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

function Read.smithing(): boolean
	if not S.smithing then
		return false
	end
	if Player.is_animating() then
		S.smith_progress_at = time()
	end
	return time() - S.smith_progress_at < CONST.SMITH_IDLE_MS
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

	AntibanTasks.skills = { "Smithing", "Total" }
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
	local prices = ItemData.prices({ S.item, S.bar })
	S.item_price = if prices then prices[1] or 0 else 0
	S.bar_price = if prices then prices[2] or 0 else 0
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	S.site = Read.find_site(snap.me, snap.me.plane or 0, CONST.SITE.start_tiles)
	if S.site then
		Log.log(NAME, "There is an anvil and a bank here, smithing here")
	else
		Log.log(NAME, "No anvil and bank here, teleporting to one")
	end
	Game.load_prices()

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

function Loop.watch_bars()
	local before = S.last_bars
	S.last_bars = snap.bars
	if before == nil or snap.bars >= before or Bankmain.is_open() then
		return
	end
	local used = before - snap.bars
	stats.bars += used
	stats.made += math.floor(used / S.bars_per) * S.makes
	S.smith_progress_at = time()
	S.failures_in_row = 0
end

function Loop.report_counters()
	local key = `{stats.made}/{stats.bars}/{stats.trips}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "made", label = "Items made", value = stats.made },
		{ id = "bars", label = "Bars used", value = stats.bars },
		{ id = "profit", label = "Profit (gp)", value = stats.made * S.item_price - stats.bars * S.bar_price },
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
	elseif CONFIG.max_items > 0 and stats.made >= CONFIG.max_items then
		Game.stop(`Made {stats.made} {S.item}`)
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
	if Bankmain.inventory.contains_different(Read.keep()) or not Read.has_hammer() then
		return "BANK"
	end
	if (Bankmain.inventory.count_empty() or 0) > 0 and (Bankmain.count_ex(S.bar) or 0) > 0 then
		return "BANK"
	end
	return if snap.bars >= S.bars_per then "ANVIL" else "BANK"
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
	Loop.watch_bars()
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
	if Anvil.is_open() then
		return "SMITH"
	end
	if snap.bars >= S.bars_per then
		return if Read.smithing() then "WAIT" else "ANVIL"
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
	return Read.site_in_view(S.site :: Site)
end

function Handler.find_view(site: Site): View?
	local pitch = Antiban.pitch.max
	for _, yaw in ipairs(Read.view_yaws(site)) do
		Camera.set_angles(Camera.degrees_to_yaw(yaw), pitch)
		local zoom = Camera.zoom()
		while zoom ~= nil do
			if Read.site_in_view(site) then
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
	S.view_checked_at = time()
	if S.no_view or Read.site_in_view(site) then
		return
	end
	local view = S.view
	if view then
		Log.log(NAME, "Turning the camera back to the bank and the anvil")
		if Handler.restore_view(view) then
			return
		end
	end
	Log.log(NAME, "Looking for a camera angle that shows both the bank and the anvil")
	local found = Handler.find_view(site)
	if found == nil then
		S.no_view = true
		Log.log(NAME, "No camera angle shows both the bank and the anvil, leaving the camera alone")
		return
	end
	S.view = found
	Handler.hold_view(found)
end

function Handler.hover_deposit()
	local matcher = Item.matcher(Read.keep())
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

function Handler.click_bank(loc: Loc): boolean
	if not Read.in_view(loc) or not Toplevel.escape_clear() then
		return false
	end
	if not Objects.interact(loc, CONST.BANK_ACTIONS, false) then
		return false
	end
	Handler.hover_deposit()
	return Bankmain.wait_open(CONST.WALK_IN_MS)
end

function Handler.open_bank(): boolean
	local site = S.site :: Site
	Handler.keep_view()
	local loc = Read.scene_loc(site.bank, CONST.BANK_NAMES)
	if loc == nil then
		Game.fail("The bank booth isn't in the scene")
		return false
	end
	if not Handler.click_bank(loc) and not Bankmain.open({ loc = loc }) then
		Game.fail("Couldn't open the bank")
		return false
	end
	stats.trips += 1
	S.smithing = false
	return true
end

function Handler.get_hammer(): boolean
	if Read.has_hammer() then
		return true
	end
	if not Bankmain.contains_any(CONST.HAMMERS) then
		Game.stop("No hammer in the inventory or the bank")
		return false
	end
	if not Bankmain.withdraw(CONST.HAMMERS, 1, false) then
		Game.fail("Couldn't withdraw a hammer")
		return false
	end
	return true
end

function Handler.queue_deposit(keep: { string | number }): boolean
	for _, id in ipairs(Read.unwanted(keep)) do
		if not Bankmain.inventory.interact(id, "Deposit-All") then
			return false
		end
	end
	return true
end

function Handler.queue_bars(): boolean?
	local room = (Bankmain.inventory.count_empty() or 0) > 0 or #Read.unwanted(Read.keep()) > 0
	if not room then
		return false
	end
	if (Bankmain.count_ex(S.bar) or 0) == 0 then
		if snap.bars < S.bars_per then
			Game.stop(`Out of {S.bar}`)
		end
		return false
	end
	if not Bankmain.set_quantity(0) or not Bankmain.withdraw_selected(S.bar, false) then
		return nil
	end
	return true
end

function Handler.hover_anvil(): Loc?
	local site = S.site :: Site
	local anvil = Read.scene_loc(site.anvil, { Anvil.OBJECT })
	if anvil == nil or not Read.in_view(anvil) then
		return nil
	end
	Objects.hover_async(anvil)
	return anvil
end

function Handler.bank()
	if not Bankmain.is_open() then
		Handler.open_bank()
		return
	end
	S.bank_stand = { x = snap.me.x, y = snap.me.y }
	local keep = Read.keep()
	local bars_before = Bankmain.inventory.count_ex(S.bar) or 0
	if not Handler.queue_deposit(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if not Handler.get_hammer() then
		return
	end
	local withdrew = Handler.queue_bars()
	if withdrew == nil then
		Game.fail(`Couldn't withdraw {S.bar}`)
		return
	end
	if S.finished then
		return
	end
	local anvil = Handler.hover_anvil()
	local banked = Widgets.wait_for(function(): boolean
		return not Bankmain.inventory.contains_different(keep)
			and (not withdrew or (Bankmain.inventory.count_ex(S.bar) or 0) > bars_before)
	end, CONST.BANK_CONFIRM_MS, 50)
	if not banked then
		Game.fail("The bank didn't swap the items")
		return
	end
	Handler.leave_bank(anvil)
end

function Handler.leave_bank(anvil: Loc?)
	if anvil and Objects.interact(anvil, Anvil.OPTION, false) then
		Anvil.wait_open(CONST.WALK_IN_MS)
		return
	end
	if not Bankmain.close(1) then
		Game.fail("Couldn't close the bank")
		return
	end
	local site = S.site :: Site
	local loc = Read.scene_loc(site.anvil, { Anvil.OBJECT })
	if loc and Read.in_view(loc) and Objects.interact(loc, Anvil.OPTION, false) then
		Anvil.wait_open(CONST.WALK_IN_MS)
	end
end

function Handler.open_anvil()
	if Bankmain.is_open() then
		Handler.leave_bank(Handler.hover_anvil())
		return
	end
	local site = S.site :: Site
	Handler.keep_view()
	local loc = Read.scene_loc(site.anvil, { Anvil.OBJECT })
	if loc == nil then
		Game.fail("The anvil isn't in the scene")
		return
	end
	local ok, why = Anvil.open(loc)
	if not ok then
		Game.fail(`Couldn't open the anvil: {why or "unknown"}`)
	end
end

function Handler.start_smithing(slot: Anvil.Slot): boolean
	if slot.highlighted and Anvil.smith(S.item, "All", 1) then
		return true
	end
	return Anvil.is_open() and Anvil.smith(S.item, "All", 0)
end

function Handler.smith()
	S.anvil_stand = { x = snap.me.x, y = snap.me.y }
	local slot = Anvil.find(S.item)
	if slot == nil then
		Game.stop(`The anvil doesn't offer {S.item}`)
		return
	end
	if not slot.available then
		Game.stop(`Smithing level too low for {S.item}`)
		return
	end
	S.bars_per, S.makes = slot.bars, slot.makes
	if not slot.enough_bars then
		Anvil.close()
		return
	end
	if Handler.start_smithing(slot) then
		S.smithing, S.smith_progress_at = true, time()
		S.failures_in_row = 0
		return
	end
	S.smithing = false
	Game.fail(`Couldn't smith {S.item}`)
end

function Handler.hover_bank()
	if snap.bars >= 2 * S.bars_per or Mouse.busy() then
		return
	end
	local site = S.site :: Site
	local loc = Read.scene_loc(site.bank, CONST.BANK_NAMES)
	if loc == nil or Objects.hovered(loc) or not Read.in_view(loc) then
		return
	end
	Objects.hover_async(loc)
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

function Handler.withdraw_one(item: number): boolean
	if Bankmain.inventory.contains(item) then
		return true
	end
	return Bankmain.withdraw(item, 1, false)
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
	Game.stop(`Can't cast {CONST.SPELL}: it needs 25 Magic, its runes and the standard spellbook`)
	return false
end

function Handler.prepare_teleport(): Teleport?
	if not S.no_crystal and Read.held_or_banked(CONST.CRYSTAL.item) then
		if Handler.withdraw_one(CONST.CRYSTAL.item) then
			return "crystal"
		end
		Game.fail("Couldn't withdraw the Eternal teleport crystal")
		return nil
	end
	if Read.held_or_banked(CONST.TABLET.item) then
		if Handler.withdraw_one(CONST.TABLET.item) then
			return "tablet"
		end
		Game.fail("Couldn't withdraw a Varrock teleport")
		return nil
	end
	if Read.runes_available() or Read.can_cast() then
		return if Handler.withdraw_runes() then "spell" else nil
	end
	Game.stop(`No Eternal teleport crystal, Varrock teleport or runes for {CONST.SPELL} in the bank`)
	return nil
end

function Handler.teleport(how: Teleport): boolean
	if how == "crystal" then
		Log.log(NAME, "Teleporting to Prifddinas")
		local ok = Transports.teleport_item(CONST.CRYSTAL.row)
		if not ok then
			S.no_crystal = true
			Log.log(NAME, "The crystal didn't take us to Prifddinas, Varrock it is")
		end
		return ok
	end
	Log.log(NAME, "Teleporting to Varrock")
	if how == "tablet" then
		return (Transports.teleport_item(CONST.TABLET.row))
	end
	return Handler.cast_ready() and (Transports.teleport_spell(CONST.SPELL))
end

function Handler.travel()
	if not Bankmain.is_open() then
		if not Bankmain.open() then
			Game.fail("Couldn't open the nearest bank")
		end
		return
	end
	local keep = Read.travel_keep()
	if Bankmain.inventory.contains_different(keep) and not Bankmain.deposit_different(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	if not Handler.get_hammer() then
		return
	end
	local how = Handler.prepare_teleport()
	if how == nil then
		return
	end
	if not Bankmain.close() then
		Game.fail("Couldn't close the bank")
		return
	end
	if not Handler.teleport(how) then
		Game.fail("The teleport didn't work")
		return
	end
	local me = Player.position()
	if me == nil then
		return
	end
	S.site = Read.find_site(me, me.plane or 0, CONST.SITE.landing_tiles)
	S.anvil_stand, S.bank_stand, S.view, S.no_view = nil, nil, nil, false
	if S.site == nil then
		Game.stop(`No anvil with a bank near {me.x}, {me.y}`)
		return
	end
	S.failures_in_row = 0
	Log.log(NAME, `Smithing at the anvil at {S.site.anvil.x}, {S.site.anvil.y}`)
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
	TRAVEL = Handler.travel,
	WALK = Handler.walk,
	BANK = Handler.bank,
	ANVIL = Handler.open_anvil,
	SMITH = Handler.smith,
	WAIT = Handler.wait,
}

function Game.apply_settings(values: { [string]: any })
	CONFIG.metal = values.metal
	CONFIG.item_type = values.item_type
	CONFIG.max_items = values.max_items
	S.bar = `{CONFIG.metal} bar`
	S.item = Read.item_name(CONFIG.metal, CONFIG.item_type)
	S.bars_per = Read.bars_per(CONFIG.item_type)
	S.makes = 1
	S.smithing = false
	S.last_bars = nil
end

function Game.ask(): boolean
	local values = Host.form({
		title = NAME,
		submit = "Start",
		fields = {
			{
				kind = "label",
				text = "Start anywhere: it teleports to Prifddinas with an Eternal teleport crystal from the bank, or to Varrock with a Varrock teleport or its runes.",
			},
			{ id = "metal", kind = "choice", label = "Bar", options = METALS, default = CONFIG.metal },
			{ id = "item_type", kind = "choice", label = "Item", options = ITEMS, default = CONFIG.item_type },
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

function Game.poll_settings()
	local values = Host.form_update()
	if values == nil then
		return
	end
	Game.apply_settings(values)
	Game.load_prices()
	Log.log(NAME, `Now smithing {S.item} from {S.bar}`)
end

local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	if Bankmain.is_open() or Anvil.is_open() or BankpinKeypad.is_open() then
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
	Log.log(NAME, `{NAME} started: {S.item} from {S.bar}`)
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
		Handler.states[state]()
		sleep(Random.int(60, 140))
	end
	StatsReport.flush(report)
	Log.log(NAME, "Done")
end

Loop.run()
