--!strict
local Biometrics = require("@lib/main/antiban/biometrics")
local CombatSafeSpot = require("@lib/main/combat_safespot")
local Host = require("@lib/host")
local Log = require("@lib/utils/log")
local Player = require("@lib/main/player")
local Random = require("@lib/utils/math/random")
local SafeSpot = require("@lib/main/safespot")
local Walker = require("@lib/main/walker")
local time = Host.time

type Tile = Host.Tile
type Aims = { { number } }
type Near = { key: string, tile: Tile?, exact: boolean, checked: number?, rejected: Tile? }

export type Context = {
	name: string,
	tiles: { [string]: Tile },
	positions: { [string]: Tile },
	near_reach: number,
	zulrah_size: number,
	near: () -> Near?,
	phase: () -> number,
	target: () -> string?,
	set_target: (key: string) -> (),
	standing_phase: () -> number,
	agreed: (phase: number, part: number) -> string?,
	form_key: (phase: number) -> string?,
	expected_clouds: (phase: number) -> Aims,
	under: (aims: Aims, tile: Tile) -> boolean,
	far_side: (home: Tile, tile: Tile, at: Tile) -> boolean,
	fine_near: (key: string, tile: Tile, aims: Aims) -> boolean,
	clouded: (world: Tile) -> boolean,
	crosses_cloud: (path: { Tile }) -> boolean,
	tile_label: (key: string) -> string,
	world_tile: (scene: Tile) -> Tile,
	scene_tile: () -> Tile,
	server_scene_tile: () -> Tile?,
	arena_path: (goal: Tile) -> { Tile }?,
	can_hit_at: (scene: Tile, at: Tile) -> boolean,
	can_hit_from: (scene: Tile, npc: Host.Npc) -> boolean,
	whip_active: () -> boolean,
	in_safe_reach: (npc: Host.Npc) -> boolean,
	goal: () -> Tile?,
}

export type Fight = {
	stand_tile: (key: string) -> Tile,
	dodge_whip: (dodge: string) -> (),
	may_attack: (npc: Host.Npc, form: string) -> boolean,
	attacked: () -> (),
	step_tiles: (hit: { Tile }, any: { Tile }) -> { Tile },
	takes_dodge: boolean,
}

local WHIP_BAITS: { [string]: boolean } = { red_dodge = true, west_dodge = true }
local REACH_CHOICES = 3
local REACH_RETRY_MS = 1200
local FIRST_KEY = "start"
local BAIT_HOMES: { [string]: string } = { start = "start", red_dodge = "start" }
local MAGMA_ATTACK_TILES: { [string]: Tile } = { start = { x = 56, y = 61 } }
local ATTACK_WALK_MS = 2400
local STRIPS: { [string]: { Tile } } = {
	south_inner = { { x = 50, y = 54 }, { x = 51, y = 54 }, { x = 52, y = 54 }, { x = 53, y = 54 }, { x = 54, y = 54 } },
	south_outer = { { x = 50, y = 52 }, { x = 51, y = 52 }, { x = 52, y = 52 }, { x = 53, y = 52 }, { x = 54, y = 52 } },
	west_inner = {
		{ x = 48, y = 57 },
		{ x = 48, y = 58 },
		{ x = 48, y = 59 },
		{ x = 48, y = 60 },
		{ x = 48, y = 61 },
		{ x = 48, y = 62 },
	},
	west_outer = {
		{ x = 46, y = 55 },
		{ x = 46, y = 56 },
		{ x = 46, y = 57 },
		{ x = 46, y = 58 },
		{ x = 46, y = 59 },
		{ x = 46, y = 60 },
	},
	east_inner = {
		{ x = 56, y = 57 },
		{ x = 56, y = 58 },
		{ x = 56, y = 59 },
		{ x = 56, y = 60 },
		{ x = 56, y = 61 },
		{ x = 56, y = 62 },
	},
	east_outer = {
		{ x = 58, y = 55 },
		{ x = 58, y = 56 },
		{ x = 58, y = 57 },
		{ x = 58, y = 58 },
		{ x = 58, y = 59 },
		{ x = 58, y = 60 },
		{ x = 58, y = 61 },
	},
}
type Stop = { here: true } | { tile: string } | { strip: string }
local ROUTES: { [string]: { Stop } } = {
	["tanzanite middle between"] = { { here = true }, { tile = "east_pillar" }, { strip = "south_inner" } },
}
local FIRST_TILES: { Tile } = { { x = 56, y = 62 }, { x = 56, y = 61 } }

