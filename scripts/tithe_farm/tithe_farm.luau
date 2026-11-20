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
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local Chat = require("@lib/main/interfaces/chatbox/chat")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local GameState = require("@lib/main/game_state")
local Handoff = require("@lib/main/handoff")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Minigames = require("@lib/main/interfaces/mainscreen/minigames")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Varbits = require("@lib/main/varbits")
local Walker = require("@lib/main/walker")

local NAME = "Tithe Farm"

type Crop = { name: string, level: number }
type PatchKind = "EMPTY" | "DRY" | "GROWING" | "GROWN" | "BLIGHTED"
type Patch = { index: number, tile: Tile, loc: Loc?, kind: PatchKind }
type Offset = { dx: number, dy: number }
type Area = { x1: number, y1: number, x2: number, y2: number }

local function build_route(patches: number): { Offset }
	local rows = { 11, 8, 5, 2, -4, -7, -10, -13 }
	local out: { Offset } = {}
	for i, dy in rows do
		local first, second = 10, 5
		if i % 2 == 0 then
			first, second = second, first
		end
		table.insert(out, { dx = first, dy = dy })
		table.insert(out, { dx = second, dy = dy })
	end
	if patches > #out then
		for _, dy in { -13, -10, -7, -4 } do
			table.insert(out, { dx = 15, dy = dy })
		end
	end
	return out
end

local CONST = {
	REPORT = { counters_key = "" },
	CROPS = {
		{ name = "Logavano", level = 74 },
		{ name = "Bologano", level = 54 },
		{ name = "Golovanova", level = 34 },
	} :: { Crop },
	BARREL = { dx = 4, dy = -1 } :: Offset,
	SACK = { dx = 4, dy = 1 } :: Offset,
	FARMHOUSE = { x = 1803, y = 3501 } :: Tile,
	DOOR = "Farm door",
	SEED_TABLE = "Seed table",
	TELEPORT = "Tithe Farm",
	EMPTY_PATCH = "Tithe patch",
	FARMER_EXPERT = "I'm an expert",
	FARMER = "Farmer Gricoller",
	SEED_QUERY = "How many seeds",
	SEED_AMOUNTS = { "1000", "5000", "10000" },
	HUD = { GROUP = 241, POINTS = 6 },
	MIN_LEVEL = 34,
	MIN_CANS = 3,
	CAN_DOSES = 8,
	GRICOLLER = { NAME = "Gricoller's can", REFILL_BELOW = 500 },
	NEAR_FARMHOUSE = 8,
	WALK_RANGE = 60,
	GROW_MS = 60000,
	WAIT_LIMIT_MS = 80000,
	ANTIBAN_SLACK_MS = 20000,
	ACTION_MS = 3500,
	CLEAR_MS = 6000,
	FILL_STALL_MS = 4000,
	TELEPORT_MS = 20000,
	DOOR_MS = 6000,
	DIALOGUE_STEPS = 5,
	USE_RANGE = 8,
	CROSSINGS = {
		{ from = 8, patch = 9, lane = { x1 = 8, y1 = -6, x2 = 9, y2 = -2 } },
		{ from = 20, patch = 1, lane = { x1 = 8, y1 = 2, x2 = 9, y2 = 12 } },
	} :: { { from: number, patch: number, lane: Area } },
	CROSSING_MS = 6000,
	CANCEL = { ALWAYS_FROM = 20, CHANCE = 0.1 },
	CAN_ATTEMPTS = 3,
	BESIDE_PATCH = 3,
	SACK_BATCH = 100,
	STEP_MS = 2600,
	SLACK_MARGIN_MS = 8000,
	DEPOSIT_MS = 6000,
	BARREL_WALK_MS = 5000,
	FILL_MS_PER_CAN = 2500,
	OBSERVE_MS = 600,
	POLL_MS = 50,
}

local Read, Task, Wait, Game, Loop, Handler = {}, {}, {}, {}, {}, {}

local CONFIG = {
	max_fruit = 0,
	max_seeds = 0,
	stop_level = 0,
	stop_points = 0,
	timeouts = { idle_minutes = 10, max_failures = 6 },
	antiban = true,
}

local stats = { deposited = 0, harvested = 0, planted = 0, points = 0 }

type RunState = {
	route: { Offset },
	finished: boolean,
	stopping: string?,
	blocked: string?,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	crop: Crop?,
	cursor: number,
	at_boundary: boolean,
	resetting: boolean,
	cursor_since: number,
	hovered: number,
	seen_ids: { [number]: number },
	observed_at: number,
	since: { [number]: number },
	start_points: number?,
	total_points: number?,
	last_fruit: number,
	was_inside: boolean,
	visit_deposited: number,
	upgrade_target: number?,
	teleported_at: number?,
}

