--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
type Tile = Host.Tile
type Loc = Host.Loc
type GroundItem = Host.GroundItem
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local Biometrics = require("@volcren/biometrics")
local Chat = require("@volcren/chat")
local Events = require("./events")
local GameState = require("@volcren/game_state")
local GroundItems = require("@volcren/ground_items")
local Handoff = require("@volcren/handoff")
local Inv = require("@volcren/inv")
local Inventory = require("@volcren/inventory")
local Locations = require("./locations")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Make = require("@volcren/make")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local SpecialAttack = require("@volcren/special_attack")
local Stats = require("@volcren/stats")
local StatsReport = require("@volcren/stats_report")
local Toplevel = require("@volcren/toplevel")
local Walker = require("@volcren/walker")
local Wornitems = require("@volcren/wornitems")

local NAME = "Forestry"

type Fletchable = { menu: string, item: string, level: number }

type Mode =
	"Bank"
	| "Drop"
	| "Forester's Campfire"
	| "Tinderbox"
	| "Fletch and drop"
	| "Fletch and bank"
	| "Fletch arrow shafts"

local CONST = {
	REPORT = { counters_key = "" },
	KITS = { "Forestry kit", "Forestry basket", "Open forestry basket" },
	TINDERBOX = "Tinderbox",
	KNIVES = { "Fletching knife", "Knife" } :: { number | string },
	FLETCH_MS = 3000,
	FLETCH = {
		["Logs"] = {
			{ menu = "Longbow", item = "Longbow (u)", level = 10 },
			{ menu = "Shortbow", item = "Shortbow (u)", level = 5 },
		},
		["Oak logs"] = {
			{ menu = "Oak longbow", item = "Oak longbow (u)", level = 25 },
			{ menu = "Oak shortbow", item = "Oak shortbow (u)", level = 20 },
		},
		["Willow logs"] = {
			{ menu = "Willow longbow", item = "Willow longbow (u)", level = 40 },
			{ menu = "Willow shortbow", item = "Willow shortbow (u)", level = 35 },
		},
		["Maple logs"] = {
			{ menu = "Maple longbow", item = "Maple longbow (u)", level = 55 },
			{ menu = "Maple shortbow", item = "Maple shortbow (u)", level = 50 },
		},
		["Mahogany logs"] = {
			{ menu = "Crossbow stock", item = "Mahogany stock", level = 61 },
		},
		["Yew logs"] = {
			{ menu = "Yew longbow", item = "Yew longbow (u)", level = 70 },
			{ menu = "Yew shortbow", item = "Yew shortbow (u)", level = 65 },
		},
		["Magic logs"] = {
			{ menu = "Magic longbow", item = "Magic longbow (u)", level = 85 },
			{ menu = "Magic shortbow", item = "Magic shortbow (u)", level = 80 },
		},
	} :: { [string]: { Fletchable } },
	SHAFTS = {
		["Logs"] = { menu = "15 arrow shafts", item = "Arrow shaft", level = 1 },
		["Oak logs"] = { menu = "30 arrow shafts", item = "Arrow shaft", level = 15 },
		["Willow logs"] = { menu = "45 arrow shafts", item = "Arrow shaft", level = 30 },
		["Maple logs"] = { menu = "60 arrow shafts", item = "Arrow shaft", level = 45 },
		["Yew logs"] = { menu = "75 arrow shafts", item = "Arrow shaft", level = 60 },
		["Magic logs"] = { menu = "90 arrow shafts", item = "Arrow shaft", level = 75 },
	} :: { [string]: Fletchable },
	BUSY_GRACE_MS = 1800,
	BASKET_TOGGLE_MS = 2400,
	SPECIAL_RETRY_MS = 60000,
	SPECIAL_DELAY_MS = { 400, 2500 },
	BASKETS = { "Open log basket", "Log basket", "Open forestry basket", "Forestry basket" } :: { number | string },
	CLOSED_BASKETS = { "Log basket", "Forestry basket" } :: { number | string },
	OPEN_BASKETS = { "Open log basket", "Open forestry basket" } :: { number | string },
	OPEN = "Open",
	CLOSE = "Close",
	CONFIGURE = "Configure",
	OPEN_CLOSE = "Open/close",
	CAMPFIRE_BUILD_MS = 5000,
	CAMPFIRE = "Forester's Campfire",
	FIRE = "Fire",
	TEND_ANIMATIONS = { lo = 10561, hi = 10573 },
	TREE_REACH = 14,
	NEST = "nest",
	NEST_REACH = 10,
	FAR = 6,
	BANK_NEAR = 1,
	NEST_SKIP_MS = 30000,
	BANK_BOOTH = "Bank booth",
	BANK = "Bank",
	BOOTH_REACH = 8,
	CAMPFIRE_REACH = 15,
	START_MS = 4000,
	LIGHT_MS = 6000,
	CANT_LIGHT = "can't light a fire here",
	LANE = { WIDTH = 16, HEIGHT = 3, MIN = 8, BLOCKED = 0x1240100, WALL_WEST = 0x80, WALL_EAST = 0x8 },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	location = "Maple - Seers' Village",
	mode = "Bank" :: Mode,
	events = true,
	max_logs = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
}

