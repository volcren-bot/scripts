--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local item_container = Host.item_container
local varbit = Host.varbit
local sleep = Host.sleep
local time = Host.time
local Biometrics = require("@lib/main/antiban/biometrics")
local Camera = require("@lib/main/camera")
local Core = require("./core")
local DebugDraw = require("@lib/main/debug_draw")
local Draw = require("@lib/utils/draw")
local Geometry = require("@lib/utils/math/geometry")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Projection = require("@lib/main/projection/projection")
local Random = require("@lib/utils/math/random")
local Ticks = require("@lib/utils/ticks")
local Walker = require("@lib/main/walker")
type Box = Core.Box
type Activity = Core.Activity
type Side = Core.Side
type State = Core.State
type Npc = Core.Npc
type Loc = Core.Loc
type Tile = Core.Tile
type Point = { x: number, y: number }
local CONST = Core.CONST
local Items = Core.Items
local HUD = Core.HUD
local S = Core.S
local snap = Core.snap
local events = Core.events
local plan = Core.plan
local Read = Core.Read
local Geo = Core.Geo
local Chat = Core.Chat
local Ship = Core.Ship
local Hazard = Core.Hazard
local Route = Core.Route
local Doing = Core.Doing
local Task = Core.Task
local Game = Core.Game
local Solo = Core.Solo
local Island = Core.Island

function Solo.counting(): boolean
	return (S.solo.opened and (Doing.is_doing("fish") or snap.tethered or Doing.is_doing("tether")))
		or Doing.is_doing("load")
		or S.solo.ship_hover ~= nil
		or S.solo.fire_hover ~= nil
end

function Solo.fish_until()
	local r = S.solo
	if r.fishing_cook and Read.fish_count() >= r.fishing_target - CONST.SOLO.PREHOVER_FISH then
		Task.prehover_shrine()
	end
	Route.sleep_watching(Random.int(900, 1500), nil, function(): boolean
		Read.sync_inventory()
		return Read.fish_count() >= r.fishing_target
	end)
end

function Solo.wait_at_totem(range: number, near: number, min_ms: number, max_ms: number)
	local totem = (S.side :: Side).totem
	if Geo.distance(snap.me, totem) > range then
		Route.walk_near(totem, near)
		return
	end
	Route.sleep_watching(Random.int(min_ms, max_ms))
end

function Solo.wait_wave()
	Solo.wait_at_totem(2, 2, 300, 600)
end

function Solo.wait_double()
	Solo.wait_at_totem(8, 5, 600, 1200)
end

function Solo.at_crate(): boolean
	for _, crate in ipairs(Task.crates()) do
		if Geo.distance(crate, snap.me) <= 1 then
			return true
		end
	end
	return false
end

function Solo.track_loaded()
	local r = S.solo
	Read.sync_inventory()
	local fish = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	if fish < r.last_fish and (Solo.at_crate() or time() - r.left_crate_at < CONST.SOLO.STEP_OFF_COUNT_MS) then
		local gone = r.last_fish - fish
		local raw_gone = math.clamp(r.last_raw - raw, 0, gone)
		r.inventory_loads += gone
		r.loaded_raw += raw_gone
		r.loaded_cooked += gone - raw_gone
		Log.log(
			"Tempoross",
			`   Loaded {gone - raw_gone} cooked and {raw_gone} raw, {r.loaded_cooked} cooked and {r.loaded_raw} raw this game, energy {Read.hud_percent(
				HUD.ENERGY
			) or "?"}%`
		)
	end
	r.last_fish = fish
	r.last_raw = raw
	local now = time()
	table.insert(r.fish_seen, { at = now, fish = fish })
	while #r.fish_seen > 0 and now - r.fish_seen[1].at > CONST.SOLO.FISH_SEEN_MS do
		table.remove(r.fish_seen, 1)
	end
	if not S.load_sound_missing and r.load_sounds == 0 and r.inventory_loads >= CONST.SOLO.LOAD_SOUND_MISSING then
		S.load_sound_missing = true
		Log.log(
			"Tempoross",
			`   No crate sound after {r.inventory_loads} fish left at the crate: its packet may have changed, counting from the inventory`
		)
	end
	r.loaded = if S.load_sound_missing then r.inventory_loads else r.load_sounds
	if r.loaded >= CONST.SOLO.FIRST_BATCH and r.first_loaded_at == nil then
		r.first_loaded_at = time()
		Log.log(
			"Tempoross",
			`   Loaded {r.loaded} fish ({r.inventory_loads} left the inventory at the crate), energy {Read.hud_percent(
				HUD.ENERGY
			) or "?"}%`
		)
	end
end

function Solo.step_off_tile(): Tile
	local here = snap.me
	local totem = (S.side :: Side).totem
	local dx = if totem.x > here.x then 1 elseif totem.x < here.x then -1 else 0
	local dy = if totem.y > here.y then 1 elseif totem.y < here.y then -1 else 0
	return { x = here.x + dx, y = here.y + dy }
end

function Solo.load_exact(target: number)
	local r = S.solo
	if not Doing.is_doing("load") then
		if Task.surge_waited() then
			return
		end
		if Task.walk_to_crate() == nil then
			Route.sleep_watching(Random.int(300, 600))
			return
		end
	end
	Solo.face_ahead("totem", Geo.to_tile((S.side :: Side).totem))
	local hovered = false
	local function stop(): boolean
		Solo.track_loaded()
		if r.loaded >= target or Read.fish_count() == 0 then
			return true
		end
		if not hovered and r.loaded >= target - 1 and Read.fish_count() > 1 then
			hovered = Solo.hover_next()
		end
		return Task.off_crate_stand()
	end
	Route.sleep_watching(Random.int(1500, 2500), nil, stop)
	if r.loaded >= target or (Read.fish_count() > 0 and Task.off_crate_stand()) then
		r.left_crate_at = time()
		Doing.clear_activity()
	end
end

function Solo.hover_next(): boolean
	local items: { Core.IslandItem } = S.island or {}
	local next = items[2]
	if next == nil or next.score <= 0 then
		return false
	end
	if next.npc then
		return Npcs.hover_async(next.npc :: Npc)
	end
	local t = next.stand or next.tiles[1]
	return t ~= nil and Walker.hover_tile_async(t)
end

function Solo.step_to()
	local item = plan.item :: Core.IslandItem
	local t = item.tiles[1]
	S.solo.left_crate_at = time()
	Log.log("Tempoross", `   Stepping off the crate to {t.x},{t.y}`)
	Route.click(t)
	Doing.clear_activity()
	Route.sleep_watching(Random.int(300, 500))
end

function Solo.ship_target(): Tile
	return Route.route_end(Geo.to_tile((S.side :: Side).mast))
end

function Solo.while_tethered()
	local r = S.solo
	if r.opened and not r.loading and r.loaded == 0 then
		if Read.item_count(Items.RAW_FISH) > 0 then
			Task.prehover_shrine()
		elseif Read.fish_count() >= CONST.SOLO.FIRST_BATCH then
			Solo.pick_ship_hover()
		end
	end
	Route.sleep_watching(CONST.SOLO.TETHER_POLL_MS, nil, function(): boolean
		Chat.read_chat()
		return events.wave_hit_at ~= nil or (varbit(CONST.TETHERED_VARBIT) or 0) == 0
	end)
	if events.wave_hit_at ~= nil and r.loaded == 0 and Read.item_count(Items.RAW_FISH) > 0 then
		Solo.spam_off_totem()
	end
end

function Solo.spam_off_totem()
	local shrine = (S.side :: Side).shrine
	local start = snap.me
	local deadline = time() + CONST.SOLO.UNTETHER_SPAM_MS
	local marks: { string } = {}
	local released, clicked, flagged = false, false, false
	local click_at = math.huge
	local delay = CONST.SOLO.UNTETHER_CLICK_DELAY_MS
	while time() < deadline do
		local st = game_state()
		local tick = Read.current_tick(st)
		if not released then
			local animation = Read.my_animation()
			local tether = varbit(CONST.TETHERED_VARBIT) or 0
			if animation == CONST.UNTETHER_ANIMATION or tether == 0 then
				released = true
				click_at = time() + Random.int(delay[1], delay[2])
				table.insert(marks, `released T{tick} (animation {animation}, tether {tether})`)
			end
		end
		if released then
			local pos = st.position
			if st.destination and not flagged then
				flagged = true
				table.insert(marks, `destination T{tick}`)
			end
			if pos and not Geo.same(pos, start) then
				table.insert(marks, `moving T{tick}`)
				break
			end
			local top = Minimenu.left_click()
			if top == nil or top.option ~= "Cook-at" then
				Objects.hover_async(shrine)
				Mouse.wait()
			end
			if time() >= click_at then
				Mouse.click()
				if not clicked then
					clicked = true
					table.insert(marks, `first click T{tick}`)
				end
			end
		end
		sleep(Random.int(90, 150))
	end
	Log.log("Tempoross", `   Off the totem: {table.concat(marks, ", ")}`)
	Doing.begin_activity("cook", nil, shrine)
