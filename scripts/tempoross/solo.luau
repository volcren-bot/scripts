--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local item_container = Host.item_container
local varbit = Host.varbit
local sleep = Host.sleep
local time = Host.time
local Camera = require("@lib/main/camera")
local Core = require("./core")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Minimenu = require("@lib/main/interfaces/minimenu")
local Mouse = require("@lib/utils/input/mouse")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local Walker = require("@lib/main/walker")
type Box = Core.Box
type Activity = Core.Activity
type Side = Core.Side
type State = Core.State
type Npc = Core.Npc
type Loc = Core.Loc
type Tile = Core.Tile
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
local Loop = Core.Loop
local Solo = Core.Solo

function Solo.counting(): boolean
	return (S.solo.opened and (Doing.is_doing("fish") or snap.tethered or Doing.is_doing("tether")))
		or Doing.is_doing("load")
		or S.solo.ship_hover ~= nil
		or S.solo.fire_hover ~= nil
end

function Solo.fishing_interrupted(target: number): boolean
	Read.sync_inventory()
	if Read.fish_count() >= target then
		return true
	end
	Chat.read_chat()
	return Chat.wave_coming() or Hazard.hazard_at(snap.me) ~= nil
end

function Solo.fish_until(target: number)
	if Read.fish_count() >= target - CONST.SOLO.PREHOVER_FISH then
		Task.prehover_shrine()
	end
	Route.sleep_watching(Random.int(900, 1500), nil, function(): boolean
		return Solo.fishing_interrupted(target)
	end)
	Read.sync_inventory()
	if Read.fish_count() >= target then
		Log.log("Tempoross", `   {Read.fish_count()} fish, off to cook`)
		Doing.clear_activity()
		Task.cook()
	end
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
	if fish < r.last_fish and (Solo.at_crate() or time() - r.left_crate_at < CONST.SOLO.STEP_OFF_COUNT_MS) then
		r.loaded += r.last_fish - fish
	end
	r.last_fish = fish
	if r.loaded >= CONST.SOLO.FIRST_BATCH and r.first_loaded_at == nil then
		r.first_loaded_at = time()
		Log.log("Tempoross", `   Loaded {r.loaded} fish, energy {Read.hud_percent(HUD.ENERGY) or "?"}%`)
	end
end

function Solo.step_off_tile(): Tile
	local here = snap.me
	local totem = (S.side :: Side).totem
	local dx = if totem.x > here.x then 1 elseif totem.x < here.x then -1 else 0
	local dy = if totem.y > here.y then 1 elseif totem.y < here.y then -1 else 0
	return { x = here.x + dx, y = here.y + dy }
end

function Solo.step_off(hovered: boolean)
	S.solo.left_crate_at = time()
	local top = Minimenu.left_click()
	if hovered and top ~= nil and top.option == "Walk here" then
		Mouse.click()
		Log.log("Tempoross", "   Stepped off the crate from the hover")
		return
	end
	Walker.click_tile(Solo.step_off_tile())
end

function Solo.load_exact(target: number)
	local r = S.solo
	if not Doing.is_doing("load") then
		if Task.surge_waited() then
			return
		end
		if Task.walk_to_crate() == nil then
			if events.fire_in_way == nil then
				Route.sleep_watching(Random.int(300, 600))
			end
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
			hovered = Walker.hover_tile_async(Solo.step_off_tile())
		end
		Chat.read_chat()
		return Chat.wave_coming()
			or time() < events.surge_until
			or Task.off_crate_stand()
			or Hazard.hazard_at(snap.me) ~= nil
	end
	Route.sleep_watching(Random.int(1500, 2500), nil, stop)
	if r.loaded < target and Read.fish_count() > 0 and Task.off_crate_stand() then
		Doing.clear_activity()
		return
	end
	if r.loaded >= target and Read.fish_count() > 0 then
		Solo.step_off(hovered)
		Doing.clear_activity()
		sleep(Random.int(300, 500))
		Solo.track_loaded()
	end
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

