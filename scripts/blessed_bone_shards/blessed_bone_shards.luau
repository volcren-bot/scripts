--!strict
local Host = require("@volcren/host")
local game_state = Host.game_state
local sleep = Host.sleep
local time = Host.time
type ClientState = Host.ClientState
local Antiban = require("@volcren/antiban")
local AntibanTasks = require("@volcren/antiban_tasks")
local Bankmain = require("@volcren/bankmain")
local Biometrics = require("@volcren/biometrics")
local ChatOptions = require("@volcren/chat_options")
local GameState = require("@volcren/game_state")
local Handoff = require("@volcren/handoff")
local Inventory = require("@volcren/inventory")
local Log = require("@volcren/log")
local Login = require("@volcren/login")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Random = require("@volcren/random")
local StatsReport = require("@volcren/stats_report")
local Ticks = require("@volcren/ticks")
local Toplevel = require("@volcren/toplevel")
local Walker = require("@volcren/walker")
local Widgets = require("@volcren/widgets")

local NAME = "Blessed bone shards"

local CONST = {
	CHISEL = "Chisel",
	COINS = "Coins",
	SHARDS = "Blessed bone shards",
	BANK_TILE = { x = 1519, y = 3228, plane = 0 },
	BANK_NEAR = 5,
	BANK_TABLE = "Bank table",
	BANK_TABLE_SPREAD = 4,
	SIGHT = 20,
	SIGHT_CHECK_MS = 600,
	VIRILIS = "Virilis",
	VIRILIS_TILE = { x = 1441, y = 3154, plane = 0 },
	VIRILIS_NEAR = 8,
	VIRILIS_SPREAD = 3,
	ALTAR = "Exposed altar",
	UNNOTE_COST = 10,
	DIALOG_TIMEOUT_MS = 5000,
	BLESS_TIMEOUT_MS = 10000,
	TOOL_SLOT = 27,
	CHISEL_ANIMATION = 11099,
	JUG = "Jug of wine",
	SUNFIRE = "Jug of sunfire wine",
	SPLINTERS = "Sunfire splinters",
	PESTLE = "Pestle and mortar",
	SPLINTERS_PER_WINE = 2,
	SUNFIRE_ANIMATION = 11095,
	SHARDS_PER_WINE = 400,
	BLESSED = { "Jug of blessed wine", "Jug of blessed sunfire wine" },
	WINE_BLESS_TIMEOUT_MS = 15000,
	BOWL = "Libation bowl",
	BOWL_OPTIONS = { "Sacrifice", "Fill" },
	BOWL_TILE = { x = 1457, y = 3188, plane = 0 },
	BOWL_NEAR = 1,
	BOWL_REACH_MS = 30000,
	BOWL_STILL_MS = 1800,
	OFFER_CLICK_MS = { 150, 500 },
	BOWL_DRY_MS = 4200,
	SHRINE = "Shrine of Ralos",
	SHRINE_TILE = { x = 1450, y = 3173, plane = 0 },
	SHRINE_NEAR = 3,
	RESTORE_TIMEOUT_MS = 15000,
	MIN_PRAYER = 2,
	MAX_IDLE_USES = 6,
	EMPTY_JUG = "Jug",
	AFK = { chance = 0.1, after = { 1, 4 }, ms = { 5000, 40000 } },
	SHARDS_PER_SACRIFICE = 100,
	DROP_BATCH = { 2, 3 },
	DROP_GAP_MS = { 1500, 3500 },
	DROP_MIN_WALK = 5,
	DROP_PACE = { shift_ms = { 60, 110 }, gap_ms = { 0, 120 }, confirm = false },
	PHASES = {
		["Breaking"] = { "BREAK" },
		["Sunfire wines"] = { "WINE" },
		["Offering"] = { "WINE", "OFFER" },
		["All"] = { "BREAK", "WINE", "OFFER" },
	} :: { [string]: { Phase } },
	BUSY_GRACE_MS = 3600,
	BURST = { fast_inventory = 0.4, micro_burst = 0.2, slow_stretch = 0.05, stretch = { 4, 12 }, start_delay_ms = 80 },
	SLOW_PAUSE_MS = 600,
	REOPEN_INVENTORY_MS = { 600, 4000 },
	PRE_BLESSED = { ["Sun-kissed bones"] = true },
	BREAKS = {
		["Sun-kissed bones"] = 29378,
		["Bones"] = 29344,
		["Bat bones"] = 29346,
		["Big bones"] = 29348,
		["Wyrmling bones"] = 29354,
		["Zogre bones"] = 29350,
		["Babydragon bones"] = 29352,
		["Wyrm bones"] = 29364,
		["Strykewyrm bones"] = 31264,
		["Wyvern bones"] = 29360,
		["Dragon bones"] = 29356,
		["Drake bones"] = 29366,
		["Fayrg bones"] = 29370,
		["Lava dragon bones"] = 29358,
		["Raurg bones"] = 29372,
		["Frost dragon bones"] = 31266,
		["Hydra bones"] = 29368,
		["Ourg bones"] = 29374,
		["Superior dragon bones"] = 29362,
	} :: { [string]: number },
	REPORT = { counters_key = "" },
}

local Read, Game, Loop, Handler = {}, {}, {}, {}

type Phase = "BREAK" | "WINE" | "OFFER"
type WineStep = "BANK" | "MAKE"
type Craft = { tool: string, target: number | string, animation: number }

