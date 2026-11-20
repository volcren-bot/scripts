--!strict
local Core = require("./core")
local DebugDraw = require("@lib/main/debug_draw")
local Draw = require("@lib/utils/draw")
local Geometry = require("@lib/utils/math/geometry")
local Host = require("@lib/host")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Player = require("@lib/main/player")
local Projection = require("@lib/main/projection/projection")
local time = Host.time
type Npc = Core.Npc
type Loc = Core.Loc
type Tile = Core.Tile
type Box = Core.Box
type Side = Core.Side
type State = Core.State
type Activity = Core.Activity
type Point = { x: number, y: number }
local CONST = Core.CONST
local Items = Core.Items
local HUD = Core.HUD
local S = Core.S
local snap = Core.snap
local events = Core.events
local Read = Core.Read
local Geo = Core.Geo
local Chat = Core.Chat
local Ship = Core.Ship
local Route = Core.Route
local Doing = Core.Doing
local Task = Core.Task
local Hazard = Core.Hazard
local Solo = Core.Solo
local Game = Core.Game
local Island = Core.Island

type Item = Core.IslandItem
type Drop = { count: number, water: boolean }
type Needs = {
	double: number,
	single: number,
	shrine: number,
	shrine_rank: number,
	crate: number,
	tether: number,
	untether: number,
	pump: number,
	fire: number,
	pier: number,
	attack: number,
	tools: { [string]: number },
	crew: number,
	loading: boolean,
	rush: boolean,
	load_ramp: number,
	fishing_target: number,
	fishing_cook: boolean,
	fire_box: Core.Box?,
	fire_set: { [number]: boolean }?,
	route: number,
	look: number,
	north: number,
	humidify: number,
	step: number,
	drop: Drop?,
	pickup: number,
	through_fire: boolean,
	wait: State,
	wait_tile: Tile,
}
type CrateSpot = { tile: Tile, npc: Npc?, stand: Tile, surged: boolean }
type CratePlan = { crate_need: number, fire_need: { [number]: number }, between: boolean, path_blocked: boolean }

local SEGMENTS: { [string]: string } = {
	["0"] = "abcdef",
	["1"] = "bc",
	["2"] = "abged",
	["3"] = "abgcd",
	["4"] = "fgbc",
	["5"] = "afgcd",
	["6"] = "afgedc",
	["7"] = "abc",
	["8"] = "abcdefg",
	["9"] = "abcdfg",
}

local UNCONFINED: { [string]: boolean } = {
	dodge = true,
	stunned = true,
	crew = true,
	untether = true,
	tether = true,
	surge = true,
	humidify = true,
	drop = true,
	wait = true,
	step = true,
	repair = true,
}

local PATH_KINDS: { [string]: boolean } = {
	crate = true,
	single = true,
	double = true,
	shrine = true,
	pier = true,
	pool = true,
	route = true,
	look = true,
	north = true,
	buckets = true,
	ropes = true,
	harpoons = true,
	pump = true,
	tether = true,
	multi = true,
}

function Island.loc_tiles(loc: Loc): { Tile }
	local tiles: { Tile } = {}
	for dx = 0, math.max(1, loc.size_x) - 1 do
		for dy = 0, math.max(1, loc.size_y) - 1 do
			table.insert(tiles, { x = loc.x + dx, y = loc.y + dy })
		end
	end
	return tiles
end

function Island.fit(steps: number): number
	local w = CONST.ISLAND
	return math.clamp(1 - steps / w.far_steps, w.min_fit, 1)
end

local function new_item(
	kind: string,
	steps: number,
	fit: number,
	need: number,
	npc: Npc?,
	loc: Loc?,
	footprint: { Tile }?,
	stand: Tile?
): Item
	local tiles = footprint or if loc then Island.loc_tiles(loc) elseif npc then { Geo.to_tile(npc) } else {}
	local floor = CONST.ISLAND.fit_floor
	return {
		kind = kind,
		npc = npc,
		loc = loc,
		tiles = tiles,
		steps = steps,
		fit = fit,
		need = need,
		score = need * (floor + (1 - floor) * fit),
		rank = 0,
		stand = stand,
	}
end

local function urgent_item(kind: string, tiles: { Tile }, rank_kind: string?): Item
	local item = new_item(kind, 0, 1, CONST.ISLAND.need.urgent, nil, nil, tiles, tiles[1])
	item.rank = (CONST.ISLAND.rank :: { [string]: number })[rank_kind or kind] or 0
	return item
end

function Island.tether_options(): { { loc: Loc, steps: number } }
	local hammer = Read.has_hammer()
	local options: { Loc } = {}
	for _, l in ipairs({ Ship.our_mast(), Ship.our_totem() } :: { Loc? }) do
		if l and (hammer or not Read.is_damaged(l)) then
			table.insert(options, l)
		end
	end
	if #options == 0 then
		options = Read.locs_named({ "Mast", "Totem pole" })
	end
	local ranked: { { loc: Loc, steps: number } } = {}
	for _, l in ipairs(options) do
		local d = Route.walk_steps(Geo.to_tile(l))
		if Read.is_damaged(l) then
			d += CONST.REPAIR_STEPS
		end
		local name = l.name or ""
		if
			(Doing.is_doing("fish") and Chat.contains(name, "Totem"))
			or (Doing.is_doing("load") and Chat.contains(name, "Mast"))
		then
			d -= 8
		end
		table.insert(ranked, { loc = l, steps = d })
	end
	table.sort(ranked, function(a: { loc: Loc, steps: number }, b: { loc: Loc, steps: number }): boolean
		return a.steps < b.steps
	end)
	return ranked
end

function Island.part(): number
	local r = S.solo
	if r.p5_stage ~= nil then
		return 5
	elseif r.p4_stage ~= nil then
		return 4
	elseif r.p3_stage ~= nil or r.pools >= 1 then
		return 3
	elseif r.loaded >= CONST.SOLO.FIRST_BATCH or r.p2_loading then
		return 2
	end
	return 1
end

function Island.blank_needs(): Needs
	return {
		double = 0,
		single = 0,
		shrine = 0,
		shrine_rank = 0,
		crate = 0,
		tether = 0,
		untether = 0,
		pump = 0,
		fire = 0,
		pier = 0,
		attack = 0,
		tools = { buckets = 0, ropes = 0, harpoons = 0 },
		crew = 0,
		loading = false,
		rush = false,
		load_ramp = 1,
		fishing_target = 0,
		fishing_cook = false,
		fire_box = nil,
		fire_set = nil,
		route = 0,
		look = 0,
		north = 0,
		humidify = 0,
		step = 0,
		drop = nil,
		pickup = 0,
		through_fire = false,
		wait = "CONTINUE",
		wait_tile = Geo.to_tile(snap.me),
	}
end

function Island.fishing_needs(needs: Needs, target: number, can_cook: boolean)
	local need = CONST.ISLAND.need
	local count = Read.fish_count()
	local raw = if can_cook then Read.item_count(Items.RAW_FISH) else 0
	needs.fishing_target = target
	needs.fishing_cook = can_cook
	needs.wait = "WAIT_SPOT"
	if count >= target then
		if raw > 0 then
			needs.shrine = need.shrine_full
		end
		return
	end
	needs.double = need.double
	if raw == 0 or target - count <= CONST.SOLO.TOP_UP_FISH then
		needs.single = need.single
	end
	if raw > 0 and not Doing.is_doing("fish") then
		needs.shrine = if target - count > CONST.SOLO.TOP_UP_FISH then need.shrine_first else need.shrine
	end
end

function Island.part_one_wait(needs: Needs)
	local r = S.solo
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	local totem = Geo.to_tile((S.side :: Side).totem)
	if r.loading then
		needs.wait = "CONTINUE"
	elseif not r.opened then
		needs.wait = "WAIT_SPOT"
		needs.wait_tile = totem
	elseif count >= CONST.SOLO.FIRST_BATCH then
		needs.wait = if raw == 0 and events.waves_passed == 0 then "WAIT_WAVE" else "CONTINUE"
		needs.wait_tile = if needs.wait == "WAIT_WAVE" then totem else needs.wait_tile
	elseif r.doubled and raw == 0 then
		needs.wait = "WAIT_SPOT"
		needs.wait_tile = totem
	else
		needs.wait = "WAIT_DOUBLE"
		needs.wait_tile = totem
	end
end

