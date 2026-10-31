--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local widget = Host.widget
local npcs = Host.npcs
local locs = Host.locs
local item_container = Host.item_container
local item_name = Host.item_name
local varbit = Host.varbit
local chat_messages = Host.chat_messages
local sleep = Host.sleep
local time = Host.time
type Npc = Host.Npc
type Loc = Host.Loc
type Tile = Host.Tile
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Position = require("@lib/main/position")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Ticks = require("@lib/utils/ticks")
local Varbits = require("@lib/main/varbits")
local Walker = require("@lib/main/walker")
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local CONST = {
	-- NPCs: north and south side single spot ids
	SINGLE_SPOTS = { [10565] = true, [10568] = true },
	DOUBLE_SPOT = 10569,
	-- measured double spot lifetime in ticks
	DOUBLE_LIFE_TICKS = 40,
	DOUBLE_LIFE_MAX_TICKS = 44,
	-- skip double spots with fewer ticks left
	DOUBLE_MIN_TICKS_LEFT = 8,
	FIRE = 8643,
	STORM_CLOUD = 10580,
	LIGHTNING_STRIKE = 10581,
	INACTIVE_POOL = 10570,
	SPIRIT_POOL = 10571,

	-- tether the player is tied to, 0 when none
	TETHERED_VARBIT = 11895,
	LOBBY = 687,
	LOBBY_PLAYERS = 3,
	LOBBY_DEPARTURE = 4,

	-- mast ids (intact, damaged) per ship
	WEST_MASTS = { [41352] = true, [40996] = true },
	EAST_MASTS = { [41353] = true, [40997] = true },

	-- the last totals sent to the loader's XP tracker
	REPORT = { counters_key = "" },

	-- how long a cannon shock stuns us
	STUN_MS = 5000,

	-- radius around our mast that counts as home
	HOME_RADIUS = 8,

	FIRE_REACH = 1,
	STRIKE_REACH = 2,
	-- cloud animation ids
	CLOUD_GROWING = 8876,
	CLOUD_CHARGING = 8877,
	CLOUD_ATTACK = 8878,
	-- tick each growing cloud starts charging at, by index
	GROWING_TICKS_MIN = 3,
	GROWING_TICKS_MAX = 8,

	-- poll interval of waits
	POLL_MS = 50,
	-- grace before a click's walk or animation starts
	START_GRACE_MS = 2 * Ticks.MS,
	-- idle time before an activity is over
	IDLE_MS = {
		tether = 12000,
	},
	DEFAULT_IDLE_MS = 2 * Ticks.MS,

	-- target states for an NPC or loc
	TARGET_NPC = 0,
	TARGET_LOC = 1,

	BLOCKED_MS = 20000,
	-- time tethered with no wave before it's a stray tether
	STRAY_MS = 600,
	-- max pump distance to refill
	PUMP_RANGE = 6,

	-- dock where the boat's ladder is
	DOCK = { x = 3139, y = 2838 },
	-- map squares (64x64) of the overworld: the boat's square has only ocean and the boat, the port is the next east
	BOAT_SQUARE = { x = 48, y = 44 },
	PORT_MIN_SQUARE_X = 49,
	-- ticks to wait for the boat after a ladder click
	CLIMB_TICKS = 6,

	-- the map chunk (47, 44) every Tempoross instance is copied from, by id
	TEMPOROSS_CHUNK_ID = Position.Chunk.new(47, 44):id(),
	-- async antiban tasks only while one of these (or waiting)
	TINY_ACTIVITIES = { fish = true, cook = true, load = true, attack = true },

	-- after the game: leave via the crew or wait to be sent out
	LEAVE_WAIT_MS = 20000,
	-- crew name prefixes
	CREW_TITLES = { "Captain", "First Mate" },

	-- how close to the pool counts as the pier
	PIER_RANGE = 4,
	-- Tempoross is in its second phase below this essence
	PHASE_TWO_ESSENCE = 50,
}

local Read, Geo, Chat, Ship, Hazard, Route, Doing, Task, Game, Loop, Handler =
	{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}

local CONFIG = {
	world = 422,
	solo = false,
	boarding = { min_players = 14, players_variance = 0.1, min_time = 10 },
	barehand = true,
	buckets = 3,
	cook = { -- fish to cook unless double spot
		enabled = true,
		min = 5,
		max = 7,
		min_storm = 3,
	},

	load = { intensity = 60, energy = 25 },
	-- walk to the pier when Tempoross' energy is falling and down to this (rolled per game)
	pier = { min_energy = 2, max_energy = 4 },
	max_games = 0,
	-- the script stops when stuck: no xp, fish or cooked fish for idle_minutes, this many losses in a row
	timeouts = { idle_minutes = 5, max_losses = 4 },
	antiban = true,
	antiban_departure = 30,
}

-- Items
local Items = {
	RAW_FISH = 25564,
	COOKED_FISH = 25565,
	CRYSTAL_FISH = 25566,
	BUCKET = 1925,
	WATER = 1929,
	ROPE = 954,
	HAMMER = 2347,
	IMCANDO_HAMMER = 25644,
}

-- game HUD (437) and dock lobby overlay (687)
local HUD = {
	GROUP = 437,
	POINTS = 25,
	ENERGY = 35,
	ESSENCE = 45,
	INTENSITY = 55,
}

---------------------------------------------------------------------------------------------------

local stats = { games = 0, wins = 0, losses = 0, points = 0, permits = 0 }

-- mutable state of the run
type RunState = {
	-- HUD percents read this pass, by child
	hud_cache: { [number]: number | false },
	-- tick each double spot was first seen at, by "x,y"
	double_first_seen: { [string]: number },
	-- whether we are on the Tempoross island this pass: the instance is a copy of Tempoross' map chunk
	in_game: boolean,
	-- whether the game HUD.GROUP is up this pass: the game itself is running (the voyage and the end have none)
	hud_up: boolean,
	activity: Activity?,
	chat_uid: number,
	side: Side?,
	growing_due: { [number]: number },
	-- logs routes much longer than the straight line (the walks around the island)
	last_detour: string,
	item_names_cache: { [number]: string },
	worn_cache: { number }?,
	blocked_since: { [string]: number },
	-- where the last dodge walks to
	dodging_to: Tile?,
	stray_since: number?,
	-- which way Tempoross' energy is moving: it falls from 100 to 0, then rises back to 100
	energy_dir: "up" | "down",
	last_energy: number?,
	cook_fish_threshold: number,
	pier_energy: number,
	-- status line every 20 s
	last_status: number,
	antiban_ready: boolean,
	leaving_since: number?,
	leave_by_crew: boolean,
	required_players: number,
	-- states whose handler failed: get_state skips them once so it doesn't repeat them forever
	skip: { [State]: boolean },
	finished: boolean,
	-- stuck detection, see CONFIG.timeouts
	last_progress_at: number,
	losses_in_row: number,
	last_xp: number,
	last_fish: number,
	last_cooked: number,
	-- antiban tasks, breaks and sleeps don't count towards the timeouts
	antiban_began_at: number,
	was_in_game: boolean,
	-- a game was played on this visit to the island, so a missing HUD.GROUP means it ended
	played_here: boolean,
	game_started: number,
	click_continue_dialogue: boolean?,
	end_dialogue: boolean,
	pier_logged: boolean,
}

local S: RunState = {
	hud_cache = {},
	double_first_seen = {},
	in_game = false,
	hud_up = false,
	chat_uid = -1,
	growing_due = {},
	last_detour = "",
	item_names_cache = {},
	blocked_since = {},
	energy_dir = "up",
	cook_fish_threshold = Random.int(CONFIG.cook.min, CONFIG.cook.max),
	pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy),
	last_status = 0,
	antiban_ready = false,
	leave_by_crew = true,
	required_players = 0,
	skip = {},
	finished = false,
	last_progress_at = time(),
	losses_in_row = 0,
	last_xp = -1,
	last_fish = 0,
	last_cooked = 0,
	antiban_began_at = 0,
	was_in_game = false,
	played_here = false,
	game_started = 0,
	end_dialogue = false,
	pier_logged = false,
}

---------------------------------------------------------------------------------------------------
-- Snapshot of what the client shows, read once per loop

type Snapshot = {
	state: ClientState,
	me: Tile,
	npcs: { Npc },
	locs: { Loc }?,
	inv: { [number]: number },
	free: number,
	tick: number,
	-- tied to a mast or totem
	tethered: boolean,
	busy: boolean,
}

local snap: Snapshot = nil :: any

function Read.widget_text(group: number, child: number): string?
	local w = widget(group, child)
	if w == nil or w.hidden then
		return nil
	end
	return w.text
end

function Read.parse_hud_percent(child: number): number?
	local text = Read.widget_text(HUD.GROUP, child)
	local n = text and string.match(text, "(%d+)%%")
	return if n then tonumber(n) else nil
end

function Read.hud_percent(child: number): number?
	local v = S.hud_cache[child]
	if v == nil then
		v = Read.parse_hud_percent(child) or false
		S.hud_cache[child] = v
	end
	if v then
		return v :: number
	end
	return nil
end

-- falls back to wall clock ticks
function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // Ticks.MS
end

function Read.read_inventory(): ({ [number]: number }, number)
	local counts: { [number]: number } = {}
	local used = 0
	for _, slot in ipairs(item_container(Inventory.CONTAINER) or {}) do
		if slot.id >= 0 then
			counts[slot.id] = (counts[slot.id] or 0) + 1
			used += 1
		end
	end
	return counts, Inventory.SIZE - used
end

-- NPC names without colour tags
function Read.read_npcs(): { Npc }?
	local list = npcs()
	if list then
		for _, n in ipairs(list) do
			n.name = Npcs.clean_name(n.name)
		end
	end
	return list
end

-- tracks double spots appearing and disappearing
function Read.track_doubles(list: { Npc }, me: Tile, now: number)
	local present: { [string]: boolean } = {}
	for _, n in ipairs(list) do
		if n.id == CONST.DOUBLE_SPOT then
			local key = `{n.x},{n.y}`
			present[key] = true
			local since = S.double_first_seen[key]
			if since == nil or now - since > CONST.DOUBLE_LIFE_MAX_TICKS then
				S.double_first_seen[key] = now
			end
		end
	end
	for key, _ in pairs(S.double_first_seen) do
		if not present[key] then
			local x, y = string.match(key, "(-?%d+),(-?%d+)")
			if math.max(math.abs((tonumber(x) :: number) - me.x), math.abs((tonumber(y) :: number) - me.y)) <= 10 then
				S.double_first_seen[key] = nil
			end
		end
	end
end

-- ticks left, a spot never seen appear counts as new
function Read.double_ticks_left(n: Npc, now: number): number
	local since = S.double_first_seen[`{n.x},{n.y}`]
	if since == nil or now - since > CONST.DOUBLE_LIFE_MAX_TICKS then
		return CONST.DOUBLE_LIFE_TICKS
	end
	return CONST.DOUBLE_LIFE_TICKS - (now - since)
end

function Read.refresh_snapshot(state: ClientState): boolean
	table.clear(S.hud_cache)
	if state.position == nil then
		return false
	end
	local inv, free = Read.read_inventory()
	local tick = Read.current_tick(state)
	snap = {
		state = state,
		me = { x = state.position.x, y = state.position.y },
		npcs = Read.read_npcs() or {},
		locs = nil,
		inv = inv,
		free = free,
		tick = tick,
		tethered = (varbit(CONST.TETHERED_VARBIT) or 0) ~= 0,
		busy = (varbit(Varbits.BUSY) or 0) ~= 0,
	}
	Read.track_doubles(snap.npcs, snap.me, tick)
	return true
