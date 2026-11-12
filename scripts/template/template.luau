--!strict
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local GameState = require("@lib/main/game_state")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")

local NAME = "Template"

local CONST = {
	REPORT = { counters_key = "" },
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
	skip: { [string]: boolean },
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	skip = {},
}

type Snapshot = {
	state: ClientState,
	tick: number,
}

local snap: Snapshot = nil :: any

type State = "LOADING" | "LOGIN" | "IDLE"

type Plan = { target: number? }

local plan: Plan = {}

local report = StatsReport.new()

function Read.current_tick(state: ClientState): number
	return state.tick_count or time() // 600
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

function Loop.get_state(): State
	local skipped = S.skip
	S.skip = {}
	plan = {}

	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	if not Read.refresh_snapshot(s) then
		return "LOADING"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	plan.target = snap.tick
	if skipped["IDLE"] then
		return "LOADING"
	end
	return "IDLE"
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	IDLE = function()
		Log.log(NAME, `Tick {plan.target}`)
		if CONFIG.antiban and S.antiban_ready then
			if not Antiban.do_antiban() then
				S.skip["IDLE"] = true
			end
		end
	end,
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
