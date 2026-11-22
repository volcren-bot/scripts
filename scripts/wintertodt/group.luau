--!strict
local Biometrics = require("@volcren/biometrics")
local Core = require("./core")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local SpecialAttack = require("@volcren/special_attack")
local WorldSwitcher = require("@volcren/worldswitcher")
type State = Core.State
local NAME = Core.NAME
local CONST = Core.CONST
local ITEMS = Core.ITEMS
local CONFIG = Core.CONFIG
local S = Core.S
local Read = Core.Read
local Loop = Core.Loop
local Group = Core.Group

function Group.switch_sides()
	if Biometrics.random_boolean() then
		S.current = if S.current == "west" then "east" else "west"
		Log.log(NAME, `Switching to the {S.current} brazier`)
	end
end
function Group.check_world()
	if not CONFIG.wintertodt_worlds then
		Log.warn(NAME, "For guaranteed results use a Wintertodt world.")
		return
	end
	if not WorldSwitcher.open(true) then
		error("Failed to open the world switcher.")
	end
	local worlds: { number } = {}
	for _, row in ipairs(WorldSwitcher.rows() or {}) do
		if row.available and row.activity and string.find(string.lower(row.activity), "wintertodt", 1, true) then
			table.insert(worlds, row.world)
		end
	end
	if #worlds == 0 then
		error("The world list has no Wintertodt worlds.")
	end
	local world = WorldSwitcher.current()
	if world and table.find(worlds, world) then
		Log.log(NAME, `On Wintertodt world {world}`)
		WorldSwitcher.close()
		return
	end
	Log.log(NAME, `World {world or "?"} isn't a Wintertodt world (those are {table.concat(worlds, ", ")}), hopping`)
	if not WorldSwitcher.random(worlds) then
		error("Failed to hop to a Wintertodt world.")
	end
end
function Group.supply_state(): State
	local need_vials = Read.count(ITEMS.UNF) == 0
	local need_herbs = Read.count(ITEMS.HERB) < CONST.HERBS_NEEDED
	local low_space = Read.free() < CONST.SPACE_NEEDED
	local vials_first = Biometrics.random_boolean()
	if need_vials and (vials_first or not need_herbs) then
		return if low_space then "MAKE_SPACE" else "GET_VIALS"
	end
	return if low_space then "MAKE_SPACE" else "PICK_HERBS"
end
function Group.get_state(): State
	local common, me = Loop.common_state()
	if common or me == nil then
		return common or "LOADING"
	end
	if Read.threat() then
		return "DODGE"
	end

	if Read.count(ITEMS.UNF) > 0 and Read.count(ITEMS.HERB) >= CONST.HERBS_NEEDED then
		return if S.has_herblore then "MIX_POTIONS" else "TALK_TO_BREWMA"
	end

	if Read.count(ITEMS.POTION) == 0 then
		return Group.supply_state()
	end

	local warmth = Read.warmth()
	if warmth ~= nil and warmth <= S.min_warmth then
		return "WARM_UP"
	end

	local near_brazier = Read.near_brazier(me)

	if Read.boss_energy() == 0 then
		if S.warmth <= 50 then
			return "WARM_UP"
		end
		if Read.count(ITEMS.POTION) <= 2 then
			return Group.supply_state()
		end
		if not near_brazier then
			return "WALK_BRAZIER"
		end
		if not S.hovering then
			return "HOVER_BRAZIER"
		end
		return "WAIT_BOSS"
	end

	if Read.count({ ITEMS.HERB, ITEMS.UNF }) > 0 then
		return "DROP_ITEMS"
	end

	local brazier = Read.brazier_state()
	if brazier == "BROKEN" or brazier == "UNLIT" then
		return "FIX_BRAZIER"
	end
	if brazier == "DEAD" then
		return if CONFIG.help_pyromancers then "HELP_PYRO" else "SWITCH_SIDES"
	end

	local waiting: State? = if S.cutting
		then "WAIT_CUTTING"
		elseif S.fletching then "WAIT_FLETCHING"
		elseif S.burning then "WAIT_BURNING"
		else nil
	if waiting then
		return if S.hovering then waiting else "HOVER_BRAZIER"
	end

	local has_root, has_kindling = Read.count(ITEMS.ROOT) > 0, Read.count(ITEMS.KINDLING) > 0
	if S.boss < Read.fuel(1.3) or Inventory.is_full() or has_kindling or near_brazier then
		if not near_brazier then
			return "WALK_BRAZIER"
		end
		if has_root and S.boss > CONFIG.stop_fletch_energy then
			return "FLETCH_LOGS"
		end
		if has_root or has_kindling then
			return "BURN_FUEL"
		end
	end

	if Read.distance(me, Read.spots().root_stand) > 0 then
		return "WALK_ROOT"
	end

	local spec_cost = if Read.axe_wielded() then SpecialAttack.cost() else nil
	if spec_cost ~= nil and not SpecialAttack.is_enabled() and (SpecialAttack.energy() or 0) >= spec_cost then
		return "USE_SPEC"
	end
	return "CUT_ROOTS"
end
return Group
