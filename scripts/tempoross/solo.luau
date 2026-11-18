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

function Solo.fish_until(target: number)
	local function stop(): boolean
		local inv = Read.read_inventory()
		local count = (inv[Items.RAW_FISH] or 0) + (inv[Items.COOKED_FISH] or 0) + (inv[Items.CRYSTAL_FISH] or 0)
		if count >= target then
			return true
		end
		Chat.read_chat()
		if events.wave_warning_at ~= nil and not events.tethered then
			return true
		end
		return Hazard.hazard_at(snap.me) ~= nil
	end
	if Read.fish_count() >= target - CONST.SOLO.PREHOVER_FISH then
		Task.prehover_shrine()
	end
	Route.sleep_watching(Random.int(900, 1500), nil, stop)
	snap.inv, snap.free = Read.read_inventory()
	if Read.fish_count() >= target then
		Log.log("Tempoross", `   {Read.fish_count()} fish, off to cook`)
		Doing.clear_activity()
		Task.cook()
	end
end

function Solo.wait_wave()
	local totem = (S.side :: Side).totem
	if Geo.distance(snap.me, totem) > 2 then
		Route.walk_near(totem, 2)
		return
	end
	Route.sleep_watching(Random.int(300, 600))
end

function Solo.wait_double()
	local totem = (S.side :: Side).totem
	if Geo.distance(snap.me, totem) > 8 then
		Route.walk_near(totem, 5)
		return
	end
	Route.sleep_watching(Random.int(600, 1200))
end

function Solo.crates(): { Npc }
	local mast = (S.side :: Side).mast
	local crates: { Npc } = {}
	for _, n in ipairs(snap.npcs) do
		if n.name == "Ammunition crate" and Geo.distance(n, mast) <= 4 then
			table.insert(crates, n)
		end
	end
	return crates
end

function Solo.at_crate(): boolean
	for _, crate in ipairs(Solo.crates()) do
		if Geo.distance(crate, snap.me) <= 1 then
			return true
		end
	end
	return false
end

function Solo.track_loaded()
	local r = S.solo
	snap.inv, snap.free = Read.read_inventory()
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
		if Task.surge_pending() then
			Task.wait_out_surge()
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
		return (events.wave_warning_at ~= nil and not events.tethered)
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
			if pos and (pos.x ~= start.x or pos.y ~= start.y) then
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
	if tile.x == me.x and tile.y == me.y then
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
	if Read.item_count(Items.RAW_FISH) > CONST.SOLO.HOVER_RAW then
		Route.sleep_watching(150)
		return
	end
	if S.solo.first_loaded_at ~= nil then
		Solo.prehover_route(Solo.crate_target())
	else
		Solo.pick_ship_hover()
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
	if Route.fire_free(tiles :: { Tile }) then
		r.hover_tried = false
		Solo.pick_ship_hover()
		return
	end
	local around = Route.waypoint_around_fires(target)
	if around and Walker.hover_tile_async(around :: Tile) then
		r.ship_hover = around
		r.ship_hover_waypoint = true
		Log.log("Tempoross", `   Hovering {(around :: Tile).x},{(around :: Tile).y} to go around the fires`)
		return
	end
	local fire = Route.first_fire(tiles :: { Tile })
	if fire then
		local first = Hazard.douse_target(fire)
		if Npcs.hover_async(first) then
			r.fire_hover = first
			Log.log("Tempoross", `   Hovering the fire at {first.x},{first.y} on the way`)
		end
	end
end