function Solo.walk_to_load()
	Solo.click_ship_hover()
	Solo.load_exact(CONST.SOLO.FIRST_BATCH)
end

function Solo.late_wave(): boolean
	return events.wave_warning_at ~= nil and events.waves_passed >= 1 and S.solo.pools == 0 and not S.solo.vulnerable
end

function Solo.keeping_fires(): boolean
	return S.solo.first_loaded_at ~= nil and S.solo.pools == 0
end

function Solo.fish_target(): number
	return if S.solo.first_loaded_at then CONST.SOLO.SECOND_BATCH else CONST.SOLO.FIRST_BATCH
end

function Solo.move_safely(target: Tile, act: () -> ())
	local r = S.solo
	local waypoint = r.waypoint
	if waypoint then
		local dest = Player.destination()
		if Geo.distance(snap.me, waypoint) > 1 and dest ~= nil then
			snap.npcs = Read.read_npcs() or snap.npcs
			local fire = Route.fire_ahead(dest)
			if fire and Read.item_count(Items.WATER) > 0 then
				Log.log("Tempoross", `   Fire at {fire.x},{fire.y} on the way round, putting it out`)
				r.waypoint = nil
				Hazard.douse(fire, target)
				return
			end
			Route.sleep_watching(CONST.POLL_MS)
			return
		end
		r.waypoint = nil
	end
	if not Solo.detour_fires(target) then
		act()
	end
end

function Solo.detour_fires(target: Tile): boolean
	local tiles = Route.route_to(target)
	return tiles ~= nil and not Route.fire_free(tiles) and Solo.get_past_fires(target, tiles)
end