end

function Solo.face_ahead(key: string, tile: Tile)
	local r = S.solo
	if r.faced == key or Mouse.busy() then
		return
	end
	r.faced = key
	local me = snap.me
	if Geo.same(tile, me) then
		return
	end
	local bearing = math.deg(math.atan2(tile.x - me.x, tile.y - me.y))
	local spread = Camera.LOOK_SPREAD
	Camera.set_yaw_async(Camera.degrees_to_yaw(bearing + Random.mean(-spread, spread)))
	Log.log("Tempoross", `   Turning the camera toward the {key} at {tile.x},{tile.y}`)
end

function Solo.holding_camera(kind: string): boolean
	local faced = S.solo.faced
	return (kind == "cook" and faced == "crate") or (kind == "load" and faced == "totem")
end

function Solo.hover_ship_path()
	Solo.face_ahead("crate", Solo.crate_target())
	if Read.item_count(Items.RAW_FISH) <= CONST.SOLO.HOVER_RAW then
		if S.solo.first_loaded_at ~= nil then
			Solo.prehover_route(Solo.crate_target())
		else
			Solo.pick_ship_hover()
		end
	end
	Route.sleep_watching(150)
end

function Solo.crate_target(): Tile
	local crate = Task.usable_crates(true)[1]
	return if crate then Route.npc_stand(crate) else Solo.ship_target()
end

function Solo.prehover_route(target: Tile)
	local r = S.solo
	if r.hover_tried then
		return
	end
	r.hover_tried = true
	local tiles = Route.route_to(target)
	if tiles == nil then
		return
	end
	if Route.fire_free(tiles) then
		r.hover_tried = false
		Solo.pick_ship_hover()
		return
	end
	local around = Route.waypoint_around_fires(target)
	if around and Walker.hover_tile_async(around) then
		r.ship_hover = around
		r.ship_hover_waypoint = true
		Log.log("Tempoross", `   Hovering {around.x},{around.y} to go around the fires`)
		return
	end
	local fire = Route.first_fire(tiles)
	if fire then
		local first = Hazard.douse_target(fire)
		if Npcs.hover_async(first) then
			r.fire_hover = first
			Log.log("Tempoross", `   Hovering the fire at {first.x},{first.y} on the way`)
		end
	end
end

function Solo.last_on_screen(tiles: { Tile }): (Tile?, number)
	for i = #tiles, 2, -1 do
		if Walker.on_screen(tiles[i]) then
			return tiles[i], i
		end
	end
	return nil, 0
end

function Solo.hover_start()
	local side = Ship.find_side()
	if side == nil then
		return
	end
	local route = Walker.route(Geo.to_tile(side.totem))
	local t = route and Solo.last_on_screen(route.tiles)
	if t and Geo.distance(t, snap.me) >= CONST.SOLO.HOVER_MIN_TILES and Walker.hover_tile_async(t) then
		S.start_hover = t
		Log.log("Tempoross", `   Hovering {t.x},{t.y} on the way to the totem`)
	end
end

function Solo.click_start()
	local start = S.start_hover
	if start == nil then
		return
	end
	local top = Minimenu.left_click()
	if top == nil or top.option ~= "Walk here" then
		return
	end
	Mouse.click()
	local deadline = time() + CONST.SOLO.START_CLICK_CHECK_MS
	while time() < deadline do
		if game_state().destination ~= nil then
			S.start_hover = nil
			Log.log("Tempoross", `   Off to the totem through {start.x},{start.y} under the fade`)
			return
		end
		sleep(30)
	end
end

function Solo.pick_ship_hover()
	local r = S.solo
	if r.ship_hover and not Walker.on_screen(r.ship_hover :: Tile) then
		r.ship_hover = nil
		r.hover_tried = false
	end
	if r.ship_hover == nil and not r.hover_tried then
		r.hover_tried = true
		local route = Walker.route(Solo.ship_target())
		if route then
			local t, i = Solo.last_on_screen(route.tiles)
			if
				t
				and Geo.distance(t, snap.me) >= CONST.SOLO.HOVER_MIN_TILES
				and Route.fire_free(table.move(route.tiles, 1, i, 1, {}))
			then
				r.ship_hover = t
			end
		end
		local hover: Tile? = r.ship_hover
		Log.log(
			"Tempoross",
			if hover then `   Hovering {hover.x},{hover.y} on the way to the ship` else "   No ship path tile on screen"
		)
		if hover then
			Walker.hover_tile_async(hover)
		end
	end
end

function Solo.click_ship_hover(): boolean
	local r = S.solo
	local hover = r.ship_hover
	local waypoint = r.ship_hover_waypoint
	r.ship_hover = nil
	r.ship_hover_waypoint = false
	r.hover_tried = false
	if hover == nil then
		return false
	end
	if waypoint then
		r.waypoint = hover
	end
	if not Walker.on_screen(hover) then
		Log.log("Tempoross", `   The hovered tile {hover.x},{hover.y} went off screen`)
		return false
	end
	local tiles = Route.route_to(hover)
	if tiles and (Route.landing_ahead(tiles) or Route.first_fire(tiles)) then
		Log.log("Tempoross", `   Not taking the hovered tile: fire or strike on the way`)
		return false
	end
	if Walker.click_tile(hover) then
		Log.log("Tempoross", `   Off to the ship through {hover.x},{hover.y}`)
		return true
	end
	return false
end

function Solo.late_wave(): boolean
	return events.wave_warning_at ~= nil and events.waves_passed >= 1 and S.solo.pools == 0 and not S.solo.vulnerable
end

function Solo.fish_target(): number
	return if S.solo.first_loaded_at then CONST.SOLO.SECOND_BATCH else CONST.SOLO.FIRST_BATCH
end

function Solo.move_safely(target: Tile, act: () -> ())
	local r = S.solo
	local waypoint = r.waypoint
	if waypoint then
		if Geo.distance(snap.me, waypoint) > 1 and Player.destination() ~= nil then
			Route.sleep_watching(CONST.POLL_MS)
			return
		end
		r.waypoint = nil
	end
	if not Solo.go_around_fires(target) then
		act()
	end
end

function Solo.go_around_fires(target: Tile): boolean
	local tiles = Route.route_to(target)
	if tiles == nil or Route.fire_free(tiles) then
		return false
	end
	local around = Route.waypoint_around_fires(target)
	if around == nil then
		return false
	end
	S.solo.waypoint = around
	Log.log("Tempoross", `   Going around the fires through {around.x},{around.y}`)
	Route.click(around)
	Route.sleep_watching(Random.int(200, 350))
	return true
end

function Solo.path_fires(tiles: { Tile }): { Npc }
	local all = Hazard.fire_npcs()
	local order: { Npc } = {}
	local taken: { [number]: boolean } = {}
	local function take(fire: Npc)
		taken[fire.index] = true
		table.insert(order, fire)
	end
	for i = 2, #tiles do
		for _, fire in ipairs(all) do
			if not taken[fire.index] and Hazard.fire_distance(fire, tiles[i]) <= CONST.FIRE_REACH then
				take(fire)
				for _, other in ipairs(all) do
					if not taken[other.index] and Geo.distance(fire, other) <= Hazard.fire_size(fire) then
						take(other)
					end
				end
			end
		end
	end
	return order
end

function Solo.pier_tile(): Tile?
	local pool = Geo.nearest_npc(Read.npcs_with(CONST.INACTIVE_POOL), snap.me)
		or Geo.nearest_npc(Read.npcs_with(CONST.SPIRIT_POOL), snap.me)
	return if pool then Route.npc_stand(pool) else nil
end