local Melee = {}

function Melee.new(ctx: Context): Fight
	local reach_near: Near? = nil
	local reach_at = 0
	local logged_near: Near? = nil
	local logged_phase = -1
	local magma_near: Near? = nil
	local magma_tile: Tile? = nil
	local walk_until = 0
	local route: { near: Near, stops: { Stop }, index: number, tile: Tile, attacked: boolean }? = nil

	local function reach_tile(home: Tile, at: Tile, aims: Aims): Tile?
		local range = CombatSafeSpot.weapon_range()
		if range == nil then
			return nil
		end
		local span = ctx.zulrah_size // 2 + range
		local me = ctx.scene_tile()
		local tiles: { Tile } = {}
		for dx = -span, span do
			for dy = -span, span do
				local tile = { x = at.x + dx, y = at.y + dy }
				if
					not ctx.far_side(home, tile, at)
					and not ctx.under(aims, tile)
					and not ctx.clouded(ctx.world_tile(tile))
					and ctx.can_hit_at(tile, at)
				then
					table.insert(tiles, tile)
				end
			end
		end
		table.sort(tiles, function(a: Tile, b: Tile): boolean
			return Walker.distance(a, me) < Walker.distance(b, me)
		end)
		local safe: { Tile } = {}
		for _, tile in tiles do
			local path = ctx.arena_path(ctx.world_tile(tile))
			if path and not ctx.crosses_cloud(path) then
				if tile.x == me.x and tile.y == me.y then
					return tile
				end
				table.insert(safe, tile)
				if #safe == REACH_CHOICES then
					break
				end
			end
		end
		return if #safe > 0 then safe[Random.int(1, #safe)] else nil
	end

	local function first_tile(aims: Aims): Tile?
		local me = ctx.scene_tile()
		local open: { Tile } = {}
		for _, tile in FIRST_TILES do
			if not ctx.under(aims, tile) and not ctx.clouded(ctx.world_tile(tile)) then
				if tile.x == me.x and tile.y == me.y then
					return tile
				end
				table.insert(open, tile)
			end
		end
		if #open == 2 and not Biometrics.random_boolean() then
			return open[2]
		end
		return open[1]
	end

	local function stop_tile(stop: Stop): Tile
		local me = ctx.scene_tile()
		if (stop :: any).here then
			return me
		end
		local key = (stop :: any).tile
		if key then
			return ctx.tiles[key]
		end
		local open: { Tile } = {}
		for _, tile in STRIPS[(stop :: any).strip] do
			if not ctx.clouded(ctx.world_tile(tile)) then
				table.insert(open, tile)
			end
		end
		return if #open > 0 then open[Random.int(1, #open)] else STRIPS[(stop :: any).strip][1]
	end

	local function route_tile(near: Near): Tile?
		local phase = ctx.standing_phase()
		local form, where, word = ctx.agreed(phase, 1), ctx.agreed(phase, 2), ctx.agreed(phase, 3)
		local stops = if form and where and word then ROUTES[`{form} {where} {word}`] else nil
		if stops == nil then
			return nil
		end
		local r = route
		if r == nil or r.near ~= near or r.stops ~= stops then
			r = { near = near, stops = stops, index = 1, tile = stop_tile(stops[1]), attacked = false }
			route = r
			Log.log(ctx.name, `Phase {phase} route: holding {r.tile.x},{r.tile.y}`)
		end
		if r.attacked and r.index < #r.stops and Player.is_animating() then
			r.index += 1
			r.tile, r.attacked = stop_tile(r.stops[r.index]), false
			Log.log(ctx.name, `Phase {phase} route: on to {r.tile.x},{r.tile.y}`)
		end
		return r.tile
	end

	local function near_tile(key: string): Tile
		local home = ctx.tiles[key]
		local phase = ctx.standing_phase()
		local where = ctx.agreed(phase, 2)
		local at = where and ctx.positions[where]
		local aims = ctx.expected_clouds(phase)
		if key == FIRST_KEY and phase == 1 then
			local first = first_tile(aims)
			if first then
				Log.log(ctx.name, `Phase 1 on {ctx.tile_label(key)}: standing on {first.x},{first.y}`)
				return first
			end
		end
		local hit: { Tile } = {}
		if at then
			for dx = -ctx.near_reach, ctx.near_reach do
				for dy = -ctx.near_reach, ctx.near_reach do
					local tile = { x = home.x + dx, y = home.y + dy }
					local world = ctx.world_tile(tile)
					if
						not ctx.far_side(home, tile, at)
						and not ctx.under(aims, tile)
						and not ctx.clouded(world)
						and ctx.arena_path(world) ~= nil
						and ctx.can_hit_at(tile, at)
					then
						table.insert(hit, tile)
					end
				end
			end
		end
		local me = ctx.scene_tile()
		for _, tile in hit do
			if tile.x == me.x and tile.y == me.y then
				Log.log(ctx.name, `Near {ctx.tile_label(key)} already: staying on {me.x},{me.y}`)
				return tile
			end
		end
		local form = ctx.form_key(phase)
		if #hit == 0 and at and form and form ~= "magma" then
			local reach = reach_tile(home, at, aims)
			if reach then
				Log.log(
					ctx.name,
					`Zulrah {where} can't be hit near {ctx.tile_label(key)}: walking to {reach.x},{reach.y}`
				)
				return reach
			end
		end
		local pick = if #hit > 0 then hit[Random.int(1, #hit)] else home
		Log.log(ctx.name, `Near {ctx.tile_label(key)}: standing on {pick.x},{pick.y}`)
		return pick
	end

	local function stand_tile(key: string): Tile
		local home = ctx.tiles[key]
		local near = ctx.near()
		local form = ctx.form_key(ctx.standing_phase())
		local chase = form ~= nil and form ~= "magma"
		if near ~= magma_near then
			magma_near, magma_tile, walk_until = near, nil, 0
		end
		if chase and near and near.key == key then
			local tile = route_tile(near)
			if tile then
				return tile
			end
		end
		if magma_tile and near and near.key == key and form == "magma" then
			local me = ctx.scene_tile()
			if time() < walk_until and (me.x ~= magma_tile.x or me.y ~= magma_tile.y) then
				return me
			end
			walk_until = 0
			return magma_tile
		end
		if near == nil or near.key ~= key or (near.exact and not chase) then
			return home
		end
		local magma_reach = form == "magma" and not WHIP_BAITS[key]
		if not chase and not magma_reach then
			near.exact = true
			if near.tile and (near.tile.x ~= home.x or near.tile.y ~= home.y) then
				Log.log(ctx.name, `A red phase: on {ctx.tile_label(key)} itself`)
			end
			return home
		end
		local kept = near.tile
		if kept == nil then
			local tile = near_tile(key)
			near.tile = tile
			return tile
		end
		local phase = ctx.standing_phase()
		local where = ctx.agreed(phase, 2)
		if where and near.checked ~= phase then
			near.checked = phase
			local at = ctx.positions[where]
			if ctx.far_side(home, kept, at) or not ctx.can_hit_at(kept, at) then
				Log.log(
					ctx.name,
					`Near {ctx.tile_label(key)}: Zulrah {where} can't be hit from {kept.x},{kept.y}, picking again`
				)
				near.rejected = kept
				local tile = near_tile(key)
				near.tile = tile
				return tile
			end
		end
		local aims = ctx.expected_clouds(phase)
		local me = ctx.scene_tile()
		local rejected = near.rejected
		local at = where and ctx.positions[where]
		if reach_near ~= near then
			reach_near, reach_at = near, 0
		end
		if chase and at and not ctx.can_hit_at(kept, at) and time() >= reach_at then
			reach_at = time() + REACH_RETRY_MS
			local reach = reach_tile(home, at, aims)
			if reach then
				Log.log(ctx.name, `Zulrah {where} can be reached now: walking to {reach.x},{reach.y}`)
				near.tile = reach
				return reach
			end
		end
		if
			(me.x ~= kept.x or me.y ~= kept.y)
			and not (rejected and me.x == rejected.x and me.y == rejected.y)
			and ctx.fine_near(key, me, aims)
			and at ~= nil
			and ctx.can_hit_at(me, at)
		then
			Log.log(ctx.name, `Near {ctx.tile_label(key)}: now on {me.x},{me.y}, fine to stay`)
			near.tile = me
			return me
		elseif ctx.under(aims, kept) then
			local tile = near_tile(key)
			near.tile = tile
			return tile
		end
		return kept
	end

	local function whipped_target(): boolean
		local scene, tile = ctx.server_scene_tile(), ctx.goal()
		return scene ~= nil and tile ~= nil and scene.x == tile.x and scene.y == tile.y
	end

	local function dodge_whip(dodge: string)
		if not whipped_target() then
			Log.log(ctx.name, `Whip: not aimed at {ctx.tile_label(ctx.target() or dodge)}, staying on it`)
			return
		end
		Log.log(ctx.name, `Whip: dodging to {ctx.tile_label(dodge)}`)
		ctx.set_target(dodge)
	end

	local function note_out_of_reach(npc: Host.Npc)
		local near = ctx.near()
		if logged_near == near and logged_phase == ctx.phase() then
			return
		end
		logged_near, logged_phase = near, ctx.phase()
		local scene = ctx.server_scene_tile()
		local chaser = SafeSpot.chaser(npc, ctx.zulrah_size)
		local origin = ctx.world_tile({ x = 0, y = 0 })
		local from = if scene then `{scene.x},{scene.y}` else "?"
		Log.log(
			ctx.name,
			`Melee: Zulrah ({chaser.x - origin.x},{chaser.y - origin.y}, size {chaser.size}) isn't in safe reach of {from} (range {CombatSafeSpot.weapon_range() or "?"})`
		)
	end

	local function may_attack(npc: Host.Npc, form: string): boolean
		local r = route
		if r and r.near == ctx.near() and form ~= "magma" then
			local me = ctx.scene_tile()
			return me.x == r.tile.x and me.y == r.tile.y and not ctx.clouded(ctx.world_tile(me))
		end
		local target = ctx.target()
		local home = if form == "magma" and target then BAIT_HOMES[target] else nil
		if home and ctx.whip_active() then
			return false
		end
		if home and target and target ~= home then
			local me, on, tile = ctx.scene_tile(), ctx.tiles[target], MAGMA_ATTACK_TILES[home]
			return me.x == on.x
				and me.y == on.y
				and not ctx.clouded(ctx.world_tile(tile))
				and ctx.can_hit_from(tile, npc)
		end
		if ctx.in_safe_reach(npc) then
			return true
		end
		note_out_of_reach(npc)
		return false
	end

	local function attacked()
		local r = route
		if r and r.near == ctx.near() then
			r.attacked = true
		end
		local target = ctx.target()
		local home = if target then BAIT_HOMES[target] else nil
		if home == nil or target == home or ctx.form_key(ctx.phase()) ~= "magma" then
			return
		end
		local tile = MAGMA_ATTACK_TILES[home]
		magma_near, magma_tile, walk_until = ctx.near(), tile, time() + ATTACK_WALK_MS
		Log.log(ctx.name, `Attacked from {ctx.tile_label(target :: string)}: walking in to {tile.x},{tile.y}`)
		ctx.set_target(home)
	end

	local function step_tiles(hit: { Tile }, _any: { Tile }): { Tile }
		return hit
	end

	return {
		stand_tile = stand_tile,
		dodge_whip = dodge_whip,
		may_attack = may_attack,
		attacked = attacked,
		step_tiles = step_tiles,
		takes_dodge = false,
	}
end

return Melee