function Solo.get_past_fires(target: Tile, tiles: { Tile }): boolean
	local around = Route.waypoint_around_fires(target)
	if around then
		S.solo.waypoint = around
		Log.log("Tempoross", `   Going around the fires through {around.x},{around.y}`)
		Route.click(around)
		Route.sleep_watching(Random.int(200, 350))
		return true
	end
	local fire = Route.first_fire(tiles)
	if fire and Read.item_count(Items.WATER) > 0 then
		local blocking = Route.fires_on(tiles, 3)
		if #blocking >= 2 then
			local to_first = Route.route_to(Route.route_end(Geo.to_tile(fire)))
			local budget = (if to_first then #to_first else 0) + CONST.SOLO.SHARED_SPOT_EXTRA_STEPS
			local spot, beside = Hazard.douse_spot(blocking, blocking, budget)
			if spot and #beside >= 2 then
				Hazard.douse_from(spot, beside, "path")
				return true
			end
		end
		Log.log("Tempoross", `   No way around the fires, putting out the one at {fire.x},{fire.y}`)
		Hazard.douse(fire, target)
		return true
	end
	return false
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
		return Read.fish_count() == 0 or time() < events.surge_until or Task.off_crate_stand()
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
	if time() < r.humidify_at or Doing.is_doing("load") or snap.tethered then
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
	return Read.item_count(Items.WATER) <= CONST.SOLO.HUMIDIFY_AT_WATER and Read.item_count(Items.BUCKET) > 0
end

function Solo.cast_humidify(): boolean
	if Magic.cast("Humidify") then
		return true
	end
	S.solo.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
	Log.log("Tempoross", "   Couldn't cast Humidify")
	return false
end

function Solo.humidify()
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

function Solo.nearest_spot_through_fires(): Npc?
	local best = Task.closest_spot(function(n: Npc): boolean
		if not Task.is_spot(n) then
			return false
		end
		local hazard = Hazard.hazard_at(Route.npc_stand(n))
		return hazard == nil or (hazard.id == CONST.FIRE and Read.item_count(Items.WATER) > 0)
	end)
	if best then
		Log.log("Tempoross", `   Every fishing spot is behind fire, going through to {best.x},{best.y}`)
	end
	return best
end

function Solo.fish_and_cook(target: number, cooking_last: State): State?
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	local cooking = Doing.is_doing("cook")
	if count >= target then
		return if raw == 0 then nil elseif cooking then cooking_last else "COOK_SAFELY"
	end
	local cook: State = if cooking then "CONTINUE" else "COOK_SAFELY"
	local fishing = Doing.is_doing("fish")
	if not (fishing and (S.activity :: Activity).double) then
		local double = Solo.nearest_double()
		if double and Task.double_worth(double) then
			plan.spot = double
			return "FISH_SAFELY"
		end
	end
	if fishing then
		return "FISH_TO_TARGET"
	end
	if raw > 0 and target - count > CONST.SOLO.TOP_UP_FISH then
		return cook
	end
	local spot = Task.best_spot(false, nil, true) or Solo.nearest_spot_through_fires()
	if spot then
		plan.spot = spot
		return "FISH_SAFELY"
	end
	return if raw > 0 then cook else "WAIT_SPOT"
end

function Solo.part_two(): State
	local r = S.solo
	if r.pools >= 1 then
		return Solo.part_three()
	end
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	local intensity = Read.hud_percent(HUD.INTENSITY) or 0
	if not r.p2_loading and count > 0 and intensity >= CONST.SOLO.LOAD_AT_INTENSITY then
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
		if #Solo.side_fires() > 0 then
			r.p2_clear = "side"
			return "P2_CLEAR"
		end
		r.p2_clear = "done"
		Log.log("Tempoross", "   Our side is clear, fishing")
	end
	if not r.p2_loading then
		local fishing = Solo.fish_and_cook(CONST.SOLO.SECOND_BATCH, "COOKING_TO_LOAD")
		if fishing then
			return fishing
		end
		r.p2_loading = true
		Log.log("Tempoross", `{count} cooked fish, loading them all`)
	end
	if count > 0 then
		return "LOAD_ALL"
	end
	return "GO_TO_PIER_SOLO"
end

function Solo.forfeit()
	local why = if events.burned
		then "A fire burned us"
		elseif events.wave_hit_us then "A wave hit us"
		elseif Solo.late_wave() then "A second wave came before Tempoross went under, we're too slow"
		else `Loaded {S.solo.loaded} fish instead of {CONST.SOLO.FIRST_BATCH}`
	Log.log("Tempoross", `{why}, forfeiting`)
	S.forfeiting = true
	S.leave_by_crew = true
	Game.leave()
end

function Solo.part_three(): State
	local r = S.solo
	if r.p3_stage == nil then
		r.p3_stage = "buckets"
		r.p3_buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), snap.me)
		Doing.clear_activity()
		Log.log("Tempoross", "Part 3: filling the inventory with buckets")
	end
	if r.p3_stage == "buckets" then
		if Solo.taking_buckets() then
			return "P3_BUCKETS"
		end
		r.p3_stage = "humidify"
	end
	if r.p3_stage == "humidify" then
		local side = Ship.other_side()
		if side == nil then
			Log.log("Tempoross", "   Couldn't find the other side of the island")
			return "SOLO_STOP"
		end
		S.side = side
		local buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), side.totem)
		local pier = Route.route_end(Geo.to_tile(buckets or side.totem))
		r.p3_pier = pier
		local flip = if side.totem.y < side.mast.y then 1 else -1
		r.p3_box = Solo.flipped_box(side.shrine, CONST.SOLO.BEACH_BOX, flip)
		r.p3_stage = "cross"
		Log.log("Tempoross", `   Crossing to the {side.name} side, pier at {pier.x},{pier.y}`)
	end
	if r.p3_stage == "cross" then
		if Geo.distance(snap.me, r.p3_pier :: Tile) > 1 then
			return "P3_CROSS"
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
			return "P3_CLEAR"
		end
		r.p3_stage = "done"
		r.p4_stage = "fish"
		Log.log("Tempoross", `Part 4: {why}, fishing {CONST.SOLO.THIRD_BATCH} fish`)
	end
	return Solo.part_four()