local CONFIG = {
	mode = "Breaking",
	bones = "Sun-kissed bones",
	max_bones = 0,
	wine = "Wine",
	sunfire_wines = 0,
	fast_bursts = true,
	timeouts = { idle_minutes = 5, max_failures = 4 },
	antiban = true,
}

local stats = { bones = 0, shards = 0, sunfire_made = 0, offered = 0, failures = 0 }

type RunState = {
	finished: boolean,
	blocked: string?,
	antiban_ready: boolean,
	antiban_began_at: number,
	last_progress_at: number,
	busy_until: number,
	phases: { Phase },
	phase_index: number,
	phase: Phase,
	wine_step: WineStep,
	sunfire_goal: number?,
	seen_targets: number?,
	seen_shards: number?,
	fast_inventory: boolean,
	flip_from: number,
	flip_to: number,
	target_slot: number?,
	reopen_inventory_at: number?,
	failures_in_row: number,
	idle_uses: number,
	next_drop_at: number,
	afk: { wine: number, after: number, ms: number }?,
	fills: number,
	offer_bank: boolean,
}

function Game.apply_settings(values: { [string]: any })
	CONFIG.mode = values.mode or CONFIG.mode
	CONFIG.bones = values.bones or CONFIG.bones
	CONFIG.max_bones = values.max_bones or CONFIG.max_bones
	CONFIG.wine = values.wine or CONFIG.wine
	CONFIG.sunfire_wines = values.sunfire_wines or CONFIG.sunfire_wines
end

function Game.poll_settings()
	local values = Host.form_update()
	if values then
		Game.apply_settings(values)
		Log.log(NAME, "Settings updated")
	end
end

local S: RunState = {
	finished = false,
	blocked = nil,
	antiban_ready = false,
	antiban_began_at = 0,
	last_progress_at = 0,
	busy_until = 0,
	phases = {},
	phase_index = 1,
	phase = "BREAK",
	wine_step = "BANK",
	sunfire_goal = nil,
	seen_targets = nil,
	seen_shards = nil,
	fast_inventory = false,
	flip_from = 0,
	flip_to = 0,
	target_slot = nil,
	reopen_inventory_at = nil,
	failures_in_row = 0,
	idle_uses = 0,
	next_drop_at = 0,
	afk = nil,
	fills = 0,
	offer_bank = true,
}

type State =
	"LOADING"
	| "LOGIN"
	| "BANK"
	| "EXCHANGE"
	| "BLESS"
	| "WINE_BANK"
	| "OFFER_BANK"
	| "BLESS_WINE"
	| "RESTORE"
	| "OFFER"
	| "CRAFT"
	| "BURST"
	| "WAIT"
	| "STALLED"

local report = StatsReport.new()

function Read.scene_loading(s: ClientState): boolean
	return s.game_state == GameState.LOADING or s.game_state == GameState.HOPPING or s.game_state == GameState.LOGGED_IN
end

function Read.bones_left(): number
	if CONFIG.max_bones <= 0 then
		return math.huge
	end
	return math.max(CONFIG.max_bones - stats.bones, 0)
end

function Read.unsupported(): string?
	local phases = CONST.PHASES[CONFIG.mode]
	if phases == nil then
		return `there is no {CONFIG.mode} mode`
	end
	local breaks = phases[1] == "BREAK"
	if breaks and CONST.BREAKS[CONFIG.bones] == nil then
		return `{CONFIG.bones} can't be blessed`
	end
	return nil
end

function Read.craft(): Craft
	if S.phase == "WINE" then
		return { tool = CONST.SPLINTERS, target = CONST.JUG, animation = CONST.SUNFIRE_ANIMATION }
	end
	return { tool = CONST.CHISEL, target = Read.breakable(), animation = CONST.CHISEL_ANIMATION }
end

function Read.targets(): number
	return Inventory.count(Read.craft().target) or 0
end

function Read.needs_altar(): boolean
	return not CONST.PRE_BLESSED[CONFIG.bones]
end

function Read.breakable(): number
	return CONST.BREAKS[CONFIG.bones]
end

local stackable_ids: { [number]: boolean } = {}

function Read.stacks(id: number): boolean
	local known = stackable_ids[id]
	if known == nil then
		local found = Host.item_stackable({ id })
		known = found ~= nil and found[1] == true
		stackable_ids[id] = known
	end
	return known
end

type Unblessed = { loose: number, notes: number, notes_slot: number? }

function Read.unblessed(): Unblessed
	local found: Unblessed = { loose = 0, notes = 0, notes_slot = nil }
	for _, item in ipairs(Inventory.items() or {}) do
		if item.name == CONFIG.bones then
			if Read.stacks(item.id) then
				found.notes += item.quantity
				found.notes_slot = item.slot
			else
				found.loose += 1
			end
		end
	end
	return found
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
	local MINUTE, SECOND = Antiban.MINUTE, Antiban.SECOND
	Antiban.set_zoom_range(0, 30)
	Antiban.set_pitch_range(80, 100)

	AntibanTasks.skills = { "Prayer" }
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
		if Game.ensure_logged_in(state) then
			break
		end
		sleep(100)
	end

	Biometrics.setup_player()
	if CONFIG.antiban and not S.antiban_ready then
		Game.setup_antiban()
	end
end

function Game.fail(why: string)
	Log.log(NAME, why)
	stats.failures += 1
	S.failures_in_row += 1
