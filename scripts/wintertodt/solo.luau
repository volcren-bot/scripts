--!strict
local Host = require("@volcren/host")
local time = Host.time
local Core = require("./core")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Players = require("@volcren/players")
local Random = require("@volcren/random")
local Transports = require("@volcren/transports")
local WorldSwitcher = require("@volcren/worldswitcher")
type Tile = Core.Tile
type Corner = Core.Corner
type SideSpots = Core.SideSpots
type State = Core.State
local NAME = Core.NAME
local CONST = Core.CONST
local ITEMS = Core.ITEMS
local CONFIG = Core.CONFIG
local S = Core.S
local new_round = Core.new_round
local Read = Core.Read
local Wait = Core.Wait
local Task = Core.Task
local Loop = Core.Loop
local Solo = Core.Solo

function Solo.lowest_potion(): string?
	for dose = 1, CONST.SOLO.DOSES_PER_POTION do
		local name = `Rejuvenation potion ({dose})`
		if Read.count(name) > 0 then
			return name
		end
	end
	return nil
end
function Solo.others_here(): boolean
	local me = Players.me()
	for _, p in ipairs(Host.players() or {}) do
		if (me == nil or p.index ~= me.index) and not Read.outside({ x = p.x, y = p.y }) then
			return true
		end
	end
	return false
end

function Solo.corner(corner: Corner): SideSpots
	return CONST.SOLO.CORNERS[corner]
end

function Solo.needs_light(corner: Corner): boolean
	return Read.brazier_state(Solo.corner(corner)) ~= "LIT"
end

function Solo.missing_potions(): number
	local per = CONST.SOLO.DOSES_PER_POTION
	return math.max(0, math.ceil((CONFIG.solo_potions * per - Read.doses()) / per))
end

function Solo.route(): { Corner }
	for _, climb in ipairs(Transports.allowed_climbs()) do
		if string.find(climb, CONST.SOLO.GAP, 1, true) then
			return CONST.SOLO.ROUTE_GAP
		end
	end
	return CONST.SOLO.ROUTE_AROUND
end

function Solo.nearest(me: Tile, corners: { Corner }, wanted: (Corner) -> boolean): Corner?
	local best, best_d = nil, math.huge
	for _, corner in ipairs(corners) do
		local d = Read.distance(me, Solo.corner(corner).brazier)
		if d < best_d and wanted(corner) then
			best, best_d = corner, d
		end
	end
	return best
end

function Solo.supply_state(): State?
	local missing = Solo.missing_potions()
	if missing == 0 then
		return if Read.count(Read.surplus()) > 0 then "DROP_ITEMS" else nil
	end
	local need_vials = math.max(0, missing - Read.count(ITEMS.UNF))
	local need_herbs = math.max(0, missing - Read.count(ITEMS.HERB))
	if need_vials == 0 and need_herbs == 0 then
		return if S.has_herblore then "MIX_POTIONS" else "TALK_TO_BREWMA"
	end
	if Read.free() < need_vials + need_herbs then
		return "MAKE_SPACE"
	end
	return if need_vials > 0 then "GET_VIALS" else "PICK_HERBS"
end

function Solo.make_space(): boolean
	local missing = Solo.missing_potions()
	local wanted = math.max(0, missing - Read.count(ITEMS.UNF)) + math.max(0, missing - Read.count(ITEMS.HERB))
	local short = wanted - Read.free()
	local drop: { number } = {}
	for _, item in ipairs({ ITEMS.ROOT, ITEMS.KINDLING }) do
		for _, slot in ipairs(Inventory.indices_of(item) or {}) do
			if #drop >= short then
				break
			end
			table.insert(drop, slot)
		end
	end
	if #drop < short then
		error(`Not enough inventory space for {CONFIG.solo_potions} rejuvenation potions.`)
	end
	local ordered = Inventory.pattern(drop)
	return Inventory.shift_drop_slots(ordered)
