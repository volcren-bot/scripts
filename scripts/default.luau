--!strict
local Host = require("../lib/host")
local game_state = Host.game_state
local Login = require("../lib/main/interfaces/login/login")
local Stats = require("../lib/main/interfaces/gametabs/stats")

local ok = Login.sign_in()
assert(ok, "couldn't sign in")
local state = game_state()
print("in game, top-level interface", state.root_interface)

local hp: number? = nil
for _, skill in ipairs(state.skills or {}) do
	if skill.name == "Hitpoints" then
		hp = skill.level
	end
end

print("total xp:", Stats.total_experience(state.skills))
print("hp:", hp)
