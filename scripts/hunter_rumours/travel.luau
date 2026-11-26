--!strict
local Random = require("@volcren/random")
local Transports = require("@volcren/transports")
local Walker = require("@volcren/walker")

export type Tile = { x: number, y: number, plane: number }

local Travel = {}

Travel.WHISTLE_MIN_TILES = 150
Travel.SPREAD = { 2, 4 }
Travel.SPREAD_TRIES = 12
Travel.SPREAD_DETOUR = 3

function Travel.spread(base: Tile): Tile
	local radius = Random.int(Travel.SPREAD[1], Travel.SPREAD[2])
	for _ = 1, Travel.SPREAD_TRIES do
		local tile =
			{ x = base.x + Random.int(-radius, radius), y = base.y + Random.int(-radius, radius), plane = base.plane }
		local path = Walker.path(tile, base)
		if path and #path <= radius * Travel.SPREAD_DETOUR then
			return tile
		end
	end
	return base
end

function Travel.ticks(from: Tile, goal: Tile): number
	local choice = Transports.choose(from, goal, { min_saving_ticks = 0 })
	if choice then
		return choice.ticks
	end
	return Transports.walk_ticks(from, goal)
end

function Travel.walk(goal: Tile, near: number, arrived: (() -> boolean)?): (boolean, string?)
	local me = Walker.position()
	local options: Walker.WalkOptions = { near = near, plane = goal.plane }
	if arrived then
		options.on_step = function(): boolean?
			if arrived() then
				return false
			end
			return nil
		end
	end
	if me and Walker.distance(me, goal) < Travel.WHISTLE_MIN_TILES then
		options.transports = { exclude = { ["Quetzal whistle"] = true } }
	end
	local ok, walked = pcall(function(): boolean
		return Walker.walk(goal, options)
	end)
	if arrived and arrived() then
		return true, nil
	end
	if not ok then
		return false, tostring(walked)
	end
	return walked, nil
end

return Travel