end

function Solo.hop(): boolean
	if S.worlds == nil then
		if not WorldSwitcher.open(true) then
			return false
		end
		local worlds: { number } = {}
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.members and row.available and row.activity == "-" then
				table.insert(worlds, row.world)
			end
		end
		if #worlds == 0 then
			error("The world list has no plain members worlds to hop to.")
		end
		Log.log(NAME, `{#worlds} plain members worlds to hop between`)
		S.worlds = worlds
	end
	Log.log(NAME, "Someone else is in the Wintertodt room, hopping")
	Task.stop_actions(true)
	if not WorldSwitcher.random(S.worlds :: { number }) then
		return false
	end
	S.round, S.round_points, S.stale_points = new_round(), 0, nil
	return true
end
function Solo.keeps_lit(): boolean
	return S.round.ending or CONFIG.solo_goal == "xp" or S.boss > CONST.SOLO.LOW_ENERGY
end

function Solo.idle()
	local range = CONST.SOLO.IDLE_MS
	Wait.sleep(Random.int(range[1], range[2]))
end
function Solo.light_state(turn_back: boolean): State
	S.round.turn_back = turn_back
	if Read.brazier_state() == "DEAD" then
		return "HELP_PYRO"
	end
	return "FIX_BRAZIER"
end

function Solo.keep_walking(here: Tile, left: Corner?): boolean
	local r = S.round
	if left == nil or left == S.corner or time() - r.checked_at < CONST.SOLO.CHECK_MS then
		return true
	end
	r.checked_at = time()
	if not Solo.needs_light(left) then
		return true
	end
	local back = Read.distance(here, Solo.corner(left).brazier)
	if back < Read.distance(here, Read.spots().brazier) then
		Log.log(NAME, `The {left} brazier went out and is closer, turning back`)
		return false
	end
	return true
end

function Solo.light(): boolean
	local left = if S.round.turn_back then S.round.at else nil
	local ok = Task.click_brazier(function(here: Tile): boolean
		return Solo.keep_walking(here, left)
	end)
	if ok then
		S.round.at = S.corner
	end
	return ok
end

function Solo.work_state(me: Tile, can_feed: boolean): State
	if S.cutting then
		return "WAIT_CUTTING"
	end
	if S.fletching then
		return "WAIT_FLETCHING"
	end
	if S.burning then
		return "WAIT_BURNING"
	end
	local roots, kindling = Read.count(ITEMS.ROOT), Read.count(ITEMS.KINDLING)
	local near = Read.near_brazier(me)
	if roots + kindling > 0 and (Inventory.is_full() or near or roots == 0) then
		if CONFIG.solo_goal == "points" and roots > 0 then
			return if near then "FLETCH_LOGS" else "WALK_BRAZIER"
		end
		return if can_feed then "BURN_FUEL" else "SOLO_IDLE"
	end
	return "CUT_ROOTS"
end

function Solo.focus_state(me: Tile, light: boolean): State
	local state = Read.brazier_state()
	if state == "DEAD" then
		return "HELP_PYRO"
	end
	if light and (state == "BROKEN" or state == "UNLIT") then
		return Solo.light_state(false)
	end
	return Solo.work_state(me, state == "LIT")
end

function Solo.next_to_open(): Corner?
	local r = S.round
	for _, corner in ipairs(Solo.route()) do
		if not r.lit[corner] then
			if Read.brazier_state(Solo.corner(corner)) ~= "LIT" then
				return corner
			end
			r.lit[corner] = true
		end
	end
	return nil
end

function Solo.visit_due(): Corner?
	local r = S.round
	local route = Solo.route()
	for i = #route, 1, -1 do
		local corner = route[i]
		if corner ~= CONST.SOLO.FOCUS and time() - (r.visited[corner] or 0) > r.visit_every then
			return corner
		end
	end
	return nil
end