end

function Solo.ship_fires_left(): boolean
	local r = S.solo
	return r.p4_stage ~= nil
		and r.p4_stage ~= "fish"
		and r.p5_stage == nil
		and Read.item_count(Items.WATER) > 0
		and #Solo.side_fires() > 0
end

function Solo.p4_room(): State?
	Read.sync_inventory()
	local count = Read.fish_count()
	local short = CONST.SOLO.THIRD_BATCH - count - snap.free
	if count >= CONST.SOLO.THIRD_BATCH or short <= 0 then
		return nil
	end
	local on_double = Doing.is_doing("fish") and (S.activity :: Activity).double
	local double = Solo.nearest_double()
	if on_double or (double ~= nil and Task.double_worth(double)) then
		local wanted = CONST.SOLO.P4_DOUBLE_FREE
		if snap.free == 0 or (not on_double and snap.free < wanted) then
			plan.drop = math.min(wanted - snap.free, short)
			return "P3_DROP"
		end
		return nil
	end
	if Read.item_count(Items.RAW_FISH) > 0 then
		return "P4_COOK_DROP"
	end
	plan.drop = short
	return "P3_DROP"
end

function Solo.cook_safely()
	Solo.move_safely(Route.loc_stand((S.side :: Side).shrine), function()
		Task.cook()
	end)
end

function Solo.cook_dropping()
	if not Doing.is_doing("cook") then
		Solo.cook_safely()
		return
	end
	Read.sync_inventory()
	local short = CONST.SOLO.THIRD_BATCH - Read.fish_count() - snap.free
	if short > 0 then
		Solo.drop_buckets(short, true)
		Doing.clear_activity()
	end
end

function Solo.part_four(): State
	local r = S.solo
	if r.p5_stage ~= nil then
		return Solo.part_five()
	end
	if r.p4_stage == "fish" then
		local room = Solo.p4_room()
		if room then
			return room
		end
		local fishing = Solo.fish_and_cook(CONST.SOLO.THIRD_BATCH, "COOKING_TO_LOAD")
		if fishing then
			return fishing
		end
		r.p4_stage = "ship"
		r.p2_box = Solo.home_box(S.side :: Side)
		r.p2_skip = {}
		Log.log("Tempoross", `   {Read.fish_count()} cooked fish, clearing the ship and loading them`)
	end
	local essence = Read.hud_percent(HUD.ESSENCE)
	if r.pools >= 2 or (essence ~= nil and essence <= CONST.SOLO.P4_STOP_ESSENCE) then
		return Solo.start_part_five()
	end
	local count = Read.fish_count()
	local fires = Solo.ship_fires_left()
	local storm = (Read.hud_percent(HUD.INTENSITY) or 0) >= CONST.SOLO.P4_LOAD_INTENSITY
	if count > 0 and (storm or not fires or Doing.is_doing("load")) then
		if storm and r.p4_stage ~= "rush" then
			r.p4_stage = "rush"
			Log.log("Tempoross", "   Storm at 95%, loading every fish before the fires")
		end
		return "LOAD_ALL"
	end
	if fires then
		return "P2_CLEAR"
	end
	return "GO_TO_PIER_SOLO"
end

function Solo.start_part_five(): State
	local r = S.solo
	local north = Ship.other_side()
	if north == nil then
		Log.log("Tempoross", "   Couldn't find the north side of the island")
		return "SOLO_STOP"
	end
	r.p5_north = north
	r.p5_shrine = Geo.to_tile((S.side :: Side).shrine)
	r.p5_stage = "buckets"
	r.p3_buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), snap.me)
	r.p5_box = Solo.home_box(north)
	local limits: { string } = {}
	local bases = CONST.SOLO.P5_BIG_CLUSTER_INTENSITY :: { [string]: number }
	local jitter = CONST.SOLO.P5_BIG_CLUSTER_JITTER
	for _, name in ipairs(CONST.SOLO.P5_ROUTE) do
		r.p5_limits[name] = bases[name] + Random.int(-jitter, jitter + 1)
		table.insert(limits, `{name} {r.p5_limits[name]}%`)
	end
	Doing.clear_activity()
	Log.log("Tempoross", "Part 5: filling the inventory with buckets")
	Log.log("Tempoross", `   Skipping big fire clusters from: {table.concat(limits, ", ")}`)
	return Solo.part_five()