function Solo.load_all()
	local r = S.solo
	if not Doing.is_doing("load") then
		if Task.surge_waited() then
			return
		end
		Solo.click_ship_hover()
		Solo.move_safely(Solo.crate_target(), function()
			if Task.walk_to_crate() == nil then
				Route.sleep_watching(Random.int(300, 600))
			end
		end)
		return
	end
	if Read.fish_count() <= CONST.SOLO.PIER_HOVER_FISH and r.pier_hover == nil then
		local pier = Solo.pier_tile()
		r.pier_hover = pier
		if pier then
			Log.log("Tempoross", `   Hovering the pier at {pier.x},{pier.y}`)
			Walker.hover_tile_async(pier)
		end
	end
	Route.sleep_watching(Random.int(150, 250), nil, function(): boolean
		Read.sync_inventory()
		Chat.read_chat()
		return Read.fish_count() == 0 or Task.surge_blocks_loading() or Task.off_crate_stand()
	end)
	if Read.fish_count() > 0 and Task.off_crate_stand() then
		Doing.clear_activity()
	end
end

function Solo.go_to_pier()
	local r = S.solo
	local pier = r.pier_hover or Solo.pier_tile()
	r.pier_hover = nil
	if pier == nil then
		Route.walk_near(Geo.to_tile((S.side :: Side).mast), 6)
		return
	end
	if Geo.distance(snap.me, pier) <= CONST.PIER_RANGE then
		Route.sleep_watching(Random.int(200, 400))
		return
	end
	Solo.move_safely(pier, function()
		Log.log("Tempoross", `   Off to the pier at {pier.x},{pier.y}`)
		Route.click(pier)
		Route.sleep_watching(Random.int(300, 500))
	end)
end

function Solo.wants_humidify(): boolean
	local r = S.solo
	local blocked = CONST.SOLO.NO_HUMIDIFY_DURING :: { [string]: boolean }
	local busy = S.activity ~= nil and blocked[(S.activity :: Activity).kind] == true
	if time() < r.humidify_at or busy or snap.tethered or Solo.humidify_settling() then
		return false
	end
	if r.p2_clear ~= nil and r.p3_stage == nil and #Solo.side_fires() == 0 then
		return false
	end
	if r.p3_stage == "buckets" or r.p3_stage == "humidify" or (r.p3_stage == "cross" and r.p3_humidify) then
		return false
	end
	if r.p5_stage == "buckets" or r.p5_stage == "humidify" or r.p5_stage == "fish" or r.p5_stage == "load" then
		return false
	end
	if r.p4_stage ~= nil and r.p5_stage == nil then
		if r.pools >= 2 or Hazard.fire_near(snap.me, CONST.SOLO.P4_HUMIDIFY_FIRE_RANGE) == nil then
			return false
		end
	end
	Read.sync_inventory()
	local at_water = if r.p3_stage ~= nil then 0 else CONST.SOLO.HUMIDIFY_AT_WATER
	return Read.item_count(Items.WATER) <= at_water and Read.item_count(Items.BUCKET) > 0
end

function Solo.cast_humidify(): boolean
	Read.sync_inventory()
	local water = Read.item_count(Items.WATER)
	if Magic.cast("Humidify") then
		S.solo.humidify_cast = { at = time(), water = water }
		return true
	end
	S.solo.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
	Log.log("Tempoross", "   Couldn't cast Humidify")
	return false
end

function Solo.humidify()
	if Player.destination() ~= nil and S.solo.p3_humidify then
		Log.log("Tempoross", `   Casting Humidify while walking ({Read.item_count(Items.WATER)} buckets of water)`)
		Solo.cast_humidify()
		return
	end
	local before = Read.item_count(Items.WATER)
	Log.log("Tempoross", `   {before} buckets of water left, casting Humidify`)
	if not Solo.cast_humidify() then
		return
	end
	local filled = Route.sleep_watching(3000, nil, function(): boolean
		Read.sync_inventory()
		return Read.item_count(Items.WATER) > before
	end)
	if not filled then
		S.solo.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
	end
	Inventory.open()
	Log.log("Tempoross", `   {Read.item_count(Items.WATER)} buckets of water after Humidify`)
end

function Solo.nearest_double(): Npc?
	return (
		Task.closest_spot(function(n: Npc): boolean
			return n.id == CONST.DOUBLE_SPOT and Read.double_ticks_left(n, snap.tick) >= CONST.DOUBLE_MIN_TICKS_LEFT
		end)
	)
end

function Solo.douse_top()
	local fire = plan.fire :: Npc
	if Route.nearest_of(Route.beside(Hazard.fire_tiles(fire))) == nil then
		S.solo.p2_skip[`{fire.x},{fire.y}`] = true
		Log.log("Tempoross", `   Can't reach the fire at {fire.x},{fire.y}, skipping it`)
		return
	end
	Log.log("Tempoross", `   Putting out the top scored fire at {fire.x},{fire.y}`)
	Hazard.douse(fire, plan.after)
end

function Solo.multi_douse()
	local item = plan.item :: Core.IslandItem
	local stand = item.stand :: Tile
	local fires = item.fires :: { Npc }
	local r = S.solo
	if not Geo.same(snap.me, stand) then
		Log.log("Tempoross", `   Standing at {stand.x},{stand.y} to put out {#fires} fires from one tile`)
		Solo.move_safely(stand, function()
			Route.walk(stand, 0, 15000)
		end)
		Read.set_me(game_state().position)
		if not Geo.same(snap.me, stand) then
			return
		end
	end
	r.multi_at = stand
	for i, fire in ipairs(fires) do
		if Island.watch() then
			break
		end
		local following = fires[i + 1]
		Hazard.douse(fire, if following then Geo.to_tile(following) else nil)
	end
	r.multi_at = nil
end

function Solo.dodge()
	local target = S.dodging_to
	local flag = Player.destination()
	if target and flag and Geo.distance(flag, target) <= 1 and Hazard.hazard_at(flag, 1) == nil then
		Route.sleep_watching(100, flag)
		return
	end
	local hazard = plan.hazard
	local a = S.activity
	Log.log(
		"Tempoross",
		"Dodging the",
		if hazard then Hazard.describe_hazard(hazard) else "hazard",
		if a then `({a.kind})` else ""
	)
	Doing.clear_activity()
	if target == nil then
		Log.log("Tempoross", "   No safe tile nearby")
		Route.sleep_watching(Random.int(300, 500))
		return
	end
	local t = target :: Tile
	Log.log("Tempoross", "   Stepping away to", t.x, t.y)
	Route.click(t)
	Route.sleep_watching(Random.int(600, 900), nil, function(): boolean
		return Hazard.hazard_at(t) ~= nil or Geo.same(snap.me, t)
	end)
end

function Solo.walk_item()
	local item = plan.item :: Core.IslandItem
	local stand = item.stand or item.tiles[1]
	if Geo.distance(snap.me, stand) <= 1 then
		Route.sleep_watching(Random.int(200, 400))
		return
	end
	if item.kind == "look" then
		Log.log("Tempoross", `   Looking over the box toward {stand.x},{stand.y}`)
	end
	Solo.walk_to(stand, if item.kind == "north" then CONST.SOLO.P5_NORTH_RANGE - 1 else 1)
end

function Solo.load_scored()
	local item = plan.crate :: Core.IslandItem
	if Task.surge_waited() then
		return
	end
	local crate = item.npc
	if crate == nil then
		local tile = item.tiles[1]
		Solo.move_safely(Route.route_end(tile), function()
			Route.walk_near(tile, 1)
		end)
		return
	end
	local npc = crate :: Npc
	if item.between then
		Log.log("Tempoross", `   Fire can jump in front of the crate, clicking the far crate at {npc.x},{npc.y}`)
		Task.fill_crate(npc)
		return
	end
	Solo.move_safely(Route.npc_stand(npc), function()
		Task.fill_crate(npc)
	end)
end

function Solo.recent_fish(): number
	local r = S.solo
	local most = r.last_fish
	for _, seen in ipairs(r.fish_seen) do
		most = math.max(most, seen.fish)
	end
	return most
end

function Solo.settle_burn()
	local check = events.burn_check
	if check == nil or time() - check.at < Ticks.MS then
		return
	end
	events.burn_check = nil
	Read.sync_inventory()
	local lost = math.max(0, check.before - Read.fish_count())
	if lost < CONST.SOLO.P4_BURN_KEEP_GOING_FISH then
		Log.log("Tempoross", `   Burned in part 4 and lost {lost} fish, carrying on`)
		return
	end
	Log.log("Tempoross", `   Burned in part 4 and lost {lost} fish`)
	events.burned = true
end

function Solo.p4_loaded(): number
	local r = S.solo
	return r.loaded - r.p4_load_base
end

function Solo.p4_target(): number
	return CONST.SOLO.THIRD_BATCH - Solo.p4_loaded()
end