function Solo.hover_start()
	local side = Ship.find_side()
	if side == nil then
		return
	end
	local route = Walker.route(Geo.to_tile((side :: Side).totem))
	if route == nil then
		return
	end
	for i = #route.tiles, 2, -1 do
		local t = route.tiles[i]
		if Walker.on_screen(t) then
			if Geo.distance(t, snap.me) >= CONST.SOLO.HOVER_MIN_TILES and Walker.hover_tile_async(t) then
				S.start_hover = t
				Log.log("Tempoross", `   Hovering {t.x},{t.y} on the way to the totem`)
			end
			return
		end
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
			Log.log("Tempoross", `   Off to the totem through {(start :: Tile).x},{(start :: Tile).y} under the fade`)
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
			for i = #route.tiles, 2, -1 do
				local t = route.tiles[i]
				if Walker.on_screen(t) then
					if
						Geo.distance(t, snap.me) >= CONST.SOLO.HOVER_MIN_TILES
						and Route.fire_free(table.move(route.tiles, 1, i, 1, {}))
					then
						r.ship_hover = t
					end
					break
				end
			end
		end
		local hover = r.ship_hover
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
	if not Walker.on_screen(hover :: Tile) then
		Log.log("Tempoross", `   The hovered tile {(hover :: Tile).x},{(hover :: Tile).y} went off screen`)
		return false
	end
	local tiles = Route.route_to(hover :: Tile)
	local landing = tiles and Route.landing_ahead(tiles :: { Tile })
	local fire = tiles and Route.first_fire(tiles :: { Tile })
	if landing or fire then
		Log.log("Tempoross", `   Not taking the hovered tile: fire or strike on the way`)
		return false
	end
	if Walker.click_tile(hover :: Tile) then
		Log.log("Tempoross", `   Off to the ship through {(hover :: Tile).x},{(hover :: Tile).y}`)
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
	local tiles = Route.route_to(target)
	if tiles == nil or Route.fire_free(tiles :: { Tile }) or not Solo.get_past_fires(target, tiles :: { Tile }) then
		act()
	end
end

