--!strict
-- Zulrah: one inventory layout, and an equipment and a prayer layout per transformation, picked in the settings.
local Host = require("@lib/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@lib/main/antiban/antiban")
local AntibanTasks = require("@lib/main/antiban/antiban_tasks")
local Bankmain = require("@lib/main/interfaces/mainscreen/bankmain")
local Biometrics = require("@lib/main/antiban/biometrics")
local ChatOptions = require("@lib/main/interfaces/chatbox/chat_options")
local CombatSafeSpot = require("@lib/main/combat_safespot")
local EquipmentLayout = require("@lib/main/equipment_layout")
local Ferox = require("@lib/main/ferox")
local GameState = require("@lib/main/game_state")
local GroundItems = require("@lib/main/entities/ground_items")
local House = require("@lib/main/house")
local Inventory = require("@lib/main/interfaces/gametabs/inventory")
local InventoryLayout = require("@lib/main/inventory_layout")
local Log = require("@lib/utils/log")
local Login = require("@lib/main/interfaces/login/login")
local Magic = require("@lib/main/interfaces/gametabs/magic")
local Npcs = require("@lib/main/entities/npcs")
local Objects = require("@lib/main/entities/objects")
local Player = require("@lib/main/player")
local Position = require("@lib/main/position")
local Prayer = require("@lib/main/interfaces/gametabs/prayer")
local PrayerLayout = require("@lib/main/prayer_layout")
local Random = require("@lib/utils/math/random")
local SafeSpot = require("@lib/main/safespot")
local Stats = require("@lib/main/interfaces/gametabs/stats")
local StatsReport = require("@lib/utils/stats_report")
local Toplevel = require("@lib/main/interfaces/mainscreen/toplevel")
local Transports = require("@lib/main/transports")
local Varbits = require("@lib/main/varbits")
local Walker = require("@lib/main/walker")

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
	-- on the island: the boat to the arena, and the priestess who keeps what was left behind on a death
	BOAT = "Sacrificial boat",
	PRIESTESS = "Priestess Zul-Gwenwynig",
	-- after a kill: how long to wait for a picked up item to leave the ground, and the teleport scroll Zulrah leaves behind
	-- (an object, read with "Read") and how long its teleport takes
	LOOT_WAIT_MS = 1800,
	TELEPORT_LOC = 11701,
	TELEPORT_OPTION = "Read",
	LEAVE_QUESTION = "Are you ready to leave the shrine?",
	LEAVE_ANSWER = "Yes",
	TELEPORT_WAIT_MS = 8000,
	-- boarding asks this in the chatbox; how long to wait for the question after the click, and for the arena after "Yes"
	BOARD_QUESTION = "Return to Zulrah's shrine?",
	BOARD_ANSWER = "Yes",
	QUESTION_WAIT_MS = 5000,
	BOARD_WAIT_MS = 10000,
	-- how long before another Collect click, while the collection interface can't be read
	COLLECT_RETRY_MS = 10000,
	-- where supplies are restocked when there aren't enough for a kill (the "Restore method" setting); the house is reached by
	-- the tablet's "Inside" or the standard spell, cast "Inside" when varbit 4744 makes outside the default
	RESTORE_METHODS = { "House", "Ferox Enclave" },
	HOUSE_TABLET = "Teleport to house",
	HOUSE_TABLET_OPTION = "Inside",
	HOUSE_SPELL = "Teleport to House",
	HOUSE_OUTSIDE_VARBIT = 4744,
	-- in the house: with this pool, restore there and go to the bank the planner reaches fastest; without it, the jewellery box to
	-- the Ferox Enclave (its pool and bank)
	ORNATE_POOL = "Ornate pool of Rejuvenation",
	FEROX = "Ferox Enclave",
	-- the "Ferox Enclave" restore method: a ring of dueling there (the data's row), then its pool and its bank
	-- a restock that fails this many times in a row (the bank is out of something) stops the script
	RESTOCK_ATTEMPTS = 3,
	DUELING_FEROX = "Ring of dueling: Ferox Enclave",
	-- the teleport item back to the island after a restock
	ZULANDRA_TELEPORT = "Zul-andra teleport",
	-- banks to restock at, a tile in front of each (TODO: check each tile in the game; move to the lib with the banking)
	BANKS = {
		{ name = "Grand Exchange", x = 3164, y = 3487, plane = 0 },
		{ name = "Varrock West", x = 3185, y = 3436, plane = 0 },
		{ name = "Varrock East", x = 3253, y = 3420, plane = 0 },
		{ name = "Edgeville", x = 3094, y = 3493, plane = 0 },
		{ name = "Falador East", x = 3013, y = 3355, plane = 0 },
		{ name = "Falador West", x = 2946, y = 3368, plane = 0 },
		{ name = "Draynor Village", x = 3092, y = 3243, plane = 0 },
		{ name = "Al Kharid", x = 3269, y = 3167, plane = 0 },
		{ name = "Lumbridge Castle", x = 3208, y = 3220, plane = 2 },
		{ name = "Castle Wars", x = 2443, y = 3083, plane = 0 },
		{ name = "Ferox Enclave", x = 3130, y = 3631, plane = 0 },
		{ name = "Seers' Village", x = 2725, y = 3493, plane = 0 },
		{ name = "Catherby", x = 2809, y = 3441, plane = 0 },
		{ name = "Ardougne North", x = 2616, y = 3332, plane = 0 },
		{ name = "Ardougne South", x = 2655, y = 3283, plane = 0 },
		{ name = "Yanille", x = 2613, y = 3093, plane = 0 },
		{ name = "Arceuus", x = 1629, y = 3746, plane = 0 },
	},
	-- thralls (Arceuus): Zulrah can only be hit by these two; with this much time left one roll decides whether to resummon early;
	-- after a failed summon, how long to leave it
	THRALLS = { "Skeleton", "Ghost" },
	THRALL_EARLY_MS = 10000,
	THRALL_EARLY_CHANCE = 0.3,
	THRALL_RETRY_MS = 10000,
	-- supplies, by name (potions in any dose, the lowest drunk first)
	FOOD = "Anglerfish",
	-- what restores prayer, the first one held drunk: a dose gives a quarter of the real Prayer level plus this
	PRAYER_RESTORES = {
		{ base = "Prayer potion", bonus = 7 },
		{ base = "Super restore", bonus = 8 },
	},
	ANTIVENOM = "Extended anti-venom+",
	RANGING_POTION = "Divine ranging potion",
	HEART = "Saturated heart",
	-- eat at a hitpoints level rolled in this range, drink a prayer potion at a prayer level rolled in this one; each rerolls after
	EAT_AT = { 40, 60 },
	RESTORE_AT = { 10, 25 },
	-- the server takes the click on the next tick and the item's effect shows after it: the same supply isn't used again sooner
	CONSUME_MS = 1800,
	-- after an attack click, how long to wait for the first hit or projectile before clicking again
	ATTACK_PATIENCE_MS = 3000,
	-- Zulrah's animations (seen on one kill): dying, diving between phases and surfacing; it surfaces 1.8 s after diving and
	-- attacks 1.8 s after that, so a phase's prayers and gear are switched as it dives. Past SURFACE_MS a dive counts as over.
	DEATH_ANIMATION = 5804,
	DIVE_ANIMATION = 5072,
	SURFACE_ANIMATION = 5073,
	SURFACE_MS = 3000,
	-- getting ahead: in a phase that isn't red, the walk to the next phase's tile starts a rolled number of ticks after it
	-- surfaces, once the next tile is known, Zulrah can still be hit from it and no cloud lies on the way
	EARLY_TICKS = { 0, 10 },
	TICK_MS = 600,
	ZULRAH_SIZE = 5,
	-- the venom clouds: the projectile that drops one, the square it covers north and east from the tile it is aimed at (read
	-- from the hits a cloud gives), how long it stays (a guess on the safe side), and the arena's middle and reach for its grid
	CLOUD_PROJECTILE = 1045,
	CLOUD_SIZE = 3,
	CLOUD_MS = 20000,
	-- how far from a clouded phase tile to look for one to stand on instead
	CLOUD_DODGE_REACH = 3,
	ARENA_CENTER = { x = 52, y = 56 },
	ARENA_RADIUS = 16,
	-- the red form whips the tile it looks at (both animations seen on one kill); the hit lands about 3 s after it starts
	WHIP_ANIMATIONS = { [5806] = true, [5807] = true } :: { [number]: boolean },
	-- where Zulrah surfaces, as scene tiles (the scene is laid out the same in every arena instance)
	POSITIONS = {
		middle = { x = 52, y = 59 },
		east = { x = 62, y = 57 },
		south = { x = 52, y = 48 },
		west = { x = 42, y = 57 },
	} :: { [string]: { x: number, y: number } },
	-- where we stand, as scene tiles, read with the player on them; west_side is a guess (rotation 4 phase 8 only)
	TILES = {
		start = { x = 56, y = 62 },
		red_dodge = { x = 58, y = 61 },
		east_pillar = { x = 56, y = 56 },
		west_pillar = { x = 48, y = 56 },
		between = { x = 52, y = 53 },
		west_side = { x = 49, y = 54 },
	} :: { [string]: { x: number, y: number } },
	-- the tile to step to when the red form whips the one we're on
	DODGES = { start = "red_dodge", red_dodge = "start" } :: { [string]: string },
	-- each rotation's phases as form, position and the tile to stand on, and its Jad phase (the wiki's rotations, with the
	-- tiles of a helper plugin's map; 4 matched a kill for phases 1 to 7)
	ROTATIONS = {
		{
			name = "1 (Magma A)",
			jad = 9,
			phases = {
				"serpentine middle start",
				"magma middle start",
				"tanzanite middle between",
				"serpentine south west_pillar",
				"magma middle west_pillar",
				"tanzanite west between",
				"serpentine south east_pillar",
				"tanzanite south east_pillar",
				"serpentine west west_pillar",
				"magma middle start",
				"serpentine middle start",
			},
		},
		{
			name = "2 (Magma B)",
			jad = 9,
			phases = {
				"serpentine middle start",
				"magma middle start",
				"tanzanite middle between",
				"serpentine west west_pillar",
				"tanzanite south west_pillar",
				"magma middle west_pillar",
				"serpentine east between",
				"tanzanite south west_pillar",
				"serpentine west west_pillar",
				"magma middle start",
				"serpentine middle start",
			},
		},
		{
			name = "3 (Serp)",
			jad = 10,
			phases = {
				"serpentine middle start",
				"serpentine east start",
				"magma middle east_pillar",
				"tanzanite west between",
				"serpentine south between",
				"tanzanite east between",
				"serpentine middle west_pillar",
				"serpentine west west_pillar",
				"tanzanite middle east_pillar",
				"serpentine east east_pillar",
				"tanzanite middle start",
				"serpentine middle start",
			},
		},
		{
			name = "4 (Tanz)",
			jad = 11,
			phases = {
				"serpentine middle start",
				"tanzanite east start",
				"serpentine south west_pillar",
				"tanzanite west west_pillar",
				"magma middle east_pillar",
				"serpentine east east_pillar",
				"serpentine south east_pillar",
				"tanzanite west west_side",
				"serpentine middle east_pillar",
				"tanzanite middle east_pillar",
				"serpentine east east_pillar",
				"tanzanite middle start",
				"serpentine middle start",
			},
		},
	},
	-- the overheads, padlocked in the prayer layouts: the script picks the protection for each form itself
	OVERHEADS = { "protect_from_melee", "protect_from_missiles", "protect_from_magic" },
	-- Zulrah's NPC id per form, the protection prayer against it, and the states that fix our prayers and gear for it
	TRANSFORMATIONS = {
		{
			key = "serpentine",
			name = "Serpentine",
			label = "Serpentine (green)",
			id = 2042,
			protection = "protect_from_missiles",
			prayer_state = "SERPENTINE_PRAYER" :: State,
			gear_state = "SERPENTINE_GEAR" :: State,
		},
		{
			key = "magma",
			name = "Magma",
			label = "Magma (red)",
			id = 2043,
			protection = "protect_from_missiles",
			prayer_state = "MAGMA_PRAYER" :: State,
			gear_state = "MAGMA_GEAR" :: State,
		},
		{
			key = "tanzanite",
			name = "Tanzanite",
			label = "Tanzanite (blue)",
			id = 2044,
			protection = "protect_from_magic",
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

-- what the user can change
local CONFIG = {
	inventory = nil :: InventoryLayout.Layout?,
	-- by CONST.TRANSFORMATIONS key
	transformations = {
		serpentine = {},
		magma = {},
		tanzanite = {},
	} :: { [string]: TransformationLayouts },
	max_runs = 0, -- 0 is unlimited; the script stops once off the arena after this many kills
	-- where to restock (CONST.RESTORE_METHODS), and the food and prayer doses (left after the top-up on the island) a kill
	-- needs: with less, the next trip is to restock
	restore = "House",
	min_food = 3,
	min_prayer_doses = 2,
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
	-- the name of the goal last clicked (Read.goal), so a walk under way isn't clicked again
	moving_to: string?,
	-- the scene tile stood on instead of the phase's tile (`key`) while a cloud covers that
	cloud_dodge: { key: string, x: number, y: number }?,
	-- when Collect may be clicked on the priestess again
	collect_retry_at: number,
	-- loot left on the floor because it didn't fit and there was no food left to eat for room, by item id
	no_room: { [number]: boolean },
	-- the venom clouds by world tile, landed or on the way, with when each is gone; the arena's collision, read once a visit
	clouds: { [string]: { x: number, y: number, gone_at: number } },
	arena_grid: SafeSpot.Grid?,
	-- whether the mouse went to Zulrah during the walk, to attack as it ends
	hovered_on_walk: boolean,
	-- the phase Zulrah was attacked in and when (a dive or a walk ends the attack, so a new phase or a walk asks for another)
	attack_phase: number,
	attack_at: number,
	-- the levels rolled to eat and to drink a prayer potion at, and when each supply was last used
	eat_at: number,
	restore_at: number,
	used_at: { [string]: number },
	-- the boosts of this kill still to take, CONST names
	boosts: { string },
	-- restocks in a row that didn't fill the inventory layout
	restock_failures: number,
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
	moving_to = nil,
	collect_retry_at = 0,
	no_room = {},
	clouds = {},
	arena_grid = nil,
	hovered_on_walk = false,
	attack_phase = -1,
	attack_at = 0,
	eat_at = Random.int(CONST.EAT_AT[1], CONST.EAT_AT[2]),
	restore_at = Random.int(CONST.RESTORE_AT[1], CONST.RESTORE_AT[2]),
	used_at = {},
	boosts = {},
	restock_failures = 0,
}

type Snapshot = {
	state: ClientState,
	tick: number,
	-- TODO: whatever is read every loop (inventory, npcs, ...)
}

local snap: Snapshot = nil :: any

-- where we are: ZULRAH in the arena; on the island RECOVER_GEAR after a death, TELEPORT_<METHOD> without the supplies for a
-- kill, else PREPARE_GEAR into the first phase's gear, then BOARD_BOAT and CONFIRM_BOAT for its question; HOUSE in a
-- player-owned house (an ornate pool, then the fastest bank; else the box to the Ferox Enclave), FEROX in the Ferox
-- Enclave while its pool is wanted, BANKING anywhere else;
-- in the arena, <FORM>_PRAYER while ours don't match the form Zulrah is in, MOVE off the phase's tile, then <FORM>_GEAR
type State =
	"LOADING"
	| "LOGIN"
	| "ZULRAH"
	| "MOVE"
	| "SERPENTINE_PRAYER"
	| "SERPENTINE_GEAR"
	| "MAGMA_PRAYER"
	| "MAGMA_GEAR"
	| "TANZANITE_PRAYER"
	| "TANZANITE_GEAR"
	| "THRALL"
	| "EAT"
	| "PRAYER_POTION"
	| "ANTIVENOM"
	| "BOOST"
	| "ATTACK"
	| "PRAYERS_OFF"
	| "LOOT"
	| "EAT_FOR_SPACE"
	| "LEAVE"
	| "CONFIRM_LEAVE"
	| "RECOVER_GEAR"
	| "PREPARE_GEAR"
	| "BOARD_BOAT"
	| "CONFIRM_BOAT"
	| "TELEPORT_HOUSE"
	| "TELEPORT_FEROX"
	| "FEROX"
	| "HOUSE"
	| "BANKING"
	| "TELEPORT_ZULANDRA"

-- the form the fight state is for
local fighting: Transformation? = nil

-- we died at Zulrah: what was left behind is collected on the island before the next trip
local died = false

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
	-- the CONST.TILES key to stand on now: the phase's, the next phase's once it dives or the walk there starts early, its dodge
	-- after a whip; nil when unknown
	target: string?,
	-- when the early walk to the next phase's tile may start (rolled as the phase starts)
	early_at: number,
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
		target = nil,
		early_at = math.huge,
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

-- The player's scene tile, and the world tile of a scene tile (the arena's world tiles change with each instance).
function Read.scene_tile(): Host.Tile
	local pos = assert(snap.state.position)
	return { x = pos.local_x // 128, y = pos.local_y // 128 }
end

function Read.world_tile(scene: Host.Tile): Host.Tile
	local pos = assert(snap.state.position)
	return { x = scene.x + pos.x - pos.local_x // 128, y = scene.y + pos.y - pos.local_y // 128 }
end

-- The named position nearest Zulrah's scene tile.
function Read.zulrah_position(npc: Host.Npc): string
	local me, base = Read.scene_tile(), assert(snap.state.position)
	local x, y = npc.x - (base.x - me.x), npc.y - (base.y - me.y)
	local best, best_d = "middle", math.huge
	for name, p in CONST.POSITIONS do
		local d = (p.x - x) ^ 2 + (p.y - y) ^ 2
		if d < best_d then
			best, best_d = name, d
		end
	end
	return best
end

-- Word `part` of `phase` (1 form, 2 position, 3 tile) if every candidate rotation agrees on it; a phase past them all is the
-- next cycle's first.
local function agreed(phase: number, part: number): string?
	if #phases.candidates == 0 then
		return nil
	end
	local word: string? = nil
	local past_all = true
	for _, i in phases.candidates do
		local step = CONST.ROTATIONS[i].phases[phase]
		if step then
			past_all = false
			local this = string.split(step, " ")[part]
			if word ~= nil and this ~= word then
				return nil
			end
			word = this
		end
	end
	if past_all then
		return string.split(CONST.ROTATIONS[1].phases[1], " ")[part]
	end
	return word
end

local function form_of_phase(phase: number): Transformation?
	local key = agreed(phase, 1)
	return if key then transformation(key) else nil
end

local function tile_label(key: string): string
	return (string.gsub(key, "_", " "))
end

-- Stand on `key` from now on; nil (no rotation fits) keeps where we are.
local function stand(key: string?)
	if key and key ~= phases.target then
		Log.log(NAME, `Standing on {tile_label(key)}`)
		phases.target = key
	end
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
		local step = CONST.ROTATIONS[i].phases[phases.phase]
		if step and string.match(step, "^%a+ %a+") == `{t.key} {at}` then
			table.insert(left, i)
		end
	end
	phases.candidates = left
	stand(agreed(phases.phase, 3))
	phases.early_at = time() + Random.int(CONST.EARLY_TICKS[1], CONST.EARLY_TICKS[2]) * CONST.TICK_MS
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
	local started = npc.animation ~= phases.last_animation
	local surfacing = npc.animation == CONST.SURFACE_ANIMATION and started
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
		stand(agreed(phases.phase + 1, 3))
		return
	end
	-- a whip at the tile we stand on: step to its dodge
	local dodge = phases.target and CONST.DODGES[phases.target]
	if dodge and CONST.WHIP_ANIMATIONS[npc.animation] and started then
		Log.log(NAME, `Whip: dodging to {tile_label(dodge)}`)
		phases.target = dodge
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

-- the user's prayers for a form plus its protection, with nothing left to the lib's locked rule, so a switch is one round of clicks
function Read.with_protection(layout: PrayerLayout.Layout?, t: Transformation): PrayerLayout.Layout
	local prayers = { t.protection }
	for _, key in ipairs(if layout then layout.prayers else {}) do
		table.insert(prayers, key)
	end
	return { name = if layout then layout.name else "no layout", prayers = prayers }
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

-- in the arena: once Zulrah is dead, prayers off, the loot, then away to restock or by the scroll; while it lives, fixing prayers comes before gear, and nothing to fix is plain ZULRAH
function Read.fight_state(): State
	if not S.zulrah_alive then
		fighting = nil
		if Prayer.is_any_active() then
			return "PRAYERS_OFF"
		end
		local item = Read.next_loot()
		if item then
			return if GroundItems.fits(item) then "LOOT" else "EAT_FOR_SPACE"
		end
		if Read.needs_restock() then
			return Read.restore_state()
		end
		if ChatOptions.is_title(CONST.LEAVE_QUESTION) then
			return "CONFIRM_LEAVE"
		end
		return if Read.teleport() then "LEAVE" else "ZULRAH"
	end
	local npc, t = Read.zulrah()
	if npc and npc.animation == CONST.DEATH_ANIMATION and not S.zulrah_dying then
		S.zulrah_dying = true
		Log.log(NAME, "Zulrah is dying")
	end
	-- it also goes under water between forms, so gone only counts after its death animation
	if S.zulrah_dying and npc == nil then
		S.zulrah_alive = false
		stats.runs += 1
		Log.log(NAME, "Zulrah is dead")
		return Read.fight_state()
	end
	fighting = t
	if Read.must_escape() then
		return Read.restore_state()
	end
	-- nothing left to switch for or hit while it dies
	if npc == nil or t == nil or S.zulrah_dying then
		-- before it first surfaces the arrival message holds it back: walking to the start tile dismisses it
		if npc == nil and not S.zulrah_dying and Read.wants_move() then
			return "MOVE"
		end
		return Read.supplies_state() or "ZULRAH"
	end
	Read.track_phases(npc, t)
	Read.track_clouds()
	Read.update_cloud_dodge(npc)
	local early = Read.early_tile(npc, t)
	if early then
		stand(early)
	end
	-- while it dives into a phase whose form is known, that form's prayers and gear; otherwise the form it is in
	local want = if phases.diving and phases.next then phases.next else t
	fighting = want
	local layouts = CONFIG.transformations[want.key]
	-- the Jad phase alternates its attacks; flicking for it isn't written, so the prayers stay as the last phase left them
	if layouts and layouts.prayers and not Read.in_jad_phase() and not PrayerLayout.is_active(layouts.prayers) then
		return want.prayer_state
	end
	-- walking doesn't stop gear switches, so the click comes first
	if Read.wants_move() then
		return "MOVE"
	end
	local supplies = Read.supplies_state()
	if supplies then
		return supplies
	end
	if layouts and layouts.equipment and EquipmentLayout.matches(layouts.equipment) == false then
		return want.gear_state
	end
	if Read.next_boost() then
		return "BOOST"
	end
	if Read.wants_thrall() then
		return "THRALL"
	end
	if Read.wants_attack(npc) then
		return "ATTACK"
	end
	return "ZULRAH"
end

-- The slot of `base`: the item itself, or a potion's lowest dose (a potion is finished before the next is opened).
function Read.supply_slot(base: string): number?
	local slot = Inventory.find(base)
	for dose = 1, 4 do
		slot = slot or Inventory.find(`{base}({dose})`)
	end
	return slot
end

-- Whether `base` is in the inventory and wasn't used in the last CONSUME_MS.
local function ready(base: string): boolean
	return time() - (S.used_at[base] or -math.huge) >= CONST.CONSUME_MS and Read.supply_slot(base) ~= nil
end

-- The prayer restore held (CONST.PRAYER_RESTORES) and the prayer a dose of it gives back.
function Read.prayer_restore(): (string?, number)
	local _, real = Player.prayer()
	for _, r in CONST.PRAYER_RESTORES do
		if Read.supply_slot(r.base) then
			return r.base, (real or 0) // 4 + r.bonus
		end
	end
	return nil, 0
end

-- Off the arena: prayer missing at least a whole dose, so the dose isn't wasted.
-- What a piece of food heals: an anglerfish a tenth of the Hitpoints level plus 2 to 13 by that level (it can heal past full).
function Read.food_heal(): number
	local _, real = Player.hitpoints()
	local level = real or 99
	local bonus = if level < 25 then 2 elseif level < 50 then 4 elseif level < 75 then 6 elseif level < 93 then 8 else 13
	return level // 10 + bonus
end

-- The food the island top-up eats: whole pieces that each heal without going past full.
function Read.food_top_up(): number
	local hp, real = Player.hitpoints()
	if hp == nil or real == nil or hp >= real then
		return 0
	end
	return (real - hp) // Read.food_heal()
end

function Read.wants_hp_top_up(): boolean
	return Read.food_top_up() > 0 and ready(CONST.FOOD)
end

function Read.wants_prayer_top_up(): boolean
	local base, dose = Read.prayer_restore()
	local prayer, real = Player.prayer()
	return base ~= nil and prayer ~= nil and real ~= nil and real - prayer >= dose and ready(base)
end

-- Food at the rolled hitpoints level, a prayer potion at the rolled prayer level, an anti-venom once envenomed.
function Read.supplies_state(): State?
	local hp = Player.hitpoints()
	if hp and hp <= S.eat_at and ready(CONST.FOOD) then
		return "EAT"
	end
	local prayer = Player.prayer()
	local restore = Read.prayer_restore()
	if prayer and prayer <= S.restore_at and restore and ready(restore) then
		return "PRAYER_POTION"
	end
	if Player.poison() == "envenomed" and ready(CONST.ANTIVENOM) then
		return "ANTIVENOM"
	end
	return nil
end

-- Whether to leave the fight now: hitpoints or prayer down to where the script eats or drinks, with none of it left.
function Read.must_escape(): boolean
	local hp = Player.hitpoints()
	if hp and hp <= S.eat_at and Read.supply_slot(CONST.FOOD) == nil then
		Log.log(NAME, `Escaping: {hp} hitpoints and no food left`)
		return true
	end
	local prayer = Player.prayer()
	if prayer and prayer <= S.restore_at and Read.prayer_restore() == nil then
		Log.log(NAME, `Escaping: {prayer} prayer and nothing left to restore it`)
		return true
	end
	return false
end

-- The first boost of this kill still to take that is in the inventory; the ones that aren't are dropped.
function Read.next_boost(): string?
	while #S.boosts > 0 do
		local base = S.boosts[1]
		if Read.supply_slot(base) then
			return base
		end
		Log.log(NAME, `No {base} to boost with`)
		table.remove(S.boosts, 1)
	end
	return nil
end

-- Not attacking Zulrah while it can be hit: above water, and with the player on its tile or (walking there) on it on the server,
-- which is a step or two before the client shows it. A click in this phase gets ATTACK_PATIENCE_MS to show a hit or projectile.
function Read.wants_attack(npc: Host.Npc): boolean
	if phases.diving or npc.animation == CONST.DIVE_ANIMATION then
		return false
	end
	if Player.in_transit() then
		local server, tile = Host.server_tile(), Read.goal()
		if server == nil or tile == nil then
			return false
		end
		local goal = Read.world_tile(tile)
		if server.x ~= goal.x or server.y ~= goal.y then
			return false
		end
	end
	if S.attack_phase == phases.phase then
		local target = Player.attacking()
		if (target and target.index == npc.index) or time() - S.attack_at < CONST.ATTACK_PATIENCE_MS then
			return false
		end
	end
	return true
end

-- Adds the clouds on the way (their projectiles) and forgets the ones that are gone.
function Read.track_clouds()
	local now = time()
	for key, cloud in S.clouds do
		if cloud.gone_at <= now then
			S.clouds[key] = nil
		end
	end
	for _, p in ipairs(Host.projectiles() or {}) do
		if p.id == CONST.CLOUD_PROJECTILE then
			-- a new cloud on the tile of an old one lasts as long as the new one
			local key = `{p.target_x}:{p.target_y}`
			local gone_at = now + math.max(0, p.end_cycle - p.cycle) * 20 + CONST.CLOUD_MS
			local cloud = S.clouds[key]
			if cloud == nil or cloud.gone_at < gone_at then
				S.clouds[key] = { x = p.target_x, y = p.target_y, gone_at = gone_at }
			end
		end
	end
end

-- Whether a cloud covers the world tile.
local function clouded(tile: Host.Tile): boolean
	for _, cloud in S.clouds do
		local dx, dy = tile.x - cloud.x, tile.y - cloud.y
		if dx >= 0 and dx < CONST.CLOUD_SIZE and dy >= 0 and dy < CONST.CLOUD_SIZE then
			return true
		end
	end
	return false
end

-- While a cloud covers the phase's tile: the nearest tile around it out of every cloud, that can be walked to and Zulrah hit
-- from; back to the phase's tile once its cloud is gone.
function Read.update_cloud_dodge(npc: Host.Npc)
	local key = phases.target
	local home = key and CONST.TILES[key]
	if key == nil or home == nil or not clouded(Read.world_tile(home)) then
		if S.cloud_dodge and S.cloud_dodge.key == key then
			Log.log(NAME, `The cloud on {tile_label(key :: string)} is gone`)
		end
		S.cloud_dodge = nil
		return
	end
	local dodge = S.cloud_dodge
	if dodge and dodge.key == key and not clouded(Read.world_tile(dodge)) then
		return
	end
	local me = Read.scene_tile()
	for reach = 1, CONST.CLOUD_DODGE_REACH do
		local ring: { Host.Tile } = {}
		for dx = -reach, reach do
			for dy = -reach, reach do
				if math.max(math.abs(dx), math.abs(dy)) == reach then
					table.insert(ring, { x = home.x + dx, y = home.y + dy })
				end
			end
		end
		table.sort(ring, function(a: Host.Tile, b: Host.Tile): boolean
			return math.max(math.abs(a.x - me.x), math.abs(a.y - me.y))
				< math.max(math.abs(b.x - me.x), math.abs(b.y - me.y))
		end)
		for _, tile in ipairs(ring) do
			local world = Read.world_tile(tile)
			if not clouded(world) and Read.can_hit_from(tile, npc) and Read.arena_path(world) ~= nil then
				Log.log(NAME, `Cloud on {tile_label(key)}: standing on {tile.x},{tile.y} until it goes`)
				S.cloud_dodge = { key = key, x = tile.x, y = tile.y }
				return
			end
		end
	end
	if S.cloud_dodge then
		Log.log(NAME, `No tile around {tile_label(key)} is out of the clouds`)
	end
	S.cloud_dodge = nil
end

-- The arena's collision, read once a visit (the world map's walker doesn't know the instance).
function Read.arena_grid(): SafeSpot.Grid?
	if S.arena_grid == nil then
		S.arena_grid = SafeSpot.grid_around(Read.world_tile(CONST.ARENA_CENTER), CONST.ARENA_RADIUS)
	end
	return S.arena_grid
end

local STEPS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }

-- The tiles a walk from where we stand to the world tile steps on, over the arena's collision (nil when it can't be reached).
function Read.arena_path(goal: Host.Tile): { Host.Tile }?
	local grid = Read.arena_grid()
	local pos = snap.state.position
	if grid == nil or pos == nil then
		return nil
	end
	local function key(x: number, y: number): number
		return (x - grid.x) * grid.height + (y - grid.y)
	end
	local from: { [number]: number } = { [key(pos.x, pos.y)] = -1 }
	local queue, head = { { x = pos.x, y = pos.y } }, 1
	while head <= #queue do
		local at = queue[head]
		head += 1
		if at.x == goal.x and at.y == goal.y then
			local path: { Host.Tile } = {}
			local k = key(at.x, at.y)
			while from[k] ~= -1 do
				table.insert(path, 1, { x = grid.x + k // grid.height, y = grid.y + k % grid.height })
				k = from[k]
			end
			return path
		end
		for _, d in STEPS do
			local x, y = at.x + d[1], at.y + d[2]
			local k = key(x, y)
			if from[k] == nil and SafeSpot.can_step(grid, at.x, at.y, d[1], d[2]) then
				from[k] = key(at.x, at.y)
				table.insert(queue, { x = x, y = y })
			end
		end
	end
	return nil
end

-- Whether Zulrah can be hit from the scene tile with the weapon worn now.
function Read.can_hit_from(scene: Host.Tile, npc: Host.Npc): boolean
	local range = CombatSafeSpot.weapon_range()
	local grid = Read.arena_grid()
	if range == nil or grid == nil then
		return false
	end
	return CombatSafeSpot.can_attack(grid, Read.world_tile(scene), SafeSpot.chaser(npc, CONST.ZULRAH_SIZE), range)
end

-- The next phase's tile to walk to before Zulrah dives: not in a red phase (its dodges need their tiles), once the rolled
-- moment has come, when every rotation left agrees on the tile, Zulrah can still be hit from it and no cloud is on the way.
function Read.early_tile(npc: Host.Npc, t: Transformation): string?
	if phases.diving or t.key == "magma" or time() < phases.early_at then
		return nil
	end
	local key = agreed(phases.phase + 1, 3)
	if key == nil or key == phases.target or not Read.can_hit_from(CONST.TILES[key], npc) then
		return nil
	end
	local goal = Read.world_tile(CONST.TILES[key])
	local path = Read.arena_path(goal)
	if path == nil or clouded(goal) then
		return nil
	end
	for _, tile in ipairs(path) do
		if clouded(tile) then
			return nil
		end
	end
	Log.log(NAME, "Getting ahead of the next phase")
	return key
end

-- whether an item stacks in the inventory, by id (it never changes)
local stacks: { [number]: boolean } = {}

local function stackable(id: number): boolean
	if stacks[id] == nil then
		stacks[id] = (Host.item_stackable({ id }) or {})[1] == true
	end
	return stacks[id]
end

-- The nearest item on the arena's floor to pick up, one that fits first; everything for now (TODO: leave low value items on the
-- ground).
function Read.next_loot(): Host.GroundItem?
	local me = Walker.position()
	if me == nil then
		return nil
	end
	local best: Host.GroundItem? = nil
	local best_d, best_fits = math.huge, false
	for _, item in ipairs(Host.ground_items() or {}) do
		local d, fits = GroundItems.distance(item, me), GroundItems.fits(item)
		if not S.no_room[item.id] and ((fits and not best_fits) or (fits == best_fits and d < best_d)) then
			best, best_d, best_fits = item, d, fits
		end
	end
	return best
end

-- Whether every item on the tile fits at once: a slot each, but a stack carried already takes none and a new stack only one.
function Read.pile_fits(tile: Host.Tile): boolean
	local needed, counted = 0, {}
	for _, item in ipairs(Host.ground_items() or {}) do
		if item.x == tile.x and item.y == tile.y and not S.no_room[item.id] then
			if not stackable(item.id) then
				needed += 1
			elseif not counted[item.id] and Inventory.find(item.id) == nil then
				counted[item.id] = true
				needed += 1
			end
		end
	end
	return needed <= (Inventory.free_slots() or 0)
end

-- The teleport scroll Zulrah leaves on the floor when it dies.
function Read.teleport(): Host.Loc?
	local me = Walker.position()
	return if me then Objects.nearest(CONST.TELEPORT_LOC, me) else nil
end

-- Off the tile to stand on, and not already walking to it.
function Read.wants_move(): boolean
	local tile, name = Read.goal()
	if tile == nil then
		return false
	end
	local me = Read.scene_tile()
	if me.x == tile.x and me.y == tile.y then
		return false
	end
	return not (S.moving_to == name and Player.in_transit())
end

-- The scene tile to stand on and its name: the phase's tile, or the one beside it while a cloud covers it.
function Read.goal(): (Host.Tile?, string?)
	local key = phases.target
	if key == nil then
		return nil, nil
	end
	local dodge = S.cloud_dodge
	if dodge and dodge.key == key then
		return { x = dodge.x, y = dodge.y }, `cloud dodge {dodge.x},{dodge.y}`
	end
	return CONST.TILES[key], key
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
		return Read.restock_state()
	end
	local pos = assert(snap.state.position)
	if Position.Chunk.new(pos.x // 64, pos.y // 64):id() == CONST.ZULANDRA_CHUNK then
		return Read.island_state()
	end
	if Ferox.inside() and Read.wants_pool() then
		return "FEROX"
	end
	return Read.restock_state()
end

-- the first phase's gear, when it isn't worn
function Read.first_gear_off(): EquipmentLayout.Layout?
	local first = CONFIG.transformations[CONST.TRANSFORMATIONS[1].key]
	local layout = first and first.equipment
	return if layout and EquipmentLayout.matches(layout) == false then layout else nil
end

-- off the island: the first phase's gear on before the inventory (whose layout holds the other set), out of the bank if it isn't
-- carried; the bank until the inventory layout is held, then the scroll back
function Read.restock_state(): State
	local open = Bankmain.is_open()
	local gear = Read.first_gear_off()
	if gear then
		return if #EquipmentLayout.missing(gear) > 0 then "BANKING" else "PREPARE_GEAR"
	end
	local layout = CONFIG.inventory
	if not open and layout and InventoryLayout.matches(layout) then
		return "TELEPORT_ZULANDRA"
	end
	return "BANKING"
end

-- On the island: what was left behind first, then a restock if a kill needs one (counted after the top-ups), prayer topped up
-- by whole doses and hitpoints by whole pieces of food, the first phase's gear (Zulrah starts green), then the boat.
function Read.island_state(): State
	if died then
		return "RECOVER_GEAR"
	end
	if Read.needs_restock() then
		return Read.restore_state()
	end
	-- a dose shows on the next tick: until then the prayer and doses read are from before it
	local restore = Read.prayer_restore()
	if restore and time() - (S.used_at[restore] or -math.huge) < CONST.CONSUME_MS then
		return "LOADING"
	end
	if Read.wants_prayer_top_up() then
		return "PRAYER_POTION"
	end
	if time() - (S.used_at[CONST.FOOD] or -math.huge) < CONST.CONSUME_MS then
		return "LOADING"
	end
	if Read.wants_hp_top_up() then
		return "EAT"
	end
	local first = CONFIG.transformations[CONST.TRANSFORMATIONS[1].key]
	if first and first.equipment and EquipmentLayout.matches(first.equipment) == false then
		return "PREPARE_GEAR"
	end
	if ChatOptions.is_title(CONST.BOARD_QUESTION) then
		return "CONFIRM_BOAT"
	end
	return "BOARD_BOAT"
end

-- The prayer restore doses held, of every kind in CONST.PRAYER_RESTORES.
function Read.prayer_doses(): number
	local doses = 0
	for _, item in ipairs(Inventory.items() or {}) do
		for _, r in CONST.PRAYER_RESTORES do
			local n = item.name and string.match(item.name, `^{r.base}%((%d)%)$`)
			if n then
				doses += tonumber(n) :: number
			end
		end
	end
	return doses
end

-- Too few supplies for another kill: less food, or fewer prayer doses once the island's top-up has drunk its whole doses,
-- than the settings ask for.
function Read.needs_restock(): boolean
	if (Inventory.count(CONST.FOOD) or 0) - Read.food_top_up() < CONFIG.min_food then
		return true
	end
	local _, dose = Read.prayer_restore()
	local prayer, real = Player.prayer()
	local top_up = if dose > 0 and prayer and real then (real - prayer) // dose else 0
	return Read.prayer_doses() - top_up < CONFIG.min_prayer_doses
end

-- In the house: hitpoints or prayer below full, for the pool.
function Read.wants_pool(): boolean
	local hp, max_hp = Player.hitpoints()
	local prayer, max_prayer = Player.prayer()
	return (hp ~= nil and max_hp ~= nil and hp < max_hp)
		or (prayer ~= nil and max_prayer ~= nil and prayer < max_prayer)
end

-- The bank in CONST.BANKS the planner gets to in the fewest ticks from here, with that estimate.
function Read.fastest_bank(): { name: string, x: number, y: number, plane: number, ticks: number }?
	local here = Player.position()
	if here == nil then
		return nil
	end
	local best: { name: string, x: number, y: number, plane: number, ticks: number }? = nil
	for _, bank in CONST.BANKS do
		local choice = Transports.choose(here :: any, { x = bank.x, y = bank.y, plane = bank.plane })
		if choice and (best == nil or choice.ticks < best.ticks) then
			best = { name = bank.name, x = bank.x, y = bank.y, plane = bank.plane, ticks = math.floor(choice.ticks) }
		end
	end
	return best
end

-- The state that teleports to where the "Restore method" setting restocks.
function Read.restore_state(): State
	return if CONFIG.restore == "Ferox Enclave" then "TELEPORT_FEROX" else "TELEPORT_HOUSE"
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
		{
			id = "restore",
			kind = "choice",
			label = "Restore method:",
			options = CONST.RESTORE_METHODS,
			default = CONFIG.restore,
		},
		{
			id = "min_food",
			kind = "number",
			label = "Minimum food per kill",
			default = CONFIG.min_food,
			min = 0,
			max = 28,
			integer = true,
		},
		{
			id = "min_prayer_doses",
			kind = "number",
			label = "Minimum prayer doses per kill",
			default = CONFIG.min_prayer_doses,
			min = 0,
			max = 112,
			integer = true,
		},
	}
	fields[#fields + 1] = { kind = "label", text = "Forms", heading = 1 }
	for _, transformation in CONST.TRANSFORMATIONS do
		fields[#fields + 1] = { kind = "label", text = transformation.name, heading = 2 }
		fields[#fields + 1] = {
			id = `{transformation.key}_equipment`,
			kind = "equipment",
			label = "Equipment",
			row = transformation.key,
		}
		fields[#fields + 1] = {
			id = `{transformation.key}_prayers`,
			kind = "prayer",
			label = "Prayers",
			locked = CONST.OVERHEADS,
			row = transformation.key,
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
	CONFIG.restore = values.restore or CONFIG.restore
	CONFIG.min_food = values.min_food or CONFIG.min_food
	CONFIG.min_prayer_doses = values.min_prayer_doses or CONFIG.min_prayer_doses
	for _, transformation in CONST.TRANSFORMATIONS do
		CONFIG.transformations[transformation.key] = {
			equipment = values[`{transformation.key}_equipment`],
			prayers = Read.with_protection(values[`{transformation.key}_prayers`], transformation),
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
	elseif CONFIG.max_runs > 0 and stats.runs >= CONFIG.max_runs and not S.in_arena then
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
		-- the teleport scroll lies there once it is dead: a run started after a kill has nothing to fight
		S.zulrah_alive, S.zulrah_dying = Read.teleport() == nil, false
		phases = new_phases()
		phases.target = string.split(CONST.ROTATIONS[1].phases[1], " ")[3]
		S.attack_phase, S.moving_to, S.cloud_dodge = -1, nil, nil
		S.clouds, S.arena_grid, S.no_room = {}, nil, {}
		S.boosts = { CONST.HEART, CONST.RANGING_POTION }
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
		-- walking to a tile: the mouse goes to Zulrah ahead of the attack click at the end of the walk
		local npc = Read.zulrah()
		if npc and S.moving_to and not S.hovered_on_walk and Player.in_transit() then
			S.hovered_on_walk = true
			Npcs.hover_async(npc)
		end
	end,
	ATTACK = function()
		local npc = Read.zulrah()
		if npc == nil then
			return
		end
		if Npcs.interact(npc, "Attack", false) then
			S.attack_phase, S.attack_at = phases.phase, time()
		else
			Log.log(NAME, "Couldn't click Attack on Zulrah")
			S.skip["ATTACK"] = true
		end
	end,
	EAT = function()
		if Handler.use(CONST.FOOD, "Eat", "EAT") then
			S.eat_at = Random.int(CONST.EAT_AT[1], CONST.EAT_AT[2])
		end
	end,
	PRAYER_POTION = function()
		local base = Read.prayer_restore()
		if base and Handler.use(base, "Drink", "PRAYER_POTION") then
			S.restore_at = Random.int(CONST.RESTORE_AT[1], CONST.RESTORE_AT[2])
		end
	end,
	ANTIVENOM = function()
		Handler.use(CONST.ANTIVENOM, "Drink", "ANTIVENOM")
	end,
	BOOST = function()
		local base = Read.next_boost()
		if base == nil then
			return
		end
		if Handler.use(base, if base == CONST.HEART then "Invigorate" else "Drink", "BOOST") then
			table.remove(S.boosts, 1)
		end
	end,
	MOVE = function()
		local tile, name = Read.goal()
		if tile == nil or name == nil then
			return
		end
		if Walker.click_tile(Read.world_tile(tile)) then
			-- a walk ends the attack: it is clicked again as the walk ends
			S.moving_to, S.hovered_on_walk, S.attack_phase = name, false, -1
		else
			Log.log(NAME, `Couldn't click the {tile_label(name)} tile`)
			S.skip["MOVE"] = true
		end
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
	LOOT = function()
		local item = Read.next_loot()
		if item == nil then
			return
		end
		-- the whole pile is wanted: left clicks, in the game's menu order
		local tile = { x = item.x, y = item.y }
		if Read.pile_fits(tile) then
			local taken, why = GroundItems.take_pile(tile)
			if why == "failed" then
				Log.log(NAME, `Couldn't take the pile at {tile.x},{tile.y} ({taken} taken)`)
				S.skip["LOOT"] = true
			end
			return
		end
		if not GroundItems.interact(item, "Take") then
			Log.log(NAME, `Couldn't take the {item.name or item.id}`)
			S.skip["LOOT"] = true
			return
		end
		local started = time()
		while GroundItems.refresh(item) ~= nil and time() - started < CONST.LOOT_WAIT_MS do
			sleep(100)
		end
	end,
	EAT_FOR_SPACE = function()
		local item = Read.next_loot()
		if item == nil then
			return
		end
		if Read.supply_slot(CONST.FOOD) == nil then
			Log.log(NAME, `No room for the {item.name or item.id} and no food to eat for it: leaving it`)
			S.no_room[item.id] = true
			return
		end
		-- the slot frees on the next tick: until then the inventory still looks full
		local free = Inventory.free_slots() or 0
		if Handler.use(CONST.FOOD, "Eat", "EAT_FOR_SPACE") then
			local started = time()
			while (Inventory.free_slots() or 0) <= free and time() - started < CONST.CONSUME_MS do
				sleep(50)
			end
		end
	end,
	LEAVE = function()
		local scroll = Read.teleport()
		if scroll == nil or not Objects.interact(scroll, CONST.TELEPORT_OPTION) then
			Log.log(NAME, "Couldn't read the teleport scroll")
			S.skip["LEAVE"] = true
			return
		end
		if not ChatOptions.wait_title(CONST.LEAVE_QUESTION, CONST.QUESTION_WAIT_MS) then
			Log.log(NAME, "The teleport scroll didn't ask to leave")
		end
	end,
	CONFIRM_LEAVE = function()
		if not ChatOptions.select(CONST.LEAVE_ANSWER) then
			Log.log(NAME, `Couldn't answer "{CONST.LEAVE_ANSWER}" to the teleport scroll`)
			S.skip["CONFIRM_LEAVE"] = true
			return
		end
		local started = time()
		while Player.in_instance() and time() - started < CONST.TELEPORT_WAIT_MS do
			sleep(100)
		end
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
	RECOVER_GEAR = function()
		Handler.antiban("RECOVER_GEAR")
		-- TODO: take the items from the collection interface (it can't be read yet), then set `died` back to false
		if time() < S.collect_retry_at then
			return
		end
		local priestess = Npcs.nearest(CONST.PRIESTESS, assert(Walker.position()))
		if priestess and Npcs.interact(priestess, "Collect") then
			S.collect_retry_at = time() + CONST.COLLECT_RETRY_MS
		else
			Log.log(NAME, `Couldn't click Collect on {CONST.PRIESTESS}`)
			S.skip["RECOVER_GEAR"] = true
		end
	end,
	BOARD_BOAT = function()
		Handler.antiban("BOARD_BOAT")
		local boat = Objects.nearest(CONST.BOAT, assert(Walker.position()))
		-- from where the scroll lands the boat may be off screen: approach walks closer when it can't be aimed at
		if boat == nil or not Objects.approach(boat, "Board") then
			Log.log(NAME, `Couldn't board the {CONST.BOAT}`)
			S.skip["BOARD_BOAT"] = true
			return
		end
		if not ChatOptions.wait_title(CONST.BOARD_QUESTION, CONST.QUESTION_WAIT_MS) then
			Log.log(NAME, "The boat didn't ask to go to the shrine")
		end
	end,
	CONFIRM_BOAT = function()
		if not ChatOptions.select(CONST.BOARD_ANSWER) then
			Log.log(NAME, `Couldn't answer "{CONST.BOARD_ANSWER}" to the boat`)
			S.skip["CONFIRM_BOAT"] = true
			return
		end
		local started = time()
		while not Player.in_instance() and time() - started < CONST.BOARD_WAIT_MS do
			sleep(100)
		end
	end,
	PREPARE_GEAR = function()
		if Bankmain.is_open() and not Bankmain.close() then
			S.skip["PREPARE_GEAR"] = true
			return
		end
		local t = CONST.TRANSFORMATIONS[1]
		local layout = CONFIG.transformations[t.key].equipment
		if layout and not EquipmentLayout.equip(layout) then
			Log.log(NAME, `Couldn't put on the {t.label} gear ({layout.name})`)
			S.skip["PREPARE_GEAR"] = true
		end
	end,
	TELEPORT_HOUSE = function()
		local tablet = Inventory.find(CONST.HOUSE_TABLET)
		local outside = Varbits.get(CONST.HOUSE_OUTSIDE_VARBIT) == 1
		local ok = if tablet
			then Inventory.interact_slot(tablet, CONST.HOUSE_TABLET_OPTION)
			else Magic.cast(CONST.HOUSE_SPELL, if outside then "Inside" else nil)
		if not ok then
			Log.log(NAME, "Couldn't teleport to the house: no tablet held, or the spell can't be cast")
			S.skip["TELEPORT_HOUSE"] = true
			return
		end
		Log.log(
			NAME,
			`Teleporting to the house to restock ({Inventory.count(CONST.FOOD) or 0} food, {Read.prayer_doses()} prayer doses left)`
		)
		local started = time()
		while not House.inside() and time() - started < CONST.TELEPORT_WAIT_MS do
			sleep(200)
		end
	end,
	TELEPORT_FEROX = function()
		Log.log(NAME, `Teleporting to the {CONST.FEROX} to restock`)
		local landed, pointless = Transports.teleport_item(CONST.DUELING_FEROX)
		if landed then
			return
		end
		if pointless then
			local message =
				`Couldn't teleport to the {CONST.FEROX}: bring a ring of dueling, or pick another restore method`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, `The ring of dueling didn't take us to the {CONST.FEROX}`)
		S.skip["TELEPORT_FEROX"] = true
	end,
	FEROX = function()
		local restored, why = Ferox.restore()
		if not restored then
			Log.log(NAME, `Couldn't restore at the {CONST.FEROX} pool: {why}`)
			S.skip["FEROX"] = true
		end
	end,
	HOUSE = function()
		House.survey()
		if House.furniture("pool") == CONST.ORNATE_POOL then
			if Read.wants_pool() then
				local restored, why = House.restore()
				if not restored then
					Log.log(NAME, `Couldn't restore at the pool: {why}`)
					S.skip["HOUSE"] = true
				end
				return
			end
			local bank = Read.fastest_bank()
			if bank == nil then
				Log.log(NAME, "The planner found no way to a bank from the house: stopping the script")
				S.finished = true
				return
			end
			Log.log(NAME, `Going to the {bank.name} bank, the fastest from here (about {bank.ticks} ticks)`)
			if not Walker.walk({ x = bank.x, y = bank.y, plane = bank.plane }) then
				Log.log(NAME, `Couldn't get to the {bank.name} bank`)
				S.skip["HOUSE"] = true
			end
			return
		end
		if not table.find(House.offers(CONST.FEROX), "box") then
			local message =
				`No {CONST.ORNATE_POOL} or jewellery box in this house: use a ring of dueling to teleport to the {CONST.FEROX} instead`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, `Teleporting to the {CONST.FEROX} with the jewellery box`)
		local left, why = House.teleport(CONST.FEROX)
		if not left then
			Log.log(NAME, `Couldn't teleport to the {CONST.FEROX}: {why}`)
			S.skip["HOUSE"] = true
		end
	end,
	BANKING = function()
		local layout = CONFIG.inventory
		if layout == nil then
			local message = "No inventory layout to restock: pick one in the script's settings"
			Log.warn(NAME, message)
			error(message, 0)
		end
		if InventoryLayout.matches(layout) then
			if Bankmain.is_open() and not Bankmain.close() then
				S.skip["BANKING"] = true
				return
			end
			if not InventoryLayout.reorder(layout) then
				Log.log(NAME, `Couldn't put the inventory in the order of the {layout.name} layout`)
			end
			Log.log(NAME, "Restocked")
			return
		end
		-- antiban opens tabs, which closes the bank: only before it is opened
		if not Bankmain.is_open() then
			Handler.antiban("BANKING")
			if not Bankmain.open() then
				Log.log(NAME, "Couldn't open a bank")
				S.skip["BANKING"] = true
				return
			end
		end
		local gear = Read.first_gear_off()
		local done = if gear then EquipmentLayout.withdraw(gear) else InventoryLayout.withdraw(layout)
		if done then
			S.restock_failures = 0
			return
		end
		S.restock_failures += 1
		if S.restock_failures >= CONST.RESTOCK_ATTEMPTS then
			local message =
				`Couldn't restock the {layout.name} layout {S.restock_failures} times: is the bank out of something?`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, `Couldn't restock the {layout.name} layout, trying again`)
	end,
	TELEPORT_ZULANDRA = function()
		Log.log(NAME, "Teleporting back to Zul-Andra")
		local landed, pointless = Transports.teleport_item(CONST.ZULANDRA_TELEPORT)
		if landed then
			return
		end
		if pointless then
			local message =
				`Couldn't teleport back to Zul-Andra: put Zul-andra teleport scrolls in the inventory layout`
			Log.warn(NAME, message)
			error(message, 0)
		end
		Log.log(NAME, "The Zul-andra teleport didn't take us to Zul-Andra")
		S.skip["TELEPORT_ZULANDRA"] = true
	end,
}

-- Uses the slot of `base` (Read.supply_slot) with `option`; a miss is logged and its state skipped for one loop.
function Handler.use(base: string, option: string, state: State): boolean
	local slot = Read.supply_slot(base)
	if slot and Inventory.interact_slot(slot, option) then
		S.used_at[base] = time()
		Log.log(NAME, `{option}: {base}`)
		return true
	end
	Log.log(NAME, `Couldn't {string.lower(option)} the {base}`)
	S.skip[state] = true
	return false
end

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
-- an interface opened by accident (a click on the wrong thing) blocks every click: closed, but not the bank while banking
local last_stray_at = 0
local function close_stray(state: State)
	if not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	if state == "BANKING" and Bankmain.is_open() then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.run()
	if not Game.ask() then
		Log.log(NAME, "Form closed, stopping the script")
		return
	end
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
		close_stray(state)
		Game.poll_settings()
		Handler.states[state]()

		if CONFIG.antiban and S.antiban_ready and not S.in_arena then
			Antiban.do_async_tasks("outside")
		end
		sleep(Random.int(60, 140))
	end
	Log.log(NAME, "Done")
end

Loop.run()
