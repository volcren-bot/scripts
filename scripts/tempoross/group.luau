--!strict
local Core = require("./core")
local Log = require("@lib/utils/log")
type Activity = Core.Activity
type State = Core.State
type Npc = Core.Npc
local CONST = Core.CONST
local CONFIG = Core.CONFIG
local Items = Core.Items
local S = Core.S
local snap = Core.snap
local plan = Core.plan
local Read = Core.Read
local Geo = Core.Geo
local Ship = Core.Ship
local Hazard = Core.Hazard
local Doing = Core.Doing
local Task = Core.Task
local Game = Core.Game
local Loop = Core.Loop
local Group = Core.Group

function Group.get_game_state(skipped: { [State]: boolean }): State
	local common = Loop.common_game_state()
	if common then
		return common
	end
	if Doing.is_doing("load") and Read.fish_count() > 0 and Task.off_crate_stand() then
		Doing.clear_activity()
		return "LOAD_CANNON"
	end

	if Loop.wants_pier() then
		return "GO_TO_PIER"
	end
	S.pier_logged = false

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

	local committed = Doing.is_doing("repair") or Doing.is_doing("tether") or Doing.is_doing("load")
	if
		snap.free > 0
		and not committed
		and not (S.activity and (S.activity :: Activity).double)
		and Read.has_harpoon()
	then
		local double = Task.best_spot(true)
		if double and Geo.distance(double, snap.me) <= 16 and Task.double_worth(double) then
			plan.spot = double
			return "FISH_DOUBLE"
		end
	end

	if S.activity ~= nil then
		local a = S.activity :: Activity
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
		elseif
			a.kind == "fish"
			and not a.double
			and CONFIG.cook.enabled
			and Read.item_count(Items.RAW_FISH) >= S.cook_fish_threshold - CONST.PREHOVER_FISH
		then
			return "FISHING_TO_COOK"
		else
			return "CONTINUE"
		end
	end

	if snap.free > 0 then
		if not Read.has_harpoon() then
			return "TAKE_HARPOON"
		end
		if not Read.has_rope() and not Game.should_load() and not skipped["TAKE_ROPE"] then
			return "TAKE_ROPE"
		end
	end

	if Game.should_load() then
		return "LOAD_CANNON"
	end

	if snap.free > 0 and Ship.at_home(snap.me) then
		if not Read.has_hammer() and not skipped["TAKE_HAMMER"] then
			return "TAKE_HAMMER"
		end
		local need_water = Read.item_count(Items.WATER) == 0 and #Hazard.fire_npcs() > 0
		if
			Read.buckets() < CONFIG.buckets
			and (Read.fish_count() == 0 or (need_water and Read.item_count(Items.BUCKET) == 0))
			and not skipped["TAKE_BUCKETS"]
		then
			return "TAKE_BUCKETS"
		end
	end
	local fill = Task.fill_state(skipped)
	if fill then
		return fill
	end

	local raw = Read.item_count(Items.RAW_FISH)
	if CONFIG.cook.enabled and raw > 0 and (raw >= S.cook_fish_threshold or snap.free == 0) then
		return "COOK"
	end

	if snap.free > 0 then
		local spot = Task.best_spot(false)
		if spot then
			plan.spot = spot
			return "FISH"
		end
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
	if Read.fish_count() > 0 then
		return "LOAD_CANNON"
	end
	return "IDLE"
end

return Group