end

type Spot = { x: number, y: number, plane: number }

function Game.walk_to(
	goal: Spot,
	within: number,
	spread: number,
	label: string,
	in_sight: (() -> boolean)?,
	while_walking: (() -> ())?
): boolean
	local here = Walker.position()
	if here and here.plane == goal.plane and Walker.distance(here, goal) <= within then
		return true
	end
	if in_sight and in_sight() then
		return true
	end
	Log.log(NAME, `Walking to {label}`)
	local target = {
		x = goal.x + Random.int(-spread, spread + 1),
		y = goal.y + Random.int(-spread, spread + 1),
		plane = goal.plane,
	}
	local next_check = 0
	local options: Walker.WalkOptions = {
		near = 1,
		plane = goal.plane,
		on_step = function()
			if while_walking then
				while_walking()
			end
			if in_sight == nil or time() < next_check then
				return true
			end
			next_check = time() + CONST.SIGHT_CHECK_MS
			return not in_sight()
		end,
	}
	local ok, walked = pcall(Walker.walk, target, options)
	if ok and not walked and in_sight and in_sight() then
		return true
	end
	if not ok or not walked then
		Game.fail(`Couldn't walk to {label}: {if ok then "the walk stopped" else walked}`)
		return false
	end
	return true
end

function Game.next_phase()
	S.phase_index += 1
	local phase = S.phases[S.phase_index]
	if phase == nil then
		S.finished = true
		return
	end
	S.phase, S.wine_step = phase, "BANK"
	S.seen_targets, S.target_slot, S.idle_uses, S.offer_bank = nil, nil, 0, true
	S.fast_inventory, S.flip_from, S.flip_to = false, 0, 0
	Log.log(NAME, `Moving on to {string.lower(phase)}`)
end

function Game.finish_if_done(): boolean
	if Read.bones_left() > 0 then
		return false
	end
	Log.log(NAME, `Broke {stats.bones} bones`)
	Game.next_phase()
	return true
end

function Game.out_of_bones()
	Log.log(NAME, `Out of {CONFIG.bones} after breaking {stats.bones}`)
	Game.next_phase()
end

function Game.withdraw_chisel(): boolean
	if Inventory.contains(CONST.CHISEL) then
		return true
	end
	if not Bankmain.contains(CONST.CHISEL) then
		S.blocked = "no chisel in the bank"
		S.finished = true
		return false
	end
	if not Bankmain.withdraw(CONST.CHISEL, 1, false) then
		Game.fail("Couldn't withdraw a chisel")
		return false
	end
	return true
end

function Read.near(goal: Spot, range: number): Host.Tile?
	local here = Walker.position()
	if here == nil or here.plane ~= goal.plane or Walker.distance(here, goal) > range then
		return nil
	end
	return here
end

function Read.fixed_bank(): Host.Loc?
	local here = Read.near(CONST.BANK_TILE, CONST.SIGHT)
	local loc = here and Objects.nearest(CONST.BANK_TABLE, here)
	if loc == nil or Walker.distance(loc, CONST.BANK_TILE) > CONST.BANK_TABLE_SPREAD then
		return nil
	end
	return loc
end