function Island.part_one_needs(needs: Needs)
	local r = S.solo
	local need = CONST.ISLAND.need
	local target = CONST.SOLO.FIRST_BATCH
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	local energy = Read.hud_percent(HUD.ENERGY) or 0
	needs.fire = need.fire_idle
	needs.fishing_target = target
	needs.fishing_cook = true
	Island.part_one_wait(needs)
	if r.loading then
		needs.loading = true
		local p = math.clamp(r.loaded / target, 0, 1)
		needs.step = if r.loaded >= target and Doing.player_is_working("load") == true
			then need.urgent
			else need.step * p
		if #Island.home_fires() == 0 or Read.item_count(Items.WATER) == 0 then
			needs.double = need.double * p
			needs.single = need.single * p
			needs.fishing_target = Solo.part_two_left()
		end
		return
	end
	if not r.opened and energy < CONST.SOLO.OPENING_ENERGY and count < CONST.SOLO.OPENING_FISH and count < target then
		needs.single = need.single
		needs.double = need.single
		if count == 0 and Read.item_count(Items.BUCKET) > 0 then
			needs.pump = need.pump
		end
		return
	end
	if count >= target then
		if raw > 0 then
			needs.shrine = need.shrine_full
		elseif events.waves_passed > 0 then
			needs.loading = true
		end
		return
	end
	needs.double = need.double
	if r.doubled or target - count <= CONST.SOLO.TOP_UP_FISH then
		needs.single = need.single
	end
	if raw > 0 and not Doing.is_doing("fish") then
		needs.shrine = need.shrine
	end
end

function Island.part_two_needs(needs: Needs)
	local r = S.solo
	local need = CONST.ISLAND.need
	if r.p2_loading then
		local total = Solo.part_two_cooked()
		local progress = math.clamp((r.loaded - CONST.SOLO.FIRST_BATCH) / CONST.SOLO.SECOND_BATCH, 0, 1)
		needs.step = if r.loaded >= total and Doing.player_is_working("load") == true
			then need.urgent
			else need.step * progress
		if Read.fish_count() > 0 and r.loaded < total then
			needs.loading = true
		else
			needs.pier = need.pier
		end
		return
	end
	if Read.fish_count() > 0 and Solo.at_crate() and Doing.player_is_working("load") == true then
		needs.step = need.urgent
	end
	if r.p2_clear ~= "done" then
		needs.fire = need.fire
		needs.fire_box = Solo.home_box(S.side :: Side)
		return
	end
	Island.fishing_needs(needs, Solo.part_two_left(), true)
end

function Island.midwalk_humidify(): boolean
	local r = S.solo
	if not r.p3_humidify or Read.item_count(Items.BUCKET) == 0 or time() < r.humidify_at then
		return false
	end
	if Player.destination() == nil then
		return false
	end
	local cast = r.humidify_cast
	return cast == nil or time() - cast.at > CONST.SOLO.HUMIDIFY_SETTLE_MS
end

function Island.part_three_needs(needs: Needs)
	local r = S.solo
	local need = CONST.ISLAND.need
	if r.p3_stage == "route" or r.p3_stage == "clear" then
		needs.pickup = math.max(0, CONST.SOLO.P3_MIN_BUCKETS - Solo.buckets_held())
	end
	if r.p3_stage == "route" then
		needs.fire = need.fire
		needs.fire_set = Solo.route_fires()
		if Solo.p3_waypoint() ~= nil then
			needs.route = need.route
		end
	elseif r.p3_stage == "clear" then
		local set: { [number]: boolean } = {}
		for _, fire in ipairs(Solo.p3_box_fires()) do
			if r.p3_planned[`{fire.x},{fire.y}`] then
				set[fire.index] = true
			end
		end
		needs.fire = need.fire
		needs.fire_set = set
		local excess = Solo.clear_excess()
		if excess > 0 and Solo.dropping_on_the_way() then
			needs.drop = { count = math.min(excess, r.p3_drop_batch), water = true }
		end
	end
end

function Island.part_four_room(needs: Needs)
	local r = S.solo
	local count = Read.fish_count()
	local target = Solo.p4_target()
	local short = target - count - snap.free
	if count >= target or short <= 0 or Solo.humidify_settling() then
		return
	end
	local raw = Read.item_count(Items.RAW_FISH)
	if Doing.is_doing("fish") then
		needs.drop = { count = short, water = true }
		return
	end
	if snap.free > 0 and (raw == 0 or r.p4_raw) then
		return
	end
	local on_double = Doing.is_doing("fish") and (S.activity :: Activity).double
	local double = Solo.nearest_double()
	if on_double or (double ~= nil and Task.double_worth(double)) then
		local wanted = CONST.SOLO.P4_DOUBLE_FREE
		if snap.free == 0 or (not on_double and snap.free < wanted) then
			needs.drop = { count = math.min(wanted - snap.free, short), water = true }
		end
		return
	end
	if Read.item_count(Items.RAW_FISH) > 0 and not r.p4_raw then
		if Doing.is_doing("cook") then
			needs.drop = { count = CONST.SOLO.THIRD_BATCH - count - snap.free, water = true }
		else
			needs.shrine = CONST.ISLAND.need.urgent
			needs.shrine_rank = (CONST.ISLAND.rank :: { [string]: number }).drop
		end
		return
	end
	needs.drop = { count = short, water = true }
end

function Island.confine_box(): Box?
	local r = S.solo
	if r.p4_stage == "fish" then
		return r.p3_box
	end
	return nil
end

function Island.in_box(box: Box, t: Tile): boolean
	return t.x >= box.min_x and t.x <= box.max_x and t.y >= box.min_y and t.y <= box.max_y
end

function Island.confine(items: { Item })
	local box = Island.confine_box()
	if box == nil then
		return
	end
	local b = box :: Box
	for _, item in ipairs(items) do
		if not UNCONFINED[item.kind] and item.score > 0 then
			local inside = if item.kind == "fire" and item.npc
				then Solo.fire_in(b, item.npc :: Npc)
				else Island.in_box(b, item.stand or item.tiles[1] or snap.me)
			if not inside then
				item.score = 0
				item.rank = 0
			end
		end
	end
end

function Island.p4_load_ramp(): number
	if Read.fish_count() < Solo.p4_target() or Read.item_count(Items.RAW_FISH) > 0 then
		return 0
	end
	local from = CONST.SOLO.P4_LOAD_RAMP_FROM
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	return math.clamp((intensity - from) / (CONST.SOLO.LEAVE_INTENSITY - from), 0, 1)
end

function Island.part_four_needs(needs: Needs)
	local r = S.solo
	local need = CONST.ISLAND.need
	if r.p4_stage == "fish" then
		needs.fire = need.fire
		needs.fire_box = r.p3_box
		Island.fishing_needs(needs, Solo.p4_target(), not r.p4_raw)
		Island.part_four_room(needs)
		local ramp = Island.p4_load_ramp()
		if ramp > 0 then
			needs.loading = true
			needs.load_ramp = ramp
		end
		return
	end
	if Read.fish_count() > 0 then
		needs.loading = true
		needs.rush = r.p4_stage == "rush"
	else
		needs.fire = need.fire
		needs.fire_box = Solo.home_box(S.side :: Side)
		needs.pier = need.pier_after_fires
	end
end

function Island.part_five_route(needs: Needs)
	local need = CONST.ISLAND.need
	if Solo.p5_rush_north() then
		needs.north = need.north
		return
	end
	needs.fire = need.fire
	needs.look = need.look
	needs.north = if Solo.p5_route_box() ~= nil then need.north_later else need.north
end

function Island.part_five_needs(needs: Needs)
	local r = S.solo
	local need = CONST.ISLAND.need
	if r.p5_stage == "humidify" then
		Island.part_five_route(needs)
	elseif r.p5_stage == "north" then
		Island.part_five_route(needs)
	elseif r.p5_stage == "fish" then
		Island.fishing_needs(needs, CONST.SOLO.P5_FISH, false)
		needs.through_fire = true
		local short = CONST.SOLO.P5_FISH - Read.fish_count() - snap.free
		if Read.fish_count() < CONST.SOLO.P5_FISH and short > 0 and not Solo.humidify_settling() then
			needs.drop = { count = short, water = true }
		end
	elseif r.p5_stage == "sweep" then
		needs.fire = need.fire
		local set: { [number]: boolean } = {}
		for _, fire in ipairs(Solo.p5_fires()) do
			set[fire.index] = true
		end
		needs.fire_set = set
	elseif r.p5_stage == "load" then
		needs.loading = Read.fish_count() > 0
	elseif r.p5_stage == "pool" then
		needs.pier = need.pier
	end
end