end

function Solo.taking_buckets(): boolean
	Read.sync_inventory()
	if snap.free > 0 and S.solo.p3_buckets ~= nil then
		return true
	end
	S.solo.p3_humidify = Read.item_count(Items.BUCKET) > 0
	return false
end

function Solo.part_five(): State
	local r = S.solo
	if r.p5_stage == "buckets" then
		if Solo.taking_buckets() then
			return "P3_BUCKETS"
		end
		r.p5_stage = "humidify"
	end
	if r.p5_stage == "humidify" then
		if r.p3_humidify and Read.item_count(Items.BUCKET) > 0 then
			return "P5_HUMIDIFY_WALK"
		end
		r.p5_stage = "north"
		Log.log("Tempoross", "   Putting out fires on the way north")
	end
	if r.p5_stage == "north" then
		Solo.p5_remember()
		if Solo.p5_clearing_route() or not Solo.p5_north_reached() then
			return "P5_CLEAR"
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
			local short = CONST.SOLO.P5_FISH - count - snap.free
			if short > 0 then
				plan.drop = short
				return "P3_DROP"
			end
			if Doing.is_doing("fish") then
				return "P5_FISHING"
			end
			local spot = Solo.nearest_double() or Task.best_spot(false, nil, true) or Solo.nearest_spot_through_fires()
			if spot then
				plan.spot = spot
				return "FISH_SAFELY"
			end
			return "WAIT_SPOT"
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
			return "P5_CLEAR"
		end
		r.p5_stage = "load"
		Log.log("Tempoross", `   Loading the fish at {Read.hud_percent(HUD.INTENSITY) or "?"}% storm: {why}`)
	end
	if r.p5_stage == "load" then
		if Read.fish_count() > 0 then
			return "LOAD_ALL"
		end
		r.p5_stage = "pool"
		Log.log("Tempoross", "   Fish loaded, off to the north spirit pool")
	end
	return "GO_TO_PIER_SOLO"
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

function Solo.box_distance(box: Box, t: Tile): number
	return math.max(box.min_x - t.x, t.x - box.max_x, box.min_y - t.y, t.y - box.max_y, 0)
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
		if not visible[key] and Hazard.fire_distance(Hazard.fire_at(t), snap.me) <= CONST.SOLO.FIRE_FORGET_RANGE then
			r.p5_seen[key] = nil
		end
	end
	for _, name in ipairs(CONST.SOLO.P5_ROUTE) do
		if Solo.box_distance(boxes[name], snap.me) == 0 then
			r.p5_entered[name] = true
		end
	end
end

function Solo.p5_box_targets(name: string): { Tile }
	local r = S.solo
	local box = (Solo.island_boxes() :: { [string]: Box })[name]
	local known: { Npc } = {}
	for _, t in pairs(r.p5_seen) do
		local fire = Hazard.fire_at(t)
		if Solo.fire_in(box, fire) then
			table.insert(known, fire)
		end
	end
	local skip_big = (Read.hud_percent(HUD.INTENSITY) or 0) >= r.p5_limits[name]
	local targets: { Tile } = {}
	for _, cluster in ipairs(Hazard.fire_clusters(known)) do
		if not skip_big or #cluster <= CONST.SOLO.P5_MAX_CLUSTER then
			for _, fire in ipairs(cluster) do
				table.insert(targets, { x = fire.x, y = fire.y })
			end
		end
	end
	return targets
end