local stats = { logs = 0, events = 0, nests = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_began_at: number,
	last_progress_at: number,
	last_busy_at: number,
	last_xp: number,
	failures_in_row: number,
	burning: boolean,
	fletching: boolean,
	unloading: boolean,
	in_lane: boolean,
	lit: number,
	bad_tiles: { [number]: boolean },
	last_logs: number,
	event: Events.Kind?,
	skip: { [string]: boolean },
	special_tried_at: number,
	event_anchor: Tile?,
	nest_skipped: { [string]: number },
}

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_busy_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	burning = false,
	fletching = false,
	unloading = false,
	in_lane = false,
	lit = 0,
	bad_tiles = {},
	last_logs = 0,
	event = nil,
	skip = {},
	special_tried_at = 0,
	nest_skipped = {},
}

local spot: Locations.Location = Locations[CONFIG.location]

function Game.apply_settings(values: { [string]: any })
	if values.location and Locations[values.location] then
		CONFIG.location = values.location
	end
	CONFIG.mode = values.mode or CONFIG.mode
	if values.events ~= nil then
		CONFIG.events = values.events
	end
	CONFIG.max_logs = values.max_logs or CONFIG.max_logs
	spot = Locations[CONFIG.location]
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

type Snapshot = {
	state: ClientState,
	me: Tile,
	ground: boolean,
	logs: number,
	full: boolean,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "EVENT"
	| "NEST"
	| "BASKET"
	| "BANK"
	| "DROP"
	| "CAMPFIRE"
	| "TINDERBOX"
	| "FLETCH"
	| "DROP_FLETCHED"
	| "WALK"
	| "SPECIAL"
	| "CHOP"
	| "IDLE"

type Plan = { event: Events.Active?, tree: Loc?, nest: GroundItem?, choppers: number? }

local plan: Plan = {}

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	snap = {
		state = state,
		me = { x = state.position.x, y = state.position.y },
		ground = state.position.plane == 0,
		logs = Inventory.count(spot.logs) or 0,
		full = Inventory.is_full(),
	}
	return true
end

function Read.trees(): { Loc }
	local out = {}
	for _, loc in Objects.find(spot.tree) or {} do
		for _, t in spot.trees do
			if loc.x == t.x and loc.y == t.y then
				table.insert(out, loc)
			end
		end
	end
	return out
end

function Read.busiest(trees: { Loc }): { Loc }
	local counts: { [Loc]: number } = {}
	local most = 0
	for _, tree in trees do
		counts[tree] = 0
	end
	for _, player in Players.find() or {} do
		if player.name ~= snap.state.player_name and player.animation ~= -1 then
			for _, tree in trees do
				if Objects.distance(tree, player) == 1 then
					counts[tree] += 1
					most = math.max(most, counts[tree])
					break
				end
			end
		end
	end
	local out = {}
	for _, tree in trees do
		if counts[tree] == most then
			table.insert(out, tree)
		end
	end
	plan.choppers = most
	return out
end

function Read.special_ready(): boolean
	if time() - S.special_tried_at < CONST.SPECIAL_RETRY_MS then
		return false
	end
	local cost, energy = SpecialAttack.cost(), SpecialAttack.energy()
	return cost ~= nil and cost > 0 and energy ~= nil and energy >= cost
end

function Read.centre(): Tile
	local x, y = 0, 0
	for _, t in spot.trees do
		x += t.x
		y += t.y
	end
	return { x = x // #spot.trees, y = y // #spot.trees }
end

function Read.near_trees(me: Tile): boolean
	if not snap.ground then
		return false
	end
	for _, t in spot.trees do
		if Walker.distance(me, t) <= CONST.TREE_REACH then
			return true
		end
	end
	return false
end

function Read.tending(): boolean
	local anim = Player.animation() or -1
	return anim >= CONST.TEND_ANIMATIONS.lo and anim <= CONST.TEND_ANIMATIONS.hi
end

function Read.campfire(): Loc?
	local centre = Read.centre()
	local fire = Objects.nearest(CONST.CAMPFIRE, snap.me)
	if fire and Objects.distance(fire, centre) <= CONST.CAMPFIRE_REACH then
		return fire
	end
	return nil
end

function Read.occupied(): { [number]: boolean }
	local taken: { [number]: boolean } = table.clone(S.bad_tiles)
	for _, loc in Host.locs() or {} do
		local blocks = loc.kind == Objects.GAME_OBJECT
			or (loc.kind == Objects.GROUND_DECORATION and (loc.name or "") ~= "")
		if blocks then
			for dx = 0, math.max(loc.size_x, 1) - 1 do
				for dy = 0, math.max(loc.size_y, 1) - 1 do
					taken[(loc.x + dx) * 65536 + loc.y + dy] = true
				end
			end
		end
	end
	return taken
end

function Read.fire_lane(): Tile?
	local taken = Read.occupied()
	local me = snap.me
	local best: Tile? = nil
	local best_score = -math.huge
	local anchor, w, h = spot.fires, CONST.LANE.WIDTH, CONST.LANE.HEIGHT
	local c = Host.collision({ x1 = anchor.x - w, y1 = anchor.y - h, x2 = anchor.x + w, y2 = anchor.y + h })
	if c then
		local function flag(x: number, y: number): number
			return c.flags[(x - c.x) * c.height + (y - c.y) + 1]
		end
		local function free(x: number, y: number): boolean
			return bit32.band(flag(x, y), CONST.LANE.BLOCKED) == 0 and not taken[x * 65536 + y]
		end
		local function open_west(x: number, y: number): boolean
			return bit32.band(flag(x, y), CONST.LANE.WALL_WEST) == 0
				and bit32.band(flag(x - 1, y), CONST.LANE.WALL_EAST) == 0
		end
		for y = c.y + 1, c.y + c.height - 2 do
			local run = 0
			for x = c.x + 1, c.x + c.width - 2 do
				if not free(x, y) then
					run = 0
				elseif run > 0 and open_west(x, y) then
					run += 1
				else
					run = 1
				end
				if run >= CONST.LANE.MIN then
					local tile = { x = x, y = y }
					local score = math.min(run, 27) * 2 - Walker.distance(me, tile) / 2
					if score > best_score then
						best, best_score = tile, score
					end
				end
			end
		end
	end
	return best
end

function Read.is_nest(name: string?): boolean
	return string.find(string.lower(name or ""), CONST.NEST, 1, true) ~= nil
end

function Read.nest(): GroundItem?
	for _, item in GroundItems.find() or {} do
		if
			Read.is_nest(item.name)
			and time() - (S.nest_skipped[`{item.x},{item.y}`] or -math.huge) > CONST.NEST_SKIP_MS
			and GroundItems.distance(item, snap.me) <= CONST.NEST_REACH
			and GroundItems.fits(item)
		then
			return item
		end
	end
	return nil
end

function Read.banks(id: number): boolean
	local view = (Host.loc_shown({ id }) or {})[1]
	return view ~= nil and table.find(view.actions or {}, CONST.BANK) ~= nil
end

function Read.bank_booth(me: Tile): Loc?
	local best: Loc? = nil
	local best_d = math.huge
	local usable: { [number]: boolean } = {}
	for _, booth in Objects.find(CONST.BANK_BOOTH) or {} do
		if usable[booth.id] == nil then
			usable[booth.id] = Read.banks(booth.id)
		end
		local d = Objects.distance(booth, me)
		if usable[booth.id] and Walker.distance(booth, spot.bank) <= CONST.BOOTH_REACH and d < best_d then
			best, best_d = booth, d
		end
	end
	return best
end

function Read.carried_logs(): { number }
	local ids: { number } = {}
	for _, item in Inventory.items() or {} do
		local name = string.lower(item.name or "")
		if (name == "logs" or string.sub(name, -5) == " logs") and not table.find(ids, item.id) then
			table.insert(ids, item.id)
		end
	end
	return ids
end

function Read.carried_nests(): { number }
	local ids: { number } = {}
	for _, item in Inventory.items() or {} do
		if Read.is_nest(item.name) and not table.find(ids, item.id) then
			table.insert(ids, item.id)
		end
	end
	return ids
end

function Read.has_kit(): boolean
	local function has(items: { Inv.Slot }?): boolean
		for _, item in items or {} do
			if table.find(CONST.KITS, item.name) then
				return true
			end
		end
		return false
	end
	return has(Wornitems.items()) or has(Inventory.items())
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

	AntibanTasks.skills = { "Woodcutting", "Firemaking" }
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

function Game.check_requirements(): string?
	local level = Stats.real_level("Woodcutting") or 0
	if level < spot.level then
		return `{spot.tree} needs {spot.level} Woodcutting`
	end
	if CONFIG.events and not Read.has_kit() then
		return "events need a Forestry kit or Forestry basket worn or in the inventory"
	end
	if
		(CONFIG.mode == "Tinderbox" or CONFIG.mode == "Forester's Campfire")
		and (Inventory.count(CONST.TINDERBOX) or 0) == 0
	then
		return `{CONFIG.mode} needs a tinderbox in the inventory`
	end
	if Read.fletching_mode() then
		if not Inventory.contains_any(CONST.KNIVES) then
			return `{CONFIG.mode} needs a knife or a fletching knife in the inventory`
		end
		if Read.fletch_product() == nil then
			return `nothing to fletch from {spot.logs} at this Fletching level`
		end
	end
	return nil
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end
	local problem = Game.check_requirements()
	if problem then
		Log.log(NAME, `Can't start: {problem}`)
		S.blocked = problem
		S.finished = true
		return
	end
	S.last_logs = snap.logs
	Events.reset()
	Game.setup_antiban()
end

function Game.wait_start(started: () -> boolean): boolean
	local t0 = time()
	while time() - t0 < CONST.START_MS do
		if started() then
			return true
		end
		if Player.is_moving() then
			t0 = time()
		end
		sleep(100)
	end
	return started()
end

function Game.chop(tree: Loc)
	Log.log(NAME, `Chopping the {spot.tree} at {tree.x}, {tree.y} with {plan.choppers} others`)
	local clicked = Objects.distance(tree, snap.me) <= CONST.FAR and Objects.interact(tree, "Chop down")
	if not clicked and Read.standing(tree) then
		clicked = Objects.approach(tree, "Chop down")
	end
	if clicked and Game.wait_start(Player.is_animating) then
		S.failures_in_row = 0
	elseif Read.standing(tree) then
		S.failures_in_row += 1
	end
end

function Read.standing(tree: Loc): boolean
	for _, loc in Objects.find(spot.tree) or {} do
		if loc.x == tree.x and loc.y == tree.y then
			return true
		end
	end
	return false
end

function Game.take_nest(nest: GroundItem)
	Log.log(NAME, `Picking up the {nest.name or "bird nest"} at {nest.x}, {nest.y}`)
	local ok = if GroundItems.distance(nest, snap.me) > CONST.FAR
		then GroundItems.approach(nest, "Take")
		else GroundItems.interact(nest, "Take")
	if ok then
		S.failures_in_row = 0
		stats.nests += 1
	else
		S.failures_in_row += 1
		S.nest_skipped[`{nest.x},{nest.y}`] = time()
		local click = Host.menu_click()
		Log.log(
			NAME,
			`TRACE nest pickup failed, last click {click and click.entry.option} {click and click.entry.target}`
		)
	end
end

function Read.fletching_mode(): boolean
	return CONFIG.mode == "Fletch and drop" or CONFIG.mode == "Fletch and bank" or CONFIG.mode == "Fletch arrow shafts"
end

function Read.fletch_products(): { number | string }
	local names: { number | string } = {}
	for _, entry in CONST.FLETCH[spot.logs] or {} do
		table.insert(names, entry.item)
	end
	return names
end

function Read.fletch_product(): Fletchable?
	local level = Stats.real_level("Fletching") or 0
	if CONFIG.mode == "Fletch arrow shafts" then
		local shafts = CONST.SHAFTS[spot.logs]
		return if shafts and level >= shafts.level then shafts else nil
	end
	for _, entry in CONST.FLETCH[spot.logs] or {} do
		if level >= entry.level then
			return entry
		end
	end
	return nil
end

function Read.holding(names: { number | string }): boolean
	return Inventory.contains_any(names) or Wornitems.contains_any(names)
end

function Read.basket_should_open(): boolean
	return CONFIG.mode == "Bank" and S.event ~= "BEEHIVE"
end

function Read.basket_wrong(): boolean
	return Read.holding(if Read.basket_should_open() then CONST.CLOSED_BASKETS else CONST.OPEN_BASKETS)
end

function Game.toggle_basket()
	local opening = Read.basket_should_open()
	local from = if opening then CONST.CLOSED_BASKETS else CONST.OPEN_BASKETS
	local option = if opening then CONST.OPEN else CONST.CLOSE
	Log.log(NAME, if opening then "Opening the log basket" else "Closing the log basket so logs stay in the inventory")
	local clicked = Events.use_basket(from, option, CONST.CONFIGURE, CONST.OPEN_CLOSE)
	local t0 = time()
	while clicked and Read.holding(from) and time() - t0 < CONST.BASKET_TOGGLE_MS do
		sleep(100)
	end
	if clicked and not Read.holding(from) then
		S.failures_in_row = 0
	else
		S.failures_in_row += 1
	end
end

function Game.bank()
	local booth = if snap.ground then Read.bank_booth(snap.me) else nil
	local at_bank = snap.ground and Walker.distance(snap.me, spot.bank) <= CONST.BANK_NEAR
	if booth == nil and not at_bank then
		Log.log(NAME, "Walking to the bank")
		if not Walker.walk(spot.bank, { near = CONST.BANK_NEAR, plane = 0 }) then
			S.failures_in_row += 1
		end
		return
	end
	Log.log(NAME, if booth then `Opening the bank booth at {booth.x}, {booth.y}` else "Opening the bank")
	if not Bankmain.open(if booth then { loc = booth, npc = nil } else nil) then
		S.failures_in_row += 1
		return
	end
	local deposited = true
	for _, id in Read.carried_logs() do
		deposited = Bankmain.deposit(id) and deposited
	end
	if deposited then
		S.failures_in_row = 0
	end
	for _, nest in Read.carried_nests() do
		Bankmain.deposit(nest)
	end
	for _, product in Read.fletch_products() do
		if Bankmain.inventory.contains(product) then
			Bankmain.deposit(product)
		end
	end
	S.unloading = false
	if CONFIG.mode == "Bank" and Read.holding(CONST.BASKETS) then
		Log.log(NAME, "Emptying the log basket into the bank")
		Bankmain.deposit_containers()
		Host.sleep(Random.int(400, 900))
	end
	Bankmain.close()
end

function Game.fletch()
	if Player.is_animating() then
		S.last_busy_at = time()
		return
	end
	if time() - S.last_busy_at < CONST.BUSY_GRACE_MS then
		return
	end
	local product = assert(Read.fletch_product())
	Log.log(NAME, `Fletching {spot.logs} into {product.item}`)
	if not (Inventory.combine(CONST.KNIVES, spot.logs) and Make.wait_open(CONST.FLETCH_MS)) then
		S.failures_in_row += 1
		return
	end
	if Make.make(product.menu, "All") and Game.wait_start(Player.is_animating) then
		S.failures_in_row = 0
	else
		S.failures_in_row += 1
	end
end

function Game.drop_fletched()
	Log.log(NAME, "Dropping the fletched items")
	Inventory.shift_drop(Read.fletch_products())
	S.unloading = false
end

function Game.drop()
	Log.log(NAME, `Dropping {spot.logs}`)
	Inventory.shift_drop(spot.logs)
end

function Game.light_fire(): boolean
	local before = Inventory.count(spot.logs) or 0
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Inventory.combine(CONST.TINDERBOX, spot.logs) then
		return false
	end
	local t0 = time()
	while time() - t0 < CONST.LIGHT_MS do
		if (Inventory.count(spot.logs) or 0) < before then
			return true
		end
		for _, m in Chat.new_messages(seen) or {} do
			seen = m.uid
			if string.find(m.text, CONST.CANT_LIGHT, 1, true) then
				return false
			end
		end
		sleep(100)
	end
	return false
end

function Game.go_to_lane(): boolean
	local lane = Read.fire_lane()
	if lane == nil then
		Log.log(NAME, "No clear row of tiles to light fires on")
		return false
	end
	Log.log(NAME, `Walking to the clear row at {lane.x}, {lane.y} to light fires`)
	Walker.walk(lane, { near = 0, plane = 0 })
	local me = Walker.position()
	if me and (me.x ~= lane.x or me.y ~= lane.y) then
		Walker.walk_tile(lane)
	end
	Player.wait_still(3000)
	me = Walker.position()
	return me ~= nil and me.x == lane.x and me.y == lane.y
end

function Game.tinderbox()
	if not S.in_lane then
		S.in_lane = Game.go_to_lane()
		if not S.in_lane then
			S.failures_in_row += 1
		end
		return
	end
	if Game.light_fire() then
		S.failures_in_row = 0
		S.lit += 1
		Player.wait_still(3000)
		return
	end
	local me = Walker.position()
	if me then
		S.bad_tiles[me.x * 65536 + me.y] = true
		Log.log(NAME, `Lit {S.lit} fires on this row, none at {me.x}, {me.y}`)
	end
	if S.lit == 0 then
		S.failures_in_row += 1
	end
	S.lit = 0
	S.in_lane = false
end

function Read.free_tile_near(me: Tile): Tile?
	local taken = Read.occupied()
	taken[me.x * 65536 + me.y] = true
	local options: { Tile } = {}
	for dx = -2, 2 do
		for dy = -2, 2 do
			local tile: Tile = { x = me.x + dx, y = me.y + dy }
			if not taken[tile.x * 65536 + tile.y] and Walker.on_screen(tile) then
				table.insert(options, tile)
			end
		end
	end
	return Random.nearest_weighted(options, function(t: Tile): number
		return Walker.distance(me, t)
	end, 2)
end

function Game.start_campfire(): boolean
	if (Inventory.count(CONST.TINDERBOX) or 0) == 0 then
		return false
	end
	local me = assert(Walker.position())
	if Read.occupied()[me.x * 65536 + me.y] then
		local tile = Read.free_tile_near(me)
		if tile then
			Log.log(NAME, `Stepping to {tile.x}, {tile.y} to light a fire`)
			Walker.walk_tile(tile)
		end
		return true
	end
	Log.log(NAME, "No campfire here, lighting one")
	if not Game.light_fire() then
		S.bad_tiles[me.x * 65536 + me.y] = true
		return true
	end
	Player.wait_still(3000)
	local fire = Objects.nearest(CONST.FIRE, assert(Walker.position()))
	if fire == nil or Objects.distance(fire, me) > 2 then
		return true
	end
	Log.log(NAME, `Adding a log to the fire at {fire.x}, {fire.y} to make a campfire`)
	if Inventory.select(spot.logs) and Objects.interact(fire, "Use") then
		local t0 = time()
		while time() - t0 < CONST.CAMPFIRE_BUILD_MS and Read.campfire() == nil do
			sleep(150)
		end
	end
	return true
end

function Game.campfire()
	if Read.tending() then
		return
	end
	local fire = Read.campfire()
	if fire == nil then
		if not Game.start_campfire() then
			Log.log(NAME, "No campfire nearby and no tinderbox to light one")
			S.blocked = "no campfire nearby and no tinderbox"
			S.finished = true
		end
		return
	end
	Log.log(NAME, `Tending the campfire at {fire.x}, {fire.y}`)
	if Objects.interact(fire, "Tend-to") and Game.wait_start(Read.tending) then
		S.failures_in_row = 0
	else
		S.failures_in_row += 1
	end
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
	if snap.logs > S.last_logs then
		stats.logs += snap.logs - S.last_logs
	end
	S.last_logs = snap.logs
end

function Loop.report_counters()
	local key = `{stats.logs}/{stats.events}/{stats.nests}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "logs", label = "Logs", value = stats.logs },
		{ id = "events", label = "Events", value = stats.events },
		{ id = "nests", label = "Bird nests", value = stats.nests },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_logs > 0 and stats.logs >= CONFIG.max_logs then
		Log.log(NAME, `Reached {CONFIG.max_logs} logs, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.blocked = reason
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

function Loop.track_event(active: Events.Active?)
	local kind = if active then active.kind else nil
	local previous = S.event
	if previous and kind ~= previous then
		if not Events.skipped(previous) then
			stats.events += 1
		end
		Log.log(NAME, `Event over: {previous}`)
		Events.reset()
	end
	if kind ~= previous then
		S.event_anchor = if kind then snap.me else nil
	end
	S.event = kind
end

function Loop.full_state(): State?
	local mode = CONFIG.mode
	if mode == "Forester's Campfire" or mode == "Tinderbox" then
		if snap.full then
			S.burning = true
		elseif snap.logs == 0 then
			S.burning, S.in_lane = false, false
		end
		if S.burning then
			return if mode == "Tinderbox" then "TINDERBOX" else "CAMPFIRE"
		end
		return nil
	end
	if Read.fletching_mode() then
		if snap.full and snap.logs > 0 then
			S.fletching = true
		elseif snap.full and mode ~= "Fletch arrow shafts" then
			S.unloading = true
		end
		if S.fletching and snap.logs == 0 then
			S.fletching, S.unloading = false, mode ~= "Fletch arrow shafts"
		end
		if S.fletching then
			return "FLETCH"
		end
		if S.unloading then
			return if mode == "Fletch and drop" then "DROP_FLETCHED" else "BANK"
		end
		return nil
	end
	if not snap.full then
		return nil
	end
	return if mode == "Drop" then "DROP" else "BANK"
end

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

	if CONFIG.events then
		Events.trace(snap.me)
		local active = Events.find({ S.event_anchor or snap.me })
		Loop.track_event(active)
		Events.paint(if active then active.kind else nil)
		if active and not skipped["EVENT"] then
			plan.event = active
			return "EVENT"
		end
	end
	local nest = Read.nest()
	if nest then
		plan.nest = nest
		return "NEST"
	end
	if Read.basket_wrong() then
		return "BASKET"
	end
	local full = Loop.full_state()
	if full then
		return full
	end
	if not Read.near_trees(snap.me) then
		return "WALK"
	end
	if Read.special_ready() then
		return "SPECIAL"
	end
	if Player.is_animating() or Player.is_moving() then
		S.last_busy_at = time()
		return "IDLE"
	end
	if time() - S.last_busy_at < CONST.BUSY_GRACE_MS then
		return "IDLE"
	end
	local trees = Read.busiest(Read.trees())
	local me = snap.me
	plan.tree = Random.nearest_weighted(trees, function(t: Loc): number
		return Objects.distance(t, me)
	end, 2)
	if plan.tree then
		return "CHOP"
	end
	return "IDLE"
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	EVENT = function()
		local active = assert(plan.event)
		S.in_lane = false
		if not Events.step(active, snap.me, spot.logs) then
			S.skip["EVENT"] = true
		end
	end,
	NEST = function()
		Game.take_nest(assert(plan.nest))
	end,
	BASKET = function()
		Game.toggle_basket()
	end,
	SPECIAL = function()
		S.special_tried_at = time()
		Biometrics.sleep(CONST.SPECIAL_DELAY_MS[1], CONST.SPECIAL_DELAY_MS[2])
		Log.log(NAME, "Using the axe's special attack")
		SpecialAttack.use()
	end,
	BANK = function()
		Game.bank()
	end,
	DROP = function()
		Game.drop()
	end,
	FLETCH = function()
		Game.fletch()
	end,
	DROP_FLETCHED = function()
		Game.drop_fletched()
	end,
	CAMPFIRE = function()
		Game.campfire()
	end,
	TINDERBOX = function()
		Game.tinderbox()
	end,
	WALK = function()
		Log.log(NAME, `Walking to the {spot.tree}s`)
		if not Walker.walk(Read.centre(), { near = 4, plane = 0 }) then
			S.failures_in_row += 1
		end
	end,
	CHOP = function()
		Game.chop(assert(plan.tree))
	end,
	IDLE = function()
		if not Antiban.do_antiban() then
			sleep(Random.int(200, 600))
		end
	end,
}

local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.wrap_up()
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
	Log.log(NAME, `{NAME} started: {CONFIG.location}, {CONFIG.mode}`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() then
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
		Handler.states[state]()

		Antiban.do_async_tasks("outside")
		sleep(Random.int(60, 140))
	end
	Loop.wrap_up()
	Log.log(NAME, "Done")
end

Loop.run()