function Island.forfeit_reason(): string?
	local r = S.solo
	if r.stop_reason then
		return r.stop_reason
	elseif events.burned then
		return "A fire burned us"
	elseif events.wave_hit_us then
		return "A wave hit us"
	elseif Solo.late_wave() then
		return "A second wave came before Tempoross went under, we're too slow"
	elseif r.p3_stage == nil and r.loaded_raw > 0 then
		return `Loaded {r.loaded_raw} raw fish before part 3`
	elseif r.p3_stage == nil and r.loaded_cooked > Solo.part_two_cooked() then
		return `Loaded {r.loaded_cooked} cooked fish, more than {Solo.part_two_cooked()}`
	elseif S.forfeiting or (S.leave_by_crew and S.leaving_since ~= nil) then
		return "Leaving"
	end
	return nil
end

function Island.stray(): boolean
	local stray = snap.tethered
		and events.wave_warning_at == nil
		and events.wave_hit_at == nil
		and not Doing.is_doing("tether")
	return stray and S.stray_since ~= nil and time() - (S.stray_since :: number) >= CONST.STRAY_MS
end

function Island.needs(): Needs
	local needs = Island.blank_needs()
	local need = CONST.ISLAND.need
	local part = Island.part()
	if part == 1 then
		Island.part_one_needs(needs)
	elseif part == 2 then
		Island.part_two_needs(needs)
	elseif part == 3 then
		Island.part_three_needs(needs)
	elseif part == 4 then
		Island.part_four_needs(needs)
	else
		Island.part_five_needs(needs)
	end
	local warned = events.wave_warning_at ~= nil and not events.tethered and not snap.tethered and Read.has_rope()
	if warned or ((snap.tethered or Doing.is_doing("tether")) and not Island.stray()) then
		needs.tether = need.tether
	end
	if Island.stray() or events.must_untether then
		needs.untether = need.urgent
	end
	local r = S.solo
	local loading_first = Solo.loading_first()
	if Hazard.tempoross_vulnerable() and not loading_first and not Solo.ship_fires_left() then
		needs.attack = need.attack
	end
	if Island.forfeit_reason() ~= nil then
		needs.crew = need.crew
	end
	if r.p3_stage == "buckets" or r.p5_stage == "buckets" then
		needs.tools.buckets = need.tool
	end
	if Solo.wants_humidify() or Island.midwalk_humidify() then
		needs.humidify = need.humidify
	end
	return needs
end

function Island.home_fires(): { Npc }
	local box = Solo.home_box(S.side :: Side)
	local fires: { Npc } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		if Solo.fire_in(box, fire) and not S.solo.p2_skip[`{fire.x},{fire.y}`] then
			table.insert(fires, fire)
		end
	end
	return fires
end

function Island.north_ship(): boolean
	local other = Ship.other_side()
	local side = S.side :: Side
	return other == nil or side.mast.y >= other.mast.y
end

function Island.known_crates(): { CrateSpot }
	local seen = S.solo.crates_seen
	local mast = (S.side :: Side).mast
	local visible: { [string]: Npc } = {}
	for _, crate in ipairs(Task.crates()) do
		local key = `{crate.x},{crate.y}`
		seen[key] = Geo.to_tile(crate)
		visible[key] = crate
	end
	local usable: { [number]: boolean } = {}
	for _, crate in ipairs(Task.usable_crates(true)) do
		usable[crate.index] = true
	end
	local crates: { CrateSpot } = {}
	for key, tile in pairs(seen) do
		if Geo.distance(tile, mast) <= CONST.ISLAND.crate_mast_range then
			local npc = visible[key]
			local surged = npc ~= nil and not usable[npc.index]
			local stand = if npc then Route.npc_stand(npc) else Route.route_end(tile)
			table.insert(crates, { tile = tile, npc = npc, stand = stand, surged = surged })
		end
	end
	local north = Island.north_ship()
	table.sort(crates, function(a: CrateSpot, b: CrateSpot): boolean
		return if north then a.tile.y > b.tile.y else a.tile.y < b.tile.y
	end)
	return crates
end

function Island.crate_plan(needs: Needs, fires: { Npc }): CratePlan
	local need = CONST.ISLAND.need
	local plan: CratePlan = { crate_need = 0, fire_need = {}, between = false, path_blocked = false }
	if not needs.loading then
		return plan
	end
	local crates = Island.known_crates()
	local first = crates[1]
	local home = Island.home_fires()
	local home_set: { [number]: boolean } = {}
	for _, fire in ipairs(home) do
		home_set[fire.index] = true
	end
	if Island.part() == 1 then
		plan.crate_need = need.crate
		local p = math.clamp(S.solo.loaded / CONST.SOLO.FIRST_BATCH, 0, 1)
		for _, fire in ipairs(home) do
			plan.fire_need[fire.index] = math.max(need.fire_idle, need.fire * p)
		end
		return plan
	end
	local ramp = needs.load_ramp
	local early = ramp < 1
	if #home == 0 or first == nil or Read.item_count(Items.WATER) == 0 then
		plan.crate_need = need.crate * ramp
		return plan
	end
	local route = Route.route_to(first.stand) or {}
	local blocking: { [number]: boolean } = {}
	for _, fire in ipairs(home) do
		if Solo.covers(fire, route, 0) or Hazard.fire_distance(fire, first.stand) <= 1 then
			blocking[fire.index] = true
			plan.path_blocked = true
		end
	end
	local storm = needs.rush or (Read.hud_percent(HUD.INTENSITY) or 0) >= CONST.SOLO.P4_LOAD_INTENSITY
	for _, fire in ipairs(fires) do
		if blocking[fire.index] then
			plan.fire_need[fire.index] = need.fire_path * ramp
		elseif home_set[fire.index] and not early then
			plan.fire_need[fire.index] = if plan.path_blocked or storm then need.fire_waiting else need.fire
		end
	end
	if early then
		plan.crate_need = need.crate * ramp
		return plan
	end
	if plan.path_blocked and not storm then
		plan.crate_need = need.crate_waiting
		return plan
	end
	if storm then
		plan.crate_need = need.crate
		for _, fire in ipairs(home) do
			if Hazard.fire_distance(fire, first.stand) <= CONST.ISLAND.jump_range then
				plan.between = #crates >= 2 and Task.crate_safe_tile() ~= nil
			end
		end
		return plan
	end
	plan.crate_need = need.crate_waiting
	return plan
end

function Island.fires_on_way(to: Tile, covered: { [string]: { Npc } }): number
	local route = Route.route_to(to)
	if route == nil then
		return 0
	end
	local seen: { [number]: boolean } = {}
	local count = 0
	for i = 2, #route do
		local t = route[i]
		for _, fire in ipairs(covered[`{t.x},{t.y}`] or {}) do
			if not seen[fire.index] then
				seen[fire.index] = true
				count += 1
			end
		end
	end
	return count
end

function Island.spot_items(needs: Needs, items: { Item }, covered: { [string]: { Npc } })
	local single_need = CONST.ISLAND.need.single
	local a = S.activity
	local water = Read.item_count(Items.WATER) > 0
	for _, n in ipairs(snap.npcs) do
		if Task.is_spot(n) then
			local double = n.id == CONST.DOUBLE_SPOT
			local stand = Route.npc_stand(n)
			local steps = Route.walk_steps(stand)
			local fit = Island.fit(steps)
			local current = a ~= nil and a.kind == "fish" and a.npc ~= nil and (a.npc :: Npc).index == n.index
			local allowed = current or (if double then needs.double else needs.single) > 0
			if double and allowed and not current then
				allowed = Read.double_ticks_left(n, snap.tick) >= CONST.DOUBLE_MIN_TICKS_LEFT
			end
			if needs.fishing_target <= 0 or Read.fish_count() >= needs.fishing_target or snap.free == 0 then
				allowed = false
			end
			local spot_need = if allowed then single_need else 0
			local hazard = Hazard.hazard_at(stand)
			if hazard and allowed then
				if needs.through_fire and hazard.id == CONST.FIRE and water then
					spot_need *= CONST.ISLAND.need.through_fire
				else
					spot_need = 0
				end
			end
			local item = new_item(if double then "double" else "single", steps, fit, spot_need, n, nil, nil, stand)
			if double then
				item.score = math.min(1, item.score * CONST.ISLAND.double_factor)
			end
			if item.score > 0 and not current then
				item.score *= CONST.ISLAND.spot_fire_factor ^ Island.fires_on_way(stand, covered)
			end
			table.insert(items, item)
		end
	end
end