function Solo.forfeit()
	if not S.forfeiting then
		Log.log("Tempoross", `{Island.forfeit_reason() or "Leaving"}, forfeiting`)
	end
	S.forfeiting = true
	S.leave_by_crew = true
	Game.leave()
end

function Solo.ship_fires_left(): boolean
	local r = S.solo
	return r.p4_stage ~= nil
		and r.p4_stage ~= "fish"
		and r.p5_stage == nil
		and Read.item_count(Items.WATER) > 0
		and #Solo.side_fires() > 0
end

function Solo.cook_safely()
	Solo.move_safely(Route.loc_stand((S.side :: Side).shrine), function()
		Task.cook()
	end)
end

function Solo.start_part_five()
	local r = S.solo
	local north = Ship.other_side()
	if north == nil then
		Log.log("Tempoross", "   Couldn't find the north side of the island")
		r.stop_reason = "stop"
		return
	end
	r.p5_north = north
	r.p5_shrine = Geo.to_tile((S.side :: Side).shrine)
	r.p5_stage = "buckets"
	r.p3_buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), snap.me)
	r.p5_box = Solo.home_box(north)
	local limits: { string } = {}
	local bases = CONST.SOLO.P5_LEAVE_INTENSITY :: { [string]: number }
	local jitter = CONST.SOLO.P5_LEAVE_JITTER
	for _, name in ipairs(CONST.SOLO.P5_ROUTE) do
		r.p5_limits[name] = bases[name] + Random.int(-jitter, jitter + 1)
		table.insert(limits, `{name} {r.p5_limits[name]}%`)
	end
	Doing.clear_activity()
	Log.log("Tempoross", "Part 5: filling the inventory with buckets")
	Log.log("Tempoross", `   Leaving each box at: {table.concat(limits, ", ")}`)
	Solo.advance_five()
end

function Solo.taking_buckets(): boolean
	Read.sync_inventory()
	if snap.free > 0 and S.solo.p3_buckets ~= nil then
		return true
	end
	S.solo.p3_humidify = Read.item_count(Items.BUCKET) > 0
	return false
end

function Solo.has_water(): boolean
	return Read.item_count(Items.WATER) > 0 or Read.item_count(Items.BUCKET) > 0
end

function Solo.p5_north_target(): Tile
	return Route.route_end(Geo.to_tile((S.solo.p5_north :: Side).totem))
end

function Solo.p5_north_reached(): boolean
	return Geo.distance(snap.me, Solo.p5_north_target()) <= CONST.SOLO.P5_NORTH_RANGE
end

function Solo.p5_storm_after(target: Tile, extra_ms: number): number
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	local seconds = (Route.walk_steps(target) * CONST.SPOT_COST.tile_ms + extra_ms) / 1000
	return intensity + seconds * CONST.SOLO.P5_INTENSITY_PER_S
end

function Solo.p5_rush_north(): boolean
	return not Solo.has_water()
		or Solo.p5_storm_after(Solo.p5_north_target(), CONST.SOLO.P5_FISHING_MS) >= CONST.SOLO.P5_FISH_BY_INTENSITY
end

function Solo.p5_time_to_load(): boolean
	return Solo.p5_storm_after(Solo.crate_target(), 0) >= CONST.SOLO.P5_LOAD_BY_INTENSITY
end

function Solo.p5_fires(): { Npc }
	return Solo.small_clusters(Solo.p5_candidates(), CONST.SOLO.P5_MAX_CLUSTER)
end

