--!strict
local Walker = require("@volcren/walker")

export type Tile = { x: number, y: number, plane: number }

local Travel = {}

Travel.WHISTLE_MIN_TILES = 150

function Travel.walk(goal: Tile, near: number): (boolean, string?)
	local me = Walker.position()
	local options: Walker.WalkOptions = { near = near, plane = goal.plane }
	if me and Walker.distance(me, goal) < Travel.WHISTLE_MIN_TILES then
		options.transports = { exclude = { quetzal_whistle = true } }
	end
	local ok, walked = pcall(function(): boolean
		return Walker.walk(goal, options)
	end)
	if not ok then
		return false, tostring(walked)
	end
	return walked, nil
end

return Travel
