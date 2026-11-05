--!strict
-- Zulrah: one inventory layout, and an equipment and a prayer layout per transformation, picked in the settings.
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Biometrics = require("@lib/main/antiban/biometrics")
local EquipmentLayout = require("@lib/main/equipment_layout")
local GameState = require("@lib/main/game_state")
local House = require("@lib/main/house")
local InventoryLayout = require("@lib/main/inventory_layout")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Player = require("@lib/main/player")
local Position = require("@lib/main/position")
local Prayer = require("@lib/main/interfaces/gametabs/prayer")
local PrayerLayout = require("@lib/main/prayer_layout")
local Random = require("@lib/utils/math/random")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Wornitems = require("@lib/main/interfaces/gametabs/wornitems")

local NAME = "Zulrah"

-- fixed values: ids, tiles, thresholds
local CONST = {
	REPORT = { counters_key = "" },
	-- the map squares Zulrah's arena instance is copied from (regions 9007 and 9008)
	ARENA_CHUNKS = {
		[Position.Chunk.new(35, 47):id()] = true,
		[Position.Chunk.new(35, 48):id()] = true,
	},
	-- Zul-Andra's map square (region 8751)
	ZULANDRA_CHUNK = Position.Chunk.new(34, 47):id(),
	-- thralls (Arceuus): Zulrah can only be hit by these two; with this much time left one roll decides whether to resummon early;
	-- after a failed summon, how long to leave it
	THRALLS = { "Skeleton", "Ghost" },
	THRALL_EARLY_MS = 10000,
	THRALL_EARLY_CHANCE = 0.3,
	THRALL_RETRY_MS = 10000,
	-- Zulrah's animations (seen on one kill): dying, diving between phases and surfacing; it surfaces 1.8 s after diving and
	-- attacks 1.8 s after that, so a phase's prayers and gear are switched as it dives. Past SURFACE_MS a dive counts as over.
	DEATH_ANIMATION = 5804,
	DIVE_ANIMATION = 5072,
	SURFACE_ANIMATION = 5073,
	SURFACE_MS = 3000,
	-- where Zulrah surfaces, as scene tiles (the scene is laid out the same in every arena instance)
	POSITIONS = {
		middle = { x = 52, y = 59 },
		east = { x = 62, y = 57 },
		south = { x = 52, y = 48 },
		west = { x = 42, y = 57 },
	} :: { [string]: { x: number, y: number } },
	-- each rotation's phases as form and position, and its Jad phase (the wiki's rotations; 4 matched a kill for phases 1 to 7)
	ROTATIONS = {
		{
			name = "1 (Magma A)",
			jad = 9,
			phases = {
				"serpentine middle",
				"magma middle",
				"tanzanite middle",
				"serpentine south",
				"magma middle",
				"tanzanite west",
				"serpentine south",
				"tanzanite south",
				"serpentine west",
				"magma middle",
				"serpentine middle",
			},
		},
		{
			name = "2 (Magma B)",
			jad = 9,
			phases = {
				"serpentine middle",
				"magma middle",
				"tanzanite middle",
				"serpentine west",
				"tanzanite south",
				"magma middle",
				"serpentine east",
				"tanzanite south",
				"serpentine west",
				"magma middle",
				"serpentine middle",
			},
		},
		{
			name = "3 (Serp)",
			jad = 10,
			phases = {
				"serpentine middle",
				"serpentine east",
				"magma middle",
				"tanzanite west",
				"serpentine south",
				"tanzanite east",
				"serpentine middle",
				"serpentine west",
				"tanzanite middle",
				"serpentine east",
				"tanzanite middle",
				"serpentine middle",
			},
		},
		{
			name = "4 (Tanz)",
			jad = 11,
			phases = {
				"serpentine middle",
				"tanzanite east",
				"serpentine south",
				"tanzanite west",
				"magma middle",
				"serpentine east",
				"serpentine south",
				"tanzanite west",
				"serpentine middle",
				"tanzanite middle",
				"serpentine east",
				"tanzanite middle",
				"serpentine middle",
			},
		},
	},
	-- Zulrah's NPC id per form (from the wiki, not yet seen in the game), and the states that fix our prayers and gear for it
	TRANSFORMATIONS = {
		{
			key = "serpentine",
			label = "Serpentine (green)",
			id = 2042,
			prayer_state = "SERPENTINE_PRAYER" :: State,
			gear_state = "SERPENTINE_GEAR" :: State,
		},
		{
			key = "magma",
			label = "Magma (red)",
			id = 2043,
			prayer_state = "MAGMA_PRAYER" :: State,
			gear_state = "MAGMA_GEAR" :: State,
		},
		{
			key = "tanzanite",
			label = "Tanzanite (blue)",
			id = 2044,
			prayer_state = "TANZANITE_PRAYER" :: State,
			gear_state = "TANZANITE_GEAR" :: State,
		},
	},
}

