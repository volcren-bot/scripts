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
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local Clickbox = require("@lib/main/clickbox")
local Core = require("./core")
local DebugDraw = require("@lib/main/debug_draw")
local DepositBox = require("@lib/main/interfaces/mainscreen/depositbox")
local Draw = require("@lib/utils/draw")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Projectiles = require("@lib/main/entities/projectiles")
local Random = require("@lib/utils/math/random")
local Randoms = require("@lib/main/antiban/randoms")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Ticks = require("@lib/utils/ticks")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Varbits = require("@lib/main/varbits")
local Walker = require("@lib/main/walker")
local WorldSwitcher = require("@lib/main/interfaces/gametabs/worldswitcher")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")
type Box = Core.Box
type Snapshot = Core.Snapshot
type Activity = Core.Activity
type Side = Core.Side
type WayOptions = Core.WayOptions
type State = Core.State
type Npc = Core.Npc
type Loc = Core.Loc
type Tile = Core.Tile
type ClientState = Core.ClientState
local CONST = Core.CONST
local CONFIG = Core.CONFIG
local Items = Core.Items
local HUD = Core.HUD
local stats = Core.stats
local S = Core.S
local snap = Core.snap
local events = Core.events
local plan = Core.plan
local report = Core.report
local new_solo_round = Core.new_solo_round
local Read = Core.Read
local Geo = Core.Geo
local Chat = Core.Chat
local Ship = Core.Ship
local Hazard = Core.Hazard
local Route = Core.Route
local Doing = Core.Doing
local Task = Core.Task
local Game = Core.Game
local Loop = Core.Loop
local Solo = Core.Solo
local Group = Core.Group
local Handler = Core.Handler
require("./solo")
require("./group")

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

function Read.read_npcs(): { Npc }?
	local list = npcs()
	if list == nil then
		return nil
	end
	local now = time()
	local present: { [string]: boolean } = {}
	for key, at in pairs(S.doused) do
		if now - at > CONST.DOUSED_MS then
			S.doused[key] = nil
		end
	end
	for i = #list, 1, -1 do
		local n = list[i]
		n.name = Npcs.clean_name(n.name)
		if n.id == CONST.FIRE then
			local key = `{n.x},{n.y}`
			if S.doused[key] then
				table.remove(list, i)
				S.fire_seen[key] = nil
			else
				present[key] = true
				S.fire_seen[key] = { npc = n, at = now }
			end
		end
	end
	for key, seen in pairs(S.fire_seen) do
		if not present[key] then
			if now - seen.at <= CONST.FIRE_GHOST_MS then
				table.insert(list, seen.npc)
			else
				S.fire_seen[key] = nil
			end
		end
	end
	return list
end

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

function Read.double_ticks_left(n: Npc, now: number): number
	local since = S.double_first_seen[`{n.x},{n.y}`]
	if since == nil or now - since > CONST.DOUBLE_LIFE_MAX_TICKS then
		return CONST.DOUBLE_LIFE_TICKS
	end
	return CONST.DOUBLE_LIFE_TICKS - (now - since)
end

function Read.push_trail(entry: string)
	table.insert(S.trail, entry)
	if #S.trail > CONST.TRAIL_LENGTH then
		table.remove(S.trail, 1)
	end
end

function Read.note_trail()
	local last = S.trail_last
	if last and last.x == snap.me.x and last.y == snap.me.y then
		return
	end
	if last and Geo.distance(last :: Tile, snap.me) > 1 then
		local passed = Route.route_to(snap.me, last :: Tile)
		if passed then
			for i = 2, #passed - 1 do
				Read.push_trail(`~{passed[i].x},{passed[i].y}`)
			end
		end
	end
	Read.push_trail(`{snap.me.x},{snap.me.y}@{snap.tick}`)
	S.trail_last = { x = snap.me.x, y = snap.me.y }
end

function Read.set_me(position: { x: number, y: number }?)
	if position then
		snap.me = { x = position.x, y = position.y }
		Read.note_trail()
	end
end

function Read.refresh_snapshot(state: ClientState): boolean
	table.clear(S.hud_cache)
	if state.position == nil then
		return false
	end
	local inv, free = Read.read_inventory()
	local tick = Read.current_tick(state)
	local fresh: Snapshot = {
		state = state,
		me = { x = state.position.x, y = state.position.y },
		npcs = Read.read_npcs() or {},
		locs = nil,
		inv = inv,
		free = free,
		tick = tick,
		tethered = (varbit(CONST.TETHERED_VARBIT) or 0) ~= 0,
		busy = (varbit(Varbits.BUSY) or 0) ~= 0,
		walking = state.destination ~= nil,
	}
	table.clear(snap)
	for k, v in pairs(fresh :: any) do
		(snap :: any)[k] = v
	end
	Read.track_doubles(snap.npcs, snap.me, tick)
	Read.note_trail()
	return true
end

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
			local text = string.gsub(string.gsub(m.text, "<[^>]*>", ""), "@[%w_]+@", "")
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
					events.waves_passed += 1
					events.wave_hit_us = events.wave_hit_us or not Chat.contains(text, "washes over")
				elseif Chat.contains(text, "untether yourself from") then
					events.tethered = false
				elseif Chat.contains(text, "untether") then
					Log.log("Tempoross", `   Chat: {text}`)
					events.must_untether = true
				elseif
					Chat.contains(text, "surges towards a nearby cannon")
					or Chat.contains(text, "arcs from the cannon into you")
				then
					if Chat.contains(text, "arcs from the cannon into you") then
						events.stunned_until = time() - m.age + CONST.STUN_MS
						Log.log("Tempoross", "Stunned by the cannon")
					else
						events.surge_until = time() - m.age + CONST.SURGE_WAIT_MS
						S.surge_logged = false
						Log.log("Tempoross", "A cannon is about to be electrified")
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
					local st = Host.game_state()
					snap.tick = Read.current_tick(st)
					Read.set_me(st.position)
					snap.npcs = Read.read_npcs() or snap.npcs
					Log.log("Tempoross", `Lost items {math.floor(m.age)} ms ago: {text}`)
					Hazard.log_burn(st.destination)
					if Chat.contains(text, "to the fire") then
						local spares_fish = CONFIG.solo and S.solo.p3_stage ~= nil and not Chat.contains(text, "fish")
						if spares_fish then
							Log.log("Tempoross", "   Burned in part 3 without losing fish, carrying on")
						else
							events.burned = true
						end
					end
				end
			end
		end
	end
end

function Ship.find_side(): Side?
	local masts = Read.locs_named({ "Mast", "Damaged mast" })
	local mast = Geo.nearest_loc(masts, snap.me)
	if mast == nil then
		return nil
	end
	local west = CONST.WEST_MASTS[mast.id] == true
	if not west and not CONST.EAST_MASTS[mast.id] then
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

function Hazard.fire_npcs(): { Npc }
	local now = time()
	local fires: { Npc } = {}
	for _, n in ipairs(Read.npcs_with(CONST.FIRE)) do
		local at = S.doused[`{n.x},{n.y}`]
		if at == nil or now - at > CONST.DOUSED_MS then
			table.insert(fires, n)
		end
	end
	return fires
end

function Hazard.fire_size(fire: Npc): number
	if S.fire_size == nil then
		local sizes = Host.npc_sizes({ fire.index })
		S.fire_size = sizes and sizes[fire.index]
		if S.fire_size then
			Log.log("Tempoross", `   Fires are {S.fire_size}x{S.fire_size} tiles`)
		end
	end
	return S.fire_size or 1
end

function Hazard.fire_tiles(fire: Npc): { Tile }
	local size = Hazard.fire_size(fire)
	local x0, y0 = fire.x - size // 2, fire.y - size // 2
	local tiles = {}
	for x = x0, x0 + size - 1 do
		for y = y0, y0 + size - 1 do
			table.insert(tiles, { x = x, y = y })
		end
	end
	return tiles
end

function Hazard.fire_distance(fire: Npc, tile: Tile): number
	local size = Hazard.fire_size(fire)
	local x0, y0 = fire.x - size // 2, fire.y - size // 2
	local dx = math.max(x0 - tile.x, tile.x - (x0 + size - 1), 0)
	local dy = math.max(y0 - tile.y, tile.y - (y0 + size - 1), 0)
	return math.max(dx, dy)
end

function Hazard.fire_clusters(fires: { Npc }): { { Npc } }
	local group: { number } = {}
	for i = 1, #fires do
		group[i] = i
	end
	local function root(i: number): number
		while group[i] ~= i do
			i = group[i]
		end
		return i
	end
	for i = 1, #fires do
		for j = i + 1, #fires do
			if Geo.distance(fires[i], fires[j]) <= CONST.SOLO.CLUSTER_GAP then
				group[root(i)] = root(j)
			end
		end
	end
	local by_root: { [number]: { Npc } } = {}
	local clusters: { { Npc } } = {}
	for i, fire in ipairs(fires) do
		local g = root(i)
		if by_root[g] == nil then
			by_root[g] = {}
			table.insert(clusters, by_root[g])
		end
		table.insert(by_root[g], fire)
	end
	return clusters
end