function Solo.small_clusters(fires: { Npc }, max_size: number): { Npc }
	local kept: { Npc } = {}
	for _, cluster in ipairs(Hazard.fire_clusters(fires)) do
		if #cluster <= max_size then
			table.move(cluster, 1, #cluster, #kept + 1, kept)
		end
	end
	return kept
end

function Solo.p5_candidates(): { Npc }
	local r = S.solo
	if r.p5_stage == "sweep" or (Read.hud_percent(HUD.INTENSITY) or 0) < CONST.SOLO.P5_ALL_FIRES_BELOW then
		return Hazard.fire_npcs()
	end
	local route = Route.route_to(Solo.p5_north_target()) or {}
	return Solo.area_fires(function(fire: Npc): boolean
		if Solo.fire_in(r.p3_box, fire) or Solo.fire_in(r.p5_box, fire) then
			return true
		end
		local shrine = r.p5_shrine
		if shrine and Hazard.fire_distance(fire, shrine) <= CONST.SOLO.P5_SHRINE_RANGE then
			return true
		end
		for _, t in ipairs(route) do
			if Hazard.fire_distance(fire, t) <= CONST.SOLO.P5_CORRIDOR then
				return true
			end
		end
		return false
	end)
end

function Solo.box_samples(box: Box): { Tile }
	local step = CONST.SOLO.P5_LOOK_STEP
	local samples: { Tile } = {}
	local x = box.min_x
	while true do
		local y = box.min_y
		while true do
			table.insert(samples, { x = x, y = y })
			if y >= box.max_y then
				break
			end
			y = math.min(y + step, box.max_y)
		end
		if x >= box.max_x then
			break
		end
		x = math.min(x + step, box.max_x)
	end
	return samples
end

function Solo.p5_current(): string?
	return CONST.SOLO.P5_ROUTE[S.solo.p5_route_at]
end

function Solo.p5_unseen(name: string): { Tile }
	local r = S.solo
	local looked = r.p5_looked[name]
	if looked == nil then
		looked = {}
		for _, t in ipairs(Solo.box_samples((Solo.island_boxes() :: { [string]: Box })[name])) do
			looked[`{t.x},{t.y}`] = false
		end
		r.p5_looked[name] = looked
	end
	local unseen: { Tile } = {}
	for key, seen in pairs(looked) do
		if not seen then
			local x, y = string.match(key, "(-?%d+),(-?%d+)")
			table.insert(unseen, { x = tonumber(x) :: number, y = tonumber(y) :: number })
		end
	end
	return unseen
end

function Solo.p5_remember()
	local r = S.solo
	local boxes = Solo.island_boxes()
	if boxes == nil then
		return
	end
	local visible: { [string]: boolean } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		local key = `{fire.x},{fire.y}`
		visible[key] = true
		for _, name in ipairs(CONST.SOLO.P5_ROUTE) do
			if Solo.fire_in(boxes[name], fire) then
				r.p5_seen[key] = { x = fire.x, y = fire.y }
				break
			end
		end
	end
	for key, t in pairs(r.p5_seen) do
		if
			not visible[key]
			and Hazard.fire_distance(Hazard.fire_at(t), snap.me) <= CONST.SOLO.FIRE_FORGET_RANGE
			and Walker.on_screen(t)
		then
			r.p5_seen[key] = nil
		end
	end
	local name = Solo.p5_current()
	if name == nil then
		return
	end
	local looked = r.p5_looked[name]
	if looked == nil then
		Solo.p5_unseen(name)
		looked = r.p5_looked[name]
	end
	for _, t in ipairs(Solo.p5_unseen(name)) do
		if Geo.distance(t, snap.me) <= CONST.SOLO.P5_LOOK_NEAR or Walker.on_screen(t) then
			(looked :: { [string]: boolean })[`{t.x},{t.y}`] = true
		end
	end
end

function Solo.p5_box_targets(name: string): { Tile }
	local box = (Solo.island_boxes() :: { [string]: Box })[name]
	local targets: { Tile } = {}
	for _, t in pairs(S.solo.p5_seen) do
		if Solo.fire_in(box, Hazard.fire_at(t)) then
			table.insert(targets, t)
		end
	end
	return targets
end

function Solo.p5_route_box(): (string?, { Tile }, { Tile })
	local r = S.solo
	if Solo.island_boxes() == nil then
		return nil, {}, {}
	end
	while Solo.p5_current() ~= nil do
		local name = Solo.p5_current() :: string
		local intensity = Read.hud_percent(HUD.INTENSITY) or 0
		local targets = Solo.p5_box_targets(name)
		if intensity >= r.p5_limits[name] then
			Log.log("Tempoross", `   Leaving {name} at {intensity}% storm with {#targets} fires left`)
			r.p5_route_at += 1
		else
			local unseen = Solo.p5_unseen(name)
			if #targets > 0 or #unseen > 0 then
				return name, targets, unseen
			end
			Log.log("Tempoross", `   {name} clear at {intensity}% storm`)
			r.p5_route_at += 1
		end
	end
	return nil, {}, {}
end

function Solo.p5_clearing_route(): boolean
	return not Solo.p5_rush_north() and Solo.p5_route_box() ~= nil
end

function Solo.take_buckets()
	local r = S.solo
	local loc = r.p3_buckets :: Loc
	local menu_ready = false
	Read.sync_inventory()
	local takes = math.ceil(snap.free / CONST.SOLO.TAKE_BUCKETS_PER_CLICK)
	Log.log("Tempoross", `   {snap.free} slots free, taking buckets {takes} time{if takes == 1 then "" else "s"}`)
	for take = 1, takes do
		Read.sync_inventory()
		if snap.free == 0 then
			return
		end
		local before = snap.free
		local taken = if menu_ready and Minimenu.is_open()
			then Objects.interact(loc, { "Take-10" }, false)
			else Task.use_loc(loc, { "Take-10" })
		if not taken then
			return
		end
		menu_ready = take < takes
			and before > CONST.SOLO.TAKE_BUCKETS_PER_CLICK
			and not Biometrics.random_boolean(CONST.SOLO.TAKE_BUCKETS_SLOW_CHANCE)
			and Objects.hover(loc)
			and Minimenu.open()
		Route.sleep_watching(CONST.SOLO.TAKE_BUCKETS_WAIT_MS, nil, function(): boolean
			Read.sync_inventory()
			return snap.free < before
		end)
		Log.log("Tempoross", `   Took buckets, {snap.free} slots free`)
	end
end

function Solo.humidify_settling(): boolean
	local r = S.solo
	local cast = r.humidify_cast
	if cast == nil then
		return false
	end
	Read.sync_inventory()
	if Read.item_count(Items.WATER) > cast.water or time() - cast.at > CONST.SOLO.HUMIDIFY_SETTLE_MS then
		r.humidify_cast = nil
		return false
	end
	return true
end

function Solo.drop_buckets(count: number, allow_water: boolean)
	if Solo.humidify_settling() then
		return
	end
	local slots: { number } = {}
	for _, wanted in ipairs(if allow_water then { Items.BUCKET, Items.WATER } else { Items.BUCKET }) do
		local held: { number } = {}
		for _, slot in ipairs(item_container(Inventory.CONTAINER) or {}) do
			if slot.id == wanted then
				table.insert(held, slot.slot)
			end
		end
		if #held > 0 then
			for _, slot in ipairs((Inventory.pattern(held))) do
				if #slots < count then
					table.insert(slots, slot)
				end
			end
		end
	end
	if #slots == 0 then
		return
	end
	Log.log("Tempoross", `   Dropping {#slots} bucket{if #slots == 1 then "" else "s"}`)
	Inventory.shift_drop_slots((Inventory.pattern(slots)))
end

function Solo.walk_to(target: Tile, near: number)
	Solo.move_safely(target, function()
		Route.walk(target, near, 30000)
	end)
end

function Solo.in_box(fire: Npc): boolean
	return Solo.fire_in(S.solo.p3_box, fire)
end

function Solo.area_fires(accept: (Npc) -> boolean): { Npc }
	local fires: { Npc } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		if accept(fire) then
			table.insert(fires, fire)
		end
	end
	return fires
end

function Solo.flipped_box(
	origin: Tile,
	b: { west: number, east: number, south: number, north: number },
	flip: number
): Box
	local xa, xb = origin.x + flip * b.west, origin.x + flip * b.east
	local ya, yb = origin.y + flip * b.south, origin.y + flip * b.north
	return { min_x = math.min(xa, xb), max_x = math.max(xa, xb), min_y = math.min(ya, yb), max_y = math.max(ya, yb) }
end

function Solo.island_boxes(): { [string]: Box }?
	local r = S.solo
	if r.island_boxes then
		return r.island_boxes
	end
	local here = S.side
	if here == nil then
		return nil
	end
	local west = if here.name == "west" then here else Ship.other_side()
	if west == nil then
		return nil
	end
	local flip = if west.totem.y > west.mast.y then 1 else -1
	local boxes: { [string]: Box } = {}
	local offsets =
		CONST.SOLO.ISLAND_BOXES :: { [string]: { west: number, east: number, south: number, north: number } }
	for name, b in offsets do
		boxes[name] = Solo.flipped_box(Geo.to_tile(west.mast), b, flip)
	end
	r.island_boxes = boxes
	return boxes
end

function Solo.home_box(side: Side): Box
	return Solo.flipped_box(side.mast, CONST.SOLO.NORTH_BOX, if side.totem.y > side.mast.y then 1 else -1)
end

function Solo.fire_in(box: Box?, fire: Npc): boolean
	if box == nil then
		return false
	end
	for _, t in ipairs(Hazard.fire_tiles(fire)) do
		if t.x >= box.min_x and t.x <= box.max_x and t.y >= box.min_y and t.y <= box.max_y then
			return true
		end
	end
	return false
end

function Solo.our_side_fire(fire: Npc): boolean
	local r = S.solo
	return not r.p2_skip[`{fire.x},{fire.y}`] and Solo.fire_in(r.p2_box, fire)
end

function Solo.side_fires(): { Npc }
	return Solo.area_fires(Solo.our_side_fire)
end

function Solo.beach_target(): (Npc?, Npc?)
	return Solo.cluster_target(Solo.area_fires(Solo.in_box))
end

function Solo.cluster_target(fires: { Npc }): (Npc?, Npc?)
	local best: { Npc }, target: Npc?, best_score = {}, nil, math.huge
	for _, cluster in ipairs(Hazard.fire_clusters(fires)) do
		local nearest, nearest_steps = cluster[1], math.huge
		for _, fire in ipairs(cluster) do
			local steps = Route.walk_steps(fire)
			if steps < nearest_steps then
				nearest, nearest_steps = fire, steps
			end
		end
		local score = nearest_steps + CONST.SOLO.CLUSTER_WEIGHT * #cluster
		if score < best_score then
			best, target, best_score = cluster, nearest, score
		end
	end
	if target == nil then
		return nil, nil
	end
	local after: Npc? = nil
	for _, fire in ipairs(best) do
		if
			fire.index ~= target.index and (after == nil or Geo.distance(fire, target) < Geo.distance(after, target))
		then
			after = fire
		end
	end
	return target, after
end

function Solo.travel_goal(): Tile?
	local r = S.solo
	if r.p5_stage ~= nil then
		return if r.p5_stage == "north" then Solo.p5_north_target() else nil
	end
	if r.p4_stage == "ship" or r.p4_stage == "rush" then
		return Solo.crate_target()
	end
	if r.p3_stage == "cross" then
		return r.p3_pier
	end
	if r.p3_stage ~= nil then
		return nil
	end
	if r.p2_loading then
		return Solo.crate_target()
	end
	if r.p2_clear ~= "done" then
		local spot = Task.best_spot(false, nil, true)
		return if spot then Route.npc_stand(spot) else nil
	end
	return nil
end

function Solo.current_box(): (Box?, { Box })
	local boxes = Solo.island_boxes()
	if boxes == nil then
		return nil, {}
	end
	local r = S.solo
	local current = Solo.p5_current()
	if r.p5_stage ~= nil and current ~= nil then
		local left: { Box } = {}
		for i = 1, r.p5_route_at - 1 do
			table.insert(left, boxes[CONST.SOLO.P5_ROUTE[i]])
		end
		return boxes[current], left
	end
	if r.p3_stage == "clear" and r.p3_box ~= nil then
		return r.p3_box, {}
	end
	local me = snap.me
	for _, box: Box in boxes :: { [string]: Box } do
		if me.x >= box.min_x and me.x <= box.max_x and me.y >= box.min_y and me.y <= box.max_y then
			return box, {}
		end
	end
	return nil, {}
end

function Solo.corner(quad: Geometry.Quad, name: string): Point
	if name == "top" then
		return quad.top
	elseif name == "right" then
		return quad.right
	elseif name == "bottom" then
		return quad.bottom
	end
	return quad.left
end

function Solo.box_segments(box: Box): { { Point } }
	local edges: { { tile: Tile, from: string, to: string } } = {}
	for x = box.min_x, box.max_x do
		table.insert(edges, { tile = { x = x, y = box.min_y }, from = "top", to = "left" })
	end
	for y = box.min_y, box.max_y do
		table.insert(edges, { tile = { x = box.max_x, y = y }, from = "left", to = "bottom" })
	end
	for x = box.max_x, box.min_x, -1 do
		table.insert(edges, { tile = { x = x, y = box.max_y }, from = "bottom", to = "right" })
	end
	for y = box.max_y, box.min_y, -1 do
		table.insert(edges, { tile = { x = box.min_x, y = y }, from = "right", to = "top" })
	end
	local segments: { { Point } } = {}
	local first: Point? = nil
	local last: Point? = nil
	local whole = true
	local edge_tiles: { Tile } = {}
	for i, edge in ipairs(edges) do
		edge_tiles[i] = edge.tile
	end
	local quads = Projection.tiles(edge_tiles)
	for i, edge in ipairs(edges) do
		local quad = quads[i]
		if quad == nil then
			last = nil
			whole = false
		else
			local a, b = Solo.corner(quad, edge.from), Solo.corner(quad, edge.to)
			if last then
				table.insert(segments, { last :: Point, a })
			end
			table.insert(segments, { a, b })
			first = first or a
			last = b
		end
	end
	if whole and first and last then
		table.insert(segments, { last :: Point, first :: Point })
	end
	return segments
end

function Solo.show_boxes()
	local r = S.solo
	local boxes = Solo.island_boxes()
	local wanted = r.p5_stage ~= nil or (r.p3_stage ~= nil and r.p4_stage == nil)
	if not DebugDraw.on() or boxes == nil or not wanted then
		if S.boxes_shown ~= "" then
			S.boxes_shown = ""
			DebugDraw.set("island_boxes", nil)
		end
		return
	end
	local current, left = Solo.current_box()
	local key = `{if current then `{current.min_x},{current.min_y}` else "none"}:{#left}`
	if key == S.boxes_shown then
		return
	end
	S.boxes_shown = key
	DebugDraw.set("island_boxes", function()
		for _, box: Box in boxes :: { [string]: Box } do
			local color = if box == current
				then CONST.CURRENT_BOX_COLOR
				elseif table.find(left, box) then CONST.LEFT_BOX_COLOR
				else CONST.BOX_COLOR
			Draw.lines(Solo.box_segments(box), color, CONST.BOX_DEBUG_WIDTH)
		end
	end)
end

function Solo.covers(fire: Npc, things: { Tile }, range: number): boolean
	for _, t in ipairs(things) do
		if Hazard.fire_distance(fire, t) <= range then
			return true
		end
	end
	return false
end

function Solo.burning_tiles(): { [string]: { Npc } }
	local covered: { [string]: { Npc } } = {}
	for _, fire in ipairs(Hazard.fire_npcs()) do
		for _, t in ipairs(Hazard.fire_tiles(fire)) do
			local key = `{t.x},{t.y}`
			local list = covered[key]
			if list == nil then
				list = {}
				covered[key] = list
			end
			table.insert(list, fire)
		end
	end
	return covered
end

function Solo.shared_stand(a: Npc, b: Npc, covered: { [string]: { Npc } }): boolean
	for _, t in ipairs(Route.beside(Hazard.fire_tiles(a))) do
		if Hazard.beside_fire(b, t) and covered[`{t.x},{t.y}`] == nil then
			return true
		end
	end
	return false
end

function Solo.crosses_fire(route: { Tile }, fire: Npc, covered: { [string]: { Npc } }): boolean
	for i = 2, #route do
		local t = route[i]
		for _, other in ipairs(covered[`{t.x},{t.y}`] or {}) do
			if other.index ~= fire.index then
				return true
			end
		end
	end
	return false
end

function Solo.fire_values(fires: { Npc }, wanted: { [number]: boolean }?): { [number]: number }
	local w = CONST.SOLO.FIRE_VALUE
	local covered = Solo.burning_tiles()
	local size: { [number]: number } = {}
	for _, cluster in ipairs(Hazard.fire_clusters(fires)) do
		for _, f in ipairs(cluster) do
			size[f.index] = #cluster
		end
	end
	local spots: { Tile } = {}
	local pools: { Tile } = {}
	for _, n in ipairs(snap.npcs) do
		if n.id == CONST.SPIRIT_POOL or n.id == CONST.INACTIVE_POOL then
			table.insert(pools, n)
		elseif S.side ~= nil and Task.is_spot(n) then
			table.insert(spots, n)
		end
	end
	local crates: { Tile } = if S.side ~= nil then Task.crates() else {}
	local shrines: { Tile } = if S.side ~= nil then { (S.side :: Side).shrine } else {}
	local goal = Solo.travel_goal()
	local path = if goal then Route.route_to(goal) or {} else {}
	local function flag(on: boolean): number
		return if on then 1 else 0
	end
	local base_weight = w.near + w.small + w.spot + w.shrine + w.crate + w.pool
	local base: { [number]: number } = {}
	local crossing: { [number]: boolean } = {}
	local function base_of(fire: Npc): number
		local known = base[fire.index]
		if known ~= nil then
			return known
		end
		local route = Route.route_to(fire)
		local steps = if route then #route - 1 else math.huge
		local raw = w.near * math.max(0, 1 - steps / w.far_steps)
			+ w.small / (size[fire.index] or 1)
			+ w.spot * flag(Solo.covers(fire, spots, w.spot_range))
			+ w.shrine * flag(Solo.covers(fire, shrines, w.shrine_range))
			+ w.crate * flag(Solo.covers(fire, crates, w.crate_range))
			+ w.pool * flag(Solo.covers(fire, pools, w.pool_range))
		base[fire.index] = raw / base_weight
		crossing[fire.index] = route == nil or Solo.crosses_fire(route, fire, covered)
		return raw / base_weight
	end
	local box, left = Solo.current_box()
	local values: { [number]: number } = {}
	for _, fire in ipairs(fires) do
		if wanted ~= nil and not wanted[fire.index] then
			values[fire.index] = 0
			continue
		end
		local own = base_of(fire)
		local partner = 0
		for _, other in ipairs(fires) do
			if
				other.index ~= fire.index
				and Geo.distance(fire, other) <= w.pair_range
				and Solo.shared_stand(fire, other, covered)
			then
				partner = math.max(partner, base_of(other))
			end
		end
		local value = (own * base_weight + w.pair * partner) / (base_weight + w.pair)
		if Solo.covers(fire, path, 0) then
			value += w.path
		end
		if crossing[fire.index] then
			value *= w.crossing
		end
		if box ~= nil and not Solo.fire_in(box, fire) then
			value *= w.outside
		end
		for _, gone in ipairs(left) do
			if Solo.fire_in(gone, fire) and not Solo.fire_in(box, fire) then
				value = 0
			end
		end
		values[fire.index] = math.clamp(value, 0, 1)
	end
	return values
end

function Solo.stop_here()
	local r = S.solo
	if r.p4_stage then
		Log.log("Tempoross", "End of part 4, stopping here on the island")
		S.finished = true
		return
	end
	local part = if r.p3_stage then 3 else 2
	Log.log("Tempoross", `End of part {part}, stopping here and forfeiting`)
	S.leave_by_crew = true
	Game.leave()
	S.finished = true
end

function Solo.track_pools()
	local r = S.solo
	local vulnerable = Hazard.tempoross_vulnerable()
	if r.vulnerable and not vulnerable then
		r.pools += 1
		Log.log(
			"Tempoross",
			`Tempoross resurfaced at {Read.hud_percent(HUD.ENERGY) or "?"}% energy, essence {Read.hud_percent(
				HUD.ESSENCE
			) or "?"}%`
		)
	elseif vulnerable and not r.vulnerable then
		Log.log("Tempoross", "Tempoross is vulnerable")
	end
	r.vulnerable = vulnerable
end

function Solo.walk_to_load()
	Solo.click_ship_hover()
	Solo.load_exact(CONST.SOLO.FIRST_BATCH)
end

function Solo.fishing_done(target: number, can_cook: boolean): boolean
	return Read.fish_count() >= target and (not can_cook or Read.item_count(Items.RAW_FISH) == 0)
end

function Solo.track_island(): State?
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
	if Chat.wave_coming() and not snap.tethered and Read.has_rope() then
		if time() - (events.wave_warning_at :: number) >= CONST.SOLO.TETHER_WARNING_MS then
			events.wave_warning_at = nil
		end
	end
	local stray = snap.tethered
		and events.wave_warning_at == nil
		and events.wave_hit_at == nil
		and not Doing.is_doing("tether")
	if stray then
		S.stray_since = S.stray_since or time()
	else
		S.stray_since = nil
	end
	local hit = events.wave_hit_at
	local tied = snap.tethered or Doing.is_doing("tether")
	if hit and not tied and not (snap.busy and time() - hit < CONST.SOLO.WAVE_BUSY_MS) then
		Log.log(
			"Tempoross",
			string.format(
				"   Free again %.1f s after the wave%s",
				(time() - hit) / 1000,
				if snap.busy then " (still busy)" else ""
			)
		)
		events.wave_hit_at = nil
	end
	local loading_first = S.solo.p2_loading and Read.fish_count() > 0
	local attack = Hazard.tempoross_vulnerable() and not loading_first and not Solo.ship_fires_left()
	if Doing.is_doing("attack") and not attack then
		Doing.clear_activity()
	end
	local cast = S.solo.humidify_cast
	if cast and S.solo.p3_humidify then
		Read.sync_inventory()
		if Read.item_count(Items.WATER) > cast.water then
			S.solo.humidify_cast = nil
			S.solo.p3_humidify = false
		end
	end
	if S.solo.p3_humidify and Read.item_count(Items.BUCKET) == 0 then
		S.solo.p3_humidify = false
	end
	return nil
end

function Solo.advance_one()
	local r = S.solo
	if r.opened then
		return
	end
	local energy = Read.hud_percent(HUD.ENERGY) or 0
	local count = Read.fish_count()
	local target = CONST.SOLO.FIRST_BATCH
	if not (energy < CONST.SOLO.OPENING_ENERGY and count < CONST.SOLO.OPENING_FISH and count < target) then
		r.opened = true
		Doing.clear_activity()
		Log.log("Tempoross", `Energy {energy}%, cooking {count} fish and waiting for a double spot`)
	end
end

function Solo.advance_two()
	local r = S.solo
	if r.pools >= 1 then
		Solo.advance_three()
		return
	end
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	if not r.p2_loading and count > 0 and intensity >= CONST.SOLO.LEAVE_INTENSITY then
		r.p2_loading = true
		Doing.clear_activity()
		Log.log("Tempoross", `Intensity {intensity}%, loading the {count} fish we have ({raw} raw)`)
	end
	if not r.p2_loading and r.p2_clear ~= "done" then
		if r.p2_clear == nil then
			local b = Solo.home_box(S.side :: Side)
			r.p2_box = b
			Log.log(
				"Tempoross",
				`Part 2: putting out every fire in x {b.min_x}..{b.max_x} y {b.min_y}..{b.max_y} ({#Solo.side_fires()})`
			)
		end
		if #Solo.side_fires() > 0 and Read.item_count(Items.WATER) > 0 then
			r.p2_clear = "side"
		else
			r.p2_clear = "done"
			Log.log("Tempoross", "   Our side is clear, fishing")
		end
	end
	if not r.p2_loading and r.p2_clear == "done" and Solo.fishing_done(CONST.SOLO.SECOND_BATCH, true) then
		r.p2_loading = true
		Log.log("Tempoross", `{count} cooked fish, loading them all`)
	end
end

function Solo.advance_three()
	local r = S.solo
	if r.p3_stage == nil then
		r.p3_stage = "buckets"
		r.p3_buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), snap.me)
		Doing.clear_activity()
		Log.log("Tempoross", "Part 3: filling the inventory with buckets")
	end
	if r.p3_stage == "buckets" then
		if Solo.taking_buckets() then
			return
		end
		r.p3_stage = "humidify"
	end
	if r.p3_stage == "humidify" then
		local side = Ship.other_side()
		if side == nil then
			Log.log("Tempoross", "   Couldn't find the other side of the island")
			r.stop_reason = "stop"
			return
		end
		S.side = side
		local buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), side.totem)
		local pier = Route.route_end(Geo.to_tile(buckets or side.totem))
		r.p3_pier = pier
		local boxes = Solo.island_boxes()
		r.p3_box = if boxes then boxes.south_beach else nil
		r.p3_stage = "cross"
		Log.log("Tempoross", `   Crossing to the {side.name} side, pier at {pier.x},{pier.y}`)
	end
	if r.p3_stage == "cross" then
		if Geo.distance(snap.me, r.p3_pier :: Tile) > 1 then
			return
		end
		r.p3_stage = "clear"
		Log.log("Tempoross", "   On the other side, clearing the pier and the beach")
	end
	if r.p3_stage == "clear" then
		local intensity = Read.hud_percent(HUD.INTENSITY) or 0
		local why = if intensity >= CONST.SOLO.P3_STOP_INTENSITY
			then `storm at {intensity}%, leaving {#Solo.area_fires(Solo.in_box)} fires on the beach`
			elseif Read.item_count(Items.WATER) == 0 then "out of water"
			elseif Solo.beach_target() == nil then "beach clear"
			else nil
		if why == nil then
			return
		end
		r.p3_stage = "done"
		r.p4_stage = "fish"
		r.p4_load_base = r.loaded
		Log.log("Tempoross", `Part 4: {why}, fishing {CONST.SOLO.THIRD_BATCH} fish`)
	end
	Solo.advance_four()
