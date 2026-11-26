--!strict
local Biometrics = require("@volcren/biometrics")
local Host = require("@volcren/host")
local sleep = Host.sleep
local time = Host.time
type Loc = Host.Loc
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Objects = require("@volcren/objects")
local Walker = require("@volcren/walker")

local Logs = {}

Logs.NAME = "Logs"
Logs.OPTIONS = { "Chop down", "Chop-down", "Cut" }
Logs.RANGE = 30
Logs.TIMEOUT_MS = 20000
Logs.POLL_MS = 100
Logs.MAX_GOAL = 4

function Logs.goal(minimum: number): number
	local mode = 1 + (Logs.MAX_GOAL - 1) * Biometrics.get_probability(Biometrics.PATTERN)
	return Biometrics.random_mode_integer(mode, minimum, Logs.MAX_GOAL)
end

function Logs.count(): number
	return Inventory.count_ex(Logs.NAME) or 0
end

function Logs.tree(me: Host.Tile): (Loc?, string?)
	local found: { Loc } = {}
	local ids: { number } = {}
	for _, loc in ipairs(Objects.find() or {}) do
		if Walker.distance(me, loc) <= Logs.RANGE then
			table.insert(found, loc)
			table.insert(ids, loc.id)
		end
	end
	local views = if #ids > 0 then Host.loc_shown(ids) else nil
	local best: Loc? = nil
	local best_option: string? = nil
	local best_d = math.huge
	for i, loc in ipairs(found) do
		local view = views and views[i]
		if view then
			for _, option in ipairs(Logs.OPTIONS) do
				local d = Walker.distance(me, loc)
				if table.find(view.actions, option) and d < best_d then
					best, best_option, best_d = loc, option, d
				end
			end
		end
	end
	return best, best_option
end

function Logs.chop(name: string, stop: () -> boolean): (boolean, string?)
	local me = Walker.position()
	if me == nil then
		return false, nil
	end
	local tree, option = Logs.tree(me)
	if tree == nil or option == nil then
		return false, "no trees to cut logs from"
	end
	Log.log(name, `Cutting logs from the {(tree :: Loc).name or "tree"}`)
	local before = Logs.count()
	if not Objects.approach(tree :: Loc, option :: string) then
		return false, nil
	end
	local deadline = time() + Logs.TIMEOUT_MS
	repeat
		if Logs.count() > before or stop() then
			return true, nil
		end
		sleep(Logs.POLL_MS)
	until time() >= deadline
	return Logs.count() > before, nil
end

return Logs