local S: RunState = {
	route = {},
	finished = false,
	stopping = nil,
	blocked = nil,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	crop = nil,
	cursor = 0,
	at_boundary = true,
	resetting = false,
	cursor_since = 0,
	hovered = 0,
	seen_ids = {},
	observed_at = 0,
	since = {},
	start_points = nil,
	total_points = nil,
	last_fruit = 0,
	was_inside = false,
	visit_deposited = 0,
	upgrade_target = nil,
	teleported_at = nil,
}

type Carried = {
	seeds: { [string]: number },
	fruit: number,
	doses: number,
	cans: number,
	unfilled: number,
	lowest_can: string?,
	wet_can: string?,
	gricoller: boolean,
	dibber: boolean,
	spade: boolean,
}

type Snapshot = {
	state: ClientState,
	me: Tile,
	door: Loc?,
	inside: boolean,
	carried: Carried,
	field: { Patch },
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "TRAVEL"
	| "TAKE_SEEDS"
	| "ENTER"
	| "ANSWER"
	| "HARVEST"
	| "PLANT"
	| "WATER"
	| "CLEAR"
	| "WAIT"
	| "REFILL"
	| "DEPOSIT"
	| "BREAK"
	| "LEAVE"
	| "DONE"

local report = StatsReport.new()
local views: { [number]: Host.LocView } = {}

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.logged_in(s: ClientState): boolean
	return s.game_state == GameState.LOGGED_IN and s.position ~= nil
end

function Read.at(anchor: Loc, offset: Offset): Tile
	return { x = anchor.x + offset.dx, y = anchor.y + offset.dy }
end

function Read.view(id: number): Host.LocView?
	local cached = views[id]
	if cached then
		return cached
	end
	local shown = Host.loc_shown({ id })
	local view = shown and shown[1]
	if view then
		views[id] = view
	end
	return view
end

function Read.has_action(view: Host.LocView, action: string): boolean
	return table.find(view.actions or {}, action) ~= nil
end

function Read.kind(loc: Loc): PatchKind
	local view = Read.view(loc.id)
	if not view then
		return "GROWING"
	end
	if Read.has_action(view, "Clear") then
		return "BLIGHTED"
	elseif Read.has_action(view, "Harvest") then
		return "GROWN"
	elseif Read.has_action(view, "Water") then
		return "DRY"
	elseif view.name == CONST.EMPTY_PATCH then
		return "EMPTY"
	end
	return "GROWING"
end

function Read.carried(): Carried
	local carried: Carried = {
		seeds = {},
		fruit = 0,
		doses = 0,
		cans = 0,
		unfilled = 0,
		lowest_can = nil,
		wet_can = nil,
		gricoller = false,
		dibber = false,
		spade = false,
	}
	local lowest = math.huge
	local wettest, wettest_can = 0, nil
	local gricoller_wet = false
	local gricoller_low = false
	for _, item in Inventory.items() or {} do
		local name: string = item.name or ""
		local crop = name:match("^(%a+) seed$")
		if crop then
			carried.seeds[crop] = (carried.seeds[crop] or 0) + item.quantity
		elseif name:match("^%a+ fruit$") then
			carried.fruit += item.quantity
		elseif name == "Seed dibber" then
			carried.dibber = true
		elseif name == "Spade" then
			carried.spade = true
		elseif name == "Watering can" or name:match("^Watering can%(%d%)$") then
			local doses = tonumber(name:match("%((%d)%)")) or 0
			carried.cans += 1
			carried.doses += doses
			if doses < CONST.CAN_DOSES then
				carried.unfilled += 1
			end
			if doses < CONST.CAN_DOSES and doses < lowest then
				lowest = doses
				carried.lowest_can = name
			end
			if doses > wettest then
				wettest = doses
				wettest_can = name
			end
		elseif name == CONST.GRICOLLER.NAME then
			local charges = Varbits.get(Varbits.GRICOLLER_CAN_CHARGES) or 0
			carried.gricoller = true
			carried.cans += 1
			carried.doses += charges
			gricoller_low = charges < CONST.GRICOLLER.REFILL_BELOW
			gricoller_wet = charges > 0
		end
	end
	if gricoller_low and not carried.lowest_can then
		carried.lowest_can = CONST.GRICOLLER.NAME
	end
	carried.wet_can = if gricoller_wet then CONST.GRICOLLER.NAME else wettest_can
	return carried
end

function Read.fruit_in_hand(): number
	return stats.deposited + if snap then snap.carried.fruit else 0
end

function Read.held_crop(carried: Carried): Crop?
	for _, crop in CONST.CROPS do
		if (carried.seeds[crop.name] or 0) > 0 then
			return crop
		end
	end
	return nil
end

function Read.best_crop(): Crop?
	local level = Stats.real_level("Farming") or 0
	for _, crop in CONST.CROPS do
		if level >= crop.level then
			return crop
		end
	end
	return nil
end

function Read.seeds(): number
	local crop = S.crop
	return if crop then snap.carried.seeds[crop.name] or 0 else 0
end

function Read.field(locs: { Loc }, door: Loc): { Patch }
	local by_tile: { [string]: Loc } = {}
	for _, loc in locs do
		if loc.size_x == 3 and loc.size_y == 3 then
			by_tile[`{loc.x},{loc.y}`] = loc
		end
	end
	local field: { Patch } = {}
	for i, offset in S.route do
		local tile = Read.at(door, offset)
		local loc = by_tile[`{tile.x},{tile.y}`]
		local kind: PatchKind = if loc then Read.kind(loc) else "GROWING"
		table.insert(field, { index = i, tile = tile, loc = loc, kind = kind })
		local id = if loc then loc.id else -1
		local seen = S.seen_ids[i]
		if seen ~= id then
			S.seen_ids[i] = id
			S.since[i] = if seen == nil then time() - CONST.GROW_MS else time()
		end
	end
	S.observed_at = time()
	return field
end

function Read.observe()
	local door = snap and snap.door
	if snap and snap.inside and door and time() - S.observed_at >= CONST.OBSERVE_MS then
		Read.field(Host.locs() or {}, door)
	end
end

function Read.deadline(patch: Patch): number?
	local since = S.since[patch.index] or time()
	if patch.kind == "DRY" then
		return since + CONST.GROW_MS
	elseif patch.kind == "GROWING" then
		return since + 2 * CONST.GROW_MS
	end
	return nil
end

function Read.ready_in(): number
	local patch = snap.field[S.cursor]
	if not patch or patch.kind ~= "GROWING" then
		return 0
	end
	return (S.since[S.cursor] or time()) + CONST.GROW_MS - time()
end

function Read.slack(): number
	local slack = math.huge
	local count = #snap.field
	local start = math.max(S.cursor, 1)
	for k = 0, count - 1 do
		local patch = snap.field[(start + k - 1) % count + 1]
		local deadline = Read.deadline(patch)
		if deadline then
			slack = math.min(slack, deadline - (time() + k * CONST.STEP_MS))
		end
	end
	return slack
end

function Read.door(locs: { Loc }, me: Tile): Loc?
	local best: Loc? = nil
	local best_distance = math.huge
	for _, loc in locs do
		if loc.name == CONST.DOOR then
			local distance = Objects.distance(loc, me)
			if distance < best_distance then
				best, best_distance = loc, distance
			end
		end
	end
	return best
end

function Read.nearest(tiles: { Tile }, from: Tile): Tile?
	local best: Tile? = nil
	local best_distance = math.huge
	for _, tile in tiles do
		local distance = Walker.distance(tile, from)
		if distance < best_distance then
			best, best_distance = tile, distance
		end
	end
	return best
end

function Read.area(anchor: Loc, offsets: Area): Area
	return {
		x1 = anchor.x + offsets.x1,
		y1 = anchor.y + offsets.y1,
		x2 = anchor.x + offsets.x2,
		y2 = anchor.y + offsets.y2,
	}
end

function Read.inside(area: Area, tile: Tile): boolean
	return tile.x >= area.x1 and tile.x <= area.x2 and tile.y >= area.y1 and tile.y <= area.y2
end

function Read.middle(area: Area): Tile
	return { x = (area.x1 + area.x2) // 2, y = (area.y1 + area.y2) // 2 }
end

function Read.crossing_lane(): Area?
	local door = snap.door
	if not door then
		return nil
	end
	for _, crossing in CONST.CROSSINGS do
		local from = S.route[crossing.from]
		if
			crossing.patch == S.cursor
			and from
			and Walker.distance(snap.me, Read.at(door, from)) <= CONST.BESIDE_PATCH
		then
			local lane = Read.area(door, crossing.lane)
			return if Read.inside(lane, snap.me) then nil else lane
		end
	end
	return nil
end

function Read.loc_at(tile: Tile, name: string): Loc?
	for _, loc in Host.locs() or {} do
		if loc.x == tile.x and loc.y == tile.y and loc.name == name then
			return loc
		end
	end
	return nil
end

function Read.points(): number?
	local widget = Host.widget(CONST.HUD.GROUP, CONST.HUD.POINTS)
	local text = widget and widget.text
	return text and tonumber(text:match("(%d+)"))
end

function Read.refresh_snapshot(state: ClientState): boolean
	local position = state.position
	if position == nil then
		return false
	end
	local me = { x = position.x, y = position.y }
	local locs = Host.locs() or {}
	local door = Read.door(locs, me)
	local inside = door ~= nil and Player.in_instance()
	if inside and not S.was_inside then
		S.visit_deposited = 0
		S.upgrade_target = nil
	end
	S.was_inside = inside
	snap = {
		state = state,
		me = me,
		door = door,
		inside = inside,
		carried = Read.carried(),
		field = if inside and door then Read.field(locs, door) else {},
	}
	return true
end

function Read.patch(index: number): Patch?
	local door = snap.door
	if not door then
		return nil
	end
	return Read.field(Host.locs() or {}, door)[index]
end

function Read.field_empty(): boolean
	for _, patch in snap.field do
		if patch.kind ~= "EMPTY" then
			return false
		end
	end
	return true
end

function Read.dry_after(index: number): boolean
	for i = index + 1, #snap.field do
		if snap.field[i].kind == "DRY" then
			return true
		end
	end
	return false
end

function Read.near_farmhouse(): boolean
	return not snap.inside and snap.door ~= nil and Walker.distance(snap.me, CONST.FARMHOUSE) <= CONST.NEAR_FARMHOUSE
end

function Wait.until_true(timeout_ms: number, check: () -> boolean): boolean
	local deadline = time() + timeout_ms
	while time() < deadline do
		if check() then
			return true
		end
		Read.observe()
		sleep(CONST.POLL_MS)
	end
	return check()
end

function Wait.patch_change(index: number, from: number?, timeout_ms: number): Patch?
	local changed: Patch? = nil
	Wait.until_true(timeout_ms, function(): boolean
		local patch = Read.patch(index)
		local id = patch and patch.loc and patch.loc.id
		if patch and id ~= from then
			changed = patch
			return true
		end
		return false
	end)
	return changed
end

function Task.advance()
	S.cursor += 1
	if S.cursor > #S.route then
		S.cursor = 1
		S.at_boundary = true
	end
	S.cursor_since = time()
end

function Task.start_pass()
	S.at_boundary = false
end

function Task.clear_selection(option: string): boolean
	if Inventory.selected() and not Inventory.deselect() then
		Log.log(NAME, `Couldn't clear the selected item before {option}`)
		return false
	end
	return true
end

function Task.approach(loc: Loc, option: string): boolean
	return Task.clear_selection(option) and Objects.approach(loc, option)
end

function Task.use_on(item: string, loc: Loc, early: boolean?): boolean
	if Objects.distance(loc, snap.me) > CONST.USE_RANGE or not Objects.clickbox(loc) then
		local stand = Read.nearest(Objects.stand_tiles(loc) or {}, snap.me)
		if not stand or not Walker.walk(stand, { near = 1 }) then
			return false
		end
	end
	return Inventory.select(item) and Objects.interact(loc, "Use", if early then false else nil)
end

function Task.reveal(tile: Tile)
	if not Walker.on_screen(tile) then
		Camera.face(tile, true)
	end
	if not Walker.on_screen(tile) then
		Camera.look_at(tile)
	end
end

function Task.cross(loc: Loc, lane: Area, option: string, item: string?): boolean
	local stand = { x = Random.int(lane.x1, lane.x2), y = Random.int(lane.y1, lane.y2) }
	Task.reveal(stand)
	if not Walker.click_tile(stand) then
		local cam = Camera.state()
		local view = if cam then `yaw {cam.yaw}, pitch {cam.pitch}, zoom {cam.zoom}` else "unknown"
		Log.log(NAME, `Couldn't click the crossing tile from {snap.me.x},{snap.me.y} (camera {view})`)
		return if item then Task.use_on(item, loc) else Objects.approach(loc, option)
	end
	if item and not Inventory.select(item) then
		return false
	end
	Objects.hover_async(loc, stand)
	local clicked_at = time()
	local in_lane = Wait.until_true(CONST.CROSSING_MS, function(): boolean
		local here = Host.server_tile()
		return here ~= nil and Read.inside(lane, here)
	end)
	local reached_ms = time() - clicked_at
	if Objects.interact(loc, if item then "Use" else option, false) then
		return true
	end
	local here = Host.server_tile()
	local spot = if here then `{here.x},{here.y}` else "unknown"
	Log.log(
		NAME,
		`{option} on patch {S.cursor} after crossing didn't land (lane reached {in_lane} after {reached_ms} ms, now at {spot}, aimed at {stand.x},{stand.y})`
	)
	return false
end

function Task.act(option: string, timeout_ms: number, item: string?, meanwhile: (() -> ())?): Patch?
	local patch = snap.field[S.cursor]
	local loc = patch and patch.loc
	if not loc then
		return nil
	end
	Task.start_pass()
	if not item and not Task.clear_selection(option) then
		return nil
	end
	local lane = Read.crossing_lane()
	local ok = if lane
		then Task.cross(loc, lane, option, item)
		elseif item then Task.use_on(item, loc, true)
		else Objects.approach(loc, option, { arrive_ms = false })
	if not ok then
		Log.log(NAME, `{option} failed on patch {S.cursor}`)
		return nil
	end
	S.hovered = S.cursor
	if meanwhile then
		meanwhile()
	end
	return Wait.patch_change(S.cursor, loc.id, if lane then timeout_ms + CONST.CROSSING_MS else timeout_ms)
end

function Task.next_index(): number
	return S.cursor % #S.route + 1
end

function Task.prehover(index: number)
	local patch = snap.field[index]
	local loc = patch and patch.loc
	if not loc then
		return
	end
	if index ~= S.cursor then
		for _, crossing in CONST.CROSSINGS do
			if crossing.patch == index and S.route[crossing.from] then
				if snap.door then
					Task.reveal(Read.middle(Read.area(snap.door, crossing.lane)))
				end
				return
			end
		end
		Camera.face({ x = patch.tile.x + 1, y = patch.tile.y + 1 })
		local crop = S.crop
		if patch.kind == "EMPTY" and crop and not Inventory.select(`{crop.name} seed`) then
			return
		end
	end
	if Objects.hover_async(loc, Player.destination()) then
		S.hovered = index
	end
end

function Task.harvest(): boolean
	local replant = not Loop.draining()
	local crop = S.crop
	local after = Task.act("Harvest", CONST.ACTION_MS, nil, function()
		if replant and crop and Inventory.select(`{crop.name} seed`) then
			Task.prehover(S.cursor)
		elseif not replant then
			Task.prehover(Task.next_index())
		end
	end)
	if not after then
		return false
	end
	if not replant and after.kind == "EMPTY" then
		Task.advance()
	end
	return true
end

function Task.cancels_planting(): boolean
	return #S.route >= CONST.CANCEL.ALWAYS_FROM or Biometrics.random_boolean(CONST.CANCEL.CHANCE)
end

function Task.plant(): boolean
	local crop = S.crop
	local can = snap.carried.wet_can
	local cancel = Task.cancels_planting()
	local after = crop
		and Task.act("Plant", CONST.ACTION_MS, `{crop.name} seed`, function()
			if can then
				Inventory.select(can)
			end
			Task.prehover(S.cursor)
		end)
	if not after then
		return false
	end
	if after.kind ~= "EMPTY" then
		stats.planted += 1
	end
	if not (can and after.kind == "DRY" and after.loc) then
		return true
	end
	if not cancel then
		Wait.until_true(CONST.ACTION_MS, function(): boolean
			return not Player.is_animating()
		end)
	end
	return Task.water_with(can, after.loc)
end

function Task.water_with(can: string, loc: Loc): boolean
	local used = false
	for _ = 1, CONST.CAN_ATTEMPTS do
		if not Inventory.select(can) then
			Log.log(NAME, `Water failed on patch {S.cursor}: couldn't select the {can}`)
			return false
		end
		used = Objects.interact(loc, "Use", false)
		if used then
			break
		end
	end
	if not used then
		Log.log(NAME, `Water failed on patch {S.cursor}: the {can} never landed on it`)
		return false
	end
	Task.prehover(Task.next_index())
	local after = Wait.patch_change(S.cursor, loc.id, CONST.ACTION_MS)
	if not after then
		return false
	end
	if after.kind == "GROWING" then
		Task.advance()
	end
	return true
end

function Task.water(): boolean
	local after = Task.act("Water", CONST.ACTION_MS, nil, function()
		Task.prehover(Task.next_index())
	end)
	if not after then
		return false
	end
	if after.kind == "GROWING" then
		Task.advance()
	end
	return true
end

function Task.clear(): boolean
	Log.log(NAME, `Clearing blighted patch {S.cursor}`)
	return Task.act("Clear", CONST.CLEAR_MS, nil, function()
		Task.prehover(S.cursor)
	end) ~= nil
end

function Task.wait(): boolean
	local patch = snap.field[S.cursor]
	local loc = patch and patch.loc
	if not loc then
		return false
	end
	if S.hovered ~= S.cursor then
		S.hovered = S.cursor
		Objects.hover(loc)
	end
	if CONFIG.antiban and S.antiban_ready and Read.slack() > CONST.ANTIBAN_SLACK_MS then
		if Antiban.do_antiban(true, false, false) then
			S.hovered = 0
			return true
		end
		Antiban.do_async_tasks("game")
	end
	Wait.patch_change(S.cursor, loc.id, Random.int(400, 900))
	return true
end

function Task.refill(): boolean
	S.hovered = 0
	local door = snap.door
	local can = snap.carried.lowest_can
	if not door or not can then
		return false
	end
	local barrel = Read.loc_at(Read.at(door, CONST.BARREL), "Water Barrel")
	if not barrel or not Task.use_on(can, barrel) then
		return false
	end
	local must = snap.carried.doses < #S.route
	local fill_all = Read.field_empty()
	local doses = Read.carried().doses
	local moved_at = time()
	Wait.until_true(snap.carried.cans * 3000 + CONST.FILL_STALL_MS, function(): boolean
		local carried = Read.carried()
		if carried.doses ~= doses then
			doses, moved_at = carried.doses, time()
		end
		if carried.lowest_can == nil or time() - moved_at > CONST.FILL_STALL_MS then
			return true
		end
		local patch = Read.patch(S.cursor)
		local needed = fill_all or (must and carried.doses < #S.route)
		return not needed and patch ~= nil and patch.kind ~= "GROWING"
	end)
	return Read.carried().doses > snap.carried.doses
end

function Task.deposit(): boolean
	S.hovered = 0
	local door = snap.door
	local before = snap.carried.fruit
	local sack = door and Read.loc_at(Read.at(door, CONST.SACK), "Sack")
	if not sack or not Task.approach(sack, "Deposit") then
		return false
	end
	if not Wait.until_true(CONST.ACTION_MS, function(): boolean
		return Read.carried().fruit == 0
	end) then
		return false
	end
	stats.deposited += before
	S.visit_deposited += before
	Log.log(NAME, `Deposited {before} fruit, {S.visit_deposited} this visit`)
	return true
end

function Task.take_seeds(): boolean
	local crop = S.crop
	if not crop then
		return false
	end
	if Chat.find_query(CONST.SEED_QUERY) then
		local amount = CONST.SEED_AMOUNTS[Random.int(1, #CONST.SEED_AMOUNTS)]
		Chat.answer_query(CONST.SEED_QUERY, amount, 1200)
		return Wait.until_true(2400, function(): boolean
			return (Read.carried().seeds[crop.name] or 0) > 0
		end)
	end
	local option = `{crop.name} seed`
	if ChatOptions.contains(option) then
		ChatOptions.select(option)
		return Chat.wait_query(CONST.SEED_QUERY, 2400)
	end
	local table_loc = Objects.nearest(CONST.SEED_TABLE, snap.me)
	if not table_loc or not Task.approach(table_loc, "Search") then
		return false
	end
	return ChatOptions.wait_option(option, false, 3000)
end

function Task.use_door(): boolean
	S.hovered = 0
	local door = snap.door
	if not door or not Task.approach(door, "Open") then
		return false
	end
	local was_inside = snap.inside
	return Wait.until_true(CONST.DOOR_MS, function(): boolean
		return Player.in_instance() ~= was_inside
			or ChatOptions.contains(CONST.FARMER_EXPERT)
			or ChatOptions.contains_continue()
	end)
end

function Task.answer_farmer(): boolean
	if ChatOptions.contains(CONST.FARMER_EXPERT) then
		Log.log(NAME, "Telling the farmer not to ask again")
		if not ChatOptions.select(CONST.FARMER_EXPERT) then
			return false
		end
	end
	for _ = 1, CONST.DIALOGUE_STEPS do
		if not ChatOptions.contains_continue() then
			break
		end
		ChatOptions.continue_chat()
	end
	return not ChatOptions.contains_continue()
end

function Task.travel(): boolean
	if Walker.distance(snap.me, CONST.FARMHOUSE) <= CONST.WALK_RANGE then
		return Walker.walk(CONST.FARMHOUSE, { near = 2 })
	end
	if S.teleported_at then
		S.blocked = "the minigame teleport didn't bring the player to the farm"
		return false
	end
	Log.log(NAME, "Teleporting to the farm")
	local ok, why = Minigames.teleport(CONST.TELEPORT)
	if not ok then
		S.blocked = `couldn't teleport to the farm: {why or "unknown reason"}`
		return false
	end
	S.teleported_at = time()
	return Wait.until_true(CONST.TELEPORT_MS, function(): boolean
		local position = game_state().position
		return position ~= nil and Walker.distance(position, CONST.FARMHOUSE) <= CONST.WALK_RANGE
	end)
end

function Game.sign_in(): boolean
	Log.log(NAME, "Logging in")
	if not Login.sign_in() then
		Log.log(NAME, "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Game.apply_settings(values: { [string]: any })
	CONFIG.max_fruit = values.max_fruit or CONFIG.max_fruit
	CONFIG.max_seeds = values.max_seeds or CONFIG.max_seeds
	CONFIG.stop_level = values.stop_level or CONFIG.stop_level
	CONFIG.stop_points = values.stop_points or CONFIG.stop_points
	CONFIG.timeouts.idle_minutes = values.idle_minutes or CONFIG.timeouts.idle_minutes
	CONFIG.antiban = values.antiban ~= false
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

function Game.check_requirements(): string?
	if (Stats.real_level("Farming") or 0) < CONST.MIN_LEVEL then
		return `Tithe Farm needs Farming level {CONST.MIN_LEVEL}`
	end
	local carried = snap.carried
	if not carried.dibber then
		return "no seed dibber in the inventory"
	end
	if not carried.spade then
		return "no spade in the inventory"
	end
	if carried.cans < CONST.MIN_CANS and not carried.gricoller then
		return `needs at least {CONST.MIN_CANS} watering cans in the inventory`
	end
	return nil
end

function Game.setup_antiban()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Farming", "Total" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
	Antiban.add_task(AntibanTasks.handle_randoms, 30 * SECOND, 0.33)
	Antiban.add_task(AntibanTasks.adjust_camera, 3 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.adjust_minimap_zoom, 13 * MINUTE, 0.33)

	Antiban.add_walk_task(AntibanTasks.adjust_camera, 2 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.small_camera_rotation, 4 * MINUTE, 0.33)

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_pitch_change, 45 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_zoom_change, 60 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_npc, 90 * SECOND, 0.4, "game")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.setup()
	while true do
		local state = game_state()
		if Read.logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		if Read.scene_loading(state) then
			sleep(100)
		else
			Game.sign_in()
		end
	end
	Biometrics.setup_player()

	local missing = Game.check_requirements()
	if missing then
		S.blocked = missing
		S.finished = true
		return
	end
	S.crop = Read.held_crop(snap.carried) or Read.best_crop()
	Log.log(NAME, `Growing {(S.crop :: Crop).name}`)

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
	local fruit = snap.carried.fruit
	if fruit > S.last_fruit then
		stats.harvested += fruit - S.last_fruit
	end
	S.last_fruit = fruit
	if snap.inside then
		local points = Read.points()
		if points then
			S.start_points = S.start_points or points
			S.total_points = points
			stats.points = points - (S.start_points :: number)
		end
	end
end

function Loop.report_counters()
	local key = `{stats.deposited}/{stats.harvested}/{stats.planted}/{stats.points}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "fruit", label = "Fruit deposited", value = stats.deposited },
		{ id = "harvested", label = "Fruit harvested", value = stats.harvested },
		{ id = "planted", label = "Seeds planted", value = stats.planted },
		{ id = "points", label = "Points", value = stats.points },
	})
end

function Loop.check_stops()
	local t = CONFIG.timeouts
	if time() - S.last_progress_at >= t.idle_minutes * 60000 then
		S.blocked = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		S.blocked = `{S.failures_in_row} failures in a row`
	end
	if S.blocked then
		Log.log(NAME, `Stuck: {S.blocked}, stopping the script`)
		S.finished = true
		return
	end
	if S.stopping then
		return
	end
	if Handoff.finishing() then
		S.stopping = "the queue asked to wrap up"
	elseif CONFIG.max_fruit > 0 and Read.fruit_in_hand() >= CONFIG.max_fruit then
		S.stopping = `{Read.fruit_in_hand()} fruit harvested`
	elseif CONFIG.max_seeds > 0 and stats.planted >= CONFIG.max_seeds then
		S.stopping = `planted {stats.planted} seeds`
	elseif CONFIG.stop_level > 0 and (Stats.real_level("Farming") or 0) >= CONFIG.stop_level then
		S.stopping = `reached Farming level {CONFIG.stop_level}`
	elseif CONFIG.stop_points > 0 and (S.total_points or 0) >= CONFIG.stop_points then
		S.stopping = `reached {S.total_points} points`
	end
	if S.stopping then
		Log.log(NAME, `Finishing up: {S.stopping}`)
	end
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	local paused = time() - S.antiban_began_at
	S.last_progress_at += paused
	S.cursor_since += paused
	S.hovered = 0
end

function Loop.hook_antiban()
	Antiban.on_start_task, Antiban.on_finish_task = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.antiban_began, Loop.antiban_ended
end

function Loop.break_due(): boolean
	return CONFIG.antiban and S.antiban_ready and Antiban.break_due()
end

function Loop.upgrade_due(): boolean
	local crop, best = S.crop, Read.best_crop()
	return crop ~= nil and best ~= nil and best.level > crop.level
end

function Loop.upgrading(): boolean
	if not Loop.upgrade_due() then
		return false
	end
	if not S.upgrade_target then
		S.upgrade_target = (S.visit_deposited // CONST.SACK_BATCH + 1) * CONST.SACK_BATCH
		Log.log(NAME, `{(Read.best_crop() :: Crop).name} unlocked, switching after {S.upgrade_target} fruit this visit`)
	end
	local planted = 0
	for _, patch in snap.field do
		if patch.kind ~= "EMPTY" then
			planted += 1
		end
	end
	return S.visit_deposited + snap.carried.fruit + planted >= (S.upgrade_target :: number)
end

function Loop.draining(): boolean
	return S.resetting or S.stopping ~= nil or Loop.break_due() or Read.seeds() == 0 or Loop.upgrading()
end

function Loop.first_cursor(): number
	for i, patch in snap.field do
		if patch.kind ~= "GROWING" then
			return i
		end
	end
	return 1
end

function Loop.outside_state(): State
	if S.stopping then
		return "DONE"
	end
	if Loop.break_due() then
		return "BREAK"
	end
	if not Read.near_farmhouse() then
		return "TRAVEL"
	end
	local held, best = Read.held_crop(snap.carried), Read.best_crop()
	if held and best and held.level < best.level then
		return "LOADING"
	end
	S.crop = held or best
	if Read.seeds() == 0 then
		return "TAKE_SEEDS"
	end
	return "ENTER"
end

function Loop.reset_state(): State
	if Read.field_empty() then
		S.resetting = false
		S.cursor = 0
		S.at_boundary = true
		Log.log(NAME, "Every patch is empty, starting over")
		return Loop.field_state()
	end
	for _ = 1, #S.route do
		local kind = snap.field[S.cursor].kind
		if kind == "GROWN" then
			return "HARVEST"
		elseif kind == "BLIGHTED" then
			return "CLEAR"
		end
		Task.advance()
	end
	return "WAIT"
end

function Loop.field_state(): State
	if S.cursor == 0 then
		S.cursor = Loop.first_cursor()
		S.cursor_since = time()
	end
	if not S.resetting then
		for _, patch in snap.field do
			if patch.kind == "BLIGHTED" then
				S.resetting = true
				Log.log(
					NAME,
					`A plant died on patch {patch.index}: harvesting without replanting until every patch is empty`
				)
				break
			end
		end
	end
	if S.resetting then
		return Loop.reset_state()
	end
	local draining = Loop.draining()

	if Read.field_empty() then
		if snap.carried.fruit > 0 then
			return "DEPOSIT"
		end
		if snap.carried.lowest_can then
			return "REFILL"
		end
		if draining then
			if S.stopping or Read.seeds() == 0 or Loop.upgrade_due() then
				return "LEAVE"
			end
			return "BREAK"
		end
	end

	if S.at_boundary then
		local carried = snap.carried
		local idle = math.min(Read.ready_in(), Read.slack() - CONST.SLACK_MARGIN_MS)
		if carried.fruit > 0 and idle > CONST.DEPOSIT_MS then
			return "DEPOSIT"
		end
		local must = carried.doses < #S.route
		local want = not draining and idle > CONST.BARREL_WALK_MS + CONST.FILL_MS_PER_CAN
		if carried.lowest_can and (must or want) then
			return "REFILL"
		end
	end

	for _ = 1, #S.route do
		local patch = snap.field[S.cursor]
		if not (draining and patch.kind == "EMPTY") then
			break
		end
		Task.advance()
	end

	local patch = snap.field[S.cursor]
	if patch.kind == "GROWN" then
		return "HARVEST"
	elseif patch.kind == "EMPTY" then
		return "PLANT"
	elseif patch.kind == "DRY" then
		return "WATER"
	elseif patch.kind == "BLIGHTED" then
		return "CLEAR"
	end
	if Read.dry_after(S.cursor) then
		Task.advance()
		return Loop.field_state()
	end
	if time() - math.max(S.cursor_since, S.since[S.cursor] or 0) > CONST.WAIT_LIMIT_MS then
		Log.log(NAME, `Patch {S.cursor} hasn't changed for too long, moving on`)
		Task.advance()
		return Loop.field_state()
	end
	return "WAIT"
end

function Loop.get_state(): State
	local s = game_state()
	if not Read.logged_in(s) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	if ChatOptions.contains(CONST.FARMER_EXPERT) then
		return "ANSWER"
	end
	local speech = ChatOptions.speech()
	if speech and speech.name == CONST.FARMER then
		return "ANSWER"
	end
	if not snap.inside then
		return Loop.outside_state()
	end
	return Loop.field_state()
end

local function run(task: () -> boolean): () -> ()
	return function()
		if task() then
			S.failures_in_row = 0
		else
			S.failures_in_row += 1
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
	TRAVEL = run(Task.travel),
	TAKE_SEEDS = run(Task.take_seeds),
	ENTER = run(Task.use_door),
	ANSWER = run(Task.answer_farmer),
	HARVEST = run(Task.harvest),
	PLANT = run(Task.plant),
	WATER = run(Task.water),
	CLEAR = run(Task.clear),
	WAIT = run(Task.wait),
	REFILL = run(Task.refill),
	DEPOSIT = run(Task.deposit),
	BREAK = function()
		S.cursor = 0
		S.at_boundary = true
		if not Antiban.do_antiban(false, true, true) then
			sleep(Random.int(300, 700))
		end
	end,
	LEAVE = run(function(): boolean
		S.cursor = 0
		S.at_boundary = true
		return Task.use_door()
	end),
	DONE = function()
		S.finished = true
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

function Loop.leave_farm()
	if not (Read.logged_in(game_state()) and Player.in_instance()) then
		return
	end
	local me = Walker.position()
	local door = me and Read.door(Host.locs() or {}, me)
	if door and Task.approach(door, "Open") then
		Wait.until_true(CONST.DOOR_MS, function(): boolean
			return not Player.in_instance()
		end)
	end
end

function Loop.wrap_up()
	Loop.leave_farm()
	local settled, why = Handoff.settle()
	if not settled then
		error(`Couldn't leave the account settled: {why}`, 0)
	end
	if S.blocked then
		Handoff.blocked(S.blocked)
	else
		Handoff.done(S.stopping)
	end
end

function Loop.run()
	local values = Host.settings()
	Game.apply_settings(values)
	S.route = build_route(tonumber(values.patches) or 20)
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban()

	local last_logged = ""
	while not S.finished do
		Game.poll_settings()
		local state = Loop.get_state()
		Loop.check_stops()
		if S.finished then
			break
		end
		local label = if S.cursor > 0 and snap.inside then `{state} {S.cursor}` else state
		if label ~= last_logged then
			Log.log(NAME, label)
			last_logged = label
		end
		close_stray()
		Handler.states[state]()
		sleep(Random.int(60, 140))
	end
	Loop.wrap_up()
	Log.log(NAME, "Done")
end

Loop.run()