function Solo.p5_route_box(): (string?, { Tile })
	local r = S.solo
	if Solo.island_boxes() == nil then
		return nil, {}
	end
	while r.p5_route_at <= #CONST.SOLO.P5_ROUTE do
		local name = CONST.SOLO.P5_ROUTE[r.p5_route_at]
		local targets = Solo.p5_box_targets(name)
		if not r.p5_entered[name] or #targets > 0 then
			return name, targets
		end
		Log.log("Tempoross", `   {name} clear at {Read.hud_percent(HUD.INTENSITY) or "?"}% storm`)
		r.p5_route_at += 1
	end
	return nil, {}
end

function Solo.p5_clearing_route(): boolean
	return not Solo.p5_rush_north() and Solo.p5_route_box() ~= nil
end

function Solo.visible_fires(tiles: { Tile }): { Npc }
	local wanted: { [string]: boolean } = {}
	for _, t in ipairs(tiles) do
		wanted[`{t.x},{t.y}`] = true
	end
	return Solo.area_fires(function(fire: Npc): boolean
		return wanted[`{fire.x},{fire.y}`] == true
	end)
end

function Solo.box_entry(box: Box): Tile
	return Route.route_end({
		x = math.clamp(snap.me.x, box.min_x, box.max_x),
		y = math.clamp(snap.me.y, box.min_y, box.max_y),
	})
end

function Solo.p5_clear_route(): boolean
	local r = S.solo
	Solo.p5_remember()
	local name, targets = Solo.p5_route_box()
	if name == nil then
		return false
	end
	local visible = Solo.visible_fires(targets)
	if #visible > 0 then
		Solo.clear_fires(visible, name)
		return true
	end
	local goal: Tile
	if #targets > 0 then
		table.sort(targets, function(a: Tile, b: Tile): boolean
			return Geo.distance(a, snap.me) < Geo.distance(b, snap.me)
		end)
		goal = Route.route_end(targets[1])
	else
		goal = Solo.box_entry((Solo.island_boxes() :: { [string]: Box })[name])
		if Geo.distance(snap.me, goal) <= 1 then
			r.p5_entered[name] = true
			return true
		end
	end
	Log.log("Tempoross", `   Heading into {name} through {goal.x},{goal.y}`)
	Solo.walk_with_buckets(goal, 1, function(): boolean
		Solo.p5_remember()
		return #Solo.visible_fires(Solo.p5_box_targets(name)) > 0
	end)
	return true
end

function Solo.humidify_walk()
	Solo.p5_remember()
	local _, targets = Solo.p5_route_box()
	local fires = Solo.visible_fires(targets)
	local first = if #fires > 0 then Solo.cluster_target(fires) else nil
	local target = if first then Route.npc_stand(first) else Solo.p5_north_target()
	Log.log("Tempoross", `   Walking to {target.x},{target.y} and casting Humidify on the way`)
	Solo.walk_with_buckets(target, 1, function(): boolean
		return not S.solo.p3_humidify
	end)
	S.solo.p3_humidify = false
end

function Solo.clear_way_north()
	local r = S.solo
	if r.p5_stage ~= "north" then
		local fires = Solo.p5_fires()
		if #fires > 0 and Solo.has_water() then
			Solo.clear_fires(fires, "north")
			return
		end
		Route.sleep_watching(Random.int(200, 400))
		return
	end
	if not Solo.p5_rush_north() and Solo.p5_clear_route() then
		return
	end
	local target = Solo.p5_north_target()
	if Solo.detour_fires(target) then
		return
	end
	Solo.walk_with_buckets(target, CONST.SOLO.P5_NORTH_RANGE - 1)
end

function Solo.fish_for_p5()
	Route.sleep_watching(Random.int(300, 600), nil, function(): boolean
		return Solo.fishing_interrupted(CONST.SOLO.P5_FISH)
	end)
end