function Island.crate_items(plan: CratePlan, items: { Item })
	local crates = Island.known_crates()
	local far: Npc? = nil
	local far_steps = -1
	for _, crate in ipairs(crates) do
		if crate.npc then
			local steps = Route.walk_steps(crate.stand)
			if steps > far_steps then
				far, far_steps = crate.npc, steps
			end
		end
	end
	for i, crate in ipairs(crates) do
		local steps = Route.walk_steps(crate.stand)
		local need = if crate.surged then 0 else plan.crate_need
		local fit = if i == 1 then 1 else CONST.ISLAND.second_crate_fit
		if i == 1 and plan.between and far then
			local between = Task.crate_safe_tile() :: Tile
			local item = new_item("crate", steps, fit, need, far, nil, { between }, between)
			item.between = true
			table.insert(items, item)
		else
			table.insert(items, new_item("crate", steps, fit, need, crate.npc, nil, { crate.tile }, crate.stand))
		end
	end
	if #crates == 0 and plan.crate_need > 0 then
		local ship = Solo.ship_target()
		local steps = Route.walk_steps(ship)
		table.insert(items, new_item("crate", steps, Island.fit(steps), plan.crate_need, nil, nil, { ship }, ship))
	end
end

function Island.loc_item(kind: string, loc: Loc?, need: number, items: { Item })
	if loc == nil then
		return
	end
	local stand = Route.loc_stand(loc)
	local steps = Route.walk_steps(stand)
	table.insert(items, new_item(kind, steps, Island.fit(steps), need, nil, loc, nil, stand))
end

function Island.npc_item(kind: string, npc: Npc?, need: number, items: { Item }, fallback: Tile?)
	if npc == nil then
		if fallback == nil or need <= 0 then
			return
		end
		local steps = Route.walk_steps(fallback)
		table.insert(items, new_item(kind, steps, Island.fit(steps), need, nil, nil, { fallback }, fallback))
		return
	end
	local stand = Route.npc_stand(npc)
	local steps = Route.walk_steps(stand)
	table.insert(items, new_item(kind, steps, Island.fit(steps), need, npc, nil, nil, stand))
end

function Island.tile_item(kind: string, tile: Tile?, need: number, items: { Item })
	if tile == nil or need <= 0 then
		return
	end
	local stand = Route.route_end(tile)
	local steps = Route.walk_steps(stand)
	table.insert(items, new_item(kind, steps, Island.fit(steps), need, nil, nil, { tile }, stand))
end

function Island.slots_of(ids: { number }): { number }
	local slots: { number } = {}
	for _, wanted in ipairs(ids) do
		for _, slot in ipairs(Host.item_container(Inventory.CONTAINER) or {}) do
			if slot.id == wanted then
				table.insert(slots, slot.slot)
			end
		end
	end
	return slots
end

function Island.humidify_item(needs: Needs, items: { Item })
	local slots = Island.slots_of({ Items.BUCKET })
	if #slots == 0 then
		return
	end
	local item = new_item("humidify", 0, 1, needs.humidify, nil, nil, {})
	item.slots = slots
	if needs.humidify > 0 then
		item.rank = (CONST.ISLAND.rank :: { [string]: number }).humidify
	end
	table.insert(items, item)
end

function Island.pickup_item(needs: Needs, items: { Item })
	if needs.pickup <= 0 or snap.free == 0 then
		return
	end
	local pile = Solo.nearest_dropped_bucket()
	if pile == nil then
		return
	end
	local item = urgent_item("pickup", { pile }, "pickup")
	item.steps = Route.walk_steps(pile)
	table.insert(items, item)
end