end

function Solo.advance_four()
	local r = S.solo
	if r.p5_stage ~= nil then
		Solo.advance_five()
		return
	end
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	if r.p4_stage == "fish" and intensity >= CONST.SOLO.LEAVE_INTENSITY then
		local count = Read.fish_count()
		if count >= Solo.p4_target() then
			r.p4_stage = "rush"
			r.p2_box = Solo.home_box(S.side :: Side)
			r.p2_skip = {}
			Log.log("Tempoross", `   Storm at {intensity}%, loading the {count} fish now`)
		elseif r.stop_reason == nil then
			r.stop_reason = `Storm at {intensity}% with {count} of {Solo.p4_target()} fish`
		end
		return
	end
	if r.p4_stage == "fish" then
		if not Solo.fishing_done(Solo.p4_target(), not r.p4_raw) then
			return
		end
		r.p4_stage = "ship"
		r.p2_box = Solo.home_box(S.side :: Side)
		r.p2_skip = {}
		Log.log("Tempoross", `   {Read.fish_count()} fish, clearing the ship and loading them`)
	end
	local essence = Read.hud_percent(HUD.ESSENCE)
	if r.pools >= 2 or (essence ~= nil and essence <= CONST.SOLO.P4_STOP_ESSENCE) then
		Solo.start_part_five()
		return
	end
	local count = Read.fish_count()
	local storm = intensity >= CONST.SOLO.LEAVE_INTENSITY
	if
		r.p4_stage == "ship"
		and not storm
		and count < Solo.p4_target()
		and not Doing.is_doing("load")
		and not Solo.at_crate()
		and time() - r.left_crate_at >= CONST.SOLO.STEP_OFF_COUNT_MS
	then
		r.p4_stage = "fish"
		r.p4_raw = true
		Doing.clear_activity()
		Log.log(
			"Tempoross",
			`   {Solo.p4_loaded()} loaded and {count} fish left, fishing {Solo.p4_target() - count} more to load raw`
		)
		Solo.advance_four()
		return
	end
	if storm and count > 0 and r.p4_stage ~= "rush" then
		r.p4_stage = "rush"
		Log.log("Tempoross", `   Storm at {intensity}%, loading every fish before the fires`)
	end