function Solo.take_buckets()
	local r = S.solo
	local loc = r.p3_buckets :: Loc
	for _ = 1, 2 do
		Read.sync_inventory()
		if snap.free == 0 then
			return
		end
		local before = snap.free
		if not Task.use_loc(loc, { "Take-10" }) then
			return
		end
		Route.sleep_watching(CONST.SOLO.TAKE_BUCKETS_WAIT_MS, nil, function(): boolean
			Read.sync_inventory()
			return snap.free < before
		end)
		Log.log("Tempoross", `   Took buckets, {snap.free} slots free`)
	end
end

function Solo.drop_buckets(count: number, allow_water: boolean)
	local slots: { number } = {}
	for _, wanted in ipairs(if allow_water then { Items.BUCKET, Items.WATER } else { Items.BUCKET }) do
		for _, slot in ipairs(item_container(Inventory.CONTAINER) or {}) do
			if slot.id == wanted and #slots < count then
				table.insert(slots, slot.slot)
			end
		end
	end
	if #slots == 0 then
		return
	end
	Log.log("Tempoross", `   Dropping {#slots} bucket{if #slots == 1 then "" else "s"}`)
	Inventory.shift_drop_slots(slots)
end

function Solo.drop_midwalk()
	local dest = Player.destination()
	if dest == nil or Geo.distance(snap.me, dest) < CONST.SOLO.DROP_MIN_TILES then
		return
	end
	Read.sync_inventory()
	local short = CONST.SOLO.THIRD_BATCH - snap.free
	if short <= 0 or Read.item_count(Items.BUCKET) == 0 then
		return
	end
	local ahead = Route.route_to(dest)
	if ahead == nil or not Route.fire_free(ahead) then
		return
	end
	Solo.drop_buckets(math.min(short, CONST.SOLO.DROP_PER_STEP), false)
end

function Solo.cross()
	local target = S.solo.p3_pier :: Tile
	if not Solo.detour_fires(target) then
		Solo.walk_with_buckets(target, 1)
	end
end

function Solo.walk_with_buckets(target: Tile, near: number, stop: (() -> boolean)?)
	Route.walk(target, near, 30000, function(): boolean
		if S.solo.p3_humidify then
			Solo.humidify_midwalk()
		elseif S.solo.p5_stage == nil then
			Solo.drop_midwalk()
		end
		return not (stop and stop())
	end)
end

function Solo.humidify_midwalk()
	local r = S.solo
	if Read.item_count(Items.BUCKET) == 0 then
		r.p3_humidify = false
		return
	end
	if time() < r.humidify_at or Player.destination() == nil then
		return
	end
	Log.log("Tempoross", `   Casting Humidify while walking ({Read.item_count(Items.WATER)} buckets of water)`)
	if Solo.cast_humidify() then
		r.p3_humidify = false
	end
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

function Solo.clear_p2()
	if Task.surge_waited() then
		return
	end
	local fires = Solo.side_fires()
	if #fires == 0 then
		return
	end
	table.sort(fires, function(a: Npc, b: Npc): boolean
		return Geo.distance(a, snap.me) < Geo.distance(b, snap.me)
	end)
	local fire = fires[1]
	if Route.nearest_of(Route.beside(Hazard.fire_tiles(fire))) == nil then
		S.solo.p2_skip[`{fire.x},{fire.y}`] = true
		Log.log("Tempoross", `   Can't reach the fire at {fire.x},{fire.y}, skipping it`)
		return
	end
	local after = fires[2]
	Log.log("Tempoross", `   Putting out the fire at {fire.x},{fire.y} ({#fires} left on our side)`)
	Hazard.douse(fire, if after then Geo.to_tile(after) else nil)
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

function Solo.clear_beach()
	Solo.clear_fires(Solo.area_fires(Solo.in_box), "beach")
end