type Transformation = typeof(CONST.TRANSFORMATIONS[1])

local Read, Game, Loop, Handler = {}, {}, {}, {}

type TransformationLayouts = {
	equipment: EquipmentLayout.Layout?,
	prayers: PrayerLayout.Layout?,
}

-- TEMPORARY: gear and prayers hardcoded for testing. To undo: delete down to END TEMPORARY, empty CONFIG.transformations, and call Game.ask and Game.poll_settings in Loop.run again.
local function worn(slot: number, id: number, name: string): EquipmentLayout.Slot
	return { slot = slot, mode = "item", id = id, quantity = 1, name = name, stackable = false }
end

local function no_item(slot: number): EquipmentLayout.Slot
	return { slot = slot, mode = "empty" }
end

local function any_item(slot: number): EquipmentLayout.Slot
	return { slot = slot, mode = "any" }
end

local TEMP_MAGIC: TransformationLayouts = {
	equipment = {
		name = "Zulrah Green/Red",
		slots = {
			worn(Wornitems.HEAD, 23971, "Crystal helm"),
			worn(Wornitems.CAPE, 21791, "Imbued Saradomin cape"),
			worn(Wornitems.AMULET, 19720, "Occult necklace (or)"),
			worn(Wornitems.WEAPON, 31113, "Eye of Ayak"),
			worn(Wornitems.BODY, 4870, "Ahrim's robetop 50"),
			no_item(Wornitems.SHIELD),
			worn(Wornitems.LEGS, 4876, "Ahrim's robeskirt 50"),
			worn(Wornitems.HANDS, 31106, "Confliction gauntlets"),
			worn(Wornitems.FEET, 13237, "Pegasian boots"),
			worn(Wornitems.RING, 20657, "Ring of suffering (ri)"),
			worn(Wornitems.AMMO, 22947, "Rada's blessing 4"),
			any_item(Wornitems.SECONDARY_AMMO),
		},
	},
	prayers = { name = "Zulrah Green/Red", prayers = { "protect_from_missiles", "augury" } },
}

local TEMP_RANGED: TransformationLayouts = {
	equipment = {
		name = "Zulrah Blue",
		slots = {
			worn(Wornitems.HEAD, 23971, "Crystal helm"),
			worn(Wornitems.CAPE, 22109, "Ava's assembler"),
			worn(Wornitems.AMULET, 19547, "Necklace of anguish"),
			worn(Wornitems.WEAPON, 25867, "Bow of Faerdhinen (c)"),
			worn(Wornitems.BODY, 23975, "Crystal body"),
			no_item(Wornitems.SHIELD),
			worn(Wornitems.LEGS, 23979, "Crystal legs"),
			worn(Wornitems.HANDS, 7462, "Barrows gloves"),
			worn(Wornitems.FEET, 13237, "Pegasian boots"),
			worn(Wornitems.RING, 20657, "Ring of suffering (ri)"),
			worn(Wornitems.AMMO, 22947, "Rada's blessing 4"),
			any_item(Wornitems.SECONDARY_AMMO),
		},
	},
	prayers = { name = "Zulrah Blue", prayers = { "protect_from_magic", "rigour" } },
}
-- END TEMPORARY