end

function Solo.advance_five()
	local r = S.solo
	if r.p5_stage == "buckets" then
		if Solo.taking_buckets() then
			return
		end
		r.p5_stage = "humidify"
	end
	if r.p5_stage == "humidify" then
		Solo.p5_remember()
		if r.p3_humidify and Read.item_count(Items.BUCKET) > 0 then
			return
		end
		r.p5_stage = "north"
		Log.log("Tempoross", "   Putting out fires on the way north")
	end
	if r.p5_stage == "north" then
		Solo.p5_remember()
		if Solo.p5_clearing_route() or not Solo.p5_north_reached() then
			return
		end
		r.p5_stage = "fish"
		S.side = r.p5_north
		Doing.clear_activity()
		Log.log(
			"Tempoross",
			`   North at {Read.hud_percent(HUD.INTENSITY) or "?"}% storm, getting {CONST.SOLO.P5_FISH} fish`
		)
	end
	if r.p5_stage == "fish" then
		Read.sync_inventory()
		local count = Read.fish_count()
		if count < CONST.SOLO.P5_FISH then
			return
		end
		Doing.clear_activity()
		r.p5_stage = "sweep"
		Log.log("Tempoross", `   {count} fish, putting out fires until the storm reaches 92%`)
	end
	if r.p5_stage == "sweep" then
		local why = if Solo.p5_time_to_load()
			then "the storm is close to 92%"
			elseif not Solo.has_water() then "no water left"
			elseif #Solo.p5_fires() == 0 then "no fires left"
			else nil
		if why == nil then
			return
		end
		r.p5_stage = "load"
		Log.log("Tempoross", `   Loading the fish at {Read.hud_percent(HUD.INTENSITY) or "?"}% storm: {why}`)
	end
	if r.p5_stage == "load" then
		if Read.fish_count() > 0 then
			return
		end
		r.p5_stage = "pool"
		Log.log("Tempoross", "   Off to the north spirit pool")
	end