function Island.drop_item(needs: Needs, items: { Item })
	local drop = needs.drop
	if drop == nil or drop.count <= 0 then
		return
	end
	local slots = Island.slots_of(if drop.water then { Items.BUCKET, Items.WATER } else { Items.BUCKET })
	if #slots == 0 then
		return
	end
	local shown: { number } = {}
	for i = 1, math.min(drop.count, #slots) do
		shown[i] = slots[i]
	end
	local item = new_item("drop", 0, 1, CONST.ISLAND.need.urgent, nil, nil, {})
	item.slots = shown
	item.drop = drop
	item.rank = (CONST.ISLAND.rank :: { [string]: number }).drop
	table.insert(items, item)
end

function Island.dodge_tile(): Tile?
	local held = S.dodging_to
	if held and Hazard.hazard_at(held, 1) == nil and Route.reaching(held) ~= nil then
		return held
	end
	local a = S.activity
	local towards: Tile? = if a then (a.npc or a.loc) :: Tile? else nil
	local top = S.island and (S.island :: { Item })[1]
	if top and top.kind ~= "dodge" and top.stand then
		towards = top.stand
	end
	local t = Route.safe_tile(towards)
	S.dodging_to = t
	return t
end

function Island.urgent_items(needs: Needs, items: { Item }): Npc?
	local me = Geo.to_tile(snap.me)
	local busy_after_wave = events.wave_hit_at ~= nil
		and snap.busy
		and time() - (events.wave_hit_at :: number) < CONST.SOLO.WAVE_BUSY_MS
	if time() < events.stunned_until or busy_after_wave then
		table.insert(items, urgent_item("stunned", { me }))
	end
	if needs.crew > 0 then
		local crew = Geo.nearest_npc(snap.npcs, snap.me, function(n: Npc): boolean
			return n.name ~= nil and Game.is_crew(n.name)
		end)
		local item = urgent_item("crew", { if crew then Geo.to_tile(crew) else me })
		item.npc = crew
		table.insert(items, item)
	end
	if needs.untether > 0 then
		local pole = Geo.nearest_walk(Read.locs_named({ "Mast", "Totem pole" }))
		local item = urgent_item("untether", if pole then Island.loc_tiles(pole) else { me })
		item.loc = pole
		table.insert(items, item)
	end
	if Doing.is_doing("load") and Task.surge_blocks_loading() then
		table.insert(items, urgent_item("surge", { me }))
	end
	local hazard = Hazard.hazard_at(snap.me)
	if hazard and Route.walking_out_of(hazard) then
		hazard = nil
	end
	if hazard == nil then
		local dest = Player.destination()
		hazard = if dest then Hazard.incoming_at(dest, 0) else nil
		local tiles = if hazard == nil and dest then Route.route_to(dest) else nil
		local landing = if tiles then Route.landing_ahead(tiles) else nil
		if landing then
			hazard =
				{ id = CONST.INCOMING_FIRE, x = landing.x, y = landing.y, index = -1, name = "Incoming fire" } :: any
		end
	end
	if hazard == nil then
		S.dodging_to = nil
		return nil
	end
	local h = hazard :: Npc
	if h.id == CONST.FIRE and Read.item_count(Items.WATER) > 0 then
		return h
	end
	local tile = Island.dodge_tile()
	if tile then
		local item = urgent_item("dodge", { tile })
		item.npc = h
		table.insert(items, item)
	end
	return nil
end

function Island.cloud_near(tile: Tile, margin: number): boolean
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.STORM_CLOUD and Hazard.in_cloud_square(n, tile, margin) then
			return true
		end
	end
	return false
end

function Island.dodge_by_crate(items: { Item })
	if not Doing.is_doing("load") then
		return
	end
	local dodge: number? = nil
	for i, item in ipairs(items) do
		if item.kind == "dodge" then
			dodge = i
		end
	end
	if dodge == nil then
		return
	end
	local a = S.activity
	local loading_at = if a and a.npc then (a.npc :: Npc).index else nil
	local best: Item? = nil
	for _, item in ipairs(items) do
		local stand = item.stand
		local npc = item.npc
		if
			item.kind == "crate"
			and npc
			and npc.index ~= loading_at
			and not item.between
			and item.score > 0
			and stand
			and not Geo.same(stand, snap.me)
		then
			local tiles = Route.route_to(stand)
			local safe = Hazard.hazard_at(stand, 1) == nil
				and not Island.cloud_near(stand, 1)
				and tiles ~= nil
				and Route.landing_ahead(tiles) == nil
			if safe and (best == nil or item.steps < (best :: Item).steps) then
				best = item
			end
		end
	end
	if best == nil then
		return
	end
	local crate = best :: Item
	crate.score = CONST.ISLAND.need.urgent
	crate.rank = (CONST.ISLAND.rank :: { [string]: number }).dodge
	table.remove(items, dodge)
end

function Island.wait_item(needs: Needs, items: { Item })
	local item = new_item("wait", 0, 1, CONST.ISLAND.need.wait, nil, nil, { needs.wait_tile })
	item.wait = needs.wait
	table.insert(items, item)
end

function Island.north_items(needs: Needs, items: { Item })
	local r = S.solo
	if (r.p5_stage ~= "north" and r.p5_stage ~= "humidify") or r.p5_north == nil then
		return
	end
	Island.tile_item("north", Solo.p5_north_target(), needs.north, items)
	local name = Solo.p5_current()
	if name == nil or needs.look <= 0 then
		return
	end
	local spots: { Tile } = {}
	local visible: { [string]: boolean } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		visible[`{fire.x},{fire.y}`] = true
	end
	for _, t in ipairs(Solo.p5_box_targets(name)) do
		if not visible[`{t.x},{t.y}`] then
			table.insert(spots, t)
		end
	end
	for _, t in ipairs(Solo.p5_unseen(name)) do
		table.insert(spots, t)
	end
	table.sort(spots, function(a: Tile, b: Tile): boolean
		return Geo.distance(a, snap.me) < Geo.distance(b, snap.me)
	end)
	local looked = r.p5_looked[name]
	local kept = 0
	for _, t in ipairs(spots) do
		if kept >= CONST.ISLAND.look_items then
			break
		end
		local stand = Route.route_end(t)
		local steps = Route.walk_steps(stand)
		local straight = Geo.distance(snap.me, stand)
		if steps > straight * CONST.SOLO.P5_LOOK_DETOUR + CONST.SOLO.P5_LOOK_DETOUR_STEPS then
			if looked then
				looked[`{t.x},{t.y}`] = true
			end
			Log.log("Tempoross", `   Not looking over {t.x},{t.y}: {steps} steps for {straight} straight`)
		else
			kept += 1
			table.insert(items, new_item("look", steps, Island.fit(steps), needs.look, nil, nil, { t }, stand))
		end
	end
end

function Island.path_fires(target: Item, fires: { Npc }): { Npc }
	local stand = target.stand
	if stand == nil or #fires == 0 then
		return {}
	end
	local tiles = Route.route_to(stand)
	if tiles == nil then
		return {}
	end
	local found: { Npc }
	if S.solo.p4_stage == "fish" then
		found = Solo.path_fires(tiles)
	else
		found = {}
		local taken: { [number]: boolean } = {}
		for i = 2, #tiles do
			for _, fire in ipairs(fires) do
				if not taken[fire.index] and Hazard.fire_distance(fire, tiles[i]) <= CONST.FIRE_REACH then
					taken[fire.index] = true
					table.insert(found, fire)
				end
			end
		end
	end
	if target.kind == "tether" then
		local warned = events.wave_warning_at
		if warned and time() - warned > CONST.SOLO.TETHER_DOUSE_CUTOFF_MS then
			return {}
		end
		if #found > 0 and Route.waypoint_around_fires(stand) ~= nil then
			found = {}
		end
		local near = Hazard.fire_near(stand, 1)
		if near and not table.find(found, near) then
			table.insert(found, near)
		end
		return found
	end
	local around_first = Island.part() >= 2
		and S.solo.p4_stage ~= "fish"
		and target.kind ~= "look"
		and target.kind ~= "north"
	if #found > 0 and around_first and Route.waypoint_around_fires(stand) ~= nil then
		return {}
	end
	return found
end

function Island.better(a: Item, b: Item): boolean
	if a.score ~= b.score then
		return a.score > b.score
	end
	if a.rank ~= b.rank then
		return a.rank > b.rank
	end
	return a.steps < b.steps
end

function Island.inherit_path(items: { Item }, fires: { Npc })
	if Read.item_count(Items.WATER) == 0 then
		return
	end
	local by_index: { [number]: Item } = {}
	for _, item in ipairs(items) do
		if item.kind == "fire" and item.npc then
			by_index[(item.npc :: Npc).index] = item
		end
	end
	local path_rank = (CONST.ISLAND.rank :: { [string]: number }).path
	local step = CONST.ISLAND.path_step
	local seen: { [Item]: boolean } = {}
	for _ = 1, CONST.ISLAND.path_rounds do
		table.sort(items, Island.better)
		local top = items[1]
		if top == nil or top.score <= 0 or not PATH_KINDS[top.kind] or seen[top] then
			return
		end
		seen[top] = true
		local blocking = Island.path_fires(top, fires)
		local n = #blocking
		local lifted = false
		for i, fire in ipairs(blocking) do
			local item = by_index[fire.index]
			if item then
				local lift = n - i + 1
				item.score = math.max(item.score, math.min(1, top.score + step * lift))
				item.rank = math.max(item.rank, top.rank + step * lift, path_rank)
				if item.steps == math.huge then
					item.steps = Route.walk_steps(fire)
				end
				lifted = true
			end
		end
		if not lifted then
			return
		end
	end
end

function Island.inherit_douse(items: { Item })
	local top: Item? = nil
	local by_index: { [number]: Item } = {}
	for _, item in ipairs(items) do
		if item.kind == "fire" and item.npc then
			by_index[(item.npc :: Npc).index] = item
			local best = top
			if
				item.score > 0
				and (best == nil or item.score > best.score or (item.score == best.score and item.rank > best.rank))
			then
				top = item
			end
		end
	end
	if top == nil then
		return
	end
	local t = top :: Item
	local target = Hazard.douse_target(t.npc :: Npc)
	local closer = by_index[target.index]
	if closer and closer ~= t then
		closer.score = math.max(closer.score, t.score)
		closer.rank = math.max(closer.rank, t.rank, (CONST.ISLAND.rank :: { [string]: number }).path)
		if closer.steps == math.huge then
			closer.steps = Route.walk_steps(target)
		end
	end
end

function Island.douse_here(items: { Item }, scored: { Item }, covered: { [string]: { Npc } }, water: number)
	local me = Geo.to_tile(snap.me)
	if covered[`{me.x},{me.y}`] ~= nil then
		return
	end
	local beside: { Item } = {}
	local best, rank = 0, 0
	for _, item in ipairs(items) do
		if (item.kind == "fire" or item.kind == "multi") and item.score > 0 then
			best = math.max(best, item.score)
			rank = math.max(rank, item.rank)
		end
	end
	for _, item in ipairs(scored) do
		if Hazard.beside_fire(item.npc :: Npc, me) then
			table.insert(beside, item)
		end
	end
	if #beside == 0 then
		return
	end
	table.sort(beside, Island.better)
	local fires: { Npc } = {}
	for k = 1, math.min(#beside, water) do
		fires[k] = beside[k].npc :: Npc
	end
	local here = new_item("multi", 0, 1, 1, nil, nil, { me }, me)
	here.score = math.min(1, best + CONST.ISLAND.here_bonus)
	here.rank = rank + CONST.ISLAND.path_step
	here.fires = fires
	table.insert(items, here)
end

function Island.multi_items(items: { Item }, covered: { [string]: { Npc } })
	local water = Read.item_count(Items.WATER)
	if water == 0 then
		return
	end
	local scored: { Item } = {}
	for _, item in ipairs(items) do
		if item.kind == "fire" and item.score > 0 and item.npc then
			table.insert(scored, item)
		end
	end
	if water >= 2 and #scored >= 2 then
		Island.stand_items(items, scored, covered, water)
	end
	Island.douse_here(items, scored, covered, water)
end

function Island.stand_items(items: { Item }, scored: { Item }, covered: { [string]: { Npc } }, water: number)
	local seen: { [string]: boolean } = {}
	local me = Geo.to_tile(snap.me)
	seen[`{me.x},{me.y}`] = true
	for _, item in ipairs(scored) do
		for _, t in ipairs(Route.beside(Hazard.fire_tiles(item.npc :: Npc))) do
			local key = `{t.x},{t.y}`
			if not seen[key] and covered[key] == nil and (S.solo.multi_failed[key] or 0) <= time() then
				seen[key] = true
				local beside: { Item } = {}
				for _, other in ipairs(scored) do
					if Hazard.beside_fire(other.npc :: Npc, t) then
						table.insert(beside, other)
					end
				end
				if #beside >= 2 and Hazard.hazard_at(t) == nil then
					local route = Route.reaching(t)
					if route and Route.fire_free(route) then
						table.sort(beside, function(a: Item, b: Item): boolean
							return a.score > b.score
						end)
						local count = math.min(#beside, water)
						local best = beside[1]
						local fires: { Npc } = {}
						local rank = 0
						for k = 1, count do
							fires[k] = beside[k].npc :: Npc
							rank = math.max(rank, beside[k].rank)
						end
						local multi = new_item("multi", #route - 1, 1, 1, nil, nil, { t }, t)
						multi.score = math.min(1, best.score + CONST.ISLAND.multi_bonus * (count - 1))
						local multi_key = Island.key(multi)
						if multi.score < 1 and (multi_key == S.solo.acting or multi_key == S.solo.island_top) then
							multi.score = math.min(1, multi.score + CONST.ISLAND.stick)
						end
						multi.rank = rank
						multi.fires = fires
						table.insert(items, multi)
					end
				end
			end
		end
	end
end

function Island.block_unsafe(items: { Item })
	local water = Read.item_count(Items.WATER) > 0
	local landings = next(S.incoming) ~= nil or next(S.cloud_started) ~= nil
	for _, item in ipairs(items) do
		if landings and item.kind == "fire" and item.score > 0 and item.rank == 0 and item.npc then
			local route = Hazard.douse_route(item.npc :: Npc)
			local stand = route and route[#route]
			if stand and (Route.landing_ahead(route :: { Tile }) or Hazard.incoming_at(stand, 0)) then
				item.score = 0
			end
		end
		local stand = item.stand
		if item.score > 0 and item.rank == 0 and stand and item.kind ~= "wait" then
			local tiles = Route.route_to(stand)
			local landing = tiles and Route.landing_ahead(tiles)
			local through = item.kind == "single" or item.kind == "double"
			local hazard = if through then nil else Hazard.hazard_at(stand)
			if landing or (hazard and (hazard.id ~= CONST.FIRE or not water)) then
				item.score = 0
			end
		end
	end
end

function Island.hub_targets(side: Side): { Tile }
	local targets: { Tile } = {}
	for _, crate in ipairs(Island.known_crates()) do
		table.insert(targets, crate.stand)
	end
	local pool = Solo.pier_tile()
	if pool then
		table.insert(targets, pool)
	end
	local buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), side.totem)
	if buckets then
		local stand: Tile = Route.loc_stand(buckets)
		table.insert(targets, stand)
	end
	local seen: { [string]: boolean } = {}
	for _, t in ipairs(Solo.spot_tiles(side)) do
		seen[`{t.x},{t.y}`] = true
		table.insert(targets, t)
	end
	for _, n in ipairs(snap.npcs) do
		if Task.is_spot(n) and not seen[`{n.x},{n.y}`] then
			local spot: Tile = Geo.to_tile(n)
			table.insert(targets, spot)
		end
	end
	return targets
end

function Island.clear_flood(hub: Tile, fires: { Npc }, open: Core.Flood): Core.Flood?
	local r = S.solo
	local keys: { string } = {}
	local blocked: { [number]: boolean } = {}
	for _, fire in ipairs(fires) do
		table.insert(keys, `{fire.x},{fire.y}`)
		for _, t in ipairs(Hazard.fire_tiles(fire)) do
			local n = Route.flood_index(open, t)
			if n then
				blocked[n] = true
			end
		end
	end
	table.sort(keys)
	local key = `{hub.x},{hub.y}|{table.concat(keys, ";")}`
	local cached = r.hub_flood
	if cached and cached.key == key then
		return cached.flood
	end
	local flood = Route.flood(hub, nil, blocked)
	if flood then
		r.hub_flood = { key = key, flood = flood }
	end
	return flood
end

function Island.hub_fires(fires: { Npc }): { [number]: boolean }
	local r = S.solo
	local out: { [number]: boolean } = {}
	if r.p4_stage == nil or r.p5_stage ~= nil or #fires == 0 then
		return out
	end
	local side = S.side :: Side
	local hub = Route.loc_stand(side.shrine)
	local open = Route.flood_from(hub)
	if open == nil then
		return out
	end
	for _, fire in ipairs(fires) do
		if Hazard.fire_distance(fire, hub) <= CONST.SOLO.SHRINE_GUARD then
			out[fire.index] = true
		end
	end
	local clear = Island.clear_flood(hub, fires, open)
	if clear == nil then
		return out
	end
	for _, target in ipairs(Island.hub_targets(side)) do
		local direct = Route.flood_path(open, target)
		local stand = direct and direct[#direct]
		local n = stand and Route.flood_index(open, stand)
		if direct and n then
			local around = clear.dist[n]
			if around == nil or around > #direct - 1 + CONST.SOLO.HUB_DETOUR then
				for _, fire in ipairs(Solo.path_fires(direct)) do
					out[fire.index] = true
				end
			end
		end
	end
	return out
end

function Island.box_zones(needs: Needs): { Box }?
	local boxes = Solo.island_boxes()
	if boxes == nil then
		return nil
	end
	local m = CONST.SOLO.BOX_MARGIN
	local zones: { Box } = {}
	local function widen(b: Box): Box
		return { min_x = b.min_x - m, max_x = b.max_x + m, min_y = b.min_y - m, max_y = b.max_y + m }
	end
	local function add_at(t: Tile?)
		if t == nil then
			return
		end
		for _, b in boxes :: { [string]: Box } do
			local w = widen(b)
			if t.x >= w.min_x and t.x <= w.max_x and t.y >= w.min_y and t.y <= w.max_y then
				table.insert(zones, w)
			end
		end
	end
	add_at(snap.me)
	if #zones == 0 then
		return nil
	end
	add_at(Solo.travel_goal())
	local top = Island.top()
	if top then
		add_at(top.stand or top.tiles[1])
	end
	local current = Solo.current_box()
	if current then
		table.insert(zones, widen(current))
	end
	if needs.fire_box then
		table.insert(zones, widen(needs.fire_box :: Box))
	end
	return zones
end

function Island.box_fires(
	fires: { Npc },
	needs: Needs,
	plan: CratePlan,
	keep: { [number]: boolean },
	under: Npc?
): { Npc }
	local zones = Island.box_zones(needs)
	if zones == nil then
		return fires
	end
	local set = needs.fire_set
	local kept: { Npc } = {}
	for _, fire in ipairs(fires) do
		local wanted = keep[fire.index]
			or (set ~= nil and set[fire.index])
			or (plan.fire_need[fire.index] or 0) > 0
			or (under ~= nil and under.index == fire.index)
		if not wanted then
			for _, zone in ipairs(zones) do
				if Solo.fire_in(zone, fire) then
					wanted = true
					break
				end
			end
		end
		if wanted then
			table.insert(kept, fire)
		end
	end
	return kept
end

function Island.memo_key(): string
	local a = S.activity
	local dest = Player.destination()
	local parts: { string } = {
		tostring(snap.tick),
		`{snap.me.x},{snap.me.y}`,
		if dest then `{dest.x},{dest.y}` else "-",
		tostring(Read.fish_count()),
		tostring(Read.item_count(Items.RAW_FISH)),
		tostring(Read.item_count(Items.WATER)),
		tostring(Read.item_count(Items.BUCKET)),
		tostring(snap.free),
		if a then `{a.kind}:{if a.npc then a.npc.index else -1}` else "idle",
		S.solo.acting or "-",
		tostring(snap.tethered),
		tostring(snap.busy),
		tostring(events.wave_warning_at),
		tostring(events.wave_hit_at),
		tostring(events.stunned_until > time()),
		tostring(S.solo.p3_stage),
		tostring(S.solo.p4_stage),
		tostring(S.solo.p5_stage),
		tostring(S.solo.p2_loading),
		tostring(S.solo.loading),
	}
	for _ in pairs(S.incoming) do
		table.insert(parts, "i")
	end
	return table.concat(parts, "|")
end

function Island.evaluate(): { Item }
	if S.side == nil then
		return {}
	end
	local memo = Island.memo_key()
	if memo == S.solo.island_signature and S.island ~= nil then
		return S.island :: { Item }
	end
	local started = Host.time()
	local laps: { string } = {}
	local lap_at = started
	local function lap(name: string)
		local now = Host.time()
		table.insert(laps, string.format("%s %.1f", name, now - lap_at))
		lap_at = now
	end
	local side = S.side :: Side
	local needs = Island.needs()
	S.solo.fishing_target = needs.fishing_target
	S.solo.fishing_cook = needs.fishing_cook
	lap("needs")
	local all_fires = Hazard.fire_npcs()
	local items: { Item } = {}
	local under = Island.urgent_items(needs, items)
	lap("urgent")
	local plan = Island.crate_plan(needs, all_fires)
	lap("crates")
	local hub = Island.hub_fires(all_fires)
	lap("hub")
	local fires = Island.box_fires(all_fires, needs, plan, hub, under)
	lap("boxes")
	local water = Read.item_count(Items.WATER) > 0
	local skip = S.solo.p2_skip
	local fire_need: { [number]: number } = {}
	local wanted: { [number]: boolean } = {}
	for _, fire in ipairs(fires) do
		local need = plan.fire_need[fire.index] or needs.fire
		local box = needs.fire_box
		local skipped = skip[`{fire.x},{fire.y}`]
		if box ~= nil and (not Solo.fire_in(box, fire) or skipped) then
			need = 0
		end
		if needs.fire_set ~= nil and not (needs.fire_set :: { [number]: boolean })[fire.index] then
			need = 0
		end
		if hub[fire.index] and not skipped then
			need = math.max(need, CONST.ISLAND.need.fire)
		end
		if not water then
			need = 0
		end
		fire_need[fire.index] = need
		wanted[fire.index] = need > 0
	end
	local values = if #fires > 0 then Solo.fire_values(fires, wanted) else {}
	for index in pairs(hub) do
		if values[index] ~= nil and wanted[index] then
			values[index] = math.max(values[index], CONST.SOLO.FIRE_VALUE.hub_floor)
		end
	end
	lap("values")
	local covered = Solo.burning_tiles()
	Island.spot_items(needs, items, covered)
	lap("spots")
	Island.loc_item("shrine", side.shrine, needs.shrine, items)
	if needs.shrine_rank > 0 then
		local shrine = items[#items]
		shrine.score = needs.shrine
		shrine.rank = needs.shrine_rank
	end
	Island.crate_items(plan, items)
	if needs.rush then
		local chosen: Item? = nil
		for _, item in ipairs(items) do
			if item.kind == "crate" and item.score > 0 then
				local best = chosen
				if Island.current(item) or best == nil or (not Island.current(best) and item.steps < best.steps) then
					chosen = item
				end
			end
		end
		if chosen then
			chosen.score = CONST.ISLAND.need.urgent
			chosen.rank = (CONST.ISLAND.rank :: { [string]: number }).load
		end
	end
	Island.dodge_by_crate(items)
	lap("crate items")
	for _, option in ipairs(Island.tether_options()) do
		local loc = option.loc
		local tile = Geo.to_tile(loc)
		local item = new_item("tether", option.steps, Island.fit(option.steps), needs.tether, nil, loc, nil, tile)
		if needs.tether > 0 then
			item.score = needs.tether
			item.rank = (CONST.ISLAND.rank :: { [string]: number }).tether
			needs.tether = 0
			if Read.is_damaged(loc) and Read.has_hammer() and not snap.tethered and not Doing.is_doing("tether") then
				local repair = urgent_item("repair", Island.loc_tiles(loc))
				repair.loc = loc
				repair.stand = Route.loc_stand(loc)
				table.insert(items, repair)
			end
		end
		table.insert(items, item)
	end
	lap("tethers")
	Island.loc_item("pump", Task.pump_in_reach(), needs.pump, items)
	Island.tile_item("route", Solo.p3_waypoint(), needs.route, items)
	for _, tool in ipairs(CONST.ISLAND.tools) do
		local need = needs.tools[tool.kind] or 0
		if tool.kind == "buckets" then
			local used = S.solo.p3_buckets
			local nearest = used or Geo.nearest_walk(Read.locs_named({ tool.name }))
			for _, crate in ipairs(Read.locs_named({ tool.name })) do
				local chosen = nearest ~= nil and crate.x == nearest.x and crate.y == nearest.y
				Island.loc_item(tool.kind, crate, if chosen then need else 0, items)
			end
		else
			Island.loc_item(tool.kind, Geo.nearest_loc(Read.locs_named({ tool.name }), side.mast), need, items)
		end
	end
	local mast = Route.route_end(Geo.to_tile(side.mast))
	Island.npc_item(
		"pier",
		Geo.nearest_npc(Read.npcs_with(CONST.INACTIVE_POOL), snap.me),
		needs.pier,
		items,
		Solo.pier_tile() or mast
	)
	Island.npc_item("pool", Geo.nearest_npc(Read.npcs_with(CONST.SPIRIT_POOL), snap.me), needs.attack, items, mast)
	if needs.attack > 0 then
		local pool = items[#items]
		pool.score = needs.attack
		pool.rank = (CONST.ISLAND.rank :: { [string]: number }).pool
	end
	Island.humidify_item(needs, items)
	Island.drop_item(needs, items)
	Island.pickup_item(needs, items)
	if needs.step > 0 then
		local t = Solo.step_off_tile()
		local step = new_item("step", 1, 1, needs.step, nil, nil, { t }, t)
		if needs.step >= CONST.ISLAND.need.urgent then
			step.rank = (CONST.ISLAND.rank :: { [string]: number }).step
		end
		table.insert(items, step)
	end
	Island.north_items(needs, items)
	lap("others")
	for _, fire in ipairs(fires) do
		local value = values[fire.index] or 0
		local need = if value > 0 then fire_need[fire.index] else 0
		local steps = if need > 0 then Route.walk_steps(fire) else math.huge
		local item = new_item("fire", steps, value, need, fire, nil, Hazard.fire_tiles(fire))
		if under and under.index == fire.index then
			item.score = CONST.ISLAND.need.urgent
			item.rank = (CONST.ISLAND.rank :: { [string]: number }).dodge
			item.steps = 0
		end
		table.insert(items, item)
	end
	Island.wait_item(needs, items)
	lap("fire items")
	Island.block_unsafe(items)
	lap("safety")
	Island.stick(items)
	Island.multi_items(items, covered)
	lap("multi")
	Island.inherit_path(items, fires)
	lap("path")
	Island.inherit_douse(items)
	Island.confine(items)
	lap("douse")
	table.sort(items, Island.better)
	S.island = items
	S.solo.island_signature = memo
	S.solo.island_round = S.solo.loop_round
	Island.log_top(items)
	lap("sort")
	Island.draw(items)
	lap("draw")
	local took = Host.time() - started
	if took > CONST.ISLAND.slow_ms or DebugDraw.on() then
		Log.log(
			"Tempoross",
			string.format(
				"   Evaluation %.1f ms, %d of %d fires, %d items: %s",
				took,
				#fires,
				#all_fires,
				#items,
				table.concat(laps, ", ")
			)
		)
	end
	return items
end

function Island.top(): Item?
	local items = S.island
	return if items then (items :: { Item })[1] else nil
end

function Island.watch_mark(): number
	local landings = 0
	for _ in pairs(S.incoming) do
		landings += 1
	end
	return snap.tick * 100000 + Read.fish_count() * 1000 + math.min(S.solo.loaded, 99) * 10 + math.min(landings, 9)
end

function Island.scoring(): boolean
	return Core.CONFIG.solo and S.hud_up and S.side ~= nil and S.solo.acting ~= nil
end

function Island.watch(): boolean
	local r = S.solo
	if not Island.scoring() then
		return false
	end
	Read.sync_inventory()
	local mark = Island.watch_mark()
	if mark == r.watch_tick then
		return r.watch_changed
	end
	r.watch_tick = mark
	Solo.bookkeep()
	local top = Island.evaluate()[1]
	local changed = top ~= nil and Island.key(top) ~= r.acting
	if changed then
		Log.log("Tempoross", `   Top score is now {Island.describe(top)}, stopping {r.acting}`)
	end
	r.watch_changed = changed
	return changed
end

function Island.fire_key(fire: Npc): string
	local t = Hazard.fire_tiles(fire)[1]
	return `fire:{t.x},{t.y}`
end

function Island.describe(item: Item?): string
	if item == nil then
		return "nothing"
	end
	local at = item.tiles[1]
	return `{item.kind} {string.format("%.2f", item.score)}{if at then ` at {at.x},{at.y}` else ""}`
end

function Island.key(item: Item): string
	local at = item.tiles[1]
	if (CONST.ISLAND.alone :: { [string]: boolean })[item.kind] or at == nil then
		return item.kind
	end
	return `{item.kind}:{at.x},{at.y}`
end

function Island.current(item: Item): boolean
	local a = S.activity
	if a == nil then
		return false
	end
	if a.kind == "fish" then
		return (item.kind == "single" or item.kind == "double")
			and item.npc ~= nil
			and a.npc ~= nil
			and (item.npc :: Npc).index == (a.npc :: Npc).index
	elseif a.kind == "cook" then
		return item.kind == "shrine"
	elseif a.kind == "load" then
		return item.kind == "crate"
			and item.npc ~= nil
			and a.npc ~= nil
			and (item.npc :: Npc).index == (a.npc :: Npc).index
	elseif a.kind == "pump" then
		return item.kind == "pump"
	elseif a.kind == "attack" then
		return item.kind == "pool"
	elseif a.kind == "tether" then
		return item.kind == "tether"
			and item.loc ~= nil
			and a.loc ~= nil
			and (item.loc :: Loc).x == (a.loc :: Loc).x
			and (item.loc :: Loc).y == (a.loc :: Loc).y
	end
	return false
end

function Island.stick(items: { Item })
	local r = S.solo
	for _, item in ipairs(items) do
		if item.score > 0 and item.score < 1 then
			local key = Island.key(item)
			if Island.current(item) or key == r.island_top or key == r.acting then
				item.score = math.min(1, item.score + CONST.ISLAND.stick)
			end
		end
	end
end

function Island.draw_slots(item: Item, text_color: Draw.Color)
	local boxes = Inventory.boxes()
	if boxes == nil or item.slots == nil then
		return
	end
	local colors = CONST.ISLAND_DRAW.colors :: { [string]: Draw.Color }
	local color = colors[item.kind] or CONST.ISLAND_DRAW.default_color
	local segments: { { Point } } = {}
	local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
	for _, slot in ipairs(item.slots :: { number }) do
		local b = boxes[slot]
		if b then
			local x1, y1, x2, y2 = b.x, b.y, b.x + b.width, b.y + b.height
			table.insert(segments, { { x = x1, y = y1 }, { x = x2, y = y1 } })
			table.insert(segments, { { x = x2, y = y1 }, { x = x2, y = y2 } })
			table.insert(segments, { { x = x2, y = y2 }, { x = x1, y = y2 } })
			table.insert(segments, { { x = x1, y = y2 }, { x = x1, y = y1 } })
			min_x, min_y = math.min(min_x, x1), math.min(min_y, y1)
			max_x, max_y = math.max(max_x, x2), math.max(max_y, y2)
		end
	end
	if #segments == 0 then
		return
	end
	Draw.batch(function()
		Draw.lines(segments, color, CONST.ISLAND_DRAW.outline_width)
		Island.text(string.format("%.2f", item.score), { x = (min_x + max_x) / 2, y = (min_y + max_y) / 2 }, text_color)
	end, "ui")
end

function Island.log_top(items: { Item })
	local top = items[1]
	local key = if top and top.score > 0 then Island.key(top) else "nothing"
	if key == S.solo.island_top then
		return
	end
	S.solo.island_top = key
	Log.log(
		"Tempoross",
		`   Top score: {if top and top.score > 0 then Island.describe(top) else "nothing"}, next {Island.describe(
			items[2]
		)}`
	)
end

function Island.segment_points(ch: string, x: number, y: number, h: number): { { Point } }
	local w = h * 0.5
	local corners: { [string]: { Point } } = {
		a = { { x = x, y = y }, { x = x + w, y = y } },
		b = { { x = x + w, y = y }, { x = x + w, y = y + h / 2 } },
		c = { { x = x + w, y = y + h / 2 }, { x = x + w, y = y + h } },
		d = { { x = x, y = y + h }, { x = x + w, y = y + h } },
		e = { { x = x, y = y + h / 2 }, { x = x, y = y + h } },
		f = { { x = x, y = y }, { x = x, y = y + h / 2 } },
		g = { { x = x, y = y + h / 2 }, { x = x + w, y = y + h / 2 } },
	}
	local out: { { Point } } = {}
	local segs = SEGMENTS[ch] or ""
	for k = 1, #segs do
		table.insert(out, corners[string.sub(segs, k, k)])
	end
	return out
end

function Island.text_width(text: string, h: number): number
	local width = 0
	for i = 1, #text do
		width += if string.sub(text, i, i) == "." then h * 0.4 else h * 0.8
	end
	return width
end

function Island.text(text: string, center: Point, color: Draw.Color)
	local h = CONST.ISLAND_DRAW.text_size
	local x = center.x - Island.text_width(text, h) / 2
	local y = center.y - h / 2
	local strokes: { { Point } } = {}
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		if ch == "." then
			table.insert(strokes, { { x = x + 1, y = y + h }, { x = x + 3, y = y + h } })
			x += h * 0.4
		else
			for _, seg in ipairs(Island.segment_points(ch, x, y, h)) do
				table.insert(strokes, seg)
			end
			x += h * 0.8
		end
	end
	local shadow: { { Point } } = {}
	local offset = CONST.ISLAND_DRAW.shadow_offset
	for _, seg in ipairs(strokes) do
		table.insert(shadow, {
			{ x = seg[1].x + offset, y = seg[1].y + offset },
			{ x = seg[2].x + offset, y = seg[2].y + offset },
		})
	end
	Draw.lines(shadow, CONST.ISLAND_DRAW.shadow_color, CONST.ISLAND_DRAW.text_width + 2)
	Draw.lines(strokes, color, CONST.ISLAND_DRAW.text_width)
end

function Island.center(quads: { Geometry.Quad? }, from: number, to: number): Point?
	local sx, sy, n = 0, 0, 0
	for i = from, to do
		local quad = quads[i]
		if quad then
			for _, p in ipairs({ quad.top, quad.right, quad.bottom, quad.left }) do
				sx += p.x
				sy += p.y
				n += 1
			end
		end
	end
	return if n > 0 then { x = sx / n, y = sy / n } else nil
end

function Island.outline(tiles: { Tile }, quads: { Geometry.Quad? }, from: number): { { Point } }
	local inside: { [string]: boolean } = {}
	for _, t in ipairs(tiles) do
		inside[`{t.x},{t.y}`] = true
	end
	local segments: { { Point } } = {}
	for i, t in ipairs(tiles) do
		local quad = quads[from + i - 1]
		if quad then
			local sw, nw, ne, se = quad.top, quad.right, quad.bottom, quad.left
			if not inside[`{t.x - 1},{t.y}`] then
				table.insert(segments, { sw, nw })
			end
			if not inside[`{t.x},{t.y + 1}`] then
				table.insert(segments, { nw, ne })
			end
			if not inside[`{t.x + 1},{t.y}`] then
				table.insert(segments, { ne, se })
			end
			if not inside[`{t.x},{t.y - 1}`] then
				table.insert(segments, { se, sw })
			end
		end
	end
	return segments
end

function Island.draw(items: { Item })
	if not DebugDraw.on() then
		return
	end
	local shown = table.clone(items)
	local colors: { [string]: Draw.Color } = CONST.ISLAND_DRAW.colors :: any
	DebugDraw.set("island", function()
		local burning: { [string]: boolean } = {}
		for _, fire in ipairs(Read.npcs_with(CONST.FIRE)) do
			burning[`{fire.x},{fire.y}`] = true
		end
		local live: { Item } = {}
		for _, item in ipairs(shown) do
			local fire = item.npc
			if item.kind ~= "fire" or fire == nil or burning[`{fire.x},{fire.y}`] then
				table.insert(live, item)
			end
		end
		local all: { Tile } = {}
		local starts: { number } = {}
		for i, item in ipairs(live) do
			starts[i] = #all + 1
			if item.slots == nil then
				table.move(item.tiles, 1, #item.tiles, #all + 1, all)
			end
		end
		local quads = Projection.tiles(all)
		for i, item in ipairs(live) do
			local text_color = if i == 1 and item.score > 0
				then CONST.ISLAND_DRAW.best_color
				else CONST.ISLAND_DRAW.score_color
			if item.slots then
				Island.draw_slots(item, text_color)
			else
				local from = starts[i]
				if item.kind ~= "fire" then
					local color = colors[item.kind] or CONST.ISLAND_DRAW.default_color
					Draw.lines(Island.outline(item.tiles, quads, from), color, CONST.ISLAND_DRAW.outline_width)
				end
				local center = Island.center(quads, from, from + #item.tiles - 1)
				if center then
					Island.text(string.format("%.2f", item.score), center, text_color)
				end
			end
		end
		Island.draw_waypoints()
	end)
end

function Island.draw_waypoints()
	local r = S.solo
	if r.p3_stage ~= "route" and r.p3_stage ~= "clear" then
		return
	end
	local tiles: { Tile } = {}
	local labels: { string } = {}
	local at: { [string]: number } = {}
	for i, t in ipairs(r.p3_route) do
		local key = `{t.x},{t.y}`
		local known = at[key]
		if known then
			labels[known] ..= ` {i}`
		else
			table.insert(tiles, t)
			table.insert(labels, tostring(i))
			at[key] = #tiles
		end
	end
	local quads = Projection.tiles(tiles)
	local color = (CONST.ISLAND_DRAW.colors :: { [string]: Draw.Color }).route
	Draw.lines(Island.outline(tiles, quads, 1), color, CONST.ISLAND_DRAW.outline_width)
	for i, label in ipairs(labels) do
		local center = Island.center(quads, i, i)
		if center then
			Island.text(label, center, color)
		end
	end
end

function Island.clear()
	if S.island ~= nil then
		S.island = nil
		DebugDraw.set("island", nil)
	end
end

return Island