-- what the user can change
local CONFIG = {
	inventory = nil :: InventoryLayout.Layout?,
	-- by CONST.TRANSFORMATIONS key
	transformations = {
		serpentine = TEMP_MAGIC,
		magma = TEMP_MAGIC,
		tanzanite = TEMP_RANGED,
	} :: { [string]: TransformationLayouts },
	max_runs = 0, -- 0 is unlimited
	-- the script stops when stuck: no xp for idle_minutes, this many failures in a row
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

-- counters shown next to the skills in the loader's XP tracker
local stats = { runs = 0, failures = 0 }

type RunState = {
	finished: boolean,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	last_xp: number,
	failures_in_row: number,
	-- states to ignore for one loop
	skip: { [string]: boolean },
	-- in Zulrah's arena, whatever the fight state: no antiban at all
	in_arena: boolean,
	-- the early resummon roll for the thrall that is out (nil: not rolled yet), and when a failed summon may be tried again
	thrall_early: boolean?,
	thrall_retry_at: number,
	-- set on entering the arena; false once Zulrah played its death animation and is gone
	zulrah_alive: boolean,
	zulrah_dying: boolean,
}

local S: RunState = {
	finished = false,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	last_xp = 0,
	failures_in_row = 0,
	skip = {},
	in_arena = false,
	thrall_early = nil,
	thrall_retry_at = 0,
	zulrah_alive = false,
	zulrah_dying = false,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	-- TODO: whatever is read every loop (inventory, npcs, ...)
}

local snap: Snapshot = nil :: any

-- where we are: ZULRAH in the arena, ZULANDRA on the island, HOUSE in a player-owned house, BANKING anywhere else;
-- in the arena, <FORM>_PRAYER and then <FORM>_GEAR while ours don't match the form Zulrah is in
type State =
	"LOADING"
	| "LOGIN"
	| "ZULRAH"
	| "SERPENTINE_PRAYER"
	| "SERPENTINE_GEAR"
	| "MAGMA_PRAYER"
	| "MAGMA_GEAR"
	| "TANZANITE_PRAYER"
	| "TANZANITE_GEAR"
	| "THRALL"
	| "PRAYERS_OFF"
	| "ZULANDRA"
	| "HOUSE"
	| "BANKING"

-- the form the fight state is for
local fighting: Transformation? = nil

-- following the fight's phases: a dive ends one, and where and as what Zulrah surfaces narrows down the rotation
type Phases = {
	-- the phase Zulrah is in, 0 before it is first seen
	phase: number,
	-- the rotations that fit every phase seen in this cycle, by index in CONST.ROTATIONS
	candidates: { number },
	diving: boolean,
	dive_at: number,
	-- its form and tile as it dived, to tell when it has surfaced elsewhere, and in the phase seen last
	dive_from: string,
	seen: string,
	-- its animation at the last look, to see the surfacing animation start
	last_animation: number,
	-- the form the next phase is in, when every candidate agrees: what to switch to while it dives
	next: Transformation?,
}

local function new_phases(): Phases
	return {
		phase = 0,
		candidates = { 1, 2, 3, 4 },
		diving = false,
		dive_at = 0,
		dive_from = "",
		seen = "",
		last_animation = -1,
		next = nil,
	}
end

local phases = new_phases()

-- gains go to Volcren once a minute
local report = StatsReport.new()

-- Reading the client

-- falls back to wall clock ticks
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

-- Zulrah and the form it is in now, by its NPC id; nil while it is under water or gone
function Read.zulrah(): (Host.Npc?, Transformation?)
	for _, npc in ipairs(Host.npcs() or {}) do
		for _, t in CONST.TRANSFORMATIONS do
			if npc.id == t.id then
				return npc, t
			end
		end
	end
	return nil, nil
end

local function transformation(key: string): Transformation?
	for _, t in CONST.TRANSFORMATIONS do
		if t.key == key then
			return t
		end
	end
	return nil
end

-- The named position nearest Zulrah's scene tile.
function Read.zulrah_position(npc: Host.Npc): string
	local pos = assert(snap.state.position)
	local x = npc.x - (pos.x - pos.local_x // 128)
	local y = npc.y - (pos.y - pos.local_y // 128)
	local best, best_d = "middle", math.huge
	for name, p in CONST.POSITIONS do
		local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
		if d < best_d then
			best, best_d = name, d
		end
	end
	return best
end

-- The form of `phase` if every candidate rotation agrees on it; a phase past them all is the next cycle's first, green in the middle.
local function form_of_phase(phase: number): Transformation?
	if #phases.candidates == 0 then
		return nil
	end
	local key: string? = nil
	local past_all = true
	for _, i in phases.candidates do
		local step = CONST.ROTATIONS[i].phases[phase]
		if step then
			past_all = false
			local form = string.match(step, "^(%a+)")
			if key ~= nil and form ~= key then
				return nil
			end
			key = form
		end
	end
	if past_all then
		return transformation("serpentine")
	end
	return if key then transformation(key) else nil
end

-- A new phase: Zulrah is in form `t` at `at`. The rotations that don't have that there drop out; past the longest left, a new cycle starts.
local function observe(t: Transformation, at: string)
	local longest = 0
	for _, i in phases.candidates do
		longest = math.max(longest, #CONST.ROTATIONS[i].phases)
	end
	phases.phase += 1
	if phases.phase > longest then
		phases.phase, phases.candidates = 1, { 1, 2, 3, 4 }
	end
	local before = #phases.candidates
	local left: { number } = {}
	for _, i in phases.candidates do
		if CONST.ROTATIONS[i].phases[phases.phase] == `{t.key} {at}` then
			table.insert(left, i)
		end
	end
	phases.candidates = left
	local which = if #left == 1 then `rotation {CONST.ROTATIONS[left[1]].name}` else `{#left} rotations fit`
	Log.log(NAME, `Phase {phases.phase}: {t.label} {at}; {which}{if Read.in_jad_phase() then " (Jad phase)" else ""}`)
	if #left == 0 and before > 0 then
		Log.log(NAME, "No rotation fits: switching on what surfaces until the next cycle")
	end
end

-- Follows the phases each loop: the dive animation ends one, and the next form (when known) is switched to while it dives.
function Read.track_phases(npc: Host.Npc, t: Transformation)
	local at = Read.zulrah_position(npc)
	local here = `{npc.id} {at}`
	if phases.phase == 0 then
		phases.seen = here
		observe(t, at)
		return
	end
	local surfacing = npc.animation == CONST.SURFACE_ANIMATION and phases.last_animation ~= CONST.SURFACE_ANIMATION
	phases.last_animation = npc.animation
	-- a dive the loop was too busy to see: it surfaced all the same, as something else or (between cycles) as the same
	if not phases.diving and npc.animation ~= CONST.DIVE_ANIMATION and (here ~= phases.seen or surfacing) then
		phases.seen = here
		observe(t, at)
		return
	end
	if not phases.diving and npc.animation == CONST.DIVE_ANIMATION then
		phases.diving, phases.dive_at, phases.dive_from = true, time(), here
		phases.next = form_of_phase(phases.phase + 1)
		if phases.next then
			Log.log(NAME, `Diving: switching to {phases.next.label} now`)
		end
		return
	end
	-- surfaced: the animation, a new form or tile, or simply enough time (a cycle can go from green middle to green middle)
	if
		phases.diving
		and (
			npc.animation == CONST.SURFACE_ANIMATION
			or here ~= phases.dive_from
			or time() - phases.dive_at > CONST.SURFACE_MS
		)
	then
		phases.diving, phases.next = false, nil
		phases.seen = here
		observe(t, at)
	end
end

-- Whether Zulrah is in its Jad phase: every candidate rotation has it at this phase.
function Read.in_jad_phase(): boolean
	if #phases.candidates == 0 or phases.phase == 0 then
		return false
	end
	for _, i in phases.candidates do
		if CONST.ROTATIONS[i].jad ~= phases.phase then
			return false
		end
	end
	return true
end

-- in the arena: once Zulrah is dead, prayers off; while it lives, fixing prayers comes before gear, and nothing to fix is plain ZULRAH
function Read.fight_state(): State
	if not S.zulrah_alive then
		fighting = nil
		return if Prayer.is_any_active() then "PRAYERS_OFF" else "ZULRAH"
	end
	local npc, t = Read.zulrah()
	if npc and npc.animation == CONST.DEATH_ANIMATION and not S.zulrah_dying then
		S.zulrah_dying = true
		Log.log(NAME, "Zulrah is dying")
	end
	-- it also goes under water between forms, so gone only counts after its death animation
	if S.zulrah_dying and npc == nil then
		S.zulrah_alive = false
		Log.log(NAME, "Zulrah is dead")
		return Read.fight_state()
	end
	fighting = t
	-- nothing left to switch for while it dies
	if npc == nil or t == nil or S.zulrah_dying then
		return "ZULRAH"
	end
	Read.track_phases(npc, t)
	-- while it dives into a phase whose form is known, that form's prayers and gear; otherwise the form it is in
	local want = if phases.diving and phases.next then phases.next else t
	fighting = want
	local layouts = CONFIG.transformations[want.key]
	-- the Jad phase alternates its attacks, so its protection prayers are the player's
	if layouts and layouts.prayers and not Read.in_jad_phase() and not PrayerLayout.is_active(layouts.prayers) then
		return want.prayer_state
	end
	if layouts and layouts.equipment and EquipmentLayout.matches(layouts.equipment) == false then
		return want.gear_state
	end
	if Read.wants_thrall() then
		return "THRALL"
	end
	return "ZULRAH"
end

-- On the Arceuus spellbook: a thrall when none is out, or, once one has THRALL_EARLY_MS left, on a single roll for it.
-- A thrall summoned before the script started has no known time left, so it is only replaced once it is gone.
function Read.wants_thrall(): boolean
	if not Magic.is_spellbook("arceuus") or Magic.thrall_on_cooldown() or time() < S.thrall_retry_at then
		return false
	end
	if not Magic.thrall_active() then
		return true
	end
	local left = Magic.thrall_remaining_ms()
	if left == nil or left > CONST.THRALL_EARLY_MS then
		return false
	end
	if S.thrall_early == nil then
		S.thrall_early = Biometrics.random_boolean(CONST.THRALL_EARLY_CHANCE)
		if S.thrall_early then
			Log.log(NAME, `Resummoning the thrall early ({math.floor(left / 1000)} s left)`)
		end
	end
	return S.thrall_early == true
end

-- which of the areas the snapshot is in; the arena and a house are instances, told apart by where they were copied from
function Read.area(): State
	if Player.in_instance() then
		for _, chunk in ipairs(Player.instance_chunks() or {}) do
			if CONST.ARENA_CHUNKS[chunk:id()] then
				return "ZULRAH"
			end
		end
		if House.inside() then
			return "HOUSE"
		end
		return "BANKING"
	end
	local pos = assert(snap.state.position)
	if Position.Chunk.new(pos.x // 64, pos.y // 64):id() == CONST.ZULANDRA_CHUNK then
		return "ZULANDRA"
	end
	return "BANKING"
end

-- Game setup

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
	-- scene reload while logged in
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

	AntibanTasks.skills = { "Total" } -- TODO: skills the hover task looks at
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

	-- queued without blocking: camera, hover and random tab in the game, tabs and chat outside it
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

	-- breaks and sleeps come from the loader's Breaks tab
	Antiban.sync_config()
	S.antiban_ready = true
	Log.log(NAME, "Antiban set up")
end

-- asks for the settings; false when the form is closed
function Game.ask(): boolean
	local fields: { Host.FormField } = {
		{ id = "inventory", kind = "inventory", label = "Inventory" },
	}
	for _, transformation in CONST.TRANSFORMATIONS do
		fields[#fields + 1] = {
			id = `{transformation.key}_equipment`,
			kind = "equipment",
			label = `{transformation.label} equipment`,
		}
		fields[#fields + 1] = {
			id = `{transformation.key}_prayers`,
			kind = "prayer",
			label = `{transformation.label} prayers`,
		}
	end
	local values = Host.form({ title = NAME, submit = "Start", fields = fields })
	if values == nil then
		return false
	end
	Game.apply_settings(values)
	return true
end

-- puts the form's values in CONFIG; they are read where they are used, so it works while the script runs too
function Game.apply_settings(values: { [string]: any })
	CONFIG.inventory = values.inventory
	for _, transformation in CONST.TRANSFORMATIONS do
		CONFIG.transformations[transformation.key] = {
			equipment = values[`{transformation.key}_equipment`],
			prayers = values[`{transformation.key}_prayers`],
		}
	end
end

-- takes the settings the user sent with Update in the loader, if there are any
function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

function Game.setup()
	while true do
		local state = game_state()
		if Game.ensure_logged_in(state) and Read.refresh_snapshot(state) then
			break
		end
		sleep(100)
	end

	-- TODO: check requirements here (levels, items, world) and adjust CONFIG or stop

	-- the first prayer read is slow (about half a second): here, not in the fight
	PrayerLayout.is_active({ name = "", prayers = {} })

	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

-- Loop

-- resets the idle timeout on xp and reports it
function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local xp = Stats.total_experience(s.skills) or S.last_xp
	-- TODO: other signs of progress (new items, ...) also reset the timeout
	if xp > S.last_xp then
		S.last_progress_at = time()
	end
	S.last_xp = xp
end

-- what the loader's XP tracker shows next to the skills: the totals, it works out the rates itself
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

-- stops the script when it hasn't progressed or keeps failing
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

-- time spent in antiban doesn't count as idle
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

-- reads the client and decides what to do next; handlers do it
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

	local area = Read.area()
	if area == "ZULRAH" and not S.in_arena then
		S.zulrah_alive, S.zulrah_dying = true, false
		phases = new_phases()
	end
	S.in_arena = area == "ZULRAH"
	if S.in_arena then
		area = Read.fight_state()
	end
	if skipped[area] then
		return "LOADING"
	end
	return area
end

-- Handlers

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	ZULRAH = function()
		-- TODO: the fight; no antiban in here
	end,
	SERPENTINE_PRAYER = function()
		Handler.fix_prayers("SERPENTINE_PRAYER")
	end,
	SERPENTINE_GEAR = function()
		Handler.fix_gear("SERPENTINE_GEAR")
	end,
	MAGMA_PRAYER = function()
		Handler.fix_prayers("MAGMA_PRAYER")
	end,
	MAGMA_GEAR = function()
		Handler.fix_gear("MAGMA_GEAR")
	end,
	TANZANITE_PRAYER = function()
		Handler.fix_prayers("TANZANITE_PRAYER")
	end,
	TANZANITE_GEAR = function()
		Handler.fix_gear("TANZANITE_GEAR")
	end,
	PRAYERS_OFF = function()
		if not PrayerLayout.deactivate() then
			Log.log(NAME, "Couldn't turn the prayers off")
			S.skip["PRAYERS_OFF"] = true
		end
	end,
	THRALL = function()
		local kind = CONST.THRALLS[if Biometrics.random_boolean(0.5) then 1 else 2] :: Magic.Thrall
		if Magic.summon_thrall(kind) then
			S.thrall_early = nil
			Log.log(NAME, `Summoned a {string.lower(kind)} thrall`)
		else
			S.thrall_retry_at = time() + CONST.THRALL_RETRY_MS
		end
	end,
	ZULANDRA = function()
		-- TODO: board the boat
		Handler.antiban("ZULANDRA")
	end,
	HOUSE = function()
		-- TODO: restore at the pool, leave for Zul-Andra
		Handler.antiban("HOUSE")
	end,
	BANKING = function()
		-- TODO: bank, then travel to Zul-Andra
		Handler.antiban("BANKING")
	end,
}

-- a failed switch is logged and its state skipped for one loop, so the next loop looks at the fight again
function Handler.fix_prayers(state: State)
	local t = fighting
	local layout = t and CONFIG.transformations[t.key].prayers
	if t == nil or layout == nil then
		return
	end
	if not PrayerLayout.activate(layout) then
		Log.log(NAME, `Couldn't switch to the {t.label} prayers ({layout.name})`)
		S.skip[state] = true
	end
end

function Handler.fix_gear(state: State)
	local t = fighting
	local layout = t and CONFIG.transformations[t.key].equipment
	if t == nil or layout == nil then
		return
	end
	if not EquipmentLayout.equip(layout) then
		Log.log(NAME, `Couldn't switch to the {t.label} gear ({layout.name})`)
		S.skip[state] = true
	end
end

-- antiban between fights; a state whose antiban can't run now is skipped for one loop
function Handler.antiban(state: State)
	if CONFIG.antiban and S.antiban_ready and not Antiban.do_antiban() then
		S.skip[state] = true
	end
end
-- an interface opened by accident (a click on the wrong thing) blocks every click: closed
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

	local last_state: State? = nil
	while not S.finished do
		local state: State = Loop.get_state()
		Loop.check_timeouts()
		if S.finished then
			break
		end
		if state ~= last_state and state ~= "LOADING" then
			Log.log(NAME, `State: {state}`)
			last_state = state
		end
		close_stray()
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready and not S.in_arena then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