function Hazard.show_fires(force: boolean?)
	local layers: { { tiles: { Tile }, color: Draw.Color } } = {}
	local keys: { string } = {}
	if DebugDraw.on() then
		local in_p5 = CONFIG.solo and S.solo.p5_stage ~= nil
		local clusters = Hazard.fire_clusters(Hazard.fire_npcs())
		table.sort(clusters, function(a: { Npc }, b: { Npc }): boolean
			return a[1].x * 100000 + a[1].y < b[1].x * 100000 + b[1].y
		end)
		for i, cluster in ipairs(clusters) do
			local tiles: { Tile } = {}
			for _, fire in ipairs(cluster) do
				for _, t in ipairs(Hazard.fire_tiles(fire)) do
					table.insert(tiles, t)
					table.insert(keys, `{t.x},{t.y}`)
				end
			end
			local ignored = in_p5 and #cluster > CONST.SOLO.P5_MAX_CLUSTER
			local palette = CONST.CLUSTER_COLORS
			local color = if ignored then CONST.IGNORED_CLUSTER_COLOR else palette[(i - 1) % #palette + 1]
			table.insert(layers, { tiles = tiles, color = color })
		end
		table.sort(keys)
		table.insert(keys, if in_p5 then "p5" else "")
	end
	local shown = table.concat(keys, ";")
	if shown == S.fires_shown and not force then
		return
	end
	S.fires_shown = shown
	if #layers == 0 then
		DebugDraw.set("fires", nil)
		return
	end
	DebugDraw.set("fires", function()
		for _, layer in ipairs(layers) do
			DebugDraw.outline(layer.tiles, layer.color, CONST.FIRE_DEBUG_WIDTH)
		end
	end)
end

function Hazard.watch_clouds()
	local now = snap.tick
	local seen: { [number]: boolean } = {}
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.STORM_CLOUD and n.animation == CONST.CLOUD_GROWING then
			seen[n.index] = true
			if S.growing_due[n.index] == nil then
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
	local active: { [number]: boolean } = {}
	for _, n in ipairs(snap.npcs) do
		local a = n.animation
		if
			n.id == CONST.STORM_CLOUD
			and (a == CONST.CLOUD_GROWING or a == CONST.CLOUD_CHARGING or a == CONST.CLOUD_ATTACK)
		then
			active[n.index] = true
			S.cloud_started[n.index] = S.cloud_started[n.index] or time()
		end
	end
	for index in pairs(S.cloud_started) do
		if not active[index] then
			S.cloud_started[index] = nil
		end
	end
end

function Hazard.is_striking(n: Npc): boolean
	if n.animation == CONST.CLOUD_CHARGING or n.animation == CONST.CLOUD_ATTACK then
		return true
	end
	local due = S.growing_due[n.index]
	return due ~= nil and snap.tick >= due
end

function Hazard.in_cloud_square(n: Npc, tile: Tile, more: number): boolean
	local dx = math.max(n.x - 1 - tile.x, tile.x - n.x, 0)
	local dy = math.max(n.y - 1 - tile.y, tile.y - n.y, 0)
	return math.max(dx, dy) <= more
end

function Hazard.hazard_at(tile: Tile, extra: number?): Npc?
	local more = extra or 0
	local incoming = if snap.walking then nil else Hazard.incoming_at(tile, more)
	if incoming then
		return incoming
	end
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
				local d = Hazard.fire_distance(n, tile)
				if d <= reach + more and d < best_d then
					best, best_d = n, d
				end
			end
		end
	end
	return best
end

function Hazard.log_burn(dest: Tile?)
	local fires: { string } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		if Hazard.fire_distance(fire, snap.me) <= 3 then
			local tiles = Hazard.fire_tiles(fire)
			local a, b = tiles[1], tiles[#tiles]
			table.insert(fires, `{fire.x},{fire.y} covering {a.x}..{b.x},{a.y}..{b.y}`)
		end
	end
	local landings: { string } = {}
	for _, landing in pairs(S.incoming) do
		table.insert(landings, `{landing.tile.x},{landing.tile.y} in {math.floor(landing.lands - time())} ms`)
	end
	Log.log(
		"Tempoross",
		`   At {snap.me.x},{snap.me.y} tick {snap.tick}, destination {if dest then `{dest.x},{dest.y}` else "none"}`
	)
	Log.log("Tempoross", `   Fires within 3: {table.concat(fires, "; ")}`)
	Log.log("Tempoross", `   Landings: {table.concat(landings, "; ")}`)
	Log.log("Tempoross", `   Walked: {table.concat(S.trail, " ")}`)
end

function Hazard.fire_near(tile: Tile, range: number): Npc?
	return Geo.nearest_npc(Hazard.fire_npcs(), tile, function(n)
		return Hazard.fire_distance(n, tile) <= range
	end)
end

function Hazard.track_fires()
	local seen: { [string]: boolean } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		local key = `{fire.x},{fire.y}`
		seen[key] = true
		if not S.fires_known[key] then
			S.fires_known[key] = true
			Log.log("Tempoross", `   Fire appeared at {key} (tick {snap.tick})`)
		end
	end
	for key in pairs(S.fires_known) do
		if not seen[key] then
			S.fires_known[key] = nil
			Log.log("Tempoross", `   Fire gone at {key} (tick {snap.tick})`)
		end
	end
end

function Hazard.watch_projectiles()
	Hazard.track_fires()
	local now = time()
	for key, landing in pairs(S.incoming) do
		if now > landing.lands + CONST.INCOMING_LINGER_MS then
			S.incoming[key] = nil
		end
	end
	for _, p in ipairs(Projectiles.find() or {}) do
		local key = `{p.id}:{p.source_x},{p.source_y}:{p.target_x},{p.target_y}:{p.end_cycle}`
		if not S.projectiles_seen[key] then
			S.projectiles_seen[key] = true
			local eta = math.max(0, (p.end_cycle - p.cycle) * Projectiles.CYCLE_MS)
			if p.id == CONST.FIRE_SPREAD then
				S.incoming[key] = { tile = { x = p.target_x, y = p.target_y }, lands = now + eta }
				Log.log(
					"Tempoross",
					`   Fire spreading from {p.source_x},{p.source_y} to {p.target_x},{p.target_y}, lands in {eta} ms`
				)
			elseif not S.projectiles_seen[`id:{p.id}`] then
				S.projectiles_seen[`id:{p.id}`] = true
				Log.log(
					"Tempoross",
					`   Projectile {p.id} from {p.source_x},{p.source_y} to {p.target_x},{p.target_y}, lands in {eta} ms`
				)
			end
		end
	end
end

function Hazard.incoming_at(tile: Tile, more: number): Npc?
	for _, landing in pairs(S.incoming) do
		local spot = landing.tile
		local probe = { id = CONST.FIRE, x = spot.x, y = spot.y, index = -1 } :: any
		if Hazard.fire_distance(probe, tile) <= CONST.FIRE_REACH + more then
			return { id = CONST.INCOMING_FIRE, x = spot.x, y = spot.y, index = -1, name = "Incoming fire" } :: any
		end
	end
	return nil
end

function Hazard.describe_hazard(n: Npc): string
	return `{if n.id == CONST.FIRE
		then "fire"
		elseif n.id == CONST.INCOMING_FIRE then "fire landing"
		elseif n.id == CONST.LIGHTNING_STRIKE then "lightning strike"
		else "storm cloud"} at {n.x},{n.y}`
end

function Route.sleep_watching(ms: number, at: Tile?, should_stop: (() -> boolean)?): boolean
	local deadline = time() + ms
	repeat
		sleep(math.floor(math.max(1, math.min(CONST.POLL_MS, deadline - time()))))
		local s = game_state()
		if s.position then
			snap.me = { x = s.position.x, y = s.position.y }
		end
		snap.walking = s.destination ~= nil
		snap.tick = Read.current_tick(s)
		Read.note_trail()
		snap.npcs = Read.read_npcs() or snap.npcs
		Hazard.watch_clouds()
		Hazard.watch_projectiles()
		Hazard.show_fires()
		if DebugDraw.on() then
			Walker.show_route()
		end
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

function Route.first_fire(tiles: { Tile }, ignore: Npc?): Npc?
	local all = Hazard.fire_npcs()
	if #all == 0 then
		return nil
	end
	for i = 2, #tiles do
		local t = tiles[i]
		local fire = Geo.nearest_npc(all, t, function(n)
			return Hazard.fire_distance(n, t) <= CONST.FIRE_REACH
				and (ignore == nil or n.index ~= (ignore :: Npc).index)
		end)
		if fire then
			return fire
		end
	end
	return nil
end

function Route.landing_ahead(tiles: { Tile }): (Tile?, number)
	local now = time()
	local landings: { { tile: Tile, lands: number } } = {}
	for _, landing in pairs(S.incoming) do
		table.insert(landings, landing)
	end
	for _, n in ipairs(snap.npcs) do
		local started = S.cloud_started[n.index]
		if n.id == CONST.STORM_CLOUD and started then
			table.insert(landings, { tile = { x = n.x, y = n.y }, lands = started + CONST.CLOUD_STRIKE_MS })
		end
	end
	local burning: { [string]: boolean } = {}
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.FIRE then
			burning[`{n.x},{n.y}`] = true
		end
	end
	for _, landing in ipairs(landings) do
		local probe = { id = CONST.FIRE, x = landing.tile.x, y = landing.tile.y, index = -1 } :: any
		local until_landing = landing.lands - now
		local landed = until_landing <= 0 and burning[`{landing.tile.x},{landing.tile.y}`] == true
		if not landed then
			for i = 2, #tiles do
				local arrival = (i - 1) * CONST.SPOT_COST.tile_ms
				if
					arrival >= until_landing - CONST.LANDING_MARGIN_MS
					and Hazard.fire_distance(probe, tiles[i]) <= CONST.FIRE_REACH
				then
					return landing.tile, math.max(0, until_landing)
				end
			end
		end
	end
	return nil, 0
end

function Route.safe_route(tiles: { Tile }, count_fires: boolean?): boolean
	for i = 2, #tiles do
		local hazard = Hazard.hazard_at(tiles[i])
		if hazard and hazard.id ~= CONST.FIRE then
			return false
		end
	end
	for _, n in ipairs(snap.npcs) do
		local reach = if n.id == CONST.FIRE
			then (if count_fires == false then nil else CONST.FIRE_REACH)
			elseif n.id == CONST.LIGHTNING_STRIKE then CONST.FIRE_REACH
			else nil
		if reach then
			local function distance(t: Tile): number
				return if n.id == CONST.FIRE then Hazard.fire_distance(n, t) else Geo.distance(n, t)
			end
			local limit = math.min(reach + 1, distance(snap.me))
			for i = 2, #tiles do
				if distance(tiles[i]) < limit then
					return false
				end
			end
		end
	end
	return true
end

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

function Route.route_end(to: Tile): Tile
	local tiles = Route.route_to(to)
	return if tiles and #tiles > 0 then tiles[#tiles] else to
end

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

function Doing.check_activity()
	local a = S.activity
	if a == nil then
		return
	end
	if a.kind == "fish" or a.kind == "cook" or a.kind == "load" or a.kind == "pump" then
		Inventory.open()
	end
	local sig = Read.progress_signature()
	local at = `{snap.me.x},{snap.me.y}`
	if sig ~= a.last_signature or at ~= a.last_tile then
		a.last_signature = sig
		a.last_tile = at
		a.last_progress_ms = time()
	end
	if a.kind == "pump" and Read.item_count(Items.BUCKET) == 0 then
		S.activity = nil
		return
	end
	if a.kind == "repair" and a.loc then
		local now = Read.loc_at(a.loc :: Loc, { "Mast", "Damaged mast", "Totem pole", "Damaged totem pole" })
		if now == nil or not Chat.contains(now.name or "", "Damaged") then
			S.activity = nil
			return
		end
	end
	local can_go = (a.kind ~= "fish" or snap.free > 0)
		and (a.kind ~= "cook" or Read.item_count(Items.RAW_FISH) > 0)
		and (a.kind ~= "load" or Read.fish_count() > 0)
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
		Doing.log_stall(a)
		S.activity = nil
	end
end

function Doing.log_stall(a: Activity)
	local s = Host.game_state()
	local dest = s.destination
	local me = s.player_name
	local animation, target = -1, -1
	for _, p in ipairs(Host.players() or {}) do
		if p.name == me then
			animation, target = p.animation, p.target_state
			break
		end
	end
	Log.log(
		"Tempoross",
		`   {a.kind} stalled at {snap.me.x},{snap.me.y}: destination {if dest then `{dest.x},{dest.y}` else "none"}, animation {animation}, target {target}, menu [{Read.menu_text()}], walked {table.concat(
			S.trail,
			" "
		)}`
	)
end

function Read.menu_text(): string
	local parts = {}
	for _, e in ipairs(Minimenu.entries() or {}) do
		table.insert(parts, Minimenu.text(e))
	end
	return table.concat(parts, ", ")
end

function Route.clear_route(target: Tile, what: string, opts: WayOptions?): boolean
	local o: WayOptions = opts or {}
	local tiles = Route.route_to(target)
	Route.log_detour(what, snap.me, target, tiles)
	if tiles == nil or #tiles == 0 then
		return true
	end
	Hazard.watch_projectiles()
	local landing, wait_ms = Route.landing_ahead(tiles)
	if landing and not o.urgent then
		local l = landing :: Tile
		Log.log(
			"Tempoross",
			`   Fire landing at {l.x},{l.y} on the way to {what} in {math.floor(wait_ms)} ms, waiting for it`
		)
		Route.sleep_watching(wait_ms + CONST.LANDING_MARGIN_MS)
		return false
	end
	local fire = if o.ignore then nil else Route.first_fire(tiles, o.ignore)
	if fire and CONFIG.solo and Solo.keeping_fires() and not o.urgent then
		if Solo.get_past_fires(target, tiles) then
			return false
		end
		Log.log("Tempoross", `   No water left, walking past the fire at {(fire :: Npc).x},{(fire :: Npc).y}`)
		fire = nil
	end
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

function Task.use_npc(npc: Npc, options: { string }, way: WayOptions?): boolean
	local stand = if npc.id == CONST.FIRE then npc else Route.npc_stand(npc)
	if not Route.clear_route(stand, npc.name, way) then
		return false
	end
	local ok = Npcs.approach(npc, options, Route.approach_opts(way))
	if not ok then
		Log.log("Tempoross", "   Can't", table.concat(options, "/"), "on", npc.name)
		return false
	end
	return true
end

function Task.use_loc(loc: Loc, options: { string }, way: WayOptions?): boolean
	if not Route.clear_route(Route.loc_stand(loc), loc.name or "?", way) then
		return false
	end
	local ok = Objects.approach(loc, options, Route.approach_opts(way))
	if not ok then
		Log.log("Tempoross", "   Can't", table.concat(options, "/"), "on", loc.name or "?")
		return false
	end
	return true
end

function Route.walking_out_of(hazard: Npc): boolean
	if hazard.id ~= CONST.FIRE or not snap.walking then
		return false
	end
	local dest = Player.destination()
	local tiles = dest and Route.route_to(dest :: Tile)
	if tiles == nil or #tiles < 2 then
		return false
	end
	return Hazard.fire_distance(hazard, tiles[2]) > 0
end

function Route.fire_ahead(dest: Tile?, ignore: Npc?): Npc?
	if dest == nil then
		return nil
	end
	local tiles = Route.route_to(dest :: Tile)
	return tiles and Route.first_fire(tiles :: { Tile }, ignore)
end

function Route.should_interrupt_walk(for_wave: boolean, known: { [number]: boolean }, ignore: Npc?): boolean
	Chat.read_chat()
	if not for_wave and events.wave_warning_at ~= nil and not events.tethered and Read.has_rope() then
		return true
	end
	if events.game_result and S.in_game then
		return true
	end
	local s = game_state()
	if s.position then
		snap.tick = Read.current_tick(s)
		Read.set_me(s.position)
		snap.npcs = Read.read_npcs() or snap.npcs
		Hazard.watch_projectiles()
		if not for_wave and Read.item_count(Items.WATER) > 0 and Hazard.fire_near(snap.me, CONST.FIRE_REACH) then
			return true
		end
		local fire = if for_wave then nil else Route.fire_ahead(s.destination, ignore)
		if fire and Read.item_count(Items.WATER) > 0 then
			Log.log("Tempoross", `   Fire at {fire.x},{fire.y} on our way, putting it out`)
			events.fire_in_way = fire
			return true
		end
		if fire and not known[fire.index] then
			Log.log("Tempoross", `   New fire at {fire.x},{fire.y} on our way, replanning`)
			return true
		end
	end
	return false
end

function Route.walk_checks(for_wave: boolean, ignore: Npc?): Walker.WalkOptions
	snap.npcs = Read.read_npcs() or snap.npcs
	local known: { [number]: boolean } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		known[fire.index] = true
	end
	return {
		on_step = function()
			if CONFIG.antiban and not S.in_game then
				Antiban.do_walking_antiban()
			end
			return not Route.should_interrupt_walk(for_wave, known, ignore)
		end,
		before_click = function(target: Tile, here: Tile): boolean?
			if for_wave or Read.item_count(Items.WATER) == 0 then
				return true
			end
			snap.npcs = Read.read_npcs() or snap.npcs
			Hazard.watch_projectiles()
			local tiles = Route.route_to(target, here)
			Route.log_detour("walk click", here, target, tiles)
			local landing = tiles and Route.landing_ahead(tiles :: { Tile })
			if landing then
				Log.log("Tempoross", `   Fire landing at {landing.x},{landing.y} on the way`)
				return false
			end
			local fire = tiles and Route.first_fire(tiles :: { Tile }, ignore)
			if fire then
				Log.log("Tempoross", `   Fire at {fire.x},{fire.y} on the way`)
				events.fire_in_way = fire
				return false
			end
			return true
		end,
	}
end

function Route.jitter_tile(tile: Tile): Tile
	for _ = 1, 10 do
		local t = { x = tile.x + Random.int(-4, 4), y = tile.y + Random.int(-4, 4) }
		local tiles = Route.route_to(t)
		if tiles ~= nil and #tiles > 0 and tiles[#tiles].x == t.x and tiles[#tiles].y == t.y then
			return t
		end
	end
	return tile
end

function Route.walk_near(tile: Tile, near: number, for_wave: boolean?): boolean
	Read.set_me(Walker.position())
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

function Route.approach_opts(way: WayOptions?): Clickbox.Approach
	return {
		walk = Route.walk_checks(way ~= nil and way.urgent == true, way and way.ignore),
		arrive_ms = false,
	}
end

function Route.beside(footprint: { Tile }): { Tile }
	local taken: { [string]: boolean } = {}
	for _, t in ipairs(footprint) do
		taken[`{t.x},{t.y}`] = true
	end
	local out: { Tile } = {}
	for _, t in ipairs(footprint) do
		for _, d in ipairs({ { x = 1, y = 0 }, { x = -1, y = 0 }, { x = 0, y = 1 }, { x = 0, y = -1 } }) do
			local c = { x = t.x + d.x, y = t.y + d.y }
			local key = `{c.x},{c.y}`
			if not taken[key] then
				taken[key] = true
				table.insert(out, c)
			end
		end
	end
	return out
end

function Route.nearest_of(candidates: { Tile }): { Tile }?
	local best: { Tile }? = nil
	for _, c in ipairs(candidates) do
		local route = Route.route_to(c)
		if route and #route > 0 then
			local last = route[#route]
			if last.x == c.x and last.y == c.y and (best == nil or #route < #(best :: { Tile })) then
				best = route
			end
		end
	end
	return best
end

function Route.npc_stand(npc: Npc): Tile
	local route = Route.nearest_of(Route.beside({ { x = npc.x, y = npc.y } }))
	return if route then route[#route] else Route.route_end(Geo.to_tile(npc))
end

function Route.loc_stand(loc: Loc): Tile
	local route = Route.nearest_of(Objects.stand_tiles(loc) or {})
	return if route then route[#route] else Route.route_end(Geo.to_tile(loc))
end

function Hazard.douse_route(fire: Npc): { Tile }?
	return Route.nearest_of(Route.beside(Hazard.fire_tiles(fire))) or Route.route_to(fire)
end

function Hazard.douse_target(fire: Npc): Npc
	for _ = 1, 4 do
		local tiles = Hazard.douse_route(fire)
		local closer = tiles and Route.first_fire(tiles :: { Tile }, fire)
		if closer == nil then
			break
		end
		fire = closer :: Npc
	end
	return fire
end

function Hazard.prehover_after_douse(fire: Npc, toward: Tile)
	local to_fire = Hazard.douse_route(fire)
	local stand = to_fire and to_fire[#to_fire] or snap.me
	local onward = Route.route_to(toward, stand)
	if onward == nil then
		return
	end
	local next_fire = Route.first_fire(onward, fire)
	if next_fire then
		if Npcs.hover_async(next_fire, stand) then
			S.solo.fire_hover = next_fire
			Log.log("Tempoross", `   Hovering the next fire at {next_fire.x},{next_fire.y}`)
		end
		return
	end
	for i = #onward, 2, -1 do
		if Walker.hover_tile_async(onward[i], stand) then
			Log.log("Tempoross", `   Hovering {onward[i].x},{onward[i].y} past the fire`)
			return
		end
	end
end

function Hazard.burning_at(fire: Npc): boolean
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.FIRE and n.x == fire.x and n.y == fire.y then
			return true
		end
	end
	return false
end

function Hazard.douse(fire: Npc, toward: Tile?): boolean
	local before = Read.item_count(Items.WATER)
	if before == 0 then
		return false
	end
	local current = Npcs.refresh(fire)
	if current == nil or current.id ~= CONST.FIRE then
		return false
	end
	fire = Hazard.douse_target(current :: Npc)
	S.solo.fire_hover = nil
	if not Task.use_npc(fire, { "Douse" }, { ignore = fire }) then
		return false
	end
	Log.log("Tempoross", "   Dousing fire at", fire.x, fire.y)
	if toward then
		Hazard.prehover_after_douse(fire, toward :: Tile)
	end
	local deadline = time() + 6000
	local animation_ended = false
	while time() < deadline do
		local dousing = Read.my_animation() == CONST.DOUSE_ANIMATION
		animation_ended = animation_ended or not dousing
		if dousing and animation_ended then
			S.doused[`{fire.x},{fire.y}`] = time()
			return true
		end
		local st = game_state()
		snap.tick = Read.current_tick(st)
		Read.set_me(st.position)
		snap.npcs = Read.read_npcs() or snap.npcs
		if not Hazard.burning_at(fire) then
			S.doused[`{fire.x},{fire.y}`] = time()
			return true
		end
		Hazard.watch_projectiles()
		local dest = st.destination
		local ahead = dest and Route.route_to(dest :: Tile)
		local other = ahead and Route.first_fire(ahead :: { Tile }, fire)
		if other then
			Log.log("Tempoross", `   Fire at {other.x},{other.y} on the way to the fire at {fire.x},{fire.y}`)
			events.fire_in_way = other
			return false
		end
		sleep(CONST.POLL_MS)
	end
	return false
end

function Route.safe_tile(towards: Tile?, margin: number?): Tile?
	local clearance = if margin == nil then 1 else margin :: number
	local candidates: { { tile: Tile, score: number } } = {}
	for dx = -7, 7 do
		for dy = -7, 7 do
			local t = { x = snap.me.x + dx, y = snap.me.y + dy }
			local d = Geo.distance(t, snap.me)
			if d >= 1 and Hazard.hazard_at(t, clearance) == nil then
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
	if clearance > 0 then
		return Route.safe_tile(towards, 0) or reachable
	end
	return reachable
end

function Route.step_away(towards: Tile?): boolean
	local t = Route.safe_tile(towards)
	if t == nil then
		Log.log("Tempoross", "   No safe tile nearby")
		Route.sleep_watching(Random.int(300, 500), nil, function()
			return false
		end)
		return false
	end
	Log.log("Tempoross", "   Stepping away to", t.x, t.y)
	Doing.clear_activity()
	S.dodging_to = t
	if not Walker.click_tile(t :: Tile) then
		Walker.click_minimap(t :: Tile)
	end
	local landed = Route.sleep_watching(Random.int(600, 900), nil, function(): boolean
		return Hazard.hazard_at(t) ~= nil or (snap.me.x == t.x and snap.me.y == t.y)
	end)
	if landed and Hazard.hazard_at(t) ~= nil then
		return Route.step_away(towards)
	end
	return true
end

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

function Read.offers_untether(loc: Loc): boolean
	local views = Host.loc_shown({ loc.id })
	local view = views and views[1]
	return view ~= nil and table.find(view.actions, "Untether") ~= nil
end

function Read.is_tethered(target: Loc): boolean
	return (varbit(CONST.TETHERED_VARBIT) or 0) ~= 0 or Read.offers_untether(target)
end

function Task.repair_for_wave(target: Loc): Loc?
	if not Task.use_loc(target, { "Repair" }, { urgent = true }) then
		return nil
	end
	Log.log("Tempoross", `   Repairing the {target.name} before the wave`)
	local fixed: Loc? = nil
	Route.sleep_watching(CONST.REPAIR_WAIT_MS, nil, function(): boolean
		snap.locs = nil
		local now = Read.loc_at(target, { "Mast", "Totem pole" })
		fixed = now
		return now ~= nil
	end)
	return fixed
end

function Task.tether()
	local hammer = Read.has_hammer()
	local options: { Loc } = {}
	for _, l in ipairs({ Ship.our_mast(), Ship.our_totem() } :: { Loc? }) do
		if l and (hammer or not Chat.contains((l :: Loc).name or "", "Damaged")) then
			table.insert(options, l :: Loc)
		end
	end
	if #options == 0 then
		options = Read.locs_named({ "Mast", "Totem pole" })
	end
	local ranked: { { loc: Loc, steps: number } } = {}
	local seen = {}
	for _, l in ipairs(options) do
		local d = Route.walk_steps(Geo.to_tile(l), snap.me)
		local damaged = Chat.contains(l.name or "", "Damaged")
		table.insert(seen, `{l.name} {d} steps`)
		if damaged then
			d += CONST.REPAIR_STEPS
		end
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
	Log.log("Tempoross", `   Tether options: {table.concat(seen, ", ")}; picked the {target.name}`)
	if Chat.contains(target.name or "", "Damaged") then
		local fixed = Task.repair_for_wave(target)
		if fixed == nil then
			return
		end
		target = fixed :: Loc
	end
	local fire = Hazard.fire_near(target, 1)
	if fire and Read.item_count(Items.WATER) > 0 then
		Hazard.douse(fire)
	end
	Doing.clear_activity()
	if not Route.walk_near(target, 12, true) then
		return
	end
	Route.sleep_watching(Random.int(4 * Ticks.MS, 6 * Ticks.MS))
	if events.wave_warning_at == nil or events.tethered or snap.tethered then
		return
	end
	local deadline = time() + 12000
	while time() < deadline do
		if Read.is_tethered(target) then
			events.tethered = true
			return
		end
		if not Task.use_loc(target, { "Tether" }, { urgent = true }) then
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
			if Read.is_tethered(target) then
				events.tethered = true
				return
			end
			if events.tethered or events.wave_warning_at == nil then
				return
			end
			local s = game_state()
			if time() - clicked > 3600 and s.destination == nil and not Doing.player_is_working("tether") then
				Log.log("Tempoross", "   No tether yet, clicking again")
				break
			end
			sleep(100)
		end
	end
end

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
	if energy >= 100 then
		S.energy_dir = "down"
	end
	S.last_energy = energy
end

function Hazard.tempoross_vulnerable(): boolean
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.SPIRIT_POOL then
			return true
		end
	end
	local energy = Read.hud_percent(HUD.ENERGY)
	return energy ~= nil and energy <= 0 and S.energy_dir == "down"
end

function Task.usable_crates(quiet: boolean?): { Npc }
	local mast = (S.side :: Side).mast
	local crates: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.name == "Ammunition crate" and Geo.distance(n, mast) <= 4 then
			table.insert(crates, n)
		end
	end
	local usable: { Npc } = {}
	local cannons = Read.locs_named({ "Harpoonfish cannon", "Electrified harpoonfish cannon" })
	for _, crate in ipairs(crates) do
		local cannon = Geo.nearest_loc(cannons, crate)
		if cannon and (cannon :: Loc).name == "Electrified harpoonfish cannon" then
			if not quiet then
				Log.log("Tempoross", "   The crate at", crate.x, crate.y, "has an electrified cannon")
			end
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

function Task.surge_pending(): boolean
	if time() >= events.surge_until then
		return false
	end
	local mast = (S.side :: Side).mast
	for _, cannon in ipairs(Read.locs_named({ "Electrified harpoonfish cannon" })) do
		if Geo.loc_distance(cannon, mast) <= CONST.CANNON_RANGE then
			events.surge_until = 0
			return false
		end
	end
	return true
end

function Task.wait_out_surge()
	if not S.surge_logged then
		S.surge_logged = true
		Log.log("Tempoross", "   Holding off the crates until we see which cannon is electrified")
	end
	if Doing.is_doing("load") then
		Task.clear_crates()
		return
	end
	Route.sleep_watching(Random.int(300, 600))
end

function Task.clear_crates()
	local mast = (S.side :: Side).mast
	local crates: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.name == "Ammunition crate" and Geo.distance(n, mast) <= 4 then
			table.insert(crates, n)
		end
	end
	local best: Tile? = nil
	local best_d = math.huge
	for dx = -6, 6 do
		for dy = -6, 6 do
			local t = { x = snap.me.x + dx, y = snap.me.y + dy }
			local clear = Hazard.hazard_at(t, 1) == nil
			for _, crate in ipairs(crates) do
				clear = clear and Geo.distance(crate, t) >= CONST.SURGE_CLEARANCE
			end
			local d = Geo.distance(t, snap.me)
			if clear and d < best_d then
				local tiles = Route.route_to(t)
				local last = tiles and tiles[#tiles]
				if last and last.x == t.x and last.y == t.y then
					best, best_d = t, d
				end
			end
		end
	end
	Doing.clear_activity()
	if best == nil then
		Route.step_away(mast)
		return
	end
	Log.log("Tempoross", `   Stepping clear of the cannons to {(best :: Tile).x},{(best :: Tile).y}`)
	if not Walker.click_tile(best :: Tile) then
		Walker.click_minimap(best :: Tile)
	end
	Route.sleep_watching(Random.int(600, 900))
end

function Task.clickable_crate(): Npc?
	for _, crate in ipairs(Task.usable_crates(true)) do
		if Hazard.hazard_at(Route.npc_stand(crate)) == nil and Npcs.target(crate) ~= nil then
			return crate
		end
	end
	return nil
end

function Task.crate_safe_tile(): Tile?
	local mast = (S.side :: Side).mast
	local crates: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.name == "Ammunition crate" and Geo.distance(n, mast) <= 4 then
			table.insert(crates, n)
		end
	end
	for i = 1, #crates do
		for j = i + 1, #crates do
			local a, b = crates[i], crates[j]
			if a.x == b.x and math.abs(a.y - b.y) == 2 then
				return { x = a.x, y = (a.y + b.y) // 2 }
			end
			if a.y == b.y and math.abs(a.x - b.x) == 2 then
				return { x = (a.x + b.x) // 2, y = a.y }
			end
		end
	end
	return nil
end

function Task.crate_stand(): Tile?
	if time() < S.crate_stand_off_until or (CONFIG.solo and S.solo.first_loaded_at == nil) then
		return nil
	end
	local safe = Task.crate_safe_tile()
	if safe == nil then
		return nil
	end
	for _, fire in ipairs(Hazard.fire_npcs()) do
		if
			Hazard.fire_distance(fire, snap.me) <= CONST.CRATE_FIRE_RANGE
			or Hazard.fire_distance(fire, safe :: Tile) <= CONST.CRATE_FIRE_RANGE
		then
			return safe
		end
	end
	return nil
end

function Task.off_crate_stand(): boolean
	local stand = Task.crate_stand()
	return stand ~= nil and (snap.me.x ~= (stand :: Tile).x or snap.me.y ~= (stand :: Tile).y)
end

function Task.load_from_stand(stand: Tile): Npc?
	if snap.me.x ~= stand.x or snap.me.y ~= stand.y then
		local tiles = Route.route_to(stand)
		local last = tiles and tiles[#tiles]
		if last == nil or last.x ~= stand.x or last.y ~= stand.y then
			Log.log("Tempoross", `   The tile between the crates at {stand.x},{stand.y} can't be reached`)
			S.crate_stand_off_until = time() + CONST.CRATE_STAND_RETRY_MS
			return nil
		end
		if not Route.clear_route(stand, "the tile between the crates") then
			return nil
		end
		Log.log("Tempoross", `   Fire near the crates, loading from between them at {stand.x},{stand.y}`)
		local crate = Task.usable_crates(true)[1]
		local hovered = false
		local o = Route.walk_checks(false)
		local checks: ((Tile) -> boolean?)? = o.on_step
		o.on_step = function(tile: Tile): boolean?
			if checks and checks(tile) == false then
				return false
			end
			local dest = Player.destination()
			if crate and not hovered and dest and dest.x == stand.x and dest.y == stand.y then
				hovered = Npcs.hover_async(crate :: Npc, stand)
			end
			return true
		end
		o.near = 0
		o.timeout_ms = 20000
		Walker.walk(stand, o)
		Read.set_me(game_state().position)
		if snap.me.x ~= stand.x or snap.me.y ~= stand.y then
			return nil
		end
	end
	local crate = Task.usable_crates(true)[1]
	if crate and Task.use_npc(crate :: Npc, { "Fill" }) then
		Doing.begin_activity("load", crate)
		return crate
	end
	return nil
end

function Task.walk_to_crate(): Npc?
	local stand = Task.crate_stand()
	if stand then
		return Task.load_from_stand(stand :: Tile)
	end
	local crate = Task.clickable_crate()
	if crate == nil then
		local o = Route.walk_checks(false)
		local checks: ((Tile) -> boolean?)? = o.on_step
		o.on_step = function(tile: Tile): boolean?
			if checks and checks(tile) == false then
				return false
			end
			crate = Task.clickable_crate()
			return crate == nil
		end
		o.near = 1
		o.timeout_ms = 30000
		Walker.walk(Route.route_end(Geo.to_tile((S.side :: Side).mast)), o)
	end
	if crate and Task.use_npc(crate :: Npc, { "Fill" }) then
		Doing.begin_activity("load", crate)
		return crate
	end
	return nil
end

function Task.load_fish()
	local s = S.side :: Side
	if Task.surge_pending() then
		Task.wait_out_surge()
		return
	end
	if Geo.distance(snap.me, s.mast) > CONST.CANNON_RANGE then
		Task.walk_to_crate()
		return
	end
	local crates = Task.usable_crates()
	local crate = crates[1]
	if crates[2] and math.random() < 0.15 then
		crate = crates[2]
	end
	if crate == nil then
		Log.log("Tempoross", "   Both cannons are electrified, waiting")
		Route.sleep_watching(Random.int(600, 1200))
		return
	end
	local stand = Task.crate_stand()
	if stand then
		Task.load_from_stand(stand :: Tile)
		return
	end
	if Hazard.hazard_at(Route.npc_stand(crate)) and crates[2] and crate ~= crates[2] then
		crate = crates[2]
	end
	if Task.use_npc(crate, { "Fill" }) then
		Doing.begin_activity("load", crate)
	end
end

function Task.take_tool(name: string, got: () -> boolean, home_only: boolean?): boolean
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
		if name == "Buckets" then
			Inventory.open()
		end
		snap.inv, snap.free = Read.read_inventory()
		if got() then
			return true
		end
		if Route.sleep_watching(100) then
			return false
		end
	end
	return false
end

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

function Task.prehover_shrine()
	local shrine = (S.side :: Side).shrine
	if not Objects.hovered(shrine) then
		Objects.hover_async(shrine)
	end
end

function Task.cook()
	local shrine = (S.side :: Side).shrine
	if Task.use_loc(shrine, { "Cook-at" }) then
		Doing.begin_activity("cook", nil, shrine)
	end
end

function Task.fish_wanted(): number
	snap.inv, snap.free = Read.read_inventory()
	if CONFIG.solo then
		return math.max(0, math.min(snap.free, Solo.fish_target() - Read.fish_count()))
	end
	return snap.free
end

function Task.spot_cost(spot: Npc, steps: number, wanted: number): number
	local c = CONST.SPOT_COST
	local per_fish = if spot.id == CONST.DOUBLE_SPOT then c.double_fish_ms else c.single_fish_ms
	return steps * c.tile_ms + math.max(wanted, 1) * per_fish
end

function Task.double_worth(double: Npc): boolean
	local c = CONST.SPOT_COST
	local wanted = Task.fish_wanted()
	if wanted <= 0 then
		return false
	end
	local double_cost = Task.spot_cost(double, Route.walk_steps(double), wanted)
	local a = S.activity
	local alternative: number
	if a and a.kind == "fish" and a.npc then
		double_cost += c.switch_ms
		alternative = wanted * c.single_fish_ms
	else
		local single, single_steps = nil, math.huge
		for _, n in ipairs(snap.npcs) do
			if CONST.SINGLE_SPOTS[n.id] and Geo.distance(n, (S.side :: Side).totem) <= 14 and Task.stand_safe(n) then
				local steps = Route.walk_steps(n)
				if steps < single_steps then
					single, single_steps = n, steps
				end
			end
		end
		if single == nil then
			return true
		end
		alternative = Task.spot_cost(single :: Npc, single_steps, wanted)
	end
	if double_cost >= alternative then
		Log.log(
			"Tempoross",
			`   Skipping the double spot at {double.x},{double.y}: {wanted} fish to go, not worth the walk`
		)
		return false
	end
	return true
end

function Task.best_spot(double_only: boolean, except: Npc?, avoid_fires: boolean?): Npc?
	local now = snap.tick
	local totem = (S.side :: Side).totem
	local wanted = Task.fish_wanted()
	local candidates: { { spot: Npc, score: number } } = {}
	for _, n in ipairs(snap.npcs) do
		local kind_ok = n.id == CONST.DOUBLE_SPOT or (CONST.SINGLE_SPOTS[n.id] == true and not double_only)
		if
			kind_ok
			and (n.id ~= CONST.DOUBLE_SPOT or Read.double_ticks_left(n, now) >= CONST.DOUBLE_MIN_TICKS_LEFT)
			and Geo.distance(n, totem) <= 14
			and (except == nil or n.index ~= (except :: Npc).index)
			and Task.stand_safe(n)
		then
			table.insert(candidates, { spot = n, score = Task.spot_cost(n, Geo.distance(n, snap.me), wanted) })
		end
	end
	table.sort(candidates, function(a: { spot: Npc, score: number }, b: { spot: Npc, score: number }): boolean
		return a.score < b.score
	end)
	local walked: { { spot: Npc, score: number } } = {}
	for i = 1, math.min(#candidates, 6) do
		local spot = candidates[i].spot
		table.insert(walked, { spot = spot, score = Task.spot_cost(spot, Route.walk_steps(spot), wanted) })
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
				and Route.safe_route(tiles :: { Tile }, avoid_fires == true or Read.item_count(Items.WATER) == 0)
			)
		if ok then
			return spot
		end
	end
	return nil
end

function Task.fish_at(spot: Npc): boolean
	if spot.id == CONST.DOUBLE_SPOT and not CONFIG.solo then
		Route.sleep_watching(Random.int(0, 4 * Ticks.MS))
	end
	if Task.use_npc(spot, { "Harpoon" }, { avoid = true }) then
		Doing.begin_activity("fish", spot, nil, spot.id == CONST.DOUBLE_SPOT)
		return true
	end
	return false
end

function Hazard.dodge(hazard: Npc)
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
				and Hazard.hazard_at(Route.npc_stand(crate)) == nil
			then
				if Task.use_npc(crate, { "Fill" }) then
					Doing.begin_activity("load", crate)
					return
				end
			end
		end
	end
	local towards: Tile? = if a then (a.npc or a.loc) :: Tile? else nil
	if towards == nil and CONFIG.solo and S.solo.loading then
		towards = Solo.ship_target()
	end
	Route.step_away(towards)
end

function Game.new_game()
	Doing.clear_activity()
	events.wave_warning_at = nil
	events.tethered = false
	events.wave_hit_at = nil
	events.game_result = nil
	events.must_untether = false
	events.wave_hit_us = false
	events.burned = false
	events.stunned_until = 0
	events.waves_passed = 0
	events.surge_until = 0
	S.incoming = {}
	S.projectiles_seen = {}
	S.fires_known = {}
	S.fire_seen = {}
	S.doused = {}
	S.trail = {}
	S.trail_last = nil
	table.clear(S.growing_due)
	table.clear(S.cloud_started)
	S.energy_dir, S.last_energy = "up", nil
	S.pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy)
	S.worn_cache = nil
	S.solo = new_solo_round()
	S.side = Ship.find_side()
	if not S.preparing then
		stats.games += 1
	end
	local name = if S.preparing then "Preparation game" else `Game {stats.games}`
	if S.side then
		S.double_first_seen = {}
		Log.log("Tempoross", `{name} started on the {(S.side :: Side).name} ship`)
	else
		Log.log("Tempoross", "Game started, but our ship wasn't found yet")
	end
	local start = S.start_hover
	S.start_hover = nil
	if start and Walker.click_tile(start :: Tile) then
		Log.log("Tempoross", `   Off to the totem through {(start :: Tile).x},{(start :: Tile).y}`)
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

function Game.should_load(): boolean
	local fish = Read.fish_count()
	if fish == 0 then
		return false
	end
	if snap.free == 0 and (not CONFIG.cook.enabled or Read.item_count(Items.RAW_FISH) == 0) then
		return true
	end
	if Read.item_count(Items.RAW_FISH) == 0 and S.side and Geo.distance(snap.me, (S.side :: Side).mast) <= 6 then
		return true
	end
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	local energy = Read.hud_percent(HUD.ENERGY) or 100
	return fish >= 4 and (intensity >= CONFIG.load.intensity or energy <= CONFIG.load.energy)
end

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

function Read.in_port(): boolean
	local x = Geo.square_of(snap.me)
	return x >= CONST.PORT_MIN_SQUARE_X and not Player.in_instance()
end

function Game.wait_boarding(done: () -> boolean): boolean
	local started = time()
	local still_since: number? = nil
	while time() - started < CONST.BOARD_WAIT_MS do
		local s = game_state()
		if s.position then
			snap.me = { x = s.position.x, y = s.position.y }
		end
		if done() or GameState.fading() then
			Log.log("Tempoross", `   Boarding after {math.floor(time() - started)} ms`)
			return true
		end
		if s.destination ~= nil or Player.is_moving() or Player.is_animating() then
			still_since = nil
		else
			still_since = still_since or time()
			if time() - (still_since :: number) >= CONST.BOARD_STILL_MS then
				Log.log("Tempoross", "   The ladder click didn't take, clicking again")
				return false
			end
		end
		sleep(100)
	end
	return false
end

function Read.on_island(): boolean
	return Player.instance_id() == CONST.TEMPOROSS_CHUNK_ID
end

function Game.tiny_antiban(boat: boolean?)
	if not CONFIG.antiban or not S.antiban_ready or (CONFIG.solo and Solo.counting()) then
		return
	end
	local a = S.activity
	local kind = if boat then "boat" elseif a then (a :: Activity).kind else "idle"
	if CONFIG.solo and Solo.holding_camera(kind) then
		return
	end
	if not boat then
		local tethered = events.tethered or snap.tethered
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
	if Read.scene_loading(s) then
		sleep(100)
		return false
	end
	return Game.sign_in()
end

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

function Game.check_spellbook()
	if CONFIG.solo and Magic.spellbook() ~= "lunar" then
		local message = "Can't start: solo firefighter casts Humidify, switch to the Lunar spellbook"
		Log.warn("Tempoross", message)
		error(message, 0)
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

	Game.check_spellbook()
	Game.check_barehand()

	if CONFIG.antiban and not S.antiban_ready then
		Biometrics.setup_player()
		local MINUTE = Antiban.MINUTE
		Antiban.set_zoom_range(0, 15)
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

		Antiban.sync_config()
		S.antiban_ready = true
		Log.log("Tempoross", "Antiban set up")
	end
end

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

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	local fish, cooked = Read.fish_count(), Read.item_count(Items.COOKED_FISH)
	if xp > S.last_xp or fish > S.last_fish or cooked > S.last_cooked then
		S.last_progress_at = time()
	end
	S.last_xp, S.last_fish, S.last_cooked = xp, fish, cooked
end

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

function Loop.wants_pier(): boolean
	local energy = Read.hud_percent(HUD.ENERGY)
	if S.energy_dir ~= "down" or energy == nil or energy > S.pier_energy then
		return false
	end
	local essence = Read.hud_percent(HUD.ESSENCE)
	if essence ~= nil and essence < CONST.PHASE_TWO_ESSENCE and Doing.is_doing("load") and Read.fish_count() > 10 then
		return false
	end
	return true
end

function Loop.common_game_state(): State?
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

	if time() < events.stunned_until then
		return "STUNNED"
	end

	if events.wave_warning_at ~= nil and not events.tethered and not snap.tethered and Read.has_rope() then
		if time() - (events.wave_warning_at :: number) < 9000 then
			return "TETHER"
		end
		events.wave_warning_at = nil
	end
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
	if snap.tethered or Doing.is_doing("tether") then
		return "WAIT_TETHERED"
	end
	if events.wave_hit_at then
		if snap.busy and time() - (events.wave_hit_at :: number) < 10000 then
			return "WAIT_FREE"
		end
		Log.log(
			"Tempoross",
			string.format(
				"   Free again %.1f s after the wave%s",
				(time() - (events.wave_hit_at :: number)) / 1000,
				if snap.busy then " (still busy)" else ""
			)
		)
		events.wave_hit_at = nil
	end
	if events.must_untether then
		return "UNTETHER_NEARBY"
	end

	local hazard = Hazard.hazard_at(snap.me)
	if hazard and not Route.walking_out_of(hazard :: Npc) then
		plan.hazard = hazard
		return "DODGE"
	end
	if snap.walking and Read.item_count(Items.WATER) > 0 then
		local ahead = Route.fire_ahead(Player.destination())
		local live = ahead and Npcs.refresh(ahead :: Npc)
		if live and live.id == CONST.FIRE then
			Log.log("Tempoross", `   Fire at {live.x},{live.y} on the way, putting it out`)
			plan.fire = live
			return "DOUSE_FIRE"
		end
	end
	if events.fire_in_way then
		local fire = Npcs.refresh(events.fire_in_way :: Npc)
		events.fire_in_way = nil
		if fire and fire.id == CONST.FIRE and Read.item_count(Items.WATER) > 0 then
			plan.fire = fire
			return "DOUSE_FIRE"
		end
	end

	if Doing.is_doing("load") and Task.surge_pending() then
		return "WAIT_SURGE"
	end

	if
		Hazard.tempoross_vulnerable()
		and not (CONFIG.solo and S.solo.p2_loading and Read.fish_count() > 0)
		and not (CONFIG.solo and Solo.ship_fires_left())
	then
		return "ATTACK"
	end
	if Doing.is_doing("attack") then
		Doing.clear_activity()
	end
	return nil
end

function Task.fill_state(skipped: { [State]: boolean }): State?
	if Read.item_count(Items.BUCKET) == 0 or skipped["FILL_BUCKETS"] then
		return nil
	end
	local pump = Task.pump_in_reach()
	if pump then
		plan.pump = pump
		return "FILL_BUCKETS"
	end
	return nil
end

function Read.my_animation(): number
	local me = Host.game_state().player_name
	for _, p in ipairs(Host.players() or {}) do
		if p.name == me then
			return p.animation
		end
	end
	return -1
end

function Route.fire_free(tiles: { Tile }): boolean
	local fires = Hazard.fire_npcs()
	for i = 2, #tiles do
		for _, fire in ipairs(fires) do
			if Hazard.fire_distance(fire, tiles[i]) == 0 then
				return false
			end
		end
	end
	return true
end

function Route.waypoint_around_fires(target: Tile): Tile?
	local me = snap.me
	local mid = { x = (me.x + target.x) // 2, y = (me.y + target.y) // 2 }
	local radius = CONST.SOLO.WAYPOINT_RADIUS
	local candidates: { { tile: Tile, cost: number } } = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			local t = { x = mid.x + dx, y = mid.y + dy }
			if Hazard.hazard_at(t) == nil then
				table.insert(candidates, { tile = t, cost = Geo.distance(me, t) + Geo.distance(t, target) })
			end
		end
	end
	table.sort(candidates, function(a: { tile: Tile, cost: number }, b: { tile: Tile, cost: number }): boolean
		return a.cost < b.cost
	end)
	for i = 1, math.min(#candidates, CONST.SOLO.WAYPOINT_TRIES) do
		local t = candidates[i].tile
		local first = Route.route_to(t)
		local last = first and first[#first]
		if last and last.x == t.x and last.y == t.y and Route.fire_free(first :: { Tile }) then
			local second = Route.route_to(target, t)
			if second and Route.fire_free(second) then
				return t
			end
		end
	end
	return nil
end

function Ship.other_side(): Side?
	local here = S.side :: Side
	local totem: Loc? = nil
	for _, t in ipairs(Read.locs_named({ "Totem pole", "Damaged totem pole" })) do
		if t.x ~= here.totem.x or t.y ~= here.totem.y then
			totem = t
		end
	end
	local mast: Loc? = nil
	for _, m in ipairs(Read.locs_named({ "Mast", "Damaged mast" })) do
		if m.x ~= here.mast.x or m.y ~= here.mast.y then
			mast = m
		end
	end
	if totem == nil or mast == nil then
		return nil
	end
	local shrine = Geo.nearest_loc(Read.locs_named({ "Shrine" }), totem :: Loc)
	if shrine == nil then
		return nil
	end
	return {
		name = if here.name == "west" then "east" else "west",
		mast = mast :: Loc,
		totem = totem :: Loc,
		shrine = shrine :: Loc,
	}
end

function Hazard.beside_fire(fire: Npc, t: Tile): boolean
	local size = Hazard.fire_size(fire)
	local x0, y0 = fire.x - size // 2, fire.y - size // 2
	local x1, y1 = x0 + size - 1, y0 + size - 1
	return (t.x >= x0 and t.x <= x1 and (t.y == y0 - 1 or t.y == y1 + 1))
		or (t.y >= y0 and t.y <= y1 and (t.x == x0 - 1 or t.x == x1 + 1))
end

function Hazard.douse_spot(near: { Npc }, countable: { Npc }, max_steps: number?): (Tile?, { Npc })
	local all = Hazard.fire_npcs()
	local seen: { [string]: boolean } = {}
	local best: Tile? = nil
	local best_fires: { Npc } = {}
	local best_steps = math.huge
	for _, around in ipairs(near) do
		for dx = -2, 1 do
			for dy = -2, 1 do
				local t = { x = around.x + dx, y = around.y + dy }
				local key = `{t.x},{t.y}`
				if not seen[key] and Hazard.beside_fire(around, t) then
					seen[key] = true
					local inside = false
					for _, fire in ipairs(all) do
						inside = inside or Hazard.fire_distance(fire, t) == 0
					end
					local beside: { Npc } = {}
					for _, fire in ipairs(countable) do
						if Hazard.beside_fire(fire, t) then
							table.insert(beside, fire)
						end
					end
					if not inside and #beside >= #best_fires and Hazard.hazard_at(t) == nil then
						local tiles = Route.route_to(t)
						local last = tiles and tiles[#tiles]
						local steps = if tiles then #(tiles :: { Tile }) else math.huge
						if
							last
							and last.x == t.x
							and last.y == t.y
							and steps <= (max_steps or math.huge)
							and Route.fire_free(tiles :: { Tile })
							and (#beside > #best_fires or steps < best_steps)
						then
							best, best_fires, best_steps = t, beside, steps
						end
					end
				end
			end
		end
	end
	return best, best_fires
end

function Hazard.lands_on(fire: Npc, stand: Tile): boolean
	local route = Hazard.douse_route(fire)
	local last = route and route[#route]
	return last ~= nil and last.x == stand.x and last.y == stand.y and Route.fire_free(route :: { Tile })
end

function Hazard.douse_from(stand: Tile, fires: { Npc }, why: string, rest: { Npc }?): boolean
	if snap.me.x ~= stand.x or snap.me.y ~= stand.y then
		local first: number? = nil
		for i, fire in ipairs(fires) do
			if Hazard.lands_on(fire, stand) then
				first = i
				break
			end
		end
		if first then
			local fire = table.remove(fires, first :: number) :: Npc
			table.insert(fires, 1, fire)
			Log.log(
				"Tempoross",
				`   Clicking the fire at {fire.x},{fire.y} walks to {stand.x},{stand.y}, putting out {#fires} fires from there ({why})`
			)
		else
			Log.log("Tempoross", `   Standing at {stand.x},{stand.y} to put out {#fires} fires from one tile ({why})`)
			local o = Route.walk_checks(false)
			o.near = 0
			o.timeout_ms = 15000
			Walker.walk(stand, o)
			Read.set_me(game_state().position)
			if snap.me.x ~= stand.x or snap.me.y ~= stand.y then
				return true
			end
		end
	end
	local doused = false
	for i, fire in ipairs(fires) do
		local following = fires[i + 1]
		local toward = if following then Geo.to_tile(following) else nil
		if toward == nil and rest and #(rest :: { Npc }) > 0 then
			local next_fire = Solo.cluster_target(rest :: { Npc })
			toward = if next_fire then Geo.to_tile(next_fire :: Npc) else nil
		end
		doused = Hazard.douse(fire, toward) or doused
	end
	return doused
end

function Route.fires_on(tiles: { Tile }, limit: number): { Npc }
	local found: { Npc } = {}
	local taken: { [number]: boolean } = {}
	for i = 2, #tiles do
		for _, fire in ipairs(Hazard.fire_npcs()) do
			if not taken[fire.index] and Hazard.fire_distance(fire, tiles[i]) <= CONST.FIRE_REACH then
				taken[fire.index] = true
				table.insert(found, fire)
				if #found >= limit then
					return found
				end
			end
		end
	end
	return found
end

function Read.buckets(): number
	return Read.item_count(Items.BUCKET, Items.WATER)
end

function Game.bucket_gap(): number
	if CONFIG.solo then
		local fish_slots = CONST.SOLO.FISH_SLOTS
		if snap.free < fish_slots then
			return -math.min(Read.buckets(), fish_slots - snap.free)
		end
		return snap.free - fish_slots
	end
	return CONFIG.buckets - Read.buckets()
end

function Game.bank_buckets()
	snap.inv, snap.free = Read.read_inventory()
	local excess = -Game.bucket_gap()
	if excess <= 0 then
		return
	end
	local before = snap.free
	if not DepositBox.open(plan.box :: Loc) then
		Log.log("Tempoross", "   Couldn't open the deposit box")
		return
	end
	local empty = math.min(excess, Read.item_count(Items.BUCKET))
	local water = math.min(excess - empty, Read.item_count(Items.WATER))
	Log.log("Tempoross", `Banking {excess} extra buckets ({empty} empty, {water} of water)`)
	if empty > 0 then
		DepositBox.deposit(Items.BUCKET, empty)
	end
	if water > 0 then
		DepositBox.deposit(Items.WATER, water)
	end
	Route.sleep_watching(3000, nil, function(): boolean
		snap.inv, snap.free = Read.read_inventory()
		return snap.free > before
	end)
	DepositBox.close()
	snap.inv, snap.free = Read.read_inventory()
end

function Game.ready(): boolean
	local gap = Game.bucket_gap()
	return Read.has_hammer() and Read.has_rope() and Read.has_harpoon() and (gap == 0 or (gap > 0 and snap.free == 0))
end

function Game.prepare_state(skipped: { [State]: boolean }): State
	local common = Loop.common_game_state()
	if common then
		return common
	end
	if S.activity ~= nil then
		return "CONTINUE"
	end
	if snap.free > 0 and not Read.has_harpoon() then
		return "TAKE_HARPOON"
	end
	if snap.free > 0 and not Read.has_rope() and not skipped["TAKE_ROPE"] then
		return "TAKE_ROPE"
	end
	if snap.free > 0 and not Read.has_hammer() and not skipped["TAKE_HAMMER"] then
		return "TAKE_HAMMER"
	end
	local gap = Game.bucket_gap()
	if gap > 0 and snap.free > 0 and not skipped["TAKE_BUCKETS"] then
		return if Ship.at_home(snap.me) then "TAKE_BUCKETS" else "WALK_SHIP"
	end
	if gap < 0 then
		return "DROP_BUCKET"
	end
	if Read.item_count(Items.BUCKET) > 0 then
		return Task.fill_state(skipped) or "WALK_PUMP"
	end
	return "LEAVE_PREPARED"
end

function Loop.get_lobby_state(skipped: { [State]: boolean }): State
	if
		CONFIG.antiban
		and S.antiban_ready
		and time() >= S.randoms_retry_at
		and not Player.in_instance()
		and Randoms.find() ~= nil
	then
		return "RANDOM_EVENT"
	end
	local ladder = Geo.nearest_walk(Read.locs_named({ "Rope ladder" }), snap.me, Geo.to_tile)
	if ladder == nil then
		return if Read.on_boat() then "IDLE" else "WALK_DOCK"
	end
	plan.ladder = ladder
	if not Read.on_boat() and Game.bucket_gap() < 0 and not skipped["BANK_BUCKETS"] then
		local box = Geo.nearest_walk(Read.locs_named({ "Bank Deposit Box" }), snap.me, Geo.to_tile)
		if box then
			plan.box = box
			return "BANK_BUCKETS"
		end
	end
	if CONFIG.solo or (not Read.on_boat() and not Game.ready()) then
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
		if Read.item_count(Items.BUCKET) > 0 and (departure == nil or departure > 5) and not Doing.is_doing("pump") then
			local pump = Geo.nearest_walk(Read.locs_named({ "Water pump" }), snap.me, Geo.to_tile)
			if pump and Geo.loc_distance(pump :: Loc, snap.me) <= 6 then
				plan.pump = pump
				return "BOAT_PUMP"
			end
		end
		return "ON_BOAT"
	end

	if departure ~= nil and departure <= CONFIG.boarding.min_time then
		return "WAIT_NEXT_BOAT"
	end
	if ready then
		return "BOARD_NOW"
	end
	if players and players + 1 >= S.required_players then
		return "BOARD_WALK"
	end
	if Geo.distance(snap.me, ladder) > 8 then
		return "WALK_LADDER"
	end
	return "WAIT_LOBBY"
end

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}
	table.clear(plan)
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

	S.end_dialogue = not S.hud_up and ChatOptions.contains_continue()
	if not S.end_dialogue then
		S.click_continue_dialogue = nil
	elseif S.click_continue_dialogue == nil then
		S.click_continue_dialogue = Biometrics.random_boolean(0.1)
	end
	if S.in_game and not S.was_in_game and not S.arrived and not S.end_dialogue then
		S.arrived = true
		S.arrival_fade = GameState.fading()
		Log.log("Tempoross", `   On the island{if GameState.fading() then " under the fade" else ""}`)
		if CONFIG.solo and not S.preparing then
			Solo.hover_start()
		end
		Biometrics.sleep(100, 800)
		Solo.click_start()
		return "LOADING"
	end
	if not S.in_game then
		S.arrived = false
	end
	local fading = GameState.fading()
	if not fading then
		S.arrival_fade = false
	end
	if fading and not S.arrival_fade and not (S.end_dialogue and not S.click_continue_dialogue) then
		return "FADING"
	end

	if S.hud_up then
		if not S.was_in_game then
			return "NEW_GAME"
		end
		if S.preparing then
			return Game.prepare_state(skipped)
		end
		return if CONFIG.solo then Solo.get_game_state(skipped) else Group.get_game_state(skipped)
	end
	if S.was_in_game then
		return "GAME_OVER"
	end

	if S.in_game then
		if S.played_here and S.leaving_since == nil then
			S.leaving_since = time()
		end
		if S.leaving_since ~= nil and not Game.leave_expired() then
			return "LEAVE"
		end
		return "WAIT_VOYAGE"
	end

	S.played_here = false
	local world = WorldSwitcher.current()
	if not CONFIG.solo and world and world ~= CONFIG.world and Read.lobby_players() ~= nil then
		return "HOP_WORLD"
	end
	if S.leaving_since ~= nil and not Game.leave_expired() then
		return "LEAVE"
	end
	return Loop.get_lobby_state(skipped)
end

function Handler.wait_untethered()
	Route.sleep_watching(150, nil, function()
		return (varbit(CONST.TETHERED_VARBIT) or 0) == 0
	end)
end

function Handler.near_ladder(ladder: Loc): Tile
	return { x = ladder.x + Random.int(2, 5), y = ladder.y + Random.int(-3, 3) }
end

function Handler.game_over()
	S.was_in_game = false
	Doing.clear_activity()
	events.wave_warning_at = nil
	events.wave_hit_at = nil
	events.tethered = false
	if S.preparing then
		S.preparing = false
		Log.log("Tempoross", `Prepared: {Read.item_count(Items.WATER)} buckets of water, {snap.free} free slots`)
		return
	end
	if S.forfeiting then
		S.forfeiting = false
		Log.log("Tempoross", "Forfeited, starting a new game")
		return
	end

	if S.antiban_ready then
		Antiban.delay_tasks(time() - S.game_started)
	end
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
	S.leave_by_crew = not (CONFIG.antiban and S.antiban_ready and Antiban.break_due())
		and Biometrics.random_boolean(0.9)
	if CONFIG.max_games > 0 and stats.games >= CONFIG.max_games then
		S.finished = true
	end
end

function Handler.attack()
	local active = if CONFIG.solo then Geo.nearest_npc(Read.npcs_with(CONST.SPIRIT_POOL), snap.me) else nil
	if active and not Doing.is_doing("attack") then
		Solo.move_safely(Route.npc_stand(active :: Npc), function()
			Task.harpoon_pool()
		end)
		Route.sleep_watching(150)
		return
	end
	if not Doing.is_doing("attack") then
		if not Task.harpoon_pool() then
			local pool = Geo.nearest_walk(Read.npcs_with(CONST.INACTIVE_POOL), snap.me, Geo.to_tile)
			if pool == nil then
				Route.walk_near((S.side :: Side).mast, 6)
			end
		end
	end
	Route.sleep_watching(150)
end

function Handler.go_to_pier()
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

function Task.stand_safe(spot: Npc): boolean
	return Hazard.hazard_at(Route.npc_stand(spot)) == nil
end

function Task.nearest_spot(): Npc?
	local totem = (S.side :: Side).totem
	return Geo.nearest_npc(snap.npcs, snap.me, function(n: Npc): boolean
		return (CONST.SINGLE_SPOTS[n.id] or n.id == CONST.DOUBLE_SPOT)
			and Geo.distance(n, totem) <= 14
			and Task.stand_safe(n)
	end)
end

function Task.walk_to_spots()
	local found: Npc? = nil
	local o = Route.walk_checks(false)
	local checks: ((Tile) -> boolean?)? = o.on_step
	o.on_step = function(tile: Tile): boolean?
		if checks and checks(tile) == false then
			return false
		end
		found = Task.nearest_spot()
		return found == nil
	end
	o.near = 5
	o.timeout_ms = 30000
	Log.log("Tempoross", "   Heading for the fishing spots")
	Walker.walk((S.side :: Side).totem, o)
	if found then
		Log.log("Tempoross", `   Fishing spot in sight at {(found :: Npc).x},{(found :: Npc).y}`)
		Task.fish_at(found :: Npc)
	end
end

function Handler.wait_spot()
	local s = S.side :: Side
	if Geo.distance(snap.me, s.totem) > 8 then
		Task.walk_to_spots()
		return
	end
	local near, blocked = 0, "nothing near the totem"
	for _, n in ipairs(snap.npcs) do
		if (CONST.SINGLE_SPOTS[n.id] or n.id == CONST.DOUBLE_SPOT) and Geo.distance(n, s.totem) <= 14 then
			near += 1
			blocked = if Hazard.hazard_at(Route.route_end(Geo.to_tile(n)))
				then Hazard.describe_hazard(Hazard.hazard_at(Route.route_end(Geo.to_tile(n))) :: Npc)
				else "a route through a hazard"
		end
	end
	Log.log("Tempoross", `   No fishing spot clear of fires and storms ({near} spots near the totem, {blocked})`)
	Route.sleep_watching(Random.int(600, 1200))
end

function Handler.wait_on_boat()
	Doing.check_activity()
	Game.tiny_antiban(true)
	sleep(Random.int(300, 600))
end

function Handler.board(ladder: Loc)
	if Task.use_loc(ladder, { "Climb" }) then
		Game.wait_boarding(Read.on_boat)
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
	WAIT_TETHERED = function()
		if CONFIG.solo then
			Solo.while_tethered()
		else
			Handler.wait_untethered()
		end
	end,
	WAIT_FREE = function()
		Route.sleep_watching(CONST.SOLO.TETHER_POLL_MS, nil, function()
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

	WAIT_VOYAGE = function()
		sleep(Random.int(300, 600))
	end,
	LEAVE = Game.leave,

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
		S.preparing = not Game.ready()
		Log.log("Tempoross", if S.preparing then "Solo start to get tools and buckets" else "Solo start")
		if Task.use_loc(plan.ladder :: Loc, { "Solo-start" }) then
			Game.wait_boarding(Player.in_instance)
		end
	end,
	RANDOM_EVENT = function()
		sleep(Random.int(CONST.RANDOMS_PAUSE_MS[1], CONST.RANDOMS_PAUSE_MS[2]))
		if not Randoms.handle() then
			S.randoms_retry_at = time() + CONST.RANDOMS_RETRY_MS
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
		local spot = Random.tile_in_box(ladder.x + 2, ladder.y - 2, ladder.x + 3, ladder.y + 2)
		if Route.walk_near(spot, 1) then
			Handler.board(ladder)
		end
	end,
	WAIT_LOBBY = function()
		sleep(Random.int(600, 1200))
	end,
	WAIT_SURGE = Task.wait_out_surge,
	WALK_PUMP = function()
		local pump = Geo.nearest_walk(Read.locs_named({ "Water pump" }), snap.me, Geo.to_tile)
		if pump then
			Route.walk_near(Geo.to_tile(pump :: Loc), CONST.PUMP_RANGE - 2)
		end
	end,
	WALK_SHIP = function()
		Route.walk_near((S.side :: Side).mast, 4)
	end,
	BANK_BUCKETS = Game.bank_buckets,
	DROP_BUCKET = function()
		local wanted = if Read.item_count(Items.BUCKET) > 0 then Items.BUCKET else Items.WATER
		for _, slot in ipairs(item_container(Inventory.CONTAINER) or {}) do
			if slot.id == wanted then
				Inventory.drop_slots({ slot.slot })
				return
			end
		end
	end,
	FISH_TO_TARGET = function()
		Solo.fish_until(Solo.fish_target())
	end,
	WAIT_DOUBLE = Solo.wait_double,
	WAIT_WAVE = Solo.wait_wave,
	COOKING_TO_LOAD = Solo.hover_ship_path,
	WALK_TO_LOAD = Solo.walk_to_load,
	FISH_SAFELY = function()
		local spot = plan.spot :: Npc
		Solo.move_safely(Route.npc_stand(spot), function()
			Task.fish_at(spot)
		end)
	end,
	COOK_SAFELY = function()
		local shrine = (S.side :: Side).shrine
		Solo.move_safely(Route.loc_stand(shrine), Task.cook)
	end,
	LOAD_ALL = Solo.load_all,
	GO_TO_PIER_SOLO = Solo.go_to_pier,
	FISHING_TO_COOK = function()
		Task.prehover_shrine()
		Route.sleep_watching(150)
	end,
	LOAD_EXACT = function()
		Solo.load_exact(CONST.SOLO.FIRST_BATCH)
	end,
	FORFEIT = Solo.forfeit,
	SOLO_STOP = Solo.stop_here,
	HUMIDIFY = Solo.humidify,
	P3_BUCKETS = Solo.take_buckets,
	P3_CROSS = Solo.cross,
	P3_CLEAR = Solo.clear_beach,
	P2_CLEAR = Solo.clear_p2,
	P3_DROP = function()
		Solo.drop_buckets(plan.drop or 0, true)
	end,
	P4_COOK_DROP = Solo.cook_dropping,
	P5_CLEAR = Solo.clear_way_north,
	P5_HUMIDIFY_WALK = Solo.humidify_walk,
	P5_FISHING = Solo.fish_for_p5,
	LEAVE_PREPARED = function()
		Log.log("Tempoross", "Tools and buckets ready, leaving")
		S.leave_by_crew = true
		Game.leave()
	end,
}

function Game.apply_settings(values: { [string]: any })
	CONFIG.world = values.world
	CONFIG.solo = values.mode == "Solo firefighter"
	CONFIG.boarding.min_players = values.min_players
	CONFIG.boarding.min_time = values.min_time
	CONFIG.barehand = values.barehand == true
	CONFIG.buckets = values.buckets
	CONFIG.cook.enabled = values.cook == true
	CONFIG.max_games = values.max_games
	S.cook_fish_threshold = Random.int(CONFIG.cook.min, CONFIG.cook.max)
	S.pier_energy = Random.int(CONFIG.pier.min_energy, CONFIG.pier.max_energy)
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Game.check_spellbook()
		Game.check_barehand()
		Log.log("Tempoross", "Settings updated")
	end
end
local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log("Tempoross", `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.run()
	Game.apply_settings(Host.settings())
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
		close_stray()
		Game.poll_settings()
		Hazard.show_fires(true)
		local started = time()
		Handler.states[state]()
		local took = time() - started
		if took > CONST.SLOW_HANDLER_MS then
			Log.log("Tempoross", `   {state} took {math.floor(took)} ms`)
		end

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