end

local spots_seen: { [string]: { tile: Tile, side: string } } = {}

function Solo.record_spots()
	local side = S.side
	if side == nil then
		return
	end
	for _, n in ipairs(snap.npcs) do
		local key = `{n.x},{n.y}`
		if spots_seen[key] == nil and (CONST.SINGLE_SPOTS[n.id] or n.id == CONST.DOUBLE_SPOT) then
			local owner = side
			local other = Ship.other_side()
			if other and Geo.distance(n, other.totem) < Geo.distance(n, side.totem) then
				owner = other
			end
			local totem = Geo.to_tile(owner.totem)
			spots_seen[key] = { tile = Geo.to_tile(n), side = owner.name }
			Log.log(
				"Tempoross",
				`   Fishing spot tile {key}: {n.x - totem.x},{n.y - totem.y} from the {owner.name} totem at {totem.x},{totem.y}`
			)
		end
	end
end

function Solo.spot_tiles(side: Side): { Tile }
	local tiles: { Tile } = {}
	for _, seen in pairs(spots_seen) do
		if seen.side == side.name then
			table.insert(tiles, seen.tile)
		end
	end
	return tiles
end

function Solo.bookkeep(): State?
	Solo.track_pools()
	Solo.record_spots()
	Solo.settle_burn()
	local early = Solo.track_island()
	if early then
		return early
	end
	local r = S.solo
	Solo.track_loaded()
	if r.loaded == CONST.SOLO.FIRST_BATCH or r.p2_loading then
		Solo.advance_two()
	elseif not r.loading then
		Solo.advance_one()
	end
	return nil
end

function Solo.next_fire(items: { Core.IslandItem }, after: number): Tile?
	for i = after + 1, #items do
		local item = items[i]
		if item.kind == "fire" and item.score > 0 and item.npc then
			return Geo.to_tile(item.npc :: Npc)
		end
	end
	return nil
end

function Solo.part_one_spot(item: Core.IslandItem): State
	local r = S.solo
	local a = S.activity
	local fishing = a ~= nil and a.kind == "fish"
	local spot = item.npc :: Npc
	local current = fishing and (a :: Activity).npc ~= nil and ((a :: Activity).npc :: Npc).index == spot.index
	if current or (fishing and item.kind == "single") then
		if not r.opened then
			local energy = Read.hud_percent(HUD.ENERGY) or 0
			local near = energy >= CONST.SOLO.OPENING_ENERGY - CONST.SOLO.PREHOVER_ENERGY
				or Read.fish_count() >= CONST.SOLO.OPENING_FISH - 2
			return if near then "FISHING_TO_COOK" else "CONTINUE"
		end
		return "FISH_TO_TARGET"
	end
	plan.spot = spot
	if item.kind == "double" and r.opened then
		r.doubled = true
		return "FISH_DOUBLE"
	end
	return "FISH"
end

function Solo.spot_state(item: Core.IslandItem): State
	if Island.part() == 1 then
		return Solo.part_one_spot(item)
	end
	local a = S.activity
	local fishing = a ~= nil and a.kind == "fish"
	local spot = item.npc :: Npc
	local current = fishing and (a :: Activity).npc ~= nil and ((a :: Activity).npc :: Npc).index == spot.index
	if current or (fishing and item.kind == "single") then
		return "FISH_TO_TARGET"
	end
	plan.spot = spot
	return "FISH_SAFELY"
end

function Solo.shrine_state(): State
	local r = S.solo
	local count = Read.fish_count()
	local fishing = Doing.is_doing("fish")
	if Island.part() == 1 then
		local target = CONST.SOLO.FIRST_BATCH
		if fishing and count < target then
			return "FISH_TO_TARGET"
		end
		if Doing.is_doing("cook") then
			return if count >= target and events.waves_passed > 0 then "COOKING_TO_LOAD" else "CONTINUE"
		end
		return "COOK"
	end
	local done = count >= r.fishing_target
	if fishing and not done then
		return "FISH_TO_TARGET"
	end
	if Doing.is_doing("cook") then
		return if done then "COOKING_TO_LOAD" else "CONTINUE"
	end
	return "COOK_SAFELY"
end

function Solo.crate_state(item: Core.IslandItem): State
	local r = S.solo
	local a = S.activity
	local npc = item.npc
	if npc and a and a.kind == "load" and a.npc and (a.npc :: Npc).index ~= npc.index then
		local stand = item.stand
		Log.log(
			"Tempoross",
			`   Switching to the crate at {npc.x},{npc.y}, expecting to stand at {if stand
				then `{stand.x},{stand.y}`
				else "?"}`
		)
		plan.crate = item
		return "LOAD_SCORED"
	end
	if Island.part() == 1 then
		if not r.loading then
			r.loading = true
			Log.log("Tempoross", `{Read.fish_count()} cooked fish, going to load {CONST.SOLO.FIRST_BATCH}`)
			return "WALK_TO_LOAD"
		end
		return if r.ship_hover ~= nil then "WALK_TO_LOAD" else "LOAD_EXACT"
	end
	if Doing.is_doing("load") then
		return "LOAD_ALL"
	end
	plan.crate = item
	return "LOAD_SCORED"
end

function Solo.state_for(item: Core.IslandItem, index: number, skipped: { [State]: boolean }): State?
	local r = S.solo
	local kind = item.kind
	if kind == "stunned" then
		return if time() < events.stunned_until then "STUNNED" else "WAIT_FREE"
	elseif kind == "crew" then
		return if r.stop_reason == "stop" then "SOLO_STOP" else "FORFEIT"
	elseif kind == "untether" then
		return if events.must_untether then "UNTETHER_NEARBY" else "UNTETHER_STRAY"
	elseif kind == "tether" then
		return if snap.tethered or Doing.is_doing("tether") then "WAIT_TETHERED" else "TETHER"
	elseif kind == "dodge" then
		plan.hazard = item.npc
		return "DODGE"
	elseif kind == "surge" then
		return "WAIT_SURGE"
	elseif kind == "pool" then
		return "ATTACK"
	elseif kind == "humidify" then
		return "HUMIDIFY"
	elseif kind == "drop" then
		local drop = item.drop :: { count: number, water: boolean }
		plan.drop = drop.count
		plan.drop_water = drop.water
		return "P3_DROP"
	elseif kind == "fire" then
		plan.fire = item.npc :: Npc
		plan.after = Solo.next_fire(S.island or {}, index)
		return "DOUSE_TOP"
	elseif kind == "crate" then
		return Solo.crate_state(item)
	elseif kind == "double" or kind == "single" then
		return Solo.spot_state(item)
	elseif kind == "shrine" then
		return Solo.shrine_state()
	elseif kind == "pier" then
		return "GO_TO_PIER_SOLO"
	elseif kind == "buckets" then
		return "P3_BUCKETS"
	elseif kind == "multi" then
		plan.item = item
		return "MULTI_DOUSE"
	elseif kind == "step" then
		plan.item = item
		return "STEP_OFF"
	elseif kind == "repair" then
		plan.broken = item.loc
		return "REPAIR"
	elseif kind == "look" or kind == "north" then
		plan.item = item
		return "P5_WALK"
	elseif kind == "crossing" then
		plan.item = item
		return "P3_CROSS"
	elseif kind == "pump" then
		if skipped["FILL_BUCKETS"] then
			return nil
		end
		if Doing.is_doing("pump") then
			return "CONTINUE"
		end
		plan.pump = item.loc :: Loc
		return "FILL_BUCKETS"
	elseif kind == "wait" then
		return item.wait or "CONTINUE"
	end
	return nil
end

function Solo.scored_choice(items: { Core.IslandItem }, skipped: { [State]: boolean }): State
	local r = S.solo
	for i, item in ipairs(items) do
		if item.score <= 0 then
			break
		end
		local state = Solo.state_for(item, i, skipped)
		if state then
			r.acting = Island.key(item)
			r.watch_tick = Island.watch_mark()
			r.watch_changed = false
			return state
		end
	end
	return "CONTINUE"
end

function Solo.get_game_state(skipped: { [State]: boolean }): State
	local r = S.solo
	r.loop_round += 1
	r.acting = nil
	local early = Solo.bookkeep()
	if early then
		return early
	end
	return Solo.scored_choice(Island.evaluate(), skipped)
end

return Solo