end

-- locs are a big read: lazy, once per loop
function Read.all_locs(): { Loc }
	if snap.locs == nil then
		snap.locs = locs() or {}
	end
	return snap.locs :: { Loc }
end

function Read.item_count(...: number): number
	local n = 0
	for i = 1, select("#", ...) do
		n += snap.inv[(select(i, ...))] or 0
	end
	return n
end

function Read.fish_count(): number
	return Read.item_count(Items.RAW_FISH, Items.COOKED_FISH, Items.CRYSTAL_FISH)
end

function Geo.distance(a: Tile, b: Tile): number
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

function Geo.loc_distance(loc: Loc, from: Tile): number
	return Objects.distance(loc, from)
end

function Read.npcs_with(id: number): { Npc }
	local found: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.id == id then
			table.insert(found, n)
		end
	end
	return found
end

function Geo.nearest_npc(list: { Npc }, from: Tile, accept: ((Npc) -> boolean)?): Npc?
	local best, best_d = nil, math.huge
	for _, n in ipairs(list) do
		local d = Geo.distance(n, from)
		if d < best_d and (accept == nil or accept(n)) then
			best, best_d = n, d
		end
	end
	return best
end

function Read.locs_named(names: { string }): { Loc }
	local found: { Loc } = {}
	for _, l in ipairs(Read.all_locs()) do
		if l.name and l.clickable and table.find(names, l.name) then
			table.insert(found, l)
		end
	end
	return found
end

function Geo.nearest_loc(list: { Loc }, from: Tile, accept: ((Loc) -> boolean)?): Loc?
	local best, best_d = nil, math.huge
	for _, l in ipairs(list) do
		local d = Geo.loc_distance(l, from)
		if d < best_d and (accept == nil or accept(l)) then
			best, best_d = l, d
		end
	end
	return best
end

-- the current activity
type Activity = {
	kind: string,
	npc: Npc?,
	loc: Loc?,
	last_progress_ms: number,
	double: boolean,
	last_signature: string,
	-- player tile as "x,y"; moving counts as progress
	last_tile: string,
}

---------------------------------------------------------------------------------------------------
-- Chat events

local events = {
	wave_warning_at = nil :: number?, -- last wave warning not yet handled
	tethered = false,
	-- last wave hit time
	wave_hit_at = nil :: number?,
	-- "won" or nil, a closed HUD.GROUP without it is a loss
	game_result = nil :: string?,
	must_untether = false,
	-- crate to avoid after a cannon surge
	shocked_crate = nil :: Npc?,
	shocked_until = 0,
	-- fire that stopped a walk, doused next
	fire_in_way = nil :: Npc?,
	-- stun end time (see CONST.STUN_MS)
	stunned_until = 0,
}

function Chat.skip_old_messages()
	for _, m in ipairs(chat_messages() or {}) do
		S.chat_uid = math.max(S.chat_uid, m.uid)
	end
end