function Solo.clear_fires(fires: { Npc }, why: string)
	local fire, after = Solo.cluster_target(fires)
	if fire == nil then
		return
	end
	local near: { Npc } = {}
	for _, other in ipairs(fires) do
		if Geo.distance(other, fire) <= CONST.SOLO.DOUSE_SPOT_RANGE then
			table.insert(near, other)
		end
	end
	local spot, beside = Hazard.douse_spot(near, fires)
	if spot == nil or #beside <= 1 then
		Log.log("Tempoross", `   Clearing the fire at {fire.x},{fire.y} ({why})`)
		Hazard.douse(fire, if after then Geo.to_tile(after) else nil)
		return
	end
	local batch: { [number]: boolean } = {}
	for _, f in ipairs(beside) do
		batch[f.index] = true
	end
	local rest: { Npc } = {}
	for _, f in ipairs(fires) do
		if not batch[f.index] then
			table.insert(rest, f)
		end
	end
	Hazard.douse_from(spot, beside, why, rest)
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

function Solo.get_game_state(skipped: { [State]: boolean }): State
	if S.side ~= nil then
		Solo.track_pools()
	end
	if events.wave_hit_us or events.burned or Solo.late_wave() then
		return "FORFEIT"
	end
	local common = Loop.common_game_state()
	if common then
		return common
	end
	if Solo.wants_humidify() then
		return "HUMIDIFY"
	end
	local r = S.solo
	local target = CONST.SOLO.FIRST_BATCH
	Solo.track_loaded()
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)

	if r.loaded > target and not r.p2_loading then
		return "FORFEIT"
	end
	if r.loaded == target or r.p2_loading then
		return Solo.part_two()
	end
	if r.loading then
		if Task.surge_pending() then
			return "WAIT_SURGE"
		end
		return if r.ship_hover ~= nil then "WALK_TO_LOAD" else "LOAD_EXACT"
	end

	if not r.opened then
		local energy = Read.hud_percent(HUD.ENERGY) or 0
		if energy < CONST.SOLO.OPENING_ENERGY and count < CONST.SOLO.OPENING_FISH and count < target then
			if Doing.is_doing("pump") then
				return "CONTINUE"
			end
			local fill = if count == 0 then Task.fill_state(skipped) else nil
			if fill then
				return fill
			end
			if Doing.is_doing("fish") then
				local near = energy >= CONST.SOLO.OPENING_ENERGY - CONST.SOLO.PREHOVER_ENERGY
					or count >= CONST.SOLO.OPENING_FISH - 2
				return if near then "FISHING_TO_COOK" else "CONTINUE"
			end
			local spot = Task.best_spot(false)
			if spot then
				plan.spot = spot
				return "FISH"
			end
			return "WAIT_SPOT"
		end
		r.opened = true
		Doing.clear_activity()
		Log.log("Tempoross", `Energy {energy}%, cooking {count} fish and waiting for a double spot`)
	end

	if count >= target then
		if raw > 0 then
			if not Doing.is_doing("cook") then
				return "COOK"
			end
			return if events.waves_passed > 0 then "COOKING_TO_LOAD" else "CONTINUE"
		end
		if events.waves_passed == 0 then
			return "WAIT_WAVE"
		end
		r.loading = true
		Log.log("Tempoross", `{count} cooked fish, going to load {target}`)
		return "WALK_TO_LOAD"
	end

	local fishing = Doing.is_doing("fish")
	if not (fishing and (S.activity :: Activity).double) then
		local double = Task.best_spot(true)
		if double and Task.double_worth(double) then
			r.doubled = true
			plan.spot = double
			return "FISH_DOUBLE"
		end
	end
	if fishing then
		return "FISH_TO_TARGET"
	end
	if r.doubled or target - count <= CONST.SOLO.TOP_UP_FISH then
		local spot = Task.best_spot(false)
		if spot then
			plan.spot = spot
			return "FISH"
		end
		if r.doubled and raw == 0 then
			return "WAIT_SPOT"
		end
	end
	if raw > 0 then
		return if Doing.is_doing("cook") then "CONTINUE" else "COOK"
	end
	return "WAIT_DOUBLE"
end

return Solo