function Solo.visit_state(me: Tile, corner: Corner): State
	S.corner = corner
	local spots = Read.spots()
	local pyro = Read.pyromancer()
	if pyro == nil or Read.distance(me, spots.pyromancer) > CONST.FIND_RANGE + 2 then
		return "WALK_BRAZIER"
	end
	if Read.incapacitated(pyro) then
		return "HELP_PYRO"
	end
	S.round.visited[corner] = time()
	S.corner = CONST.SOLO.FOCUS
	return "SOLO_IDLE"
end

function Solo.low_state(me: Tile): State
	S.corner = CONST.SOLO.FOCUS
	if Read.brazier_state() == "DEAD" then
		return "HELP_PYRO"
	end
	if S.cutting then
		return "WAIT_CUTTING"
	end
	if S.fletching then
		return "WAIT_FLETCHING"
	end
	if not Inventory.is_full() then
		return "CUT_ROOTS"
	end
	if Read.count(ITEMS.ROOT) > 0 then
		return "FLETCH_LOGS"
	end
	local due = Solo.visit_due()
	if due then
		return Solo.visit_state(me, due)
	end
	if not Read.near_brazier(me) then
		return "WALK_BRAZIER"
	end
	return "SOLO_IDLE"
end

function Solo.end_state(me: Tile): State
	S.corner = S.round.end_corner
	return Solo.focus_state(me, true)
end

function Solo.between_rounds(me: Tile): State
	if S.round.started then
		S.round = new_round()
	end
	if S.warmth <= 50 and Read.doses() > 0 then
		return "WARM_UP"
	end
	S.corner = Solo.route()[1]
	if not Read.near_brazier(me) then
		return "WALK_BRAZIER"
	end
	if not S.hovering then
		return "HOVER_BRAZIER"
	end
	return "WAIT_BOSS"
end

function Solo.round_state(me: Tile, energy: number): State
	local r = S.round
	r.started = true
	if not r.ending and CONFIG.solo_goal == "points" and S.round_points >= CONFIG.solo_points + r.points_bonus then
		r.ending = true
		r.end_corner = Solo.nearest(me, CONST.SOLO.END_CORNERS, function()
			return true
		end) or CONST.SOLO.FOCUS
		Log.log(NAME, `{S.round_points} points, ending the round at the {r.end_corner} brazier`)
	end
	if r.ending then
		return Solo.end_state(me)
	end
	if not r.opened then
		local corner = Solo.next_to_open()
		if corner then
			S.corner = corner
			return Solo.light_state(false)
		end
		r.opened = true
		Log.log(NAME, "All four braziers lit")
	end
	if energy > r.open_until then
		local all: { Corner } = { "sw", "se", "nw", "ne" }
		local out = Solo.nearest(me, all, Solo.needs_light)
		if out then
			S.corner = out
			return Solo.light_state(true)
		end
	end
	S.corner = CONST.SOLO.FOCUS
	if CONFIG.solo_goal == "xp" or energy > CONST.SOLO.LOW_ENERGY then
		return Solo.focus_state(me, true)
	end
	return Solo.low_state(me)
end

function Solo.get_state(): State
	local common, me = Loop.common_state()
	if common or me == nil then
		return common or "LOADING"
	end
	if Solo.others_here() and S.round_points < CONST.SOLO.REWARD_POINTS then
		return "HOP_WORLD"
	end
	if Read.threat() then
		return "DODGE"
	end
	local doses = Read.doses()
	local warmth = Read.warmth()
	if warmth ~= nil and warmth <= S.min_warmth and doses > 0 then
		return "WARM_UP"
	end
	local energy = Read.boss_energy()
	if doses == 0 or energy == 0 then
		local supply = Solo.supply_state()
		if supply then
			return supply
		end
	end
	if energy == 0 then
		return Solo.between_rounds(me)
	end
	return Solo.round_state(me, energy)
end
return Solo
