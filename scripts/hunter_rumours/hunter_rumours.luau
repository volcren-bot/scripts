--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local Chat = require("@lib/main/interfaces/chatbox/chat")
local GameState = require("@lib/main/game_state")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Position = require("@lib/main/position")
local Quetzal = require("@lib/main/interfaces/mainscreen/quetzal")
local Random = require("@lib/utils/math/random")
local RumourLocations = require("./rumour_locations")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Walker = require("@lib/main/walker")

local NAME = "Hunter Rumours"

local CONST = {
	REPORT = { counters_key = "" },
	MAPSQUARE = { HUNTER_GUILD = 6191, HUNTER_GUILD_BASEMENT = 6291 },
	PLANE = { GROUND = 0, TOP = 2 },
	TILE = { QUETZAL_LANDING = { x = 1557, y = 3046 } },
	LOC = { ROPE_UP = 51643, ROPE_DOWN = 51644, BANK_CHEST = 53015 },
	NPC = { PITRI = 13135 },
	OPTION = { CLIMB_UP = "Climb-up", CLIMB_DOWN = "Climb-down", RECHARGE = "Recharge-whistle" },
	CLIMB_TIMEOUT_MS = 8000,
	RECHARGE_SETTLE_MS = { 1200, 2000 },
	RUMOUR = {
		OPTION = "Rumour",
		CURRENT = "^Your current rumour target is an? (.-)%. You'll need to bring back its (.-)%. (.-) was the source of the rumour%.",
		RARE_PIECE = "You find a rare piece of the creature! You should take it back to the Hunter Guild.",
		HANDED_IN = { "would you like another rumour?", "here's your reward.", "another one done?" },
		TIMEOUT_MS = 2400,
	},
	MASTERS = {
		{ npc = 13121, name = "Gilman", tier = "novice" },
		{ npc = 13122, name = "Ornus", tier = "adept" },
		{ npc = 13123, name = "Cervus", tier = "adept" },
		{ npc = 13124, name = "Aco", tier = "expert" },
		{ npc = 13125, name = "Teco", tier = "expert" },
		{ npc = 13126, name = "Wolf", tier = "master" },
	},
	RUMOURS = {
		{ prey = "tropical wagtail", part = 29222, trap = "snare", level = 19 },
		{ prey = "wild kebbit", part = 29223, trap = "deadfall", level = 23 },
		{ prey = "sapphire glacialis", part = 29224, trap = "butterfly net", level = 25 },
		{ prey = "swamp lizard", part = 29225, trap = "net trap", level = 29 },
		{ prey = "spined larupia", part = 29226, trap = "pitfall", level = 31 },
		{ prey = "barb-tailed kebbit", part = 29223, trap = "deadfall", level = 33 },
		{ prey = "snowy knight", part = 29227, trap = "butterfly net", level = 35 },
		{ prey = "prickly kebbit", part = 29223, trap = "deadfall", level = 37 },
		{ prey = "embertailed jerboa", part = 29228, trap = "box trap", level = 39 },
		{ prey = "horned graahk", part = 29229, trap = "pitfall", level = 41 },
		{ prey = "spotted kebbit", part = 29223, trap = "falconry", level = 43 },
		{ prey = "black warlock", part = 29230, trap = "butterfly net", level = 45 },
		{ prey = "orange salamander", part = 29231, trap = "net trap", level = 47 },
		{ prey = "razor-backed kebbit", part = 29223, trap = "noose", level = 49 },
		{ prey = "sabre-toothed kebbit", part = 29223, trap = "deadfall", level = 51 },
		{ prey = "grey chinchompa", part = 29221, trap = "box trap", level = 53 },
		{ prey = "sabre-toothed kyatt", part = 29232, trap = "pitfall", level = 53 },
		{ prey = "dark kebbit", part = 29223, trap = "falconry", level = 57 },
		{ prey = "pyre fox", part = 29233, trap = "deadfall", level = 57 },
		{ prey = "red salamander", part = 29234, trap = "net trap", level = 59 },
		{ prey = "wyrmscraig goat", part = 33835, trap = "goat pit", level = 60 },
		{ prey = "carnivorous chinchompa", part = 29235, trap = "box trap", level = 63 },
		{ prey = "red chinchompa", part = 29235, trap = "box trap", level = 63 },
		{ prey = "sunlight moth", part = 29237, trap = "butterfly net", level = 65 },
		{ prey = "dashing kebbit", part = 29223, trap = "falconry", level = 69 },
		{ prey = "sunlight antelope", part = 29236, trap = "pitfall", level = 72 },
		{ prey = "moonlight moth", part = 29240, trap = "butterfly net", level = 75 },
		{ prey = "tecu salamander", part = 29238, trap = "net trap", level = 79 },
		{ prey = "herbiboar", part = 29239, trap = "herbiboar", level = 80 },
		{ prey = "moonlight antelope", part = 29241, trap = "pitfall", level = 91 },
	},
	WHISTLE_MAX_CHARGES = { [29271] = 5, [29273] = 20, [29275] = 50, [33120] = 50 },
	RECHARGE_AT = { MIN = 0.1, MAX = 0.3 },
	RECHARGE_ITEMS = {
		{ id = 29104, name = "Raw wild kebbit", charges = 1 },
		{ id = 29122, name = "Raw larupia", charges = 1 },
		{ id = 29101, name = "Raw barb-tailed kebbit", charges = 1 },
		{ id = 29119, name = "Raw graahk", charges = 2 },
		{ id = 29125, name = "Raw kyatt", charges = 2 },
		{ id = 29110, name = "Raw pyre fox", charges = 2 },
		{ id = 29116, name = "Raw sunlight antelope", charges = 3 },
		{ id = 29107, name = "Raw dashing kebbit", charges = 3 },
		{ id = 29113, name = "Raw moonlight antelope", charges = 3 },
		{ id = 29307, name = "Quetzal feed", charges = 1 },
	},
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

local CONFIG = {
	max_runs = 0,
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local stats = { runs = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	min_charges: number?,
	rumour: Rumour?,
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	min_charges = nil,
	rumour = nil,
	skip = {},
}

type Rumour = {
	prey: string,
	part: number?,
	part_word: string,
	trap: string?,
	level: number?,
	master: string,
	master_npc: number?,
	areas: { RumourLocations.Area }?,
}

type Snapshot = {
	state: ClientState,
	tick: number,
}

local snap: Snapshot = nil :: any

type State =
	"LOADING"
	| "LOGIN"
	| "GUILD_GROUND"
	| "CLIMB_UP_TO_RECHARGE"
	| "BANK_FOR_RECHARGE"
	| "RECHARGE_WHISTLE"
	| "CLIMB_DOWN"
	| "GUILD_DESCEND"
	| "GUILD_BASEMENT"
	| "AWAY"

local report = StatsReport.new()

function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
end

function Read.mapsquare(state: ClientState): number?
	local p = state.position
	if p == nil then
		return nil
	end
	return Position.new(p.local_x, p.local_y, p.x, p.y, p.plane):chunk():id()
end

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.refresh_snapshot(state: ClientState): boolean
	if state.position == nil then
		return false
	end
	snap = {
		state = state,
		tick = Read.current_tick(state),
	}
	return true
end

function Game.sign_in(): boolean
	Log.log(NAME, "Logging in")
	local ok = Login.sign_in()
	if not ok then
		Log.log(NAME, "Login failed")
		sleep(5000)
		return false
	end
	return true
end

function Game.ensure_logged_in(s: ClientState): boolean
	if s.game_state == GameState.LOGGED_IN and s.position ~= nil then
		return true
	end
	if Read.scene_loading(s) then
		sleep(100)
		return false
	end
	return Game.sign_in()
end

function Game.setup_antiban()
	Biometrics.setup_player()
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Total" }
	AntibanTasks.apply_zoom_range()
	AntibanTasks.apply_pitch_range()
	Antiban.add_task(AntibanTasks.handle_randoms, 30 * SECOND, 0.33)
	Antiban.add_task(AntibanTasks.adjust_camera, 3 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_camera_task, 7 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_mouse_task, 8 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_chat_task, 9 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.lose_focus, 10 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.random_game_tab_task, 12 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.hover_skills, 18 * MINUTE, 0.33)
	Antiban.add_task(AntibanTasks.adjust_minimap_zoom, 13 * MINUTE, 0.33)

	Antiban.add_walk_task(AntibanTasks.adjust_camera, 2 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_chat_tab, 3 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.small_camera_rotation, 4 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_right_click, 5 * MINUTE, 0.33)
	Antiban.add_walk_task(AntibanTasks.random_tab, 6 * MINUTE, 0.33)

	Antiban.add_async_task(AntibanTasks.tiny_camera_rotation, 25 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_pitch_change, 45 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.tiny_zoom_change, 60 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_camera_rotation, 70 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.small_random_mouse, 40 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_npc, 90 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.hover_random_player, 120 * SECOND, 0.4, "game")
	Antiban.add_async_task(AntibanTasks.random_tab, 90 * SECOND, 0.4, "game")

	Antiban.add_async_task(AntibanTasks.random_tab, 40 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_tab, 70 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_skills, 100 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.random_chat_tab, 50 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.toggle_chat_tab, 80 * SECOND, 0.4, "outside")
	Antiban.add_async_task(AntibanTasks.hover_random_ground_item, 120 * SECOND, 0.4, "outside")

	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

function Game.roll_min_charges()
	local max = Read.whistle_max_charges()
	if max == nil then
		S.min_charges = nil
		Log.log(NAME, "No quetzal whistle held, not tracking its charges")
		return
	end
	local at = CONST.RECHARGE_AT
	S.min_charges = math.floor(Random.float(at.MIN * max, at.MAX * max) + 0.5)
	Log.log(NAME, `Recharging the whistle at {S.min_charges} of {max} charges`)
end

function Game.wait_plane(from: number?): boolean
	local deadline = time() + CONST.CLIMB_TIMEOUT_MS
	repeat
		local p = game_state().position
		if p ~= nil and p.plane ~= from then
			return true
		end
		sleep(100)
	until time() >= deadline
	return false
end

function Game.climb(rope_id: number, option: string): boolean
	local me = Walker.position()
	local p = game_state().position
	local rope = if me then Objects.nearest(rope_id, me) else nil
	if rope == nil or p == nil then
		Log.log(NAME, `No rope {rope_id} around`)
		return false
	end
	return Objects.interact(rope, option) and Game.wait_plane(p.plane)
end

function Game.withdraw_recharge_items(): number
	local max = Read.whistle_max_charges()
	if max == nil then
		return 0
	end
	local needed = max - (Quetzal.charges(true) or 0)
	local free = Inventory.free_slots() or 0
	local gained = 0
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		if needed <= 0 or free <= 0 then
			break
		end
		local stock = Bankmain.count_ex(item.id) or 0
		if stock > 0 then
			local take = math.min(stock, math.ceil(needed / item.charges), free)
			local before = Inventory.count_ex(item.id) or 0
			if Bankmain.withdraw(item.id, take, false) then
				local taken = (Inventory.count_ex(item.id) or before) - before
				Log.log(NAME, `Withdrew {taken} {item.name}`)
				needed -= taken * item.charges
				free -= taken
				gained += taken * item.charges
			end
		end
	end
	return gained
end

function Game.bank_for_recharge(): boolean
	if not Bankmain.is_open() then
		local me = Walker.position()
		local chest = if me then Objects.nearest(CONST.LOC.BANK_CHEST, me) else nil
		if chest == nil or not Bankmain.open({ loc = chest }) then
			return false
		end
	end
	local gained = Game.withdraw_recharge_items()
	if gained == 0 and not Read.has_recharge_items() then
		Log.log(NAME, "No meat or quetzal feed in the bank to recharge the whistle with, stopping the script")
		S.finished = true
		return false
	end
	Log.log(NAME, `Took out enough for {gained} charges`)
	return Bankmain.close()
end

function Game.recharge_whistle(): boolean
	local me = Walker.position()
	local pitri = if me then Npcs.nearest(CONST.NPC.PITRI, me) else nil
	if pitri == nil then
		Log.log(NAME, "Soar Leader Pitri isn't around")
		return false
	end
	local before = Quetzal.charges(true) or 0
	if not Npcs.interact(pitri, CONST.OPTION.RECHARGE) then
		return false
	end
	Random.sleep(CONST.RECHARGE_SETTLE_MS[1], CONST.RECHARGE_SETTLE_MS[2])
	local after = Quetzal.charges()
	if after == nil or after <= before then
		Log.log(NAME, `Recharging didn't add charges ({before} -> {after or "?"})`)
		return false
	end
	Log.log(NAME, `Whistle recharged: {before} -> {after}`)
	Game.roll_min_charges()
	return true
end

function Read.parse_rumour(text: string): Rumour?
	local prey, part_word, master = string.match(text, CONST.RUMOUR.CURRENT)
	if prey == nil or part_word == nil or master == nil then
		return nil
	end
	prey = string.lower(prey)
	local rumour: Rumour = { prey = prey, part_word = part_word, master = master, areas = RumourLocations[prey] }
	for _, r in ipairs(CONST.RUMOURS) do
		if r.prey == prey then
			rumour.part, rumour.trap, rumour.level = r.part, r.trap, r.level
			break
		end
	end
	for _, m in ipairs(CONST.MASTERS) do
		if string.lower(m.name) == string.lower(master) then
			rumour.master_npc = m.npc
			break
		end
	end
	return rumour
end

function Game.read_rumour(): Rumour?
	local slot = Quetzal.whistle_slot()
	if slot == nil then
		Log.log(NAME, "No quetzal whistle held to read the rumour with")
		return nil
	end
	local last = Chat.last_message()
	local seen = if last then last.uid else -1
	if not Inventory.interact_slot(slot, CONST.RUMOUR.OPTION) then
		return nil
	end
	local unknown: { string } = {}
	local deadline = time() + CONST.RUMOUR.TIMEOUT_MS
	repeat
		for _, m in ipairs(Chat.new_messages(seen, { Chat.MessageType.GAME }) or {}) do
			seen = m.uid
			local rumour = Read.parse_rumour(m.text)
			if rumour ~= nil then
				S.rumour = rumour
				Log.log(
					NAME,
					`Rumour: {rumour.prey} ({rumour.trap or "unknown trap"}), bring its {rumour.part_word} to {rumour.master}`
				)
				if rumour.part == nil or rumour.master_npc == nil or rumour.areas == nil then
					Log.log(NAME, `Rumour not fully known: {m.text}`)
				end
				return rumour
			end
			table.insert(unknown, m.text)
		end
		sleep(Quetzal.POLL_MS)
	until time() >= deadline
	Log.log(NAME, `No rumour read from the whistle{if #unknown > 0 then ": " .. table.concat(unknown, " / ") else ""}`)
	return nil
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end

	local charges = Quetzal.charges(true)
	Log.log(NAME, if charges ~= nil then `Quetzal whistle charges: {charges}` else "No quetzal whistle charges read")
	Game.roll_min_charges()
	Game.read_rumour()
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

function Loop.report_counters()
	local key = `{stats.runs}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "runs", label = "Runs", value = stats.runs },
		{ id = "failures", label = "Failures", value = stats.failures, percent_of = "runs" },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no xp for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	elseif CONFIG.max_runs > 0 and stats.runs >= CONFIG.max_runs then
		Log.log(NAME, `Reached {CONFIG.max_runs} runs, stopping the script`)
		S.finished = true
		return
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.finished = true
	end
end

function Loop.antiban_began()
	S.antiban_began_at = time()
end

function Loop.antiban_ended()
	S.last_progress_at += time() - S.antiban_began_at
end

function Loop.hook_antiban_timeouts()
	Antiban.on_start_task, Antiban.on_finish_task = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_break, Antiban.on_finish_break = Loop.antiban_began, Loop.antiban_ended
	Antiban.on_start_sleep, Antiban.on_finish_sleep = Loop.antiban_began, Loop.antiban_ended
end

function Read.whistle_max_charges(): number?
	for _, item in ipairs(Host.item_container(Quetzal.INVENTORY) or {}) do
		local max = CONST.WHISTLE_MAX_CHARGES[item.id]
		if max ~= nil then
			return max
		end
	end
	return nil
end

function Read.needs_recharge(): boolean
	if S.min_charges == nil then
		return false
	end
	local charges = Quetzal.charges(true)
	return charges ~= nil and charges <= S.min_charges
end

function Read.has_recharge_items(): boolean
	local ids: { number } = {}
	for _, item in ipairs(CONST.RECHARGE_ITEMS) do
		table.insert(ids, item.id)
	end
	return Inventory.contains_any(ids)
end

function Read.location_state(s: ClientState): State
	local mapsquare = Read.mapsquare(s)
	if mapsquare == CONST.MAPSQUARE.HUNTER_GUILD then
		local plane = s.position and s.position.plane
		if plane == CONST.PLANE.GROUND then
			if not Read.needs_recharge() then
				return "GUILD_GROUND"
			end
			return if Read.has_recharge_items() then "CLIMB_UP_TO_RECHARGE" else "BANK_FOR_RECHARGE"
		elseif plane == CONST.PLANE.TOP then
			return if Read.needs_recharge() and Read.has_recharge_items() then "RECHARGE_WHISTLE" else "CLIMB_DOWN"
		else
			return "GUILD_DESCEND"
		end
	elseif mapsquare == CONST.MAPSQUARE.HUNTER_GUILD_BASEMENT then
		return "GUILD_BASEMENT"
	else
		return "AWAY"
	end
end

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	local state = Read.location_state(snap.state)
	if skipped[state] then
		return "LOADING"
	end
	return state
end

function Handler.outcome(ok: boolean)
	if ok then
		S.failures_in_row = 0
	else
		S.failures_in_row += 1
		stats.failures += 1
	end
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	GUILD_GROUND = function() end,
	CLIMB_UP_TO_RECHARGE = function()
		Handler.outcome(Game.climb(CONST.LOC.ROPE_UP, CONST.OPTION.CLIMB_UP))
	end,
	BANK_FOR_RECHARGE = function()
		Handler.outcome(Game.bank_for_recharge())
	end,
	RECHARGE_WHISTLE = function()
		Handler.outcome(Game.recharge_whistle())
	end,
	CLIMB_DOWN = function()
		Handler.outcome(Game.climb(CONST.LOC.ROPE_DOWN, CONST.OPTION.CLIMB_DOWN))
	end,
	GUILD_DESCEND = function()
		Log.log(NAME, "Going down to the ground floor")
		Handler.outcome(Walker.walk(CONST.TILE.QUETZAL_LANDING, { plane = CONST.PLANE.GROUND, near = 3 }))
	end,
	GUILD_BASEMENT = function() end,
	AWAY = function() end,
}
local last_stray_at = 0
local function close_stray()
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.run()
	Log.log(NAME, `{NAME} started`)
	Game.setup()
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		close_stray()
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
