--!strict
local Host = require("@lib/host")
local Log = require("@lib/utils/log")
local Random = require("@lib/utils/math/random")

type Tile = Host.Tile
type Aims = { { number } }
type Near = { key: string, tile: Tile?, exact: boolean, checked: number?, rejected: Tile? }

export type Context = {
	name: string,
	tiles: { [string]: Tile },
	positions: { [string]: Tile },
	near_reach: number,
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
	tile_label: (key: string) -> string,
	world_tile: (scene: Tile) -> Tile,
	scene_tile: () -> Tile,
	arena_path: (goal: Tile) -> { Tile }?,
	can_hit_at: (scene: Tile, at: Tile) -> boolean,
	attack_window: (form: string) -> boolean,
}

export type Fight = {
	stand_tile: (key: string) -> Tile,
	dodge_whip: (dodge: string) -> (),
	may_attack: (npc: Host.Npc, form: string) -> boolean,
	attacked: () -> (),
	step_tiles: (hit: { Tile }, any: { Tile }) -> { Tile },
	takes_dodge: boolean,
}

local Ranged = {}

function Ranged.new(ctx: Context): Fight
	local function near_tile(key: string): Tile
		local home = ctx.tiles[key]
		local phase = ctx.standing_phase()
		local where = ctx.agreed(phase, 2)
		local at = where and ctx.positions[where]
		local aims = ctx.expected_clouds(phase)
		local any: { Tile }, hit: { Tile } = {}, {}
		for dx = -ctx.near_reach, ctx.near_reach do
			for dy = -ctx.near_reach, ctx.near_reach do
				local tile = { x = home.x + dx, y = home.y + dy }
				local world = ctx.world_tile(tile)
				local away = at ~= nil and ctx.far_side(home, tile, at)
				if
					not away
					and not ctx.under(aims, tile)
					and not ctx.clouded(world)
					and ctx.arena_path(world) ~= nil
				then
					table.insert(any, tile)
					if at and ctx.can_hit_at(tile, at) then
						table.insert(hit, tile)
					end
				end
			end
		end
		local from = if #hit > 0 then hit else any
		local me = ctx.scene_tile()
		for _, tile in from do
			if tile.x == me.x and tile.y == me.y then
				Log.log(ctx.name, `Near {ctx.tile_label(key)} already: staying on {me.x},{me.y}`)
				return tile
			end
		end
		local pick = if #from > 0 then from[Random.int(1, #from)] else home
		Log.log(ctx.name, `Near {ctx.tile_label(key)}: standing on {pick.x},{pick.y}`)
		return pick
	end

	local function stand_tile(key: string): Tile
		local home = ctx.tiles[key]
		local near = ctx.near()
		if near == nil or near.key ~= key or near.exact then
			return home
		end
		local form = ctx.form_key(ctx.standing_phase())
		if form == nil or form == "magma" then
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
		if
			(me.x ~= kept.x or me.y ~= kept.y)
			and not (rejected and me.x == rejected.x and me.y == rejected.y)
			and ctx.fine_near(key, me, aims)
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

	local function dodge_whip(dodge: string)
		Log.log(ctx.name, `Whip: dodging to {ctx.tile_label(dodge)}`)
		ctx.set_target(dodge)
	end

	local function may_attack(_npc: Host.Npc, form: string): boolean
		return ctx.attack_window(form)
	end

	local function attacked() end

	local function step_tiles(hit: { Tile }, any: { Tile }): { Tile }
		return if #hit > 0 then hit else any
	end

	return {
		stand_tile = stand_tile,
		dodge_whip = dodge_whip,
		may_attack = may_attack,
		attacked = attacked,
		step_tiles = step_tiles,
		takes_dodge = true,
	}
end

return Ranged
