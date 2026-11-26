--!strict
local Antiban = require("@volcren/antiban")
local Host = require("@volcren/host")
local Random = require("@volcren/random")

local Idle = {}

Idle.GAP_MS = { 3000, 9000 }

local next_at = 0

function Idle.wait(sleep_ms: { number })
	if Host.time() >= next_at and Antiban.do_async_tasks("game") then
		next_at = Host.time() + Random.int(Idle.GAP_MS[1], Idle.GAP_MS[2])
	end
	Random.sleep(sleep_ms[1], sleep_ms[2])
end

return Idle