function Chat.contains(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

function Chat.read_chat()
	for _, m in ipairs(chat_messages() or {}) do
		if m.uid > S.chat_uid then
			S.chat_uid = m.uid
			-- strip colour tags and markers
			local text = string.gsub(string.gsub(m.text, "<[^>]*>", ""), "@[%w_]+@", "")
			-- only game messages
			if m.kind == 0 or m.kind == 105 or m.kind == 115 then
				if Chat.contains(text, "colossal wave closes in") then
					events.wave_warning_at = time() - m.age
					events.tethered = false
					Log.log("Tempoross", "Wave incoming")
				elseif Chat.contains(text, "securely tether yourself") then
					events.tethered = true
				elseif
					Chat.contains(text, "washes over you")
					or Chat.contains(text, "slams into you")
					or Chat.contains(text, "to the waves")
				then
					if events.wave_warning_at then
						Log.log(
							"Tempoross",
							if Chat.contains(text, "washes over") then "Wave passed, tethered" else "Wave hit us"
						)
					end
					if S.activity and (S.activity :: Activity).kind == "tether" then
						S.activity = nil
					end
					events.wave_warning_at = nil
					events.tethered = false
					events.wave_hit_at = time() - m.age
				elseif Chat.contains(text, "untether yourself from") then
					events.tethered = false
				elseif Chat.contains(text, "untether") then
					events.must_untether = true
				elseif
					Chat.contains(text, "surges towards a nearby cannon")
					or Chat.contains(text, "arcs from the cannon into you")
				then
					if Chat.contains(text, "arcs from the cannon into you") then
						events.stunned_until = time() - m.age + CONST.STUN_MS
						Log.log("Tempoross", "Stunned by the cannon")
					end
					if S.activity and (S.activity :: Activity).kind == "load" then
						Log.log("Tempoross", "Our cannon is being electrified, switching crates")
						events.shocked_crate = (S.activity :: Activity).npc
						events.shocked_until = time() + 15000
						S.activity = nil
					end
				elseif Chat.contains(text, "clouds roll in") then
					Log.log("Tempoross", "Storm brewing")
				elseif Chat.contains(text, "skies clear as Tempoross retreats") then
					events.game_result = "won"
				elseif Chat.contains(text, "Points:") and Chat.contains(text, "Personal best") then
					local n = string.match((string.gsub(text, ",", "")), "Points: (%d+)")
					if n then
						stats.points += tonumber(n) :: number
					end
				elseif Chat.contains(text, "Reward permits:") then
					local n = string.match(text, "Reward permits: (%d+)")
					if n then
						stats.permits += tonumber(n) :: number
					end
				elseif Chat.contains(text, "You lose") then
					Log.log("Tempoross", "Lost items:", text)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Sides: our ship and everything its crew uses

type Side = {
	name: string,
	mast: Loc,
	totem: Loc,
	shrine: Loc,
}

-- our ship is the one with the nearest mast
function Ship.find_side(): Side?
	local masts = Read.locs_named({ "Mast", "Damaged mast" })
	local mast = Geo.nearest_loc(masts, snap.me)
	if mast == nil then
		return nil
	end
	local west = CONST.WEST_MASTS[mast.id] == true
	if not west and not CONST.EAST_MASTS[mast.id] then
		-- unknown ids: the western ship is west
		west = true
		for _, other in ipairs(masts) do
			if other.x < mast.x then
				west = false
			end
		end
	end
	local totems = Read.locs_named({ "Totem pole", "Damaged totem pole" })
	local totem: Loc? = nil
	for _, t in ipairs(totems) do
		if (west and t.y > mast.y) or (not west and t.y < mast.y) then
			totem = t
		end
	end
	if totem == nil then
		return nil
	end
	local shrine = Geo.nearest_loc(Read.locs_named({ "Shrine" }), totem :: Loc)
	if shrine == nil then
		return nil
	end
	return { name = if west then "west" else "east", mast = mast, totem = totem :: Loc, shrine = shrine :: Loc }
end

-- mast and totem change id when damaged
function Read.loc_at(tile: Tile, names: { string }): Loc?
	for _, l in ipairs(Read.locs_named(names)) do
		if l.x == tile.x and l.y == tile.y then
			return l
		end
	end
	return nil
end

function Ship.our_mast(): Loc?
	return S.side and Read.loc_at((S.side :: Side).mast, { "Mast", "Damaged mast" })
end

function Ship.at_home(tile: Tile): boolean
	return S.side ~= nil and Geo.distance(tile, (S.side :: Side).mast) <= CONST.HOME_RADIUS
end

function Ship.our_totem(): Loc?
	return S.side and Read.loc_at((S.side :: Side).totem, { "Totem pole", "Damaged totem pole" })
end

---------------------------------------------------------------------------------------------------
-- Hazards

function Hazard.fire_npcs(): { Npc }
	return Read.npcs_with(CONST.FIRE)
end

-- starts timers for growing clouds, forgets the rest
function Hazard.watch_clouds()
	local now = snap.tick
	local seen: { [number]: boolean } = {}
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.STORM_CLOUD and n.animation == CONST.CLOUD_GROWING then
			seen[n.index] = true
			if S.growing_due[n.index] == nil then
				-- range excludes its upper bound
				local delay = Random.range(CONST.GROWING_TICKS_MIN, CONST.GROWING_TICKS_MAX + 1)
				S.growing_due[n.index] = now + delay
				Log.log("Tempoross", `Storm cloud at {n.x},{n.y} growing, charging in {delay} ticks`)
			end
		end
	end
	for index in pairs(S.growing_due) do
		if not seen[index] then
			S.growing_due[index] = nil
		end
	end
end

-- charging, rushing, or growing past its timer
function Hazard.is_striking(n: Npc): boolean
	if n.animation == CONST.CLOUD_CHARGING or n.animation == CONST.CLOUD_ATTACK then
		return true
	end
	local due = S.growing_due[n.index]
	return due ~= nil and snap.tick >= due
end

-- whether tile is in the cloud's 2x2 square, widened by `more`
function Hazard.in_cloud_square(n: Npc, tile: Tile, more: number): boolean
	local dx = math.max(n.x - 1 - tile.x, tile.x - n.x, 0)
	local dy = math.max(n.y - 1 - tile.y, tile.y - n.y, 0)
	return math.max(dx, dy) <= more
end

-- nearest hazard threatening a tile, widened by `extra`
function Hazard.hazard_at(tile: Tile, extra: number?): Npc?
	local more = extra or 0
	local best, best_d = nil, math.huge
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.STORM_CLOUD then
			if Hazard.is_striking(n) and Hazard.in_cloud_square(n, tile, more) then
				return n
			end
		else
			local reach = if n.id == CONST.FIRE
				then CONST.FIRE_REACH
				elseif n.id == CONST.LIGHTNING_STRIKE then CONST.STRIKE_REACH
				else nil
			if reach then
				local d = Geo.distance(n, tile)
				if d <= reach + more and d < best_d then
					best, best_d = n, d
				end
			end
		end
	end
	return best
end

function Hazard.fire_near(tile: Tile, range: number): Npc?
	return Geo.nearest_npc(Hazard.fire_npcs(), tile, function(n)
		return Geo.distance(n, tile) <= range
	end)
end

function Hazard.describe_hazard(n: Npc): string
	return `{if n.id == CONST.FIRE
		then "fire"
		elseif n.id == CONST.LIGHTNING_STRIKE then "lightning strike"
		else "storm cloud"} at {n.x},{n.y}`
end

-- sleeps in polls; true when stopped early or a hazard threatens
function Route.sleep_watching(ms: number, at: Tile?, should_stop: (() -> boolean)?): boolean
	local deadline = time() + ms
	repeat
		-- sleep takes an integer
		sleep(math.floor(math.max(1, math.min(CONST.POLL_MS, deadline - time()))))
		local s = game_state()
		if s.position then
			snap.me = { x = s.position.x, y = s.position.y }
		end
		snap.tick = Read.current_tick(s)
		snap.npcs = Read.read_npcs() or snap.npcs
		Hazard.watch_clouds()
		if should_stop then
			if should_stop() then
				return true
			end
		elseif Hazard.hazard_at(at or snap.me, if at then 1 else 0) then
			return true
		end
	until time() >= deadline
	return false
end

-- route tiles the game walks to a click on `to`
function Route.route_to(to: Tile, from: Tile?): { Tile }?
	local route = Walker.route(to, from or snap.me)
	return route and route.tiles
end

function Route.log_detour(what: string, from: Tile, to: Tile, tiles: { Tile }?)
	if tiles == nil or #tiles == 0 then
		local key = `{what}:{from.x},{from.y}:none`
		if key ~= S.last_detour then
			S.last_detour = key
			Log.log("Tempoross", `   Route to {what} ({to.x},{to.y}) from {from.x},{from.y}: none`)
		end
		return
	end
	local steps = #tiles - 1
	local straight = Geo.distance(from, to)
	local last = tiles[#tiles]
	local partial = last.x ~= to.x or last.y ~= to.y
	if steps <= straight * 1.5 + 6 and not partial then
		return
	end
	local key = `{what}:{from.x},{from.y}:{last.x},{last.y}:{steps}`
	if key == S.last_detour then
		return
	end
	S.last_detour = key
	local via = {}
	for i = 1, 4 do
		local t = tiles[math.max(1, math.floor(#tiles * i / 5))]
		table.insert(via, `{t.x},{t.y}`)
	end
	Log.log(
		"Tempoross",
		`   Detour to {what} ({to.x},{to.y}) from {from.x},{from.y}: {steps} steps for {straight} straight, ends {last.x},{last.y}{if partial
			then " (short of target)"
			else ""}, via {table.concat(via, " ")}`
	)
end

-- first fire burning a route tile, except `ignore`
function Route.first_fire(tiles: { Tile }, ignore: Npc?): Npc?
	local all = Hazard.fire_npcs()
	if #all == 0 then
		return nil
	end
	for _, t in ipairs(tiles) do
		local fire = Geo.nearest_npc(all, t, function(n)
			return Geo.distance(n, t) <= CONST.FIRE_REACH and (ignore == nil or n.index ~= (ignore :: Npc).index)
		end)
		if fire then
			return fire
		end
	end
	return nil
end

-- whether a route avoids fires and strikes
function Route.safe_route(tiles: { Tile }, count_fires: boolean?): boolean
	for _, n in ipairs(snap.npcs) do
		local reach = if n.id == CONST.FIRE
			then (if count_fires == false then nil else CONST.FIRE_REACH)
			elseif n.id == CONST.LIGHTNING_STRIKE then CONST.FIRE_REACH
			else nil
		if reach then
			local limit = math.min(reach + 1, Geo.distance(n, snap.me))
			for i = 2, #tiles do
				if Geo.distance(n, tiles[i]) < limit then
					return false
				end
			end
		end
	end
	return true
end

-- steps of the game's route, huge if none
function Route.walk_steps(to: Tile, from: Tile?): number
	local tiles = Route.route_to(to, from)
	if tiles == nil then
		return math.huge
	end
	return #tiles - 1
end

function Geo.to_tile(t: { x: number, y: number }): Tile
	return { x = t.x, y = t.y }
end

-- nearest by route steps, by straight line without routes
function Geo.nearest_walk<T>(list: { T }, from: Tile, to: (T) -> Tile, accept: ((T) -> boolean)?): T?
	local candidates: { { item: T, straight: number } } = {}
	for _, item in ipairs(list) do
		if accept == nil or accept(item) then
			table.insert(candidates, { item = item, straight = Geo.distance(to(item), from) })
		end
	end
	table.sort(candidates, function(a: { item: T, straight: number }, b: { item: T, straight: number }): boolean
		return a.straight < b.straight
	end)
	local best: T? = nil
	local best_steps = math.huge
	for _, c in ipairs(candidates) do
		if c.straight >= best_steps then
			break
		end
		local steps = Route.walk_steps(to(c.item), from)
		if steps < best_steps then
			best, best_steps = c.item, steps
		end
	end
	if best == nil and candidates[1] then
		return candidates[1].item
	end
	return best
end

-- where the route ends
function Route.route_end(to: Tile): Tile
	local tiles = Route.route_to(to)
	return if tiles and #tiles > 0 then tiles[#tiles] else to
end

---------------------------------------------------------------------------------------------------
-- Tools

function Read.item_name_lower(id: number): string
	local cached = S.item_names_cache[id]
	if cached == nil then
		cached = string.lower(item_name(id) or "")
		S.item_names_cache[id] = cached
	end
	return cached
end

function Read.worn_ids(): { number }
	if S.worn_cache == nil then
		local ids = {}
		for _, slot in pairs(Wornitems.worn() or {}) do
			table.insert(ids, slot.id)
		end
		S.worn_cache = ids
	end
	return S.worn_cache :: { number }
end

function Read.has_harpoon(): boolean
	if CONFIG.barehand then
		return true
	end
	local function is_harpoon(id: number): boolean
		local name = Read.item_name_lower(id)
		return Chat.contains(name, "harpoon") and not Chat.contains(name, "harpoonfish")
	end
	for id in pairs(snap.inv) do
		if is_harpoon(id) then
			return true
		end
	end
	for _, id in ipairs(Read.worn_ids()) do
		if is_harpoon(id) then
			return true
		end
	end
	return false
end

-- full Spirit angler outfit needs no rope
function Read.needs_rope(): boolean
	local pieces = 0
	for _, id in ipairs(Read.worn_ids()) do
		if Chat.contains(Read.item_name_lower(id), "spirit angler") then
			pieces += 1
		end
	end
	return pieces < 4
end

function Read.has_rope(): boolean
	return Read.item_count(Items.ROPE) > 0 or not Read.needs_rope()
end

function Read.has_hammer(): boolean
	return Read.item_count(Items.HAMMER, Items.IMCANDO_HAMMER) > 0
		or table.find(Read.worn_ids(), Items.IMCANDO_HAMMER) ~= nil
end

---------------------------------------------------------------------------------------------------
-- Interacting

function Read.progress_signature(): string
	return `{Read.item_count(Items.RAW_FISH)}/{Read.item_count(Items.COOKED_FISH)}/{Read.fish_count()}/{Read.item_count(
		Items.WATER
	)}/{Read.item_count(Items.BUCKET)}/{Read.hud_percent(HUD.ESSENCE) or -1}`
end

function Doing.begin_activity(kind: string, npc: Npc?, loc: Loc?, double: boolean?)
	S.activity = {
		kind = kind,
		npc = npc,
		loc = loc,
		last_progress_ms = time() + (if kind == "tether" then 0 else CONST.START_GRACE_MS),
		double = double == true,
		last_signature = Read.progress_signature(),
		last_tile = `{snap.me.x},{snap.me.y}`,
	}
	Log.log(
		"Tempoross",
		"->",
		kind,
		if npc then `{npc.name} at {npc.x},{npc.y}` elseif loc then `{loc.name} at {loc.x},{loc.y}` else ""
	)
end

function Doing.clear_activity()
	S.activity = nil
end

-- whether the player is working; nil if unreadable
function Doing.player_is_working(kind: string): boolean?
	local me = Host.game_state().player_name
	local mine: Host.PlayerInfo? = nil
	for _, p in ipairs(Host.players() or {}) do
		if p.name == me then
			mine = p
			break
		end
	end
	if mine == nil then
		return nil
	end
	local p = mine :: Host.PlayerInfo
	if p.animation == -1 then
		return false
	end
	if kind == "fish" or kind == "load" or kind == "attack" then
		return p.target_state == CONST.TARGET_NPC or p.target_state == CONST.TARGET_LOC
	end
	return true
end

function Doing.is_doing(kind: string): boolean
	return S.activity ~= nil and (S.activity :: Activity).kind == kind
end

-- keeps the activity while it progresses
function Doing.check_activity()
	local a = S.activity
	if a == nil then
		return
	end
	-- keep the inventory tab open to watch it
	if a.kind == "fish" or a.kind == "cook" or a.kind == "load" or a.kind == "pump" then
		Inventory.open()
	end
	-- progress: inventory or HUD.GROUP changed, or the player moved
	local sig = Read.progress_signature()
	local at = `{snap.me.x},{snap.me.y}`
	if sig ~= a.last_signature or at ~= a.last_tile then
		a.last_signature = sig
		a.last_tile = at
		a.last_progress_ms = time()
	end
	-- filling is done once no empty bucket is left
	if a.kind == "pump" and Read.item_count(Items.BUCKET) == 0 then
		S.activity = nil
		return
	end
	-- repair is done once the loc isn't damaged
	if a.kind == "repair" and a.loc then
		local now = Read.loc_at(a.loc :: Loc, { "Mast", "Damaged mast", "Totem pole", "Damaged totem pole" })
		if now == nil or not Chat.contains(now.name or "", "Damaged") then
			S.activity = nil
			return
		end
	end
	-- animating counts as progress while it can continue
	local can_go = (a.kind ~= "fish" or snap.free > 0)
		and (a.kind ~= "cook" or Read.item_count(Items.RAW_FISH) > 0)
		and (a.kind ~= "load" or Read.item_count(Items.COOKED_FISH) > 0)
	if not can_go and (a.kind == "cook" or a.kind == "load") then
		S.activity = nil
		return
	end
	if can_go and a.kind ~= "tether" and Doing.player_is_working(a.kind) then
		a.last_progress_ms = time()
	end
	if a.npc then
		local now = Npcs.refresh(a.npc :: Npc)
		if now == nil or now.id ~= (a.npc :: Npc).id then
			Log.log("Tempoross", "   Target gone")
			S.activity = nil
			return
		end
	end
	if time() - a.last_progress_ms > (CONST.IDLE_MS[a.kind] or CONST.DEFAULT_IDLE_MS) then
		S.activity = nil
	end
end

function Read.menu_text(): string
	local parts = {}
	for _, e in ipairs(Minimenu.entries() or {}) do
		table.insert(parts, Minimenu.text(e))
	end
	return table.concat(parts, ", ")
end

-- options for checking the route before a click
type WayOptions = {
	avoid: boolean?,
	ignore: Npc?,
	-- go whatever is in the way
	urgent: boolean?,
}

function Route.clear_route(target: Tile, what: string, opts: WayOptions?): boolean
	local o: WayOptions = opts or {}
	local tiles = Route.route_to(target)
	Route.log_detour(what, snap.me, target, tiles)
	if tiles == nil or #tiles == 0 then
		return true
	end
	-- avoids two fires dousing each other forever
	local fire = if o.ignore then nil else Route.first_fire(tiles, o.ignore)
	if fire then
		local f = fire :: Npc
		if Read.item_count(Items.WATER) > 0 and not o.urgent then
			Log.log("Tempoross", `   Fire at {f.x},{f.y} on the way to {what}, putting it out first`)
			Hazard.douse(f)
			return false
		end
		local since = S.blocked_since[what]
		if since == nil or time() - since > 2 * CONST.BLOCKED_MS then
			since = time()
			S.blocked_since[what] = since
		end
		if o.avoid or (not o.urgent and time() - since < CONST.BLOCKED_MS) then
			Log.log("Tempoross", `   Fire at {f.x},{f.y} on the way to {what} and no water`)
			return false
		end
		Log.log(
			"Tempoross",
			`   Fire at {f.x},{f.y} on the way to {what}, no water for {CONST.BLOCKED_MS // 1000} s: going anyway`
		)
	end
	if o.ignore == nil and not o.urgent then
		local hazard = Hazard.hazard_at(tiles[#tiles])
		if hazard then
			Log.log("Tempoross", `   {Hazard.describe_hazard(hazard :: Npc)} where we'd stand for {what}`)
			return false
		end
	end
	return true
end

-- walks to the NPC and picks the first matching option
function Task.use_npc(npc: Npc, options: { string }, way: WayOptions?): boolean
	if not Route.clear_route(npc, npc.name, way) then
		return false
	end
	local ok = Npcs.approach(npc, options, Route.approach_opts(way))
	if not ok then
		Log.log("Tempoross", "   Can't", table.concat(options, "/"), "on", npc.name)
		return false
	end
	return true
end

-- same for a loc
function Task.use_loc(loc: Loc, options: { string }, way: WayOptions?): boolean
	if not Route.clear_route(loc, loc.name or "?", way) then
		return false
	end
	local ok = Objects.approach(loc, options, Route.approach_opts(way))
	if not ok then
		Log.log("Tempoross", "   Can't", table.concat(options, "/"), "on", loc.name or "?")
		return false
	end
	return true
end

-- whether a walk should stop for something more urgent
function Route.should_interrupt_walk(for_wave: boolean): boolean
	Chat.read_chat()
	-- a wave only matters with a rope
	if not for_wave and events.wave_warning_at ~= nil and not events.tethered and Read.has_rope() then
		return true
	end
	if events.game_result and S.in_game then
		return true
	end
	local s = game_state()
	if s.position then
		snap.me = { x = s.position.x, y = s.position.y }
		snap.npcs = Read.read_npcs() or snap.npcs
		if not for_wave and Read.item_count(Items.WATER) > 0 and Hazard.fire_near(snap.me, CONST.FIRE_REACH) then
			return true
		end
	end
	return false
end

-- walk callbacks: interrupt for urgent things, antiban, douse fires on the route
function Route.walk_checks(for_wave: boolean): Walker.WalkOptions
	return {
		on_step = function()
			if CONFIG.antiban and not S.in_game then
				Antiban.do_walking_antiban()
			end
			return not Route.should_interrupt_walk(for_wave)
		end,
		before_click = function(target: Tile, here: Tile): boolean?
			if for_wave or Read.item_count(Items.WATER) == 0 then
				return true
			end
			snap.npcs = Read.read_npcs() or snap.npcs
			local tiles = Route.route_to(target, here)
			Route.log_detour("walk click", here, target, tiles)
			local fire = tiles and Route.first_fire(tiles :: { Tile })
			if fire then
				Log.log("Tempoross", `   Fire at {fire.x},{fire.y} on the way`)
				events.fire_in_way = fire
				return false
			end
			return true
		end,
	}
end

-- tile moved up to 4 tiles each way, must be reachable
function Route.jitter_tile(tile: Tile): Tile
	for _ = 1, 10 do
		local t = { x = tile.x + Random.int(-4, 4), y = tile.y + Random.int(-4, 4) }
		-- scene route: find_path fails in the instance
		local tiles = Route.route_to(t)
		if tiles ~= nil and #tiles > 0 and tiles[#tiles].x == t.x and tiles[#tiles].y == t.y then
			return t
		end
	end
	return tile
end

-- walks within `near` tiles using minimap clicks
function Route.walk_near(tile: Tile, near: number, for_wave: boolean?): boolean
	snap.me = Walker.position() or snap.me
	if Geo.distance(snap.me, tile) <= near then
		return true
	end
	local goal = tile
	tile = Route.jitter_tile(tile)
	Log.log(
		"Tempoross",
		`   Walking to {tile.x},{tile.y} (asked {goal.x},{goal.y}, near {near}) from {snap.me.x},{snap.me.y}`
	)
	Route.log_detour("walk_near", snap.me, tile, Route.route_to(tile))
	local o = Route.walk_checks(for_wave == true)
	o.near = near
	o.timeout_ms = 30000
	local ok = Walker.walk(tile, o)
	if not ok then
		Log.log("Tempoross", "   Walk stopped")
	end
	return ok == true
end

-- walk options for using something; the pick doesn't wait
function Route.approach_opts(way: WayOptions?): Clickbox.Approach
	return { walk = Route.walk_checks(way ~= nil and way.urgent == true), arrive_ms = false }
end

---------------------------------------------------------------------------------------------------
-- Game actions

function Hazard.douse(fire: Npc): boolean
	local before = Read.item_count(Items.WATER)
	if before == 0 then
		return false
	end
	-- nearest fire first
	fire = Geo.nearest_npc(Hazard.fire_npcs(), snap.me) or fire
	if not Task.use_npc(fire, { "Douse" }, { ignore = fire }) then
		return false
	end
	Log.log("Tempoross", "   Dousing fire at", fire.x, fire.y)
	local deadline = time() + 6000
	while time() < deadline do
		local inv = Read.read_inventory()
		if (inv[Items.WATER] or 0) < before then
			return true
		end
		local now = Npcs.refresh(fire)
		if now == nil or now.id ~= CONST.FIRE then
			return true
		end
		sleep(100)
	end
	return false
end

-- nearest tile safe from hazards, leaning towards `towards`
function Route.safe_tile(towards: Tile?): Tile?
	local candidates: { { tile: Tile, score: number } } = {}
	for dx = -7, 7 do
		for dy = -7, 7 do
			local t = { x = snap.me.x + dx, y = snap.me.y + dy }
			local d = Geo.distance(t, snap.me)
			if d >= 1 and Hazard.hazard_at(t, 1) == nil then
				local score = d + (if towards then Geo.distance(t, towards :: Tile) * 0.5 else 0) + math.random()
				table.insert(candidates, { tile = t, score = score })
			end
		end
	end
	table.sort(candidates, function(a: { tile: Tile, score: number }, b: { tile: Tile, score: number }): boolean
		return a.score < b.score
	end)
	local reachable: Tile? = nil
	for i = 1, math.min(#candidates, 12) do
		local t = candidates[i].tile
		local tiles = Route.route_to(t)
		local last = tiles and tiles[#tiles]
		if last and last.x == t.x and last.y == t.y then
			if Route.safe_route(tiles :: { Tile }) then
				return t
			end
			reachable = reachable or t
		end
	end
	-- better past a hazard than in one
	return reachable
end

function Route.step_away(towards: Tile?): boolean
	local t = Route.safe_tile(towards)
	if t == nil then
		Log.log("Tempoross", "   No safe tile nearby")
		return false
	end
	Log.log("Tempoross", "   Stepping away to", t.x, t.y)
	Doing.clear_activity()
	S.dodging_to = t
	if not Walker.click_tile(t :: Tile) then
		Walker.click_minimap(t :: Tile)
	end
	-- hazard where we're headed: pick another
	if Route.sleep_watching(Random.int(600, 900), t) then
		return Route.step_away(towards)
	end
	return true
end

-- unties from the nearest mast or totem; whether it worked
function Task.untether_nearby(): boolean
	local t = Geo.nearest_walk(
		Read.locs_named({ "Mast", "Totem pole", "Damaged mast", "Damaged totem pole" }),
		snap.me,
		Geo.to_tile
	)
	if t == nil then
		return false
	end
	local target = t :: Loc
	if Geo.loc_distance(target, snap.me) > 2 and not Route.walk_near(Geo.to_tile(target), 1) then
		return false
	end
	if not Task.use_loc(target, { "Untether" }) then
		return false
	end
	Route.sleep_watching(600)
	return true
end

-- tethers to the nearest intact mast or totem of ours
function Task.tether()
	local options: { Loc } = {}
	for _, l in ipairs({ Ship.our_mast(), Ship.our_totem() } :: { Loc? }) do
		if l and not Chat.contains((l :: Loc).name or "", "Damaged") then
			table.insert(options, l :: Loc)
		end
	end
	-- fall back to the other ship's when ours are broken
	if #options == 0 then
		options = Read.locs_named({ "Mast", "Totem pole" })
	end
	-- steps to each, favouring where we're heading
	local ranked: { { loc: Loc, steps: number } } = {}
	for _, l in ipairs(options) do
		local d = Route.walk_steps(Geo.to_tile(l), snap.me)
		if Doing.is_doing("fish") and Chat.contains(l.name or "", "Totem") then
			d -= 8
		elseif Doing.is_doing("load") and Chat.contains(l.name or "", "Mast") then
			d -= 8
		end
		table.insert(ranked, { loc = l, steps = d })
	end
	table.sort(ranked, function(a: { loc: Loc, steps: number }, b: { loc: Loc, steps: number }): boolean
		return a.steps < b.steps
	end)
	local target = if ranked[1] then ranked[1].loc else nil
	if target == nil then
		Log.log("Tempoross", "   Nothing to tether to")
		return
	end
	-- douse a fire on it first
	local fire = Hazard.fire_near(target, 1)
	if fire and Read.item_count(Items.WATER) > 0 then
		Hazard.douse(fire)
	end
	Doing.clear_activity()
	if not Route.walk_near(target, 12, true) then
		return
	end
	-- a person tethers 0 to 4 ticks after the wave shows up
	Route.sleep_watching(Random.int(0, 4 * Ticks.MS))
	if events.wave_warning_at == nil or events.tethered or snap.tethered then
		return
	end
	-- click again if the server dropped the click
	local deadline = time() + 12000
	while time() < deadline do
		if not Task.use_loc(target, { "Tether" }, { urgent = true }) then
			-- menu says "Untether" once we are on it
			if Chat.contains(Read.menu_text(), "Untether") then
				events.tethered = true
				Doing.begin_activity("tether", nil, target)
			end
			return
		end
		Doing.begin_activity("tether", nil, target)
		local clicked = time()
		while time() < deadline do
			Chat.read_chat()
			-- varbit is set before the chat
			if (varbit(CONST.TETHERED_VARBIT) or 0) ~= 0 then
				events.tethered = true
				return
			end
			if events.tethered or events.wave_warning_at == nil then
				return
			end
			local s = game_state()
			if time() - clicked > 3600 and s.destination == nil then
				Log.log("Tempoross", "   No tether yet, clicking again")
				break
			end
			sleep(100)
		end
	end
end

-- repairable damaged mast or totem within range
function Task.repair_target(range: number): Loc?
	if not Read.has_hammer() then
		return nil
	end
	local damaged: { Loc } = {}
	for _, l in ipairs({ Ship.our_mast(), Ship.our_totem() } :: { Loc? }) do
		if l and Chat.contains((l :: Loc).name or "", "Damaged") and Geo.loc_distance(l :: Loc, snap.me) <= range then
			table.insert(damaged, l :: Loc)
		end
	end
	return Geo.nearest_walk(damaged, snap.me, Geo.to_tile)
end

function Task.repair(target: Loc)
	if Task.use_loc(target, { "Repair" }) then
		Doing.begin_activity("repair", nil, target)
	end
end

function Task.harpoon_pool(): boolean
	local pool = Geo.nearest_walk(snap.npcs, snap.me, Geo.to_tile, function(n)
		return n.name == "Spirit pool"
	end)
	if pool == nil then
		return false
	end
	if Task.use_npc(pool :: Npc, { "Harpoon" }) then
		Doing.begin_activity("attack", pool)
		return true
	end
	return false
end

function Hazard.track_energy()
	local energy = Read.hud_percent(HUD.ENERGY)
	if energy == nil then
		return
	end
	if S.last_energy ~= nil then
		if energy > S.last_energy then
			S.energy_dir = "up"
		elseif energy < S.last_energy then
			S.energy_dir = "down"
		end
	end
	-- full energy can only fall
	if energy >= 100 then
		S.energy_dir = "down"
	end
	S.last_energy = energy
end

-- active spirit pool or Tempoross out of energy
function Hazard.tempoross_vulnerable(): boolean
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.SPIRIT_POOL then
			return true
		end
	end
	local energy = Read.hud_percent(HUD.ENERGY)
	-- energy starts at 0 and fills up, that's not a stun
	return energy ~= nil and energy <= 0 and S.energy_dir == "down"
end

-- our crates nearest first, without electrified cannons
function Task.usable_crates(): { Npc }
	local mast = (S.side :: Side).mast
	local crates: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.name == "Ammunition crate" and Geo.distance(n, mast) <= 4 then
			table.insert(crates, n)
		end
	end
	local electrified = Read.locs_named({ "Electrified harpoonfish cannon" })
	local usable: { Npc } = {}
	local cannons = Read.locs_named({ "Harpoonfish cannon", "Electrified harpoonfish cannon" })
	for _, crate in ipairs(crates) do
		local cannon = Geo.nearest_loc(cannons, crate)
		local shocked = false
		for _, e in ipairs(electrified) do
			if cannon and e.x == (cannon :: Loc).x and e.y == (cannon :: Loc).y then
				shocked = true
			end
		end
		local warned = events.shocked_crate ~= nil
			and (events.shocked_crate :: Npc).index == crate.index
			and time() < events.shocked_until
		if shocked or warned then
			Log.log("Tempoross", "   The crate at", crate.x, crate.y, "has an electrified cannon")
		else
			table.insert(usable, crate)
		end
	end
	local steps: { [Npc]: number } = {}
	for _, crate in ipairs(usable) do
		steps[crate] = Route.walk_steps(crate)
	end
	table.sort(usable, function(a, b)
		return steps[a] < steps[b]
	end)
	return usable
end

function Task.load_fish()
	local s = S.side :: Side
	if not Route.walk_near(s.mast, 4) then
		return
	end
	Read.refresh_snapshot(game_state())
	local crates = Task.usable_crates()
	local crate = crates[1]
	-- sometimes the other one
	if crates[2] and math.random() < 0.15 then
		crate = crates[2]
	end
	if crate == nil then
		Log.log("Tempoross", "   Both cannons are electrified, waiting")
		Route.sleep_watching(Random.int(600, 1200))
		return
	end
	-- storm over this crate: take the other
	if Hazard.hazard_at(Route.route_end(crate)) and crates[2] and crate ~= crates[2] then
		crate = crates[2]
	end
	if Task.use_npc(crate, { "Fill" }) then
		Doing.begin_activity("load", crate)
	end
end

-- takes a tool from the nearest crate until `got`
function Task.take_tool(name: string, got: () -> boolean, home_only: boolean?): boolean
	-- buckets: nearest overall, others: our ship's crate
	local from = if S.side and name ~= "Buckets" then (S.side :: Side).mast else snap.me
	local crates = Read.locs_named({ name })
	local function accept(l: Loc): boolean
		return not home_only or Ship.at_home(l)
	end
	local crate = if name == "Buckets"
		then Geo.nearest_walk(crates, snap.me, Geo.to_tile, accept)
		else Geo.nearest_loc(crates, from, accept)
	if crate == nil then
		return false
	end
	if not Task.use_loc(crate :: Loc, { "Take" }) then
		return false
	end
	Log.log("Tempoross", "   Taking", name)
	local deadline = time() + 8000
	while time() < deadline do
		-- count buckets in the inventory
		if name == "Buckets" then
			Inventory.open()
		end
		snap.inv, snap.free = Read.read_inventory()
		if got() then
			return true
		end
		-- hazard here: the game step dodges it
		if Route.sleep_watching(100) then
			return false
		end
	end
	return false
end

-- the pump within reach for refilling, if any
function Task.pump_in_reach(): Loc?
	return Geo.nearest_walk(Read.locs_named({ "Water pump" }), snap.me, Geo.to_tile, function(l: Loc): boolean
		return Geo.loc_distance(l, snap.me) <= CONST.PUMP_RANGE
	end)
end

function Task.start_pumping(pump: Loc): boolean
	if Task.use_loc(pump, { "Use", "Fill-bucket" }) then
		Doing.begin_activity("pump", nil, pump)
		return true
	end
	return false
end

function Task.cook()
	local shrine = (S.side :: Side).shrine
	if Task.use_loc(shrine, { "Cook-at" }) then
		Doing.begin_activity("cook", nil, shrine)
	end
end

-- best spot near the totem, double first, safe from hazards
function Task.best_spot(double_only: boolean, except: Npc?): Npc?
	local now = snap.tick
	local totem = (S.side :: Side).totem
	local candidates: { { spot: Npc, score: number } } = {}
	for _, n in ipairs(snap.npcs) do
		local wanted = n.id == CONST.DOUBLE_SPOT or (CONST.SINGLE_SPOTS[n.id] == true and not double_only)
		if
			wanted
			and (n.id ~= CONST.DOUBLE_SPOT or Read.double_ticks_left(n, now) >= CONST.DOUBLE_MIN_TICKS_LEFT)
			and Geo.distance(n, totem) <= 14
			and (except == nil or n.index ~= (except :: Npc).index)
			and Hazard.hazard_at(n, 1) == nil
		then
			table.insert(
				candidates,
				{ spot = n, score = Geo.distance(n, snap.me) + (if n.id == CONST.DOUBLE_SPOT then -100 else 0) }
			)
		end
	end
	table.sort(candidates, function(a: { spot: Npc, score: number }, b: { spot: Npc, score: number }): boolean
		return a.score < b.score
	end)
	-- nearest few by route steps
	local walked: { { spot: Npc, score: number } } = {}
	for i = 1, math.min(#candidates, 6) do
		local spot = candidates[i].spot
		table.insert(
			walked,
			{ spot = spot, score = Route.walk_steps(spot) + (if spot.id == CONST.DOUBLE_SPOT then -100 else 0) }
		)
	end
	table.sort(walked, function(a: { spot: Npc, score: number }, b: { spot: Npc, score: number }): boolean
		return a.score < b.score
	end)
	for i = 1, math.min(#walked, 4) do
		local spot = walked[i].spot
		local tiles = Route.route_to(spot)
		local ok = tiles == nil
			or (
				Hazard.hazard_at(tiles[#tiles]) == nil
				and Route.safe_route(tiles :: { Tile }, Read.item_count(Items.WATER) == 0)
			)
		if ok then
			return spot
		end
	end
	return nil
end

-- double spot first, then nearest, hazard-free
function Task.any_spot_near_totem(): Npc?
	local now = snap.tick
	local totem = (S.side :: Side).totem
	local best: Npc? = nil
	for _, n in ipairs(snap.npcs) do
		if
			(n.id == CONST.DOUBLE_SPOT or CONST.SINGLE_SPOTS[n.id] == true)
			and (n.id ~= CONST.DOUBLE_SPOT or Read.double_ticks_left(n, now) >= CONST.DOUBLE_MIN_TICKS_LEFT)
			and Geo.distance(n, totem) <= 14
			and Hazard.hazard_at(n, 1) == nil
		then
			if
				best == nil
				or (n.id == CONST.DOUBLE_SPOT and (best :: Npc).id ~= CONST.DOUBLE_SPOT)
				or (n.id == (best :: Npc).id and Geo.distance(n, snap.me) < Geo.distance(best :: Npc, snap.me))
			then
				best = n
			end
		end
	end
	return best
end

-- clicks the spot, a double one after 0 to 4 ticks
function Task.fish_at(spot: Npc): boolean
	if spot.id == CONST.DOUBLE_SPOT then
		Route.sleep_watching(Random.int(0, 4 * Ticks.MS))
	end
	if Task.use_npc(spot, { "Harpoon" }, { avoid = true }) then
		Doing.begin_activity("fish", spot, nil, spot.id == CONST.DOUBLE_SPOT)
		return true
	end
	return false
end

-- leaves a hazard: douse, cook, change spot or crate, or step away
function Hazard.dodge(hazard: Npc)
	-- already heading somewhere safe
	local flag = game_state().destination
	local target = S.dodging_to
	if target and flag and Geo.distance(flag, target) <= 1 and Hazard.hazard_at(flag, 1) == nil then
		Route.sleep_watching(100, flag)
		return
	end
	S.dodging_to = nil
	local a = S.activity
	Log.log("Tempoross", "Dodging the", Hazard.describe_hazard(hazard), if a then `({a.kind})` else "")
	Doing.clear_activity()
	if hazard.id == CONST.FIRE and Read.item_count(Items.WATER) > 0 and Hazard.douse(hazard) then
		return
	end
	if a and a.kind == "fish" then
		if CONFIG.cook.enabled and Read.item_count(Items.RAW_FISH) >= CONFIG.cook.min_storm then
			local shrine = (S.side :: Side).shrine
			local tiles = Route.route_to(shrine)
			local clear = tiles ~= nil
				and Hazard.hazard_at(tiles[#tiles], 1) == nil
				and Route.safe_route(tiles :: { Tile })
			if clear and Task.use_loc(shrine, { "Cook-at" }) then
				Doing.begin_activity("cook", nil, shrine)
				return
			end
		end
		local spot = Task.best_spot(false, a.npc)
		if spot then
			Task.fish_at(spot :: Npc)
			if S.activity then
				return
			end
		end
	elseif a and a.kind == "load" then
		for _, crate in ipairs(Task.usable_crates()) do
			if
				(a.npc == nil or crate.index ~= (a.npc :: Npc).index)
				and Hazard.hazard_at(Route.route_end(crate)) == nil
			then
				if Task.use_npc(crate, { "Fill" }) then
					Doing.begin_activity("load", crate)
					return
				end
			end
		end
	end
	Route.step_away(if a then (a.npc or a.loc) :: Tile? else nil)
end

---------------------------------------------------------------------------------------------------
-- The game loop

function Game.new_game()
	Doing.clear_activity()
	events.wave_warning_at = nil
	events.tethered = false
	events.wave_hit_at = nil
	events.game_result = nil
	events.must_untether = false
	events.stunned_until = 0
	table.clear(S.growing_due)
	S.energy_dir, S.last_energy = "up", nil
	S.pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy)
	S.worn_cache = nil
	S.side = Ship.find_side()
	stats.games += 1
	if S.side then
		S.double_first_seen = {}
		Log.log("Tempoross", `Game {stats.games} started on the {(S.side :: Side).name} ship`)
	else
		Log.log("Tempoross", "Game started, but our ship wasn't found yet")
	end
end

function Game.log_status()
	if time() - S.last_status < 20000 then
		return
	end
	S.last_status = time()
	Log.log(
		"Tempoross",
		`   Energy {Read.hud_percent(HUD.ENERGY) or "?"}%, essence {Read.hud_percent(HUD.ESSENCE) or "?"}%, intensity {Read.hud_percent(
			HUD.INTENSITY
		) or "?"}%, {Read.widget_text(HUD.GROUP, HUD.POINTS) or ""}, fish {Read.fish_count()} ({Read.item_count(
			Items.RAW_FISH
		)} raw), doing {if S.activity then (S.activity :: Activity).kind else "nothing"}`
	)
end

-- whether to load the cannon now
function Game.should_load(): boolean
	local fish = Read.fish_count()
	if fish == 0 then
		return false
	end
	if snap.free == 0 and (not CONFIG.cook.enabled or Read.item_count(Items.RAW_FISH) == 0) then
		return true
	end
	-- at the ship with cooked fish: finish loading
	if Read.item_count(Items.RAW_FISH) == 0 and S.side and Geo.distance(snap.me, (S.side :: Side).mast) <= 6 then
		return true
	end
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	local energy = Read.hud_percent(HUD.ENERGY) or 100
	return fish >= 4 and (intensity >= CONFIG.load.intensity or energy <= CONFIG.load.energy)
end

---------------------------------------------------------------------------------------------------
-- The lobby

function Read.lobby_players(): number?
	local text = Read.widget_text(CONST.LOBBY, CONST.LOBBY_PLAYERS)
	if text == nil then
		return nil
	end
	if Chat.contains(text, "None") then
		return 0
	end
	local n = string.match(text, ">(%d+)<")
	return if n then tonumber(n) else nil
end

-- Seconds until the boat leaves; nil while it waits for players.
function Read.lobby_departure(): number?
	local text = Read.widget_text(CONST.LOBBY, CONST.LOBBY_DEPARTURE)
	local n = text and string.match(text, "(%d+) second")
	return if n then tonumber(n) else nil
end

function Geo.square_of(tile: Tile): (number, number)
	return bit32.rshift(tile.x, 6), bit32.rshift(tile.y, 6)
end

function Read.on_boat(): boolean
	local x, y = Geo.square_of(snap.me)
	return x == CONST.BOAT_SQUARE.x and y == CONST.BOAT_SQUARE.y
end

-- instances are far east of the overworld, so the port is the squares between the boat and them
function Read.in_port(): boolean
	local x = Geo.square_of(snap.me)
	return x >= CONST.PORT_MIN_SQUARE_X and not Player.in_instance()
end

-- ticks since `from`, or by time without a tick count
function Read.ticks_since(from: number?, started: number): number
	local s = game_state()
	local now = s.tick_count
	if from and now then
		return now - from
	end
	return (time() - started) // 600
end

-- waits to be aboard after a ladder click; false if the click didn't take
function Game.wait_aboard(): boolean
	local destination = Player.destination()
	if destination == nil and Player.is_moving(100) ~= true then
		return false
	end
	local s = game_state()
	local from = s.tick_count
	local started = time()
	snap.me = Walker.position() or snap.me
	while not Read.on_boat() and Read.ticks_since(from, started) < CONST.CLIMB_TICKS do
		sleep(50)
		snap.me = Walker.position() or snap.me
	end
	local aboard = Read.on_boat()
	Log.log(
		"Tempoross",
		`   Climbing: {if aboard then "aboard" else "not aboard"} after {Read.ticks_since(from, started)} ticks`
	)
	return aboard
end

function Read.on_island(): boolean
	return Player.instance_id() == CONST.TEMPOROSS_CHUNK_ID
end

function Game.tiny_antiban(boat: boolean?)
	if not CONFIG.antiban or not S.antiban_ready then
		return
	end
	local a = S.activity
	local kind = if boat then "boat" elseif a then (a :: Activity).kind else "idle"
	if not boat then
		local tethered = events.tethered or snap.tethered
		-- a wave coming only matters while we're not tied down
		if events.wave_warning_at ~= nil and not tethered then
			return
		end
		local waiting = time() < events.stunned_until
			or events.game_result ~= nil
			or (events.wave_warning_at ~= nil and tethered)
		if not waiting and not CONST.TINY_ACTIVITIES[kind] then
			return
		end
	end
	if Biometrics.random_boolean(0.4) and Antiban.do_async_tasks("game") then
		Log.log("Tempoross", "Async antiban while", kind)
	end
end

function Game.is_crew(name: string): boolean
	for _, title in ipairs(CONST.CREW_TITLES) do
		if string.sub(name, 1, #title) == title then
			return true
		end
	end
	return false
end

function Game.roll_min_players(): number
	return math.max(
		1,
		math.floor(CONFIG.boarding.min_players * (1 + (math.random() * 2 - 1) * CONFIG.boarding.players_variance) + 0.5)
	)
end

S.required_players = Game.roll_min_players()

function Game.sign_in(): boolean
	Log.log("Tempoross", "Logging in")
	local ok = Login.sign_in()
	if not ok then
		Log.log("Tempoross", "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
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

-- bare-handed fishing needs the levels; turns it off when they are missing
function Game.check_barehand()
	if CONFIG.barehand then
		local strength = Stats.real_level("Strength")
		local fishing = Stats.real_level("Fishing")
		if strength == nil or fishing == nil or strength < 35 or fishing < 55 then
			Log.log("Tempoross", `No bare-handed fishing: strength {strength or "?"}/35, fishing {fishing or "?"}/55`)
			CONFIG.barehand = false
		end
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

	Game.check_barehand()

	if CONFIG.antiban and not S.antiban_ready then
		Biometrics.setup_player()
		local MINUTE, HOUR = Antiban.MINUTE, Antiban.HOUR
		Antiban.set_zoom_range(0, 30)
		Antiban.set_pitch_range(80, 100)

		AntibanTasks.skills = { "Fishing", "Cooking", "Construction", "Total" }
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
		local SECOND = Antiban.SECOND
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
		Log.log("Tempoross", "Antiban set up")
	end
end

---------------------------------------------------------------------------------------------------
-- Leaving

-- whether the wait to leave is over: time ran out or the boat's ladder is back
function Game.leave_expired(): boolean
	if
		time() - (S.leaving_since :: number) >= CONST.LEAVE_WAIT_MS
		or next(Read.locs_named({ "Rope ladder" })) ~= nil
	then
		S.leaving_since = nil
		return true
	end
	return false
end

-- one step of leaving: with the crew, or waiting to be sent out
function Game.leave()
	if not S.leave_by_crew then
		if CONFIG.antiban and Antiban.break_due() then
			Antiban.do_antiban(false, true, true)
		end
		sleep(Random.int(500, 900))
		return
	end
	local crew = Geo.nearest_walk(snap.npcs, snap.me, Geo.to_tile, function(n: Npc): boolean
		return n.name ~= nil and Game.is_crew(n.name)
	end)
	if crew == nil then
		sleep(Random.int(400, 800))
		return
	end
	Log.log("Tempoross", "Leaving with", crew.name)
	if Npcs.approach(crew :: Npc, { "Leave", "Forfeit" }, Route.approach_opts({ urgent = true })) then
		-- the leave shows as the screen fading; clicking again before that repeats Leave
		local deadline = time() + 2400
		while not GameState.fading() and time() < deadline do
			sleep(100)
		end
		if not GameState.fading() then
			Log.log("Tempoross", "   Clicked Leave but the screen never faded")
		end
	else
		Log.log("Tempoross", "   Couldn't Leave/Forfeit on", crew.name)
		sleep(Random.int(600, 1000))
	end
end

---------------------------------------------------------------------------------------------------
-- States

type State =
	-- client
	"LOADING"
	| "LOGIN"
	| "FADING"
	| "NEW_GAME"
	| "GAME_OVER"
	-- in a game
	| "WAIT_SIDE"
	| "STUNNED"
	| "TETHER"
	| "UNTETHER_STRAY"
	| "WAIT_TETHERED"
	| "WAIT_FREE"
	| "UNTETHER_NEARBY"
	| "DODGE"
	| "DOUSE_FIRE"
	| "ATTACK"
	| "GO_TO_PIER"
	| "REPAIR"
	| "FISH_DOUBLE"
	| "CONTINUE"
	| "TAKE_HARPOON"
	| "TAKE_ROPE"
	| "LOAD_CANNON"
	| "TAKE_HAMMER"
	| "TAKE_BUCKETS"
	| "FILL_BUCKETS"
	| "COOK"
	| "COOK_STORM"
	| "FISH"
	| "WAIT_SPOT"
	| "IDLE"
	-- on the island, no game
	| "WAIT_VOYAGE"
	| "LEAVE"
	-- the lobby
	| "HOP_WORLD"
	| "WALK_DOCK"
	| "WALK_LADDER"
	| "SOLO_START"
	| "LOBBY_ANTIBAN"
	| "LEAVE_BOAT"
	| "BOAT_PUMP"
	| "ON_BOAT"
	| "WAIT_NEXT_BOAT"
	| "BOARD_NOW"
	| "BOARD_WALK"
	| "WAIT_LOBBY"

-- what get_state found that its handler needs
type Plan = {
	hazard: Npc?,
	broken: Loc?,
	fire: Npc?,
	spot: Npc?,
	ladder: Loc?,
	pump: Loc?,
	players: number?,
	departure: number?,
}

local plan: Plan = {}

-- gains go to Volcren once a minute
local report = StatsReport.new()

-- resets the idle timeout on xp, a new fish or a newly cooked fish, and reports the xp
function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	local fish, cooked = Read.fish_count(), Read.item_count(Items.COOKED_FISH)
	if xp > S.last_xp or fish > S.last_fish or cooked > S.last_cooked then
		S.last_progress_at = time()
	end
	S.last_xp, S.last_fish, S.last_cooked = xp, fish, cooked
end

-- what the loader's XP tracker shows next to the skills: the totals, it works out the rates itself
function Loop.report_counters()
	local key = `{stats.wins}/{stats.losses}/{stats.points}/{stats.permits}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "games", label = "Games", value = stats.wins + stats.losses },
		{ id = "wins", label = "Wins", value = stats.wins, percent_of = "games" },
		{ id = "losses", label = "Losses", value = stats.losses, percent_of = "games" },
		{ id = "points", label = "Points", value = stats.points, per = "games" },
		{ id = "permits", label = "Permits", value = stats.permits, per = "games" },
	})
end

-- stops the script when it hasn't progressed or keeps losing
function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp, fish or cooked fish for {t.idle_minutes} minutes`
	elseif S.losses_in_row >= t.max_losses then
		reason = `{S.losses_in_row} losses in a row`
	end
	if reason then
		Log.log("Tempoross", `Stuck: {reason}, stopping the script`)
		S.finished = true
	end
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	local spent = time() - S.antiban_began_at
	S.last_progress_at += spent
end

function Loop.hook_antiban_timeouts()
	Antiban.on_start_task, Antiban.on_finish_task = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.antiban_began, Loop.antiban_ended
end

-- whether to wait at the pier: energy is falling and almost out
function Loop.wants_pier(): boolean
	local energy = Read.hud_percent(HUD.ENERGY)
	if S.energy_dir ~= "down" or energy == nil or energy > S.pier_energy then
		return false
	end
	-- second phase, loading a lot: finish loading first
	local essence = Read.hud_percent(HUD.ESSENCE)
	if essence ~= nil and essence < CONST.PHASE_TWO_ESSENCE and Doing.is_doing("load") and Read.fish_count() > 10 then
		return false
	end
	return true
end

function Loop.get_game_state(skipped: { [State]: boolean }): State
	if S.side == nil then
		S.side = Ship.find_side()
		if S.side == nil then
			return "WAIT_SIDE"
		end
	end
	Doing.check_activity()
	Game.log_status()
	Hazard.watch_clouds()
	Hazard.track_energy()

	-- stunned by a cannon
	if time() < events.stunned_until then
		return "STUNNED"
	end

	-- 1. the wave: tether before it hits
	if events.wave_warning_at ~= nil and not events.tethered and not snap.tethered and Read.has_rope() then
		if time() - (events.wave_warning_at :: number) < 9000 then
			return "TETHER"
		end
		events.wave_warning_at = nil
	end
	-- stray tether: untie after a short while
	local stray = snap.tethered
		and events.wave_warning_at == nil
		and events.wave_hit_at == nil
		and not Doing.is_doing("tether")
	if stray then
		S.stray_since = S.stray_since or time()
		if time() - (S.stray_since :: number) >= CONST.STRAY_MS then
			S.stray_since = nil
			return "UNTETHER_STRAY"
		end
	else
		S.stray_since = nil
	end
	-- wait out the wave until untied
	if snap.tethered or Doing.is_doing("tether") then
		return "WAIT_TETHERED"
	end
	if events.wave_hit_at then
		if snap.busy and time() - (events.wave_hit_at :: number) < 10000 then
			return "WAIT_FREE"
		end
		Log.log(
			"Tempoross",
			string.format("   Free again %.1f s after the wave", (time() - (events.wave_hit_at :: number)) / 1000)
		)
		events.wave_hit_at = nil
	end
	if events.must_untether then
		return "UNTETHER_NEARBY"
	end

	-- 2. hazards where we stand
	local hazard = Hazard.hazard_at(snap.me)
	if hazard then
		plan.hazard = hazard
		return "DODGE"
	end
	if events.fire_in_way then
		local fire = Npcs.refresh(events.fire_in_way :: Npc)
		events.fire_in_way = nil
		if fire and fire.id == CONST.FIRE and Read.item_count(Items.WATER) > 0 then
			plan.fire = fire
			return "DOUSE_FIRE"
		end
	end

	-- 3. Tempoross is vulnerable: harpoon the spirit pool
	if Hazard.tempoross_vulnerable() then
		return "ATTACK"
	end
	if Doing.is_doing("attack") then
		Doing.clear_activity()
	end

	-- 3b. the energy is about to run out: be at the pier
	if Loop.wants_pier() then
		return "GO_TO_PIER"
	end
	S.pier_logged = false

	-- 4. repairs after a wave and fires close by (points)
	local broken = Task.repair_target(6)
	if broken and not Doing.is_doing("repair") and not Doing.is_doing("load") then
		plan.broken = broken
		return "REPAIR"
	end
	if Read.item_count(Items.WATER) > 0 and not Doing.is_doing("load") then
		local fire = Hazard.fire_near(snap.me, 3)
		if fire then
			plan.fire = fire
			return "DOUSE_FIRE"
		end
	end

	-- 5. a double spot nearby beats anything but the above
	local committed = Doing.is_doing("repair") or Doing.is_doing("tether") or Doing.is_doing("load")
	if
		snap.free > 0
		and not committed
		and not (S.activity and (S.activity :: Activity).double)
		and Read.has_harpoon()
	then
		local double = Task.best_spot(true)
		if double and Geo.distance(double :: Npc, snap.me) <= 16 then
			plan.spot = double
			return "FISH_DOUBLE"
		end
	end

	-- 6. keep doing what we're doing
	if S.activity ~= nil then
		local a = S.activity :: Activity
		-- enough raw fish: off to cook (a double spot keeps us there)
		if
			a.kind == "fish"
			and not a.double
			and CONFIG.cook.enabled
			and Read.item_count(Items.RAW_FISH) >= S.cook_fish_threshold
		then
			Doing.clear_activity()
		elseif (a.kind == "fish" or a.kind == "cook") and Game.should_load() then
			Log.log("Tempoross", "Loading now")
			Doing.clear_activity()
		elseif a.kind == "fish" and snap.free == 0 then
			Doing.clear_activity()
		else
			return "CONTINUE"
		end
	end

	-- 7. tools
	if snap.free > 0 then
		if not Read.has_harpoon() then
			return "TAKE_HARPOON"
		end
		if not Read.has_rope() and not Game.should_load() and not skipped["TAKE_ROPE"] then
			return "TAKE_ROPE"
		end
	end

	-- 8. load the cannon
	if Game.should_load() then
		return "LOAD_CANNON"
	end

	-- 9. tools that can wait
	if snap.free > 0 and Ship.at_home(snap.me) then
		if not Read.has_hammer() and not skipped["TAKE_HAMMER"] then
			return "TAKE_HAMMER"
		end
		local need_water = Read.item_count(Items.WATER) == 0 and #Hazard.fire_npcs() > 0
		if
			Read.item_count(Items.BUCKET, Items.WATER) < CONFIG.buckets
			and (Read.fish_count() == 0 or (need_water and Read.item_count(Items.BUCKET) == 0))
			and not skipped["TAKE_BUCKETS"]
		then
			return "TAKE_BUCKETS"
		end
	end
	-- empty buckets: refill when a pump is within reach
	if Read.item_count(Items.BUCKET) > 0 and not skipped["FILL_BUCKETS"] then
		local pump = Task.pump_in_reach()
		if pump then
			plan.pump = pump
			return "FILL_BUCKETS"
		end
	end

	-- 10. cook
	local raw = Read.item_count(Items.RAW_FISH)
	if CONFIG.cook.enabled and raw > 0 and (raw >= S.cook_fish_threshold or snap.free == 0) then
		return "COOK"
	end

	-- 11. fish
	if snap.free > 0 then
		local spot = Task.best_spot(false)
		if spot then
			plan.spot = spot
			return "FISH"
		end
		-- every spot has a hazard by it: put a fire out, cook what we have, or wait it out
		local fire = if Read.item_count(Items.WATER) > 0 then Hazard.fire_near(snap.me, 8) else nil
		if fire then
			plan.fire = fire
			return "DOUSE_FIRE"
		end
		if CONFIG.cook.enabled and raw >= CONFIG.cook.min_storm then
			return "COOK_STORM"
		end
		return "WAIT_SPOT"
	end
	-- cooking is off or anything unexpected
	if Read.fish_count() > 0 then
		return "LOAD_CANNON"
	end
	return "IDLE"
end

function Loop.get_lobby_state(skipped: { [State]: boolean }): State
	local ladder = Geo.nearest_walk(Read.locs_named({ "Rope ladder" }), snap.me, Geo.to_tile)
	if ladder == nil then
		-- ladder out of sight: walk to the dock, unless we are on the boat
		return if Read.on_boat() then "IDLE" else "WALK_DOCK"
	end
	plan.ladder = ladder
	if CONFIG.solo then
		return if Geo.distance(snap.me, ladder) > 8 then "WALK_LADDER" else "SOLO_START"
	end
	local players = Read.lobby_players()
	local departure = Read.lobby_departure()
	plan.players, plan.departure = players, departure
	local ready = players ~= nil and players >= S.required_players

	if
		CONFIG.antiban
		and not ready
		and (departure == nil or departure > CONFIG.antiban_departure)
		and not skipped["LOBBY_ANTIBAN"]
		and Read.in_port()
	then
		return "LOBBY_ANTIBAN"
	end

	if Read.on_boat() then
		if players and players < S.required_players and departure and departure <= 10 then
			return "LEAVE_BOAT"
		end
		-- fill buckets at the boat pump until the last 5 s
		if Read.item_count(Items.BUCKET) > 0 and (departure == nil or departure > 5) and not Doing.is_doing("pump") then
			local pump = Geo.nearest_walk(Read.locs_named({ "Water pump" }), snap.me, Geo.to_tile)
			if pump and Geo.loc_distance(pump :: Loc, snap.me) <= 6 then
				plan.pump = pump
				return "BOAT_PUMP"
			end
		end
		return "ON_BOAT"
	end

	-- too late to board, wait for the next boat
	if departure ~= nil and departure <= CONFIG.boarding.min_time then
		return "WAIT_NEXT_BOAT"
	end
	if ready then
		return "BOARD_NOW"
	end
	-- board when the boat has enough players, or will have time to fill up
	if players and players + 1 >= S.required_players then
		return "BOARD_WALK"
	end
	if Geo.distance(snap.me, ladder) > 8 then
		return "WALK_LADDER"
	end
	return "WAIT_LOBBY"
end

-- reads the client and decides what to do next; handlers do it
function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}
	plan = {}
	S.in_game, S.hud_up = false, false

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()
	Chat.read_chat()
	S.in_game = Read.on_island()
	S.hud_up = S.in_game and Read.hud_percent(HUD.ENERGY) ~= nil

	-- end-of-game dialogue keeps the fade up until continued
	S.end_dialogue = not S.hud_up and ChatOptions.contains_continue()
	if not S.end_dialogue then
		S.click_continue_dialogue = nil
	elseif S.click_continue_dialogue == nil then
		S.click_continue_dialogue = Biometrics.random_boolean(0.1)
	end
	-- screen is fading: clicks would repeat Leave
	if GameState.fading() and not (S.end_dialogue and not S.click_continue_dialogue) then
		return "FADING"
	end

	if S.hud_up then
		if not S.was_in_game then
			return "NEW_GAME"
		end
		return Loop.get_game_state(skipped)
	end
	if S.was_in_game then
		return "GAME_OVER"
	end

	if S.in_game then
		-- on the island without a game: the voyage, or the game just ended and we leave
		if S.played_here and S.leaving_since == nil then
			-- the last attempt to leave ran out of time: try again
			S.leaving_since = time()
		end
		if S.leaving_since ~= nil and not Game.leave_expired() then
			return "LEAVE"
		end
		return "WAIT_VOYAGE"
	end

	S.played_here = false
	local world = WorldSwitcher.current()
	if world and world ~= CONFIG.world and Read.lobby_players() ~= nil then
		return "HOP_WORLD"
	end
	if S.leaving_since ~= nil and not Game.leave_expired() then
		return "LEAVE"
	end
	return Loop.get_lobby_state(skipped)
end

---------------------------------------------------------------------------------------------------
-- Handlers

function Handler.wait_untethered()
	Route.sleep_watching(150, nil, function()
		return (varbit(CONST.TETHERED_VARBIT) or 0) == 0
	end)
end

-- random tile around the ladder to walk to
function Handler.near_ladder(ladder: Loc): Tile
	return { x = ladder.x + Random.int(2, 5), y = ladder.y + Random.int(-3, 3) }
end

function Handler.game_over()
	S.was_in_game = false
	Doing.clear_activity()

	if S.antiban_ready then
		Antiban.delay_tasks(time() - S.game_started)
	end
	-- result messages can lag the HUD.GROUP
	local deadline = time() + 4000
	while events.game_result == nil and time() < deadline do
		sleep(200)
		Chat.read_chat()
	end
	local result = events.game_result or "lost"
	if result == "won" then
		stats.wins += 1
		S.losses_in_row = 0
	else
		stats.losses += 1
		S.losses_in_row += 1
	end
	Log.log("Progress", `Wins: {stats.wins}, Losses: {stats.losses}, Permits: {stats.permits}`)
	events.game_result = nil
	events.wave_warning_at = nil
	S.required_players = Game.roll_min_players()
	Log.log("Tempoross", `Next round waits for {S.required_players} players`)
	S.leaving_since = time()
	-- leave with the crew unless a break is due
	S.leave_by_crew = not (CONFIG.antiban and S.antiban_ready and Antiban.break_due())
		and Biometrics.random_boolean(0.9)
	if CONFIG.max_games > 0 and stats.games >= CONFIG.max_games then
		S.finished = true
	end
end

function Handler.attack()
	if not Doing.is_doing("attack") then
		if not Task.harpoon_pool() then
			-- pools are past our mast
			local pool = Geo.nearest_walk(Read.npcs_with(CONST.INACTIVE_POOL), snap.me, Geo.to_tile)
			if pool == nil then
				Route.walk_near((S.side :: Side).mast, 6)
			end
		end
	end
	Route.sleep_watching(150)
end

function Handler.go_to_pier()
	-- the pool is at the pier; out of sight, our mast is the closest known place
	local pool = Geo.nearest_walk(Read.npcs_with(CONST.INACTIVE_POOL), snap.me, Geo.to_tile)
	local target: Tile = if pool then Geo.to_tile(pool :: Npc) else (S.side :: Side).mast
	if not S.pier_logged then
		S.pier_logged = true
		Log.log("Tempoross", `Energy {Read.hud_percent(HUD.ENERGY)}% and falling, heading to the pier`)
		Doing.clear_activity()
	end
	if Geo.distance(snap.me, target) > CONST.PIER_RANGE then
		Route.walk_near(target, CONST.PIER_RANGE)
	else
		Route.sleep_watching(150)
	end
end

function Handler.untether_nearby_on_request()
	events.must_untether = false
	local t = Geo.nearest_walk(Read.locs_named({ "Mast", "Totem pole" }), snap.me, Geo.to_tile)
	if t and Geo.loc_distance(t :: Loc, snap.me) <= 2 then
		Task.use_loc(t :: Loc, { "Untether" })
		Route.sleep_watching(600)
	end
end

function Handler.wait_spot()
	local s = S.side :: Side
	if Geo.distance(snap.me, s.totem) > 8 then
		-- click a spot near the totem on the way
		local on_way = Task.any_spot_near_totem()
		if on_way and Task.fish_at(on_way) then
			return
		end
		if not Route.walk_near(s.totem, 5) then
			return
		end
	end
	-- why no spot is clear
	local near, blocked = 0, "nothing near the totem"
	for _, n in ipairs(snap.npcs) do
		if (CONST.SINGLE_SPOTS[n.id] or n.id == CONST.DOUBLE_SPOT) and Geo.distance(n, s.totem) <= 14 then
			near += 1
			blocked = if Hazard.hazard_at(n, 1)
				then Hazard.describe_hazard(Hazard.hazard_at(n, 1) :: Npc)
				else "a route through a hazard"
		end
	end
	Log.log("Tempoross", `   No fishing spot clear of fires and storms ({near} spots near the totem, {blocked})`)
	Route.sleep_watching(Random.int(600, 1200))
end

-- stays on the boat: tops up buckets, antiban, waits
function Handler.wait_on_boat()
	Doing.check_activity()
	Game.tiny_antiban(true)
	sleep(Random.int(300, 600))
end

function Handler.board(ladder: Loc)
	if Task.use_loc(ladder, { "Climb" }) then
		Game.wait_aboard()
	end
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	FADING = function()
		if S.end_dialogue then
			Log.log("Tempoross", "Continuing the end-of-game dialogue")
			ChatOptions.continue_chat()
		end
		sleep(200)
	end,
	NEW_GAME = function()
		S.was_in_game = true
		S.played_here = true
		S.game_started = time()
		Game.new_game()
	end,
	GAME_OVER = Handler.game_over,

	-- in a game
	WAIT_SIDE = function()
		Route.sleep_watching(300)
	end,
	STUNNED = function()
		Route.sleep_watching(150, nil, function()
			return time() >= events.stunned_until
		end)
	end,
	TETHER = function()
		Log.log("Tempoross", "Tethering")
		Task.tether()
	end,
	UNTETHER_STRAY = function()
		Log.log("Tempoross", "   Tethered with no wave, untethering")
		if not Task.untether_nearby() then
			Handler.wait_untethered()
		end
	end,
	WAIT_TETHERED = Handler.wait_untethered,
	WAIT_FREE = function()
		Route.sleep_watching(150, nil, function()
			return (varbit(Varbits.BUSY) or 0) == 0
		end)
	end,
	UNTETHER_NEARBY = Handler.untether_nearby_on_request,
	DODGE = function()
		Hazard.dodge(plan.hazard :: Npc)
	end,
	DOUSE_FIRE = function()
		Hazard.douse(plan.fire :: Npc)
	end,
	ATTACK = Handler.attack,
	GO_TO_PIER = Handler.go_to_pier,
	REPAIR = function()
		Log.log("Tempoross", "Repairing", (plan.broken :: Loc).name)
		Task.repair(plan.broken :: Loc)
	end,
	FISH_DOUBLE = function()
		Log.log("Tempoross", "Double spot")
		Task.fish_at(plan.spot :: Npc)
	end,
	CONTINUE = function()
		Route.sleep_watching(150)
	end,
	TAKE_HARPOON = function()
		Task.take_tool("Harpoons", Read.has_harpoon)
		S.worn_cache = nil
	end,
	TAKE_ROPE = function()
		if not Task.take_tool("Ropes", Read.has_rope) then
			S.skip["TAKE_ROPE"] = true
		end
	end,
	LOAD_CANNON = Task.load_fish,
	TAKE_HAMMER = function()
		if not Task.take_tool("Hammers", Read.has_hammer, true) then
			S.skip["TAKE_HAMMER"] = true
		end
	end,
	TAKE_BUCKETS = function()
		local before = Read.item_count(Items.BUCKET, Items.WATER)
		local taken = Task.take_tool("Buckets", function()
			return Read.item_count(Items.BUCKET, Items.WATER) > before
		end, true)
		if not taken then
			S.skip["TAKE_BUCKETS"] = true
		end
	end,
	FILL_BUCKETS = function()
		if not Task.start_pumping(plan.pump :: Loc) then
			S.skip["FILL_BUCKETS"] = true
		end
	end,
	COOK = function()
		S.cook_fish_threshold = Random.int(CONFIG.cook.min, CONFIG.cook.max)
		Task.cook()
	end,
	COOK_STORM = Task.cook,
	FISH = function()
		Task.fish_at(plan.spot :: Npc)
	end,
	WAIT_SPOT = Handler.wait_spot,
	IDLE = function() end,

	-- on the island, no game
	WAIT_VOYAGE = function()
		sleep(Random.int(300, 600))
	end,
	LEAVE = Game.leave,

	-- the lobby
	HOP_WORLD = function()
		Log.log("Tempoross", "Hopping to world", CONFIG.world)
		WorldSwitcher.switch(CONFIG.world)
	end,
	WALK_DOCK = function()
		Route.walk_near(CONST.DOCK, 3)
	end,
	WALK_LADDER = function()
		Route.walk_near(Handler.near_ladder(plan.ladder :: Loc), 2)
	end,
	SOLO_START = function()
		Log.log("Tempoross", "Solo start")
		if Task.use_loc(plan.ladder :: Loc, { "Solo-start" }) then
			-- the game takes a moment to load
			sleep(Random.int(1800, 2600))
		end
	end,
	LOBBY_ANTIBAN = function()
		if not Antiban.do_antiban() then
			S.skip["LOBBY_ANTIBAN"] = true
		end
	end,
	LEAVE_BOAT = function()
		Log.log("Tempoross", `Only {plan.players} players, leaving the boat`)
		Task.use_loc(plan.ladder :: Loc, { "Quick-climb", "Climb" })
		sleep(Random.int(1800, 2600))
	end,
	BOAT_PUMP = function()
		Task.start_pumping(plan.pump :: Loc)
		Handler.wait_on_boat()
	end,
	ON_BOAT = Handler.wait_on_boat,
	WAIT_NEXT_BOAT = function()
		sleep(Random.int(600, 1200))
	end,
	BOARD_NOW = function()
		Log.log("Tempoross", `Boarding: {plan.players} players ready already, departure {plan.departure or "-"}`)
		Handler.board(plan.ladder :: Loc)
	end,
	BOARD_WALK = function()
		local ladder = plan.ladder :: Loc
		Log.log("Tempoross", `Boarding: {plan.players} players ready, departure {plan.departure or "-"}`)
		-- random tile east of the ladder
		local spot = Random.tile_in_box(ladder.x + 2, ladder.y - 2, ladder.x + 3, ladder.y + 2)
		if Route.walk_near(spot, 1) then
			Handler.board(ladder)
		end
	end,
	WAIT_LOBBY = function()
		sleep(Random.int(600, 1200))
	end,
}

-- Settings

local function integer_field(id: string, label: string, default: number, min: number, max: number): any
	return { id = id, kind = "number", label = label, default = default, min = min, max = max, integer = true }
end

-- asks for the settings that were hard coded in CONFIG, which stay as their defaults; false when the form is closed
function Game.ask(): boolean
	local values = Host.form({
		title = "Tempoross",
		submit = "Start",
		fields = {
			integer_field("world", "World to play on", CONFIG.world, 1, 1000),
			{ id = "solo", kind = "check", label = "Solo (don't wait for a crew)", default = CONFIG.solo },
			integer_field("min_players", "Board with at least this many players", CONFIG.boarding.min_players, 1, 100),
			{
				id = "players_variance",
				kind = "number",
				label = "Variance of that number (0.1 = 10%)",
				default = CONFIG.boarding.players_variance,
				min = 0,
				max = 1,
				step = 0.05,
			},
			integer_field("min_time", "Board anyway when the boat leaves within (s)", CONFIG.boarding.min_time, 0, 120),
			{
				id = "barehand",
				kind = "check",
				label = "Bare-handed fishing (35 Strength, 55 Fishing)",
				default = CONFIG.barehand,
			},
			integer_field("buckets", "Buckets of water to carry", CONFIG.buckets, 0, 10),
			{ id = "cook", kind = "check", label = "Cook fish", default = CONFIG.cook.enabled },
			integer_field("cook_min", "Cook once holding at least (min)", CONFIG.cook.min, 1, 28),
			integer_field("cook_max", "Cook once holding at least (max)", CONFIG.cook.max, 1, 28),
			integer_field("cook_storm", "Cook during a storm from", CONFIG.cook.min_storm, 1, 28),
			integer_field("load_intensity", "Load the cannon at wave intensity", CONFIG.load.intensity, 0, 100),
			integer_field("load_energy", "...or Tempoross energy at most", CONFIG.load.energy, 0, 100),
			integer_field("pier_min", "Walk to the pier at energy (min)", CONFIG.pier.min_energy, 0, 100),
			integer_field("pier_max", "Walk to the pier at energy (max)", CONFIG.pier.max_energy, 0, 100),
			integer_field("max_games", "Stop after this many games (0 = never)", CONFIG.max_games, 0, 100000),
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
	CONFIG.world = values.world
	CONFIG.solo = values.solo == true
	CONFIG.boarding.min_players = values.min_players
	CONFIG.boarding.players_variance = values.players_variance
	CONFIG.boarding.min_time = values.min_time
	CONFIG.barehand = values.barehand == true
	CONFIG.buckets = values.buckets
	CONFIG.cook.enabled = values.cook == true
	CONFIG.cook.min = math.min(values.cook_min, values.cook_max)
	CONFIG.cook.max = math.max(values.cook_min, values.cook_max)
	CONFIG.cook.min_storm = values.cook_storm
	CONFIG.load.intensity = values.load_intensity
	CONFIG.load.energy = values.load_energy
	CONFIG.pier.min_energy = math.min(values.pier_min, values.pier_max)
	CONFIG.pier.max_energy = math.max(values.pier_min, values.pier_max)
	CONFIG.max_games = values.max_games
	-- rolled from these ranges, so roll again
	S.cook_fish_threshold = Random.int(CONFIG.cook.min, CONFIG.cook.max)
	S.pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy)
end

-- takes the settings the user sent with Update in the loader, if there are any
function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Game.check_barehand()
		Log.log("Tempoross", "Settings updated")
	end
end

function Loop.run()
	if not Game.ask() then
		Log.log("Tempoross", "Form closed, stopping the script")
		return
	end
	Chat.skip_old_messages()
	Log.log("Tempoross", "Tempoross started")
	Game.setup()
	S.last_progress_at, S.losses_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		Game.poll_settings()
		Handler.states[state]()

		if S.hud_up and S.was_in_game then
			Game.tiny_antiban()
			Route.sleep_watching(Random.int(60, 140))
		else
			if CONFIG.antiban and S.antiban_ready then
				Antiban.do_async_tasks("outside")
			end
			sleep(Random.int(60, 140))
		end
	end
	Log.log("Tempoross", "Done")
end

Loop.run()
