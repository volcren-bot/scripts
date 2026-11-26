--!strict
local Log = require("@volcren/log")
local Random = require("@volcren/random")
local WorldSwitcher = require("@volcren/worldswitcher")

local Hop = {}

Hop.SETTLE_MS = { 1200, 2400 }

local worlds: { number } = {}

local function members_worlds(): { number }
	local found: { number } = {}
	if WorldSwitcher.open(true) then
		for _, row in ipairs(WorldSwitcher.rows() or {}) do
			if row.members and row.available and (row.activity == nil or row.activity == "-") then
				table.insert(found, row.world)
			end
		end
	end
	return found
end

function Hop.away(name: string, why: string): boolean
	Log.log(name, `{why}, hopping worlds`)
	if #worlds == 0 then
		worlds = members_worlds()
	end
	if not WorldSwitcher.random(worlds) then
		Log.log(name, "Couldn't hop")
		return false
	end
	Log.log(name, `Now on world {WorldSwitcher.current() or "?"}`)
	Random.sleep(Hop.SETTLE_MS[1], Hop.SETTLE_MS[2])
	return true
end

return Hop