function Solo.get_past_fires(target: Tile, tiles: { Tile }): boolean
	local around = Route.waypoint_around_fires(target)
	if around then
		S.solo.waypoint = around
		Log.log("Tempoross", `   Going around the fires through {around.x},{around.y}`)
		if not Walker.click_tile(around) then
			Walker.click_minimap(around)
		end
		Route.sleep_watching(Random.int(200, 350))
		return true
	end
	local fire = Route.first_fire(tiles)
	if fire and Read.item_count(Items.WATER) > 0 then
		local blocking = Route.fires_on(tiles, 3)
		if #blocking >= 2 then
			local to_first = Route.route_to(Route.route_end(Geo.to_tile(fire :: Npc)))
			local budget = (if to_first then #(to_first :: { Tile }) else 0) + CONST.SOLO.SHARED_SPOT_EXTRA_STEPS
			local spot, beside = Hazard.douse_spot(blocking, blocking, budget)
			if spot and #beside >= 2 then
				Hazard.douse_from(spot :: Tile, beside, "path")
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
	return if pool then Route.npc_stand(pool :: Npc) else nil
end

function Solo.load_all()
	local r = S.solo
	if not Doing.is_doing("load") then
		if Task.surge_pending() then
			Task.wait_out_surge()
			return
		end
		Solo.click_ship_hover()
		local target = Solo.crate_target()
		Solo.move_safely(target, function()
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
		snap.inv, snap.free = Read.read_inventory()
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
	if Geo.distance(snap.me, pier :: Tile) <= CONST.PIER_RANGE then
		Route.sleep_watching(Random.int(200, 400))
		return
	end
	Solo.move_safely(pier :: Tile, function()
		Log.log("Tempoross", `   Off to the pier at {(pier :: Tile).x},{(pier :: Tile).y}`)
		if not Walker.click_tile(pier :: Tile) then
			Walker.click_minimap(pier :: Tile)
		end
		Route.sleep_watching(Random.int(300, 500))
	end)
end

function Solo.wants_humidify(): boolean
	local r = S.solo
	if time() < r.humidify_at or Doing.is_doing("load") or snap.tethered then
		return false
	end
	if r.p2_clear ~= nil and r.p3_stage == nil and #Solo.area_fires(Solo.our_side_fire) == 0 then
		return false
	end
	if r.p3_stage == "buckets" or r.p3_stage == "humidify" or (r.p3_stage == "cross" and r.p3_humidify) then
		return false
	end
	if r.p5_stage == "buckets" or r.p5_stage == "humidify" or r.p5_stage == "fish" or r.p5_stage == "load" then
		return false
	end
	if r.p4_stage ~= nil and r.p5_stage == nil and r.pools >= 2 then
		return false
	end
	snap.inv, snap.free = Read.read_inventory()
	return Read.item_count(Items.WATER) <= CONST.SOLO.HUMIDIFY_AT_WATER and Read.item_count(Items.BUCKET) > 0
end

function Solo.humidify()
	local r = S.solo
	local before = Read.item_count(Items.WATER)
	Log.log("Tempoross", `   {before} buckets of water left, casting Humidify`)
	if not Magic.cast("Humidify") then
		r.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
		Log.log("Tempoross", "   Couldn't cast Humidify")
		return
	end
	local filled = Route.sleep_watching(3000, nil, function(): boolean
		snap.inv, snap.free = Read.read_inventory()
		return Read.item_count(Items.WATER) > before
	end)
	if not filled then
		r.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
	end
	Inventory.open()
	Log.log("Tempoross", `   {Read.item_count(Items.WATER)} buckets of water after Humidify`)
end

function Solo.nearest_double(): Npc?
	local totem = (S.side :: Side).totem
	local best, best_steps = nil, math.huge
	for _, n in ipairs(snap.npcs) do
		if
			n.id == CONST.DOUBLE_SPOT
			and Geo.distance(n, totem) <= 14
			and Read.double_ticks_left(n, snap.tick) >= CONST.DOUBLE_MIN_TICKS_LEFT
		then
			local steps = Route.walk_steps(n)
			if steps < best_steps then
				best, best_steps = n, steps
			end
		end
	end
	return best
end

function Solo.nearest_spot_through_fires(): Npc?
	local totem = (S.side :: Side).totem
	local best, best_steps = nil, math.huge
	for _, n in ipairs(snap.npcs) do
		if (CONST.SINGLE_SPOTS[n.id] or n.id == CONST.DOUBLE_SPOT) and Geo.distance(n, totem) <= 14 then
			local stand = Route.npc_stand(n)
			local hazard = Hazard.hazard_at(stand)
			local steps = Route.walk_steps(n)
			local passable = hazard == nil or (hazard.id == CONST.FIRE and Read.item_count(Items.WATER) > 0)
			if passable and steps < best_steps then
				best, best_steps = n, steps
			end
		end
	end
	if best then
		Log.log("Tempoross", `   Every fishing spot is behind fire, going through to {best.x},{best.y}`)
	end
	return best
end

function Solo.fish_and_cook(target: number, cooking_last: State): State?
	local count = Read.fish_count()
	local raw = Read.item_count(Items.RAW_FISH)
	if count < target then
		local fishing = Doing.is_doing("fish")
		if not (fishing and (S.activity :: Activity).double) then
			local double = Solo.nearest_double()
			if double and Task.double_worth(double :: Npc) then
				plan.spot = double
				return "FISH_SAFELY"
			end
		end
		if fishing then
			return "FISH_TO_TARGET"
		end
		if raw > 0 and target - count > CONST.SOLO.TOP_UP_FISH then
			return if Doing.is_doing("cook") then "CONTINUE" else "COOK_SAFELY"
		end
		local spot = Task.best_spot(false, nil, true) or Solo.nearest_spot_through_fires()
		if spot then
			plan.spot = spot
			return "FISH_SAFELY"
		end
		if raw > 0 then
			return if Doing.is_doing("cook") then "CONTINUE" else "COOK_SAFELY"
		end
		return "WAIT_SPOT"
	end
	if raw > 0 then
		return if Doing.is_doing("cook") then cooking_last else "COOK_SAFELY"
	end
	return nil
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
		local stage = r.p2_clear
		if stage == nil then
			stage = "side"
			r.p2_box = Solo.home_box()
			local b = r.p2_box :: Box
			Log.log(
				"Tempoross",
				`Part 2: putting out every fire in x {b.min_x}..{b.max_x} y {b.min_y}..{b.max_y} ({#Solo.area_fires(
					Solo.our_side_fire
				)})`
			)
		end
		if stage == "side" and #Solo.area_fires(Solo.our_side_fire) == 0 then
			stage = "done"
			Log.log("Tempoross", "   Our side is clear, fishing")
		end
		r.p2_clear = stage
		if stage ~= "done" then
			return "P2_CLEAR"
		end
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
		snap.inv, snap.free = Read.read_inventory()
		if snap.free > 0 and r.p3_buckets ~= nil then
			return "P3_BUCKETS"
		end
		r.p3_stage = "humidify"
		r.p3_humidify = Read.item_count(Items.BUCKET) > 0
	end
	if r.p3_stage == "humidify" then
		local other = Ship.other_side()
		if other == nil then
			Log.log("Tempoross", "   Couldn't find the other side of the island")
			return "SOLO_STOP"
		end
		S.side = other
		local side = other :: Side
		local buckets = Geo.nearest_loc(Read.locs_named({ "Buckets" }), side.totem)
		r.p3_pier = Route.route_end(Geo.to_tile(buckets or side.totem))
		local b = CONST.SOLO.BEACH_BOX
		local flip = if side.totem.y < side.mast.y then 1 else -1
		local xa, xb = side.shrine.x + flip * b.west, side.shrine.x + flip * b.east
		local ya, yb = side.shrine.y + flip * b.south, side.shrine.y + flip * b.north
		r.p3_box = {
			min_x = math.min(xa, xb),
			max_x = math.max(xa, xb),
			min_y = math.min(ya, yb),
			max_y = math.max(ya, yb),
		}
		r.p3_stage = "cross"
		Log.log(
			"Tempoross",
			`   Crossing to the {side.name} side, pier at {(r.p3_pier :: Tile).x},{(r.p3_pier :: Tile).y}`
		)
	end
	if r.p3_stage == "cross" then
		if Geo.distance(snap.me, r.p3_pier :: Tile) > 1 then
			return "P3_CROSS"
		end
		r.p3_stage = "clear"
		Log.log("Tempoross", "   On the other side, clearing the pier and the beach")
	end
	if r.p3_stage == "clear" then
		if Solo.beach_target() ~= nil and Read.item_count(Items.WATER) > 0 then
			return "P3_CLEAR"
		end
		r.p3_stage = "done"
		r.p4_stage = "fish"
		Log.log("Tempoross", `Part 4: beach clear, fishing {CONST.SOLO.THIRD_BATCH} fish`)
	end
	return Solo.part_four()
end

function Solo.ship_fires_left(): boolean
	local r = S.solo
	return r.p4_stage ~= nil
		and r.p4_stage ~= "fish"
		and r.p5_stage == nil
		and Read.item_count(Items.WATER) > 0
		and #Solo.area_fires(Solo.our_side_fire) > 0
end

function Solo.p4_room(): State?
	snap.inv, snap.free = Read.read_inventory()
	local count = Read.fish_count()
	local short = CONST.SOLO.THIRD_BATCH - count - snap.free
	if count >= CONST.SOLO.THIRD_BATCH or short <= 0 then
		return nil
	end
	local on_double = Doing.is_doing("fish") and (S.activity :: Activity).double
	local double = Solo.nearest_double()
	if on_double or (double ~= nil and Task.double_worth(double :: Npc)) then
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

function Solo.cook_dropping()
	if not Doing.is_doing("cook") then
		Solo.move_safely(Route.loc_stand((S.side :: Side).shrine), Task.cook)
		return
	end
	snap.inv, snap.free = Read.read_inventory()
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
		r.p2_box = Solo.home_box()
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
	local here = S.side :: Side
	S.side = north
	r.p5_box = Solo.home_box()
	S.side = here
	Doing.clear_activity()
	Log.log("Tempoross", "Part 5: filling the inventory with buckets")
	return Solo.part_five()
end

function Solo.part_five(): State
	local r = S.solo
	if r.p5_stage == "buckets" then
		snap.inv, snap.free = Read.read_inventory()
		if snap.free > 0 and r.p3_buckets ~= nil then
			return "P3_BUCKETS"
		end
		r.p3_humidify = Read.item_count(Items.BUCKET) > 0
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
		if not Solo.p5_north_reached() then
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
		snap.inv, snap.free = Read.read_inventory()
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
		if shrine and Hazard.fire_distance(fire, shrine :: Tile) <= CONST.SOLO.P5_SHRINE_RANGE then
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

function Solo.humidify_walk()
	local fires = Solo.p5_fires()
	local first = if #fires > 0 then Solo.cluster_target(fires) else nil
	local target = if first then Route.npc_stand(first :: Npc) else Solo.p5_north_target()
	Log.log("Tempoross", `   Walking to {target.x},{target.y} and casting Humidify on the way`)
	Solo.walk_with_buckets(target, 1, function(): boolean
		return not S.solo.p3_humidify
	end)
	S.solo.p3_humidify = false
end

function Solo.clear_way_north()
	local r = S.solo
	local heading = r.p5_stage == "north"
	local fires = if heading and Solo.p5_rush_north() then {} else Solo.p5_fires()
	if #fires > 0 and Solo.has_water() then
		Solo.clear_fires(fires, if heading then "way north" else "north")
		return
	end
	if not heading then
		Route.sleep_watching(Random.int(200, 400))
		return
	end
	local target = Solo.p5_north_target()
	local tiles = Route.route_to(target)
	if tiles and not Route.fire_free(tiles :: { Tile }) and Solo.get_past_fires(target, tiles :: { Tile }) then
		return
	end
	local rushing = #fires == 0 and Solo.p5_rush_north()
	Solo.walk_with_buckets(target, CONST.SOLO.P5_NORTH_RANGE - 1, function(): boolean
		return not rushing and #Solo.p5_fires() > 0
	end)
end

function Solo.fish_for_p5()
	Route.sleep_watching(Random.int(300, 600), nil, function(): boolean
		snap.inv, snap.free = Read.read_inventory()
		Chat.read_chat()
		return Read.fish_count() >= CONST.SOLO.P5_FISH
			or (events.wave_warning_at ~= nil and not events.tethered)
			or Hazard.hazard_at(snap.me) ~= nil
	end)
end

function Solo.take_buckets()
	local r = S.solo
	local loc = r.p3_buckets :: Loc
	for _ = 1, 2 do
		snap.inv, snap.free = Read.read_inventory()
		if snap.free == 0 then
			return
		end
		local before = snap.free
		if not Task.use_loc(loc, { "Take-10" }) then
			return
		end
		Route.sleep_watching(CONST.SOLO.TAKE_BUCKETS_WAIT_MS, nil, function(): boolean
			snap.inv, snap.free = Read.read_inventory()
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
	if dest == nil or Geo.distance(snap.me, dest :: Tile) < CONST.SOLO.DROP_MIN_TILES then
		return
	end
	snap.inv, snap.free = Read.read_inventory()
	local short = CONST.SOLO.THIRD_BATCH - snap.free
	if short <= 0 or Read.item_count(Items.BUCKET) == 0 then
		return
	end
	local ahead = Route.route_to(dest :: Tile)
	if ahead == nil or not Route.fire_free(ahead :: { Tile }) then
		return
	end
	Solo.drop_buckets(math.min(short, CONST.SOLO.DROP_PER_STEP), false)
end

function Solo.cross()
	local target = S.solo.p3_pier :: Tile
	local tiles = Route.route_to(target)
	if tiles and not Route.fire_free(tiles :: { Tile }) and Solo.get_past_fires(target, tiles :: { Tile }) then
		return
	end
	Solo.walk_with_buckets(target, 1)
end

function Solo.walk_with_buckets(target: Tile, near: number, stop: (() -> boolean)?)
	local o = Route.walk_checks(false)
	local checks: ((Tile) -> boolean?)? = o.on_step
	o.on_step = function(tile: Tile): boolean?
		if checks and checks(tile) == false then
			return false
		end
		if S.solo.p3_humidify then
			Solo.humidify_midwalk()
		elseif S.solo.p5_stage == nil then
			Solo.drop_midwalk()
		end
		if stop and stop() then
			return false
		end
		return true
	end
	o.near = near
	o.timeout_ms = 30000
	Walker.walk(target, o)
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
	if Magic.cast("Humidify") then
		r.p3_humidify = false
	else
		r.humidify_at = time() + CONST.SOLO.HUMIDIFY_RETRY_MS
		Log.log("Tempoross", "   Couldn't cast Humidify")
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

function Solo.home_box(): Box
	local side = S.side :: Side
	local b = CONST.SOLO.NORTH_BOX
	local flip = if side.totem.y > side.mast.y then 1 else -1
	local xa, xb = side.mast.x + flip * b.west, side.mast.x + flip * b.east
	local ya, yb = side.mast.y + flip * b.south, side.mast.y + flip * b.north
	return { min_x = math.min(xa, xb), max_x = math.max(xa, xb), min_y = math.min(ya, yb), max_y = math.max(ya, yb) }
end

function Solo.fire_in(box: Box?, fire: Npc): boolean
	if box == nil then
		return false
	end
	local b = box :: Box
	for _, t in ipairs(Hazard.fire_tiles(fire)) do
		if t.x >= b.min_x and t.x <= b.max_x and t.y >= b.min_y and t.y <= b.max_y then
			return true
		end
	end
	return false
end

function Solo.our_side_fire(fire: Npc): boolean
	local r = S.solo
	return not r.p2_skip[`{fire.x},{fire.y}`] and Solo.fire_in(r.p2_box, fire)
end

function Solo.clear_p2()
	if Task.surge_pending() then
		Task.wait_out_surge()
		return
	end
	local fires = Solo.area_fires(Solo.our_side_fire)
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
	Hazard.douse(fire, if after then Geo.to_tile(after :: Npc) else nil)
end

function Solo.beach_target(): (Npc?, Npc?)
	return Solo.cluster_target(Solo.area_fires(Solo.in_box))
end

function Solo.cluster_target(fires: { Npc }): (Npc?, Npc?)
	if #fires == 0 then
		return nil, nil
	end
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
	local size: { [number]: number } = {}
	local nearest: { [number]: { fire: Npc, steps: number } } = {}
	for i, fire in ipairs(fires) do
		local g = root(i)
		size[g] = (size[g] or 0) + 1
		local steps = Route.walk_steps(fire)
		if nearest[g] == nil or steps < nearest[g].steps then
			nearest[g] = { fire = fire, steps = steps }
		end
	end
	local best_group, best_score = nil, math.huge
	for g, n in pairs(nearest) do
		local score = n.steps + CONST.SOLO.CLUSTER_WEIGHT * size[g]
		if score < best_score then
			best_group, best_score = g, score
		end
	end
	local target = (nearest[best_group :: number]).fire
	local after: Npc? = nil
	for i, fire in ipairs(fires) do
		if root(i) == best_group and fire.index ~= target.index then
			if after == nil or Geo.distance(fire, target) < Geo.distance(after :: Npc, target) then
				after = fire
			end
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
		if Geo.distance(other, fire :: Npc) <= CONST.SOLO.DOUSE_SPOT_RANGE then
			table.insert(near, other)
		end
	end
	local spot, beside = Hazard.douse_spot(near, fires)
	if spot == nil or #beside <= 1 then
		Log.log("Tempoross", `   Clearing the fire at {fire.x},{fire.y} ({why})`)
		Hazard.douse(fire, if after then Geo.to_tile(after :: Npc) else nil)
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
	Hazard.douse_from(spot :: Tile, beside, why, rest)
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
		if double and Task.double_worth(double :: Npc) then
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