function Game.drop_jugs()
	if time() < S.next_drop_at or Bankmain.is_open() then
		return
	end
	local here, going = Walker.position(), Player.destination()
	if here == nil or going == nil or Walker.distance(here, going) < CONST.DROP_MIN_WALK then
		return
	end
	local slots = Inventory.indices_of(CONST.EMPTY_JUG)
	if slots == nil or #slots == 0 then
		return
	end
	local ordered = (Inventory.pattern(slots))
	local batch =
		table.move(ordered, 1, math.min(Random.int(CONST.DROP_BATCH[1], CONST.DROP_BATCH[2] + 1), #ordered), 1, {})
	Log.log(NAME, `Dropping {#batch} of {#ordered} empty jugs`)
	Inventory.shift_drop_slots(batch, CONST.DROP_PACE :: Inventory.DropOptions)
	S.next_drop_at = time() + Random.int(CONST.DROP_GAP_MS[1], CONST.DROP_GAP_MS[2])
end

function Game.open_bank(while_walking: (() -> ())?): boolean
	if Bankmain.is_open() then
		return true
	end
	if
		not Game.walk_to(CONST.BANK_TILE, CONST.BANK_NEAR, 0, "the bank", function()
			return Read.fixed_bank() ~= nil
		end, while_walking)
	then
		return false
	end
	local loc = Read.fixed_bank()
	if not Bankmain.open(if loc then { loc = loc } else nil) then
		Game.fail("Couldn't open the bank")
		return false
	end
	return true
end

function Game.close_bank(): boolean
	if not Bankmain.close() then
		Game.fail("Couldn't close the bank")
		return false
	end
	S.seen_targets, S.seen_shards = nil, nil
	S.failures_in_row = 0
	return true
end

function Game.bank_for_altar()
	if not Game.open_bank() then
		return
	end
	local keep: { number | string } = { CONST.CHISEL, CONST.COINS, CONST.SHARDS, CONFIG.bones }
	if Bankmain.inventory.contains_different(keep) and not Bankmain.deposit_different(keep) then
		Game.fail("Couldn't deposit the inventory")
		return
	end
	local held = Read.unblessed()
	local wanted = Read.bones_left() - held.loose - held.notes
	if wanted <= 0 then
		Game.finish_if_done()
		if not S.finished then
			Game.close_bank()
		end
		return
	end
	if not Game.withdraw_chisel() then
		return
	end
	for _, item in ipairs({ CONST.COINS, CONST.SHARDS }) do
		if (Bankmain.count_ex(item) or 0) > 0 and not Bankmain.withdraw(item, 0, false) then
			Game.fail(`Couldn't withdraw {item}`)
			return
		end
	end
	if (Bankmain.count(CONFIG.bones) or 0) == 0 then
		if held.notes == 0 then
			Game.out_of_bones()
			return
		end
	elseif not Bankmain.withdraw(CONFIG.bones, wanted, true) then
		Game.fail(`Couldn't withdraw noted {CONFIG.bones}`)
		return
	end
	Game.close_bank()
end

function Game.exchange()
	if Game.finish_if_done() then
		return
	end
	if not Game.walk_to(CONST.VIRILIS_TILE, CONST.VIRILIS_NEAR, CONST.VIRILIS_SPREAD, CONST.VIRILIS) then
		return
	end
	local here = Walker.position()
	local npc = here and Npcs.nearest(CONST.VIRILIS, here)
	if npc == nil then
		Game.fail(`Couldn't find {CONST.VIRILIS}`)
		return
	end
	local held = Read.unblessed()
	if (Inventory.count_ex(CONST.COINS) or 0) < CONST.UNNOTE_COST then
		S.blocked = "out of coins to unnote bones"
		S.finished = true
		return
	end
	if held.notes_slot == nil or (Inventory.free_slots() or 0) == 0 then
		Game.fail("No room to unnote bones")
		return
	end
	if not Inventory.select_slot(held.notes_slot) or not Npcs.interact(npc, "Use") then
		Game.fail(`Couldn't use the noted {CONFIG.bones} on {CONST.VIRILIS}`)
		return
	end
	if not ChatOptions.wait_option("Exchange", false, CONST.DIALOG_TIMEOUT_MS) then
		Game.fail(`{CONST.VIRILIS} didn't offer an exchange`)
		return
	end
	if
		not ChatOptions.select("Exchange all")
		or not Widgets.wait_until(function()
			return Read.unblessed().loose > 0
		end, CONST.DIALOG_TIMEOUT_MS)
	then
		Game.fail(`Couldn't unnote the {CONFIG.bones}`)
		return
	end
	Log.log(NAME, `Unnoted {Read.unblessed().loose} {CONFIG.bones}`)
	S.failures_in_row = 0
end

function Game.bless()
	local here = Walker.position()
	local altar = here and Objects.nearest(CONST.ALTAR, here)
	if altar == nil then
		Game.walk_to(CONST.VIRILIS_TILE, CONST.VIRILIS_NEAR, CONST.VIRILIS_SPREAD, CONST.VIRILIS)
		return
	end
	if not Objects.interact(altar, "Bless") then
		Game.fail(`Couldn't bless the {CONFIG.bones}`)
		return
	end
	if not Widgets.wait_until(function()
		return Read.unblessed().loose == 0
	end, CONST.BLESS_TIMEOUT_MS) then
		Game.fail(`The {CONFIG.bones} didn't get blessed`)
		return
	end
	Game.plan_burst()
	S.failures_in_row = 0
end

function Game.bank()
	if Read.needs_altar() then
		Game.bank_for_altar()
		return
	end
	if not Game.open_bank() then
		return
	end
	if Bankmain.inventory.contains_different({ CONST.CHISEL, CONFIG.bones }) then
		if not Bankmain.deposit_different({ CONST.CHISEL, CONFIG.bones }) then
			Game.fail("Couldn't deposit the inventory")
			return
		end
	end
	local wanted = Read.bones_left() - (Inventory.count(CONFIG.bones) or 0)
	if wanted <= 0 then
		Game.finish_if_done()
		return
	end
	if not Game.withdraw_chisel() then
		return
	end
	if (Bankmain.count(CONFIG.bones) or 0) == 0 then
		Game.out_of_bones()
		return
	end
	local free = Inventory.free_slots() or 0
	if free > 0 and not Bankmain.withdraw(CONFIG.bones, if wanted >= free then 0 else wanted, false) then
		Game.fail(`Couldn't withdraw {CONFIG.bones}`)
		return
	end
	if Game.close_bank() then
		Game.plan_burst()
	end
end

function Read.banked(item: string): number
	return (Bankmain.count_ex(item) or 0) + (Bankmain.inventory.count_ex(item) or 0)
end

type WinePlan = { buy: number, make: number }

function Read.wine_plan(): WinePlan
	local jugs, sunfire = Read.banked(CONST.JUG), Read.banked(CONST.SUNFIRE)
	if CONFIG.mode == "Sunfire wines" then
		if CONFIG.sunfire_wines <= 0 then
			return { buy = 0, make = jugs }
		end
		local goal = S.sunfire_goal or sunfire + CONFIG.sunfire_wines
		S.sunfire_goal = goal
		return { buy = math.max(goal - sunfire - jugs, 0), make = math.max(goal - sunfire, 0) }
	end
	local wines = math.ceil(Read.banked(CONST.SHARDS) / CONST.SHARDS_PER_WINE)
	if CONFIG.wine == "Wine" then
		return { buy = math.max(wines - jugs, 0), make = 0 }
	end
	return { buy = math.max(wines - jugs - sunfire, 0), make = math.max(wines - sunfire, 0) }
end

function Game.withdraw_one(item: string): boolean
	if Inventory.contains(item) then
		return true
	end
	if not Bankmain.contains(item) then
		S.blocked = `no {item} in the bank`
		S.finished = true
		return false
	end
	if not Bankmain.withdraw(item, 1, false) then
		Game.fail(`Couldn't withdraw a {item}`)
		return false
	end
	return true
end

function Game.deposit_all_but(keep: { number | string }): boolean
	if Bankmain.inventory.contains_different(keep) and not Bankmain.deposit_different(keep) then
		Game.fail("Couldn't deposit the inventory")
		return false
	end
	return true
end

function Game.prepare_making(plan: WinePlan)
	if Read.banked(CONST.SPLINTERS) < CONST.SPLINTERS_PER_WINE then
		S.blocked = `out of {CONST.SPLINTERS}`
		S.finished = true
		return
	end
	Log.log(NAME, `Making {plan.make} more {CONST.SUNFIRE}`)
	if not Game.deposit_all_but({ CONST.PESTLE, CONST.SPLINTERS }) or not Game.withdraw_one(CONST.PESTLE) then
		return
	end
	if (Bankmain.count_ex(CONST.SPLINTERS) or 0) > 0 and not Bankmain.withdraw(CONST.SPLINTERS, 0, false) then
		Game.fail(`Couldn't withdraw the {CONST.SPLINTERS}`)
		return
	end
	local free = Inventory.free_slots() or 0
	if free > 0 and not Bankmain.withdraw(CONST.JUG, if plan.make >= free then 0 else plan.make, false) then
		Game.fail(`Couldn't withdraw {CONST.JUG}`)
		return
	end
	if Game.close_bank() then
		S.wine_step = "MAKE"
		Game.plan_burst()
	end
end

function Game.wine_bank()
	if not Game.open_bank() then
		return
	end
	local plan = Read.wine_plan()
	if plan.buy > 0 then
		Log.log(NAME, `Short of {plan.buy} {CONST.JUG}, buy them with the Shopper script`)
		S.blocked = `{plan.buy} more {CONST.JUG} needed`
		S.finished = true
	elseif plan.make > 0 then
		Game.prepare_making(plan)
	else
		Log.log(
			NAME,
			`Have the wine: {Read.banked(CONST.JUG)} {CONST.JUG}, {Read.banked(CONST.SUNFIRE)} {CONST.SUNFIRE}`
		)
		Game.next_phase()
	end
end

function Read.offer_wine(): string
	return if CONFIG.wine == "Sunfire wine" then CONST.SUNFIRE else CONST.JUG
end

function Read.blessed_wines(): number
	local count = 0
	for _, blessed in ipairs(CONST.BLESSED) do
		count += Inventory.count(blessed) or 0
	end
	return count
end

function Read.prayer(): number
	return (Player.prayer()) or 0
end

function Read.bowl(): Host.Loc?
	local here = Read.near(CONST.BOWL_TILE, CONST.SIGHT)
	return here and Objects.nearest(CONST.BOWL, here)
end

function Read.at_bowl(bowl: Host.Loc): boolean
	local here = Walker.position()
	return here ~= nil and Objects.distance(bowl, here) <= 1 and not Player.is_moving()
end

function Game.offer_bank()
	if not Game.open_bank(Game.drop_jugs) then
		return
	end
	local keep: { number | string } = { CONST.SHARDS }
	for _, blessed in ipairs(CONST.BLESSED) do
		table.insert(keep, blessed)
	end
	if not Game.deposit_all_but(keep) then
		return
	end
	if (Bankmain.count_ex(CONST.SHARDS) or 0) > 0 and not Bankmain.withdraw(CONST.SHARDS, 0, false) then
		Game.fail(`Couldn't withdraw the {CONST.SHARDS}`)
		return
	end
	local shards = Inventory.count_ex(CONST.SHARDS) or 0
	if shards == 0 then
		Log.log(NAME, `Offered every {CONST.SHARDS}`)
		Game.next_phase()
		return
	end
	local wine = Read.offer_wine()
	local held = Read.blessed_wines()
	local free = Inventory.free_slots() or 0
	local take = math.min(math.ceil(shards / CONST.SHARDS_PER_WINE) - held, free)
	if take > 0 then
		if (Bankmain.count_ex(wine) or 0) == 0 then
			if held == 0 then
				S.blocked = `out of {wine}`
				S.finished = true
				return
			end
		elseif not Bankmain.withdraw(wine, if take >= free then 0 else take, false) then
			Game.fail(`Couldn't withdraw {wine}`)
			return
		end
	end
	local wines = Read.blessed_wines() + (Inventory.count(wine) or 0)
	Log.log(NAME, `Offering {shards} shards with {wines} wines`)
	if Game.close_bank() then
		S.offer_bank = false
		Game.plan_afk(wines)
	end
end

function Read.loaded(name: string, around: Spot): Host.Loc?
	local here = Read.near(around, CONST.SIGHT)
	return here and Objects.nearest(name, here)
end

function Game.approach(name: string, option: string | { string }, around: Spot, within: number, spread: number): boolean
	local loc = Read.loaded(name, around)
	if loc == nil then
		local spotted = function()
			return Read.loaded(name, around) ~= nil
		end
		if not Game.walk_to(around, within, spread, `the {name}`, spotted) then
			return false
		end
		loc = Read.loaded(name, around)
	end
	if loc == nil then
		Game.fail(`Couldn't find the {name}`)
		return false
	end
	return Objects.approach(loc, option)
end

function Game.bless_wine()
	local wine = Read.offer_wine()
	local clicked = Game.approach(CONST.ALTAR, "Bless", CONST.VIRILIS_TILE, CONST.VIRILIS_NEAR, CONST.VIRILIS_SPREAD)
	if not Widgets.wait_until(function()
		return not Inventory.contains(wine)
	end, CONST.WINE_BLESS_TIMEOUT_MS) then
		Game.fail(if clicked then `The {wine} didn't get blessed` else `Couldn't click Bless on the {CONST.ALTAR}`)
		return
	end
	S.failures_in_row = 0
end

function Game.restore()
	if Inventory.contains(CONST.EMPTY_JUG) then
		Game.walk_to(CONST.SHRINE_TILE, CONST.SHRINE_NEAR, 1, CONST.SHRINE, nil, Game.drop_jugs)
	end
	local clicked = Game.approach(CONST.SHRINE, "Bask", CONST.SHRINE_TILE, CONST.SHRINE_NEAR, 1)
	local _, max = Player.prayer()
	if not Widgets.wait_until(function()
		return Read.prayer() >= (max or 1)
	end, CONST.RESTORE_TIMEOUT_MS) then
		Game.fail(if clicked then "The prayer didn't come back" else `Couldn't bask at the {CONST.SHRINE}`)
		return
	end
	Log.log(NAME, "Prayer restored")
	S.failures_in_row = 0
end

function Game.reach_bowl(): Host.Loc?
	local bowl = Read.bowl()
	if bowl and Read.at_bowl(bowl) then
		return bowl
	end
	Game.approach(CONST.BOWL, CONST.BOWL_OPTIONS, CONST.BOWL_TILE, CONST.BOWL_NEAR, 0)
	bowl = Read.bowl()
	if bowl == nil then
		return nil
	end
	local reached = bowl
	local still_since = time()
	Widgets.wait_until(function()
		if Read.at_bowl(reached) then
			return true
		end
		if Player.is_moving() then
			still_since = time()
		end
		return time() - still_since > CONST.BOWL_STILL_MS
	end, CONST.BOWL_REACH_MS)
	if not Read.at_bowl(reached) then
		Game.fail("Couldn't get to the bowl")
		return nil
	end
	return bowl
end

function Game.plan_afk(wines: number)
	S.fills, S.afk = 0, nil
	local afk = CONST.AFK
	if wines <= 0 or not Biometrics.random_boolean(afk.chance) then
		return
	end
	local plan = {
		wine = Random.int(1, wines + 1),
		after = Random.int(afk.after[1], afk.after[2] + 1),
		ms = Random.int(afk.ms[1], afk.ms[2]),
	}
	S.afk = plan
	Log.log(NAME, `This inventory goes afk after wine {plan.wine}`)
end

function Game.offer()
	local bowl = Game.reach_bowl()
	if bowl == nil then
		return
	end
	local seen = Inventory.count_ex(CONST.SHARDS) or 0
	local wines = Read.blessed_wines()
	local sacrificed = 0
	local last_drop = time()
	while true do
		if Handoff.finishing() or Read.prayer() < CONST.MIN_PRAYER then
			break
		end
		Loop.watch_progress(game_state())
		local shards = Inventory.count_ex(CONST.SHARDS) or 0
		if shards == 0 then
			break
		end
		local held = Read.blessed_wines()
		if held < wines then
			S.fills += wines - held
			sacrificed = 0
		end
		wines = held
		if shards < seen then
			sacrificed += math.max(1, math.floor((seen - shards) / CONST.SHARDS_PER_SACRIFICE))
			seen, last_drop = shards, time()
		end
		local afk = S.afk
		if afk and S.fills >= afk.wine and sacrificed >= afk.after then
			S.afk = nil
			Log.log(NAME, `Going afk for {math.floor(afk.ms / 1000)} s`)
			sleep(afk.ms)
			Loop.watch_progress(game_state())
			seen, last_drop = Inventory.count_ex(CONST.SHARDS) or 0, time()
			wines = Read.blessed_wines()
		end
		if time() - last_drop > CONST.BOWL_DRY_MS then
			if Read.blessed_wines() > 0 then
				Game.fail("The bowl isn't taking the shards")
			else
				Log.log(NAME, "Out of wine")
				S.offer_bank = true
			end
			break
		end
		if not Objects.click(bowl) then
			Game.fail("Couldn't click the bowl")
			break
		end
		local gap = CONST.OFFER_CLICK_MS
		Random.sleep(gap[1], gap[2], "left")
	end
	S.failures_in_row = 0
end

function Game.stalled()
	S.blocked = `the {Read.craft().tool} stopped doing anything`
	S.finished = true
end

function Game.plan_burst()
	S.fast_inventory, S.flip_from, S.flip_to, S.target_slot = false, 0, 0, nil
	if not CONFIG.fast_bursts then
		return
	end
	local b = CONST.BURST
	S.fast_inventory = Biometrics.random_boolean(b.fast_inventory)
	local bones = Read.targets()
	local flip_chance = if S.fast_inventory then b.slow_stretch else b.micro_burst
	if bones >= b.stretch[1] and Biometrics.random_boolean(flip_chance) then
		local length = Random.int(b.stretch[1], math.min(b.stretch[2], bones) + 1)
		S.flip_from = Random.int(length, bones + 1)
		S.flip_to = S.flip_from - length + 1
	end
	local kind = if S.fast_inventory then "Fast" else "Slow"
	local flip = if S.flip_from > 0
		then `, {if S.fast_inventory then "slow" else "fast"} from {S.flip_from} to {S.flip_to} left`
		else ""
	Log.log(NAME, `{kind} inventory{flip}`)
end

function Game.use_tool(pause_ms: number): boolean
	local craft = Read.craft()
	local tool = Inventory.index_of(craft.tool)
	if tool == nil then
		return false
	end
	if tool ~= CONST.TOOL_SLOT then
		if not Inventory.move_slot(tool, CONST.TOOL_SLOT) then
			Game.fail(`Couldn't move the {craft.tool} to the last slot`)
			return false
		end
		tool = CONST.TOOL_SLOT
	end
	local targets = Inventory.indices_of(craft.target) or {}
	local target = S.target_slot
	if target == nil or not table.find(targets, target) then
		target = Inventory.random_near(tool, targets)
		S.target_slot = target
	end
	if target == nil then
		return false
	end
	if not Inventory.select_slot(tool) then
		Game.fail(`Couldn't select the {craft.tool}`)
		return false
	end
	Random.sleep(0, pause_ms, "left")
	if not Inventory.interact_slot(target, "Use") then
		Game.fail(`Couldn't use the {craft.tool}`)
		return false
	end
	S.idle_uses += 1
	return true
end

function Read.fast(bones: number): boolean
	local flipped = bones <= S.flip_from and bones >= S.flip_to
	return bones > 0 and S.fast_inventory ~= flipped
end

function Game.burst()
	Log.log(NAME, `Fast from {Read.targets()} left`)
	while Read.fast(Read.targets()) do
		if Handoff.finishing() or Bankmain.is_open() or S.idle_uses >= CONST.MAX_IDLE_USES then
			break
		end
		Random.sleep(0, CONST.BURST.start_delay_ms, "left")
		if not Game.use_tool(0) then
			break
		end
		Loop.watch_progress(game_state())
		if Ticks.wait(1) == nil then
			break
		end
	end
	S.busy_until = time() + CONST.BUSY_GRACE_MS
	S.failures_in_row = 0
end

function Game.craft()
	if Game.use_tool(CONST.SLOW_PAUSE_MS) then
		S.busy_until = time() + CONST.BUSY_GRACE_MS
		S.failures_in_row = 0
	end
end

function Game.keep_inventory_open()
	if Inventory.is_open() then
		S.reopen_inventory_at = nil
		return
	end
	local at = S.reopen_inventory_at
	if at == nil then
		local delay = CONST.REOPEN_INVENTORY_MS
		S.reopen_inventory_at = time() + Random.left(delay[1], delay[2])
	elseif time() >= at then
		S.reopen_inventory_at = nil
		Log.log(NAME, "Reopening the inventory")
		Inventory.open()
	end
end

function Loop.watch_progress(s: ClientState)
	StatsReport.update(report, s.skills)
	local bank_open = Bankmain.is_open()
	local targets = if S.phase == "OFFER" then nil else Inventory.count(Read.craft().target)
	local shards = Inventory.count_ex(CONST.SHARDS)
	if not bank_open and targets and S.seen_targets and targets < S.seen_targets then
		local made = S.seen_targets - targets
		S.idle_uses = 0
		if S.phase == "WINE" then
			stats.sunfire_made += made
		else
			stats.bones += made
		end
		S.last_progress_at = time()
	end
	if not bank_open and shards and S.seen_shards and shards > S.seen_shards then
		stats.shards += shards - S.seen_shards
	end
	if not bank_open and S.phase == "OFFER" and shards and S.seen_shards and shards < S.seen_shards then
		stats.offered += S.seen_shards - shards
		S.last_progress_at = time()
	end
	S.seen_targets, S.seen_shards = targets, shards
end

function Loop.report_counters()
	local key = `{stats.bones}/{stats.shards}/{stats.sunfire_made}/{stats.offered}/{stats.failures}`
	if key == CONST.REPORT.counters_key then
		return
	end
	CONST.REPORT.counters_key = key
	Host.report_counters({
		{ id = "bones", label = "Bones", value = stats.bones },
		{ id = "shards", label = "Shards", value = stats.shards },
		{ id = "sunfire_made", label = "Sunfire wines made", value = stats.sunfire_made },
		{ id = "offered", label = "Shards offered", value = stats.offered },
		{ id = "failures", label = "Failures", value = stats.failures },
	})
end

function Loop.check_timeouts()
	local t = CONFIG.timeouts
	local idle = time() - S.last_progress_at
	local reason: string? = nil
	if idle >= t.idle_minutes * 60000 then
		reason = `no progress for {t.idle_minutes} minutes`
	elseif S.failures_in_row >= t.max_failures then
		reason = `{S.failures_in_row} failures in a row`
	end
	if reason then
		Log.log(NAME, `Stuck: {reason}, stopping the script`)
		S.blocked = reason
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
	local s = game_state()
	if not (s.game_state == GameState.LOGGED_IN and s.position ~= nil) then
		return if Read.scene_loading(s) then "LOADING" else "LOGIN"
	end
	Loop.watch_progress(s)
	Loop.report_counters()

	if S.phase == "OFFER" then
		return Loop.offer_state()
	end
	if S.phase == "WINE" then
		if Bankmain.is_open() or S.wine_step == "BANK" then
			return "WINE_BANK"
		end
		local splinters = Inventory.count_ex(CONST.SPLINTERS) or 0
		if not Inventory.contains(CONST.PESTLE) or splinters < CONST.SPLINTERS_PER_WINE or Read.targets() == 0 then
			S.wine_step = "BANK"
			return "WINE_BANK"
		end
		return Loop.craft_state()
	end
	local bones = Read.targets()
	if Bankmain.is_open() or not Inventory.contains(CONST.CHISEL) then
		return "BANK"
	end
	if Read.needs_altar() then
		local held = Read.unblessed()
		if held.loose > 0 then
			return "BLESS"
		end
		if bones == 0 then
			return if held.notes > 0 then "EXCHANGE" else "BANK"
		end
	elseif bones == 0 then
		return "BANK"
	end
	return Loop.craft_state()
end

function Read.offer_kit(): { number | string }
	local kit: { number | string } = { CONST.SHARDS, CONST.EMPTY_JUG, Read.offer_wine() }
	for _, blessed in ipairs(CONST.BLESSED) do
		table.insert(kit, blessed)
	end
	return kit
end

function Read.ready_to_offer(): boolean
	local wines = Read.blessed_wines() + (Inventory.count(Read.offer_wine()) or 0)
	return (Inventory.count_ex(CONST.SHARDS) or 0) > 0
		and wines > 0
		and not Inventory.contains_different(Read.offer_kit())
end

function Loop.offer_state(): State
	if S.offer_bank and not Bankmain.is_open() and Read.ready_to_offer() then
		S.offer_bank = false
	end
	if Bankmain.is_open() or S.offer_bank then
		return "OFFER_BANK"
	end
	if Inventory.contains(Read.offer_wine()) then
		return "BLESS_WINE"
	end
	if (Inventory.count_ex(CONST.SHARDS) or 0) == 0 then
		S.offer_bank = true
		return "OFFER_BANK"
	end
	if Read.prayer() < CONST.MIN_PRAYER then
		return "RESTORE"
	end
	return "OFFER"
end

function Loop.craft_state(): State
	if S.idle_uses >= CONST.MAX_IDLE_USES then
		return "STALLED"
	end
	if Player.animation() == Read.craft().animation then
		S.busy_until = time() + CONST.BUSY_GRACE_MS
	end
	if Read.fast(Read.targets()) then
		return "BURST"
	end
	if time() < S.busy_until then
		return "WAIT"
	end
	return "CRAFT"
end

Handler.states = {
	LOADING = function()
		sleep(100)
	end,
	LOGIN = function()
		Game.sign_in()
	end,
	BANK = function()
		Game.bank()
	end,
	EXCHANGE = function()
		Game.exchange()
	end,
	BLESS = function()
		Game.bless()
	end,
	WINE_BANK = function()
		Game.wine_bank()
	end,
	OFFER_BANK = function()
		Game.offer_bank()
	end,
	BLESS_WINE = function()
		Game.bless_wine()
	end,
	RESTORE = function()
		Game.restore()
	end,
	OFFER = function()
		Game.offer()
	end,
	STALLED = function()
		Game.stalled()
	end,
	CRAFT = function()
		Game.craft()
	end,
	BURST = function()
		Game.burst()
	end,
	WAIT = function()
		if CONFIG.antiban and S.antiban_ready then
			Antiban.do_antiban()
		end
		Game.keep_inventory_open()
	end,
}
local last_stray_at = 0
local function close_stray()
	if Bankmain.is_open() or not Toplevel.has_interface() or time() - last_stray_at < 2000 then
		return
	end
	last_stray_at = time()
	Log.log(NAME, `Closing the {Toplevel.interface_name() or "interface"} that is in the way`)
	Toplevel.escape_clear()
end

function Loop.wrap_up()
	local settled, why = Handoff.settle()
	if not settled then
		error(`Couldn't leave the account settled: {why}`, 0)
	end
	if S.blocked then
		Handoff.blocked(S.blocked)
	else
		Handoff.done()
	end
end

function Loop.run()
	Game.apply_settings(Host.settings())
	Log.log(NAME, `{NAME} started: {CONFIG.mode}`)
	local unsupported = Read.unsupported()
	if unsupported then
		Log.log(NAME, `Can't start: {unsupported}`)
		S.blocked = unsupported
		Loop.wrap_up()
		return
	end
	S.phases = CONST.PHASES[CONFIG.mode]
	S.phase = S.phases[1]
	Game.setup()
	if S.phase == "WINE" and S.phases[2] == "OFFER" and Read.ready_to_offer() then
		Log.log(NAME, "Already carrying shards and wine")
		Game.next_phase()
	end
	S.last_progress_at, S.failures_in_row = time(), 0
	Loop.hook_antiban_timeouts()

	while not S.finished do
		if Handoff.finishing() then
			Log.log(NAME, "The queue asked to wrap up")
			break
		end
		Game.poll_settings()
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
	if S.blocked then
		Log.log(NAME, `Stopped: {S.blocked}`)
	end
	Loop.wrap_up()
	Log.log(
		NAME,
		`Done: {stats.bones} bones, {stats.shards} shards, {stats.sunfire_made} sunfire wines made, {stats.offered} shards offered`
	)
end

Loop.run()
