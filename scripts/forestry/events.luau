--!strict
local Host = require("@volcren/host")
local time = Host.time
type Tile = Host.Tile
type Npc = Host.Npc
type Loc = Host.Loc
local Biometrics = require("@volcren/biometrics")
local Chat = require("@volcren/chat")
local Inventory = require("@volcren/inventory")
local Item = require("@volcren/item")
local Log = require("@volcren/log")
local Npcs = require("@volcren/npcs")
local Objects = require("@volcren/objects")
local Player = require("@volcren/player")
local Random = require("@volcren/random")
local Walker = require("@volcren/walker")

local NAME = "Forestry"

export type Kind =
	"ROOTS"
	| "SAPLING"
	| "ENT"
	| "FLOWERING"
	| "LEPRECHAUN"
	| "BEEHIVE"
	| "POACHERS"
	| "RITUAL"
	| "PHEASANT"

export type Active = { kind: Kind, at: Tile }

local NPC_KIND: { [number]: Kind } = {
	[12163] = "LEPRECHAUN",
	[12514] = "BEEHIVE",
	[12515] = "BEEHIVE",
	[12516] = "BEEHIVE",
	[12517] = "BEEHIVE",
	[12519] = "RITUAL",
	[12536] = "PHEASANT",
	[12541] = "POACHERS",
	[12543] = "ENT",
	[12544] = "ENT",
	[12553] = "POACHERS",
	[12554] = "POACHERS",
	[12555] = "POACHERS",
	[12559] = "POACHERS",
}
for id = 12120, 12152 do
	NPC_KIND[id] = "FLOWERING"
end
for id = 12520, 12535 do
	NPC_KIND[id] = "RITUAL"
end

local LOC_KIND: { [number]: Kind } = {
	[47482] = "ROOTS",
	[47483] = "ROOTS",
	[49934] = "LEPRECHAUN",
	[49936] = "PHEASANT",
	[49937] = "PHEASANT",
}
for _, id in { 47484, 47485, 47487, 47488, 47490, 47491, 50699, 50700 } do
	LOC_KIND[id] = "SAPLING"
end

local ID = {
	ROOT = 47482,
	ANIMA_ROOT = 47483,
	RAINBOW = 49934,
	BEEBOXES = { 12515, 12516 },
	TRAP = 12541,
	ENTLING = 12543,
	CIRCLE_FIRST = 12520,
	CIRCLE_LAST = 12535,
	NESTS = { 49936, 49937 },
	OPEN_NEST = 49937,
	PHEASANT = 12537,
	FORESTER = 12536,
	EGG = 28661,
	SAPLINGS = { 47484, 47485, 47487, 47488, 47490, 47491, 50699, 50700 },
	MULCH = { 28183, 28648, 28649, 28650 } :: { Item.Item },
	FLOWER_BUSHES = { 12120, 12134, 12141, 12143, 12145, 12147, 12149, 12151 },
	POLLEN = 28192,
	TEND_ANIMATION = 832,
	BEES = 12168,
}

local INGREDIENTS: { { name: string, ids: { number } } } = {
	{ name = "Rotting leaves", ids = { 47493 } },
	{ name = "Green leaves", ids = { 47494 } },
	{ name = "Droppings", ids = { 47495 } },
	{ name = "Wild mushrooms", ids = { 47496, 47497, 47498 } },
	{ name = "Splintered bark", ids = { 47499 } },
}

local POSITIONS = { first = 1, second = 2, third = 3 }

local ENT_REQUESTS: { [string]: { string } } = {
	["Breezy at the back!"] = { "Prune-back" },
	["A leafy mullet!"] = { "Prune-top", "Prune-sides" },
	["Short back and sides!"] = { "Prune-back", "Prune-sides" },
	["Short on top!"] = { "Prune-top" },
}

local RADIUS = 12
local INELIGIBLE = "aren't eligible for full rewards"
local ACTION_MS = 3000
local FAR = 6
local COLLECT_MS = 6000
local FEEDBACK_MS = 6000
local ENT_RESULT_MS = 3500
local BUILD_MS = 9000
local NEST_SAFE_MS = 8000
local NEST_NEIGHBOUR = 2
local STUN_MS = 3200
local RAINBOW_DELAY_MS = 1200
local FLOWER_RETRY_MS = 15000

type Sapling = {
	known: { [number]: string },
	wrong: { [number]: { [string]: boolean } },
	order: { string },
	seq: { string },
}

type Flowering = {
	source: number?,
	active: { number },
	held_from: { [number]: boolean },
	refused: { [number]: number },
	clicked: number?,
}

type Entling = { request: string?, cut: { [string]: boolean }, stale: string? }

type State = {
	kind: Kind?,
	target: string?,
	acted_at: number,
	chat_uid: number,
	rainbows: { [string]: boolean },
	rainbows_seen: { [string]: boolean },
	sapling: Sapling,
	ent: { [number]: Entling },
	flowering: Flowering,
	clicked: number?,
	done: { [number]: boolean },
	open_since: { [string]: number },
	stunned_until: number,
}

local function new_sapling(): Sapling
	local order = {}
	for _, ingredient in INGREDIENTS do
		table.insert(order, ingredient.name)
	end
	for i = #order, 2, -1 do
		local j = Random.int(1, i)
		order[i], order[j] = order[j], order[i]
	end
	return { known = {}, wrong = { {}, {}, {} }, order = order, seq = {} }
end

local S: State = {
	kind = nil,
	target = nil,
	acted_at = 0,
	chat_uid = -1,
	rainbows = {},
	rainbows_seen = {},
	sapling = new_sapling(),
	ent = {},
	flowering = { refused = {}, held_from = {}, active = {} },
	clicked = nil,
	done = {},
	open_since = {},
	stunned_until = 0,
}

local Events = {}

local function key_of(x: number, y: number, id: number): string
	return `{id}@{x},{y}`
end

local function near(list: { Npc }, me: Tile): Npc?
	local best: Npc? = nil
	local best_d = math.huge
	for _, npc in list do
		local d = Npcs.distance(npc, me)
		if d < best_d then
			best, best_d = npc, d
		end
	end
	return best
end

local function npcs_of(ids: { number }): { Npc }
	local out = {}
	for _, npc in Host.npcs() or {} do
		if table.find(ids, npc.id) then
			table.insert(out, npc)
		end
	end
	return out
end

local function locs_of(ids: { number }): { Loc }
	local out = {}
	for _, loc in Host.locs() or {} do
		if table.find(ids, loc.id) then
			table.insert(out, loc)
		end
	end
	return out
end

local function nearest_loc(ids: { number }, me: Tile): Loc?
	local best: Loc? = nil
	local best_d = math.huge
	for _, loc in locs_of(ids) do
		local d = Objects.distance(loc, me)
		if d < best_d then
			best, best_d = loc, d
		end
	end
	return best
end

local function busy_with(key: string): boolean
	if S.target ~= key then
		return false
	end
	return time() - S.acted_at < ACTION_MS or Player.is_animating() or Player.is_moving()
end

local function acted(key: string)
	S.target, S.acted_at = key, time()
end

local function use_loc(loc: Loc, option: string, me: Tile, still_wanted: (() -> boolean)?): boolean
	if Objects.distance(loc, me) > FAR then
		local walk: Walker.WalkOptions? = nil
		if still_wanted then
			walk = {
				on_step = function(): boolean?
					return still_wanted()
				end,
			} :: Walker.WalkOptions
		end
		return Objects.approach(loc, option, { walk = walk })
	end
	return Objects.interact(loc, option)
end

local function use_npc(npc: Npc, option: string, me: Tile): boolean
	local ok = if Npcs.distance(npc, me) > FAR then Npcs.approach(npc, option) else Npcs.interact(npc, option)
	if not ok then
		local click = Host.menu_click()
		Log.log(
			NAME,
			`TRACE {option} on {npc.id} failed, last click {click and click.entry.option} {click and click.entry.target}`
		)
	end
	return ok
end

local function mulch_state(): string
	local parts = {}
	for _, item in Inventory.items() or {} do
		if table.find(ID.MULCH, item.id) then
			table.insert(parts, `{item.id}x{item.quantity}`)
		end
	end
	return table.concat(parts, ",")
end

local function new_chat(): { Chat.Message }
	local messages = Chat.new_messages(S.chat_uid) or {}
	for _, m in messages do
		S.chat_uid = math.max(S.chat_uid, m.uid)
		m.text = string.gsub(m.text, "@[%w_]+@", "")
	end
	return messages
end

function Events.reset()
	S.kind, S.target, S.acted_at = nil, nil, 0
	S.rainbows, S.rainbows_seen, S.ent = {}, {}, {}
	S.flowering = { refused = {}, held_from = {}, active = {} }
	S.clicked, S.done = nil, {}
	S.open_since, S.stunned_until = {}, 0
	S.sapling = new_sapling()
	local last = Chat.last_message()
	S.chat_uid = if last then last.uid else -1
end

local TRACE = { sig = "", uid = -1, inv = "" }

function Events.trace(me: Tile)
	local parts = {}
	local traced = {}
	for _, npc in Host.npcs() or {} do
		if NPC_KIND[npc.id] or npc.id == ID.PHEASANT or npc.id == 12164 or npc.id == 12165 or npc.id == 12168 then
			table.insert(traced, npc)
		end
	end
	local indices = {}
	for _, npc in traced do
		table.insert(indices, npc.index)
	end
	local said = if #indices > 0 then Host.npc_overhead_text(indices) or {} else {}
	local area: { number }? = nil
	for _, npc in traced do
		local look = ""
		if NPC_KIND[npc.id] == "FLOWERING" and npc.id ~= ID.BEES then
			local model = Host.npc_model(npc.index)
			look = `p{(npc :: any).pose}h{(npc :: any).height}v{model and model.vertex_count}`
			local box = area or { npc.x, npc.y, npc.x, npc.y }
			area =
				{ math.min(box[1], npc.x), math.min(box[2], npc.y), math.max(box[3], npc.x), math.max(box[4], npc.y) }
		end
		table.insert(
			parts,
			`N{npc.id}#{npc.index}@{npc.x},{npc.y}a{npc.animation}g{(npc :: any).graphic}i{npc.interacting_npc}o{said[npc.index] or ""}{look}`
		)
	end
	for _, loc in Host.locs() or {} do
		local box = area
		local by_bushes = box ~= nil
			and loc.x >= box[1] - 2
			and loc.y >= box[2] - 2
			and loc.x <= box[3] + 3
			and loc.y <= box[4] + 3
		if
			by_bushes
			or LOC_KIND[loc.id]
			or (loc.id >= 47482 and loc.id <= 47499)
			or (loc.id >= 49933 and loc.id <= 49937)
		then
			local v = Host.loc_shown({ loc.id })
			table.insert(parts, `L{loc.id}@{loc.x},{loc.y}:{v and v[1] and v[1].name}`)
		end
	end
	table.sort(parts)
	local sig = table.concat(parts, " ")
	if sig ~= TRACE.sig then
		TRACE.sig = sig
		if sig ~= "" then
			Log.log(NAME, `TRACE me {me.x},{me.y} {sig}`)
		end
	end
	if TRACE.uid < 0 then
		local last = Chat.last_message()
		TRACE.uid = if last then last.uid else 0
	end
	for _, m in Chat.new_messages(TRACE.uid) or {} do
		TRACE.uid = m.uid
		if m.kind ~= 2 and sig ~= "" then
			Log.log(NAME, `TRACE chat {m.kind} {m.name}: {m.text}`)
		end
	end
	if sig ~= "" then
		local items = {}
		for _, item in Inventory.items() or {} do
			if not string.find(item.name or "", "logs", 1, true) then
				table.insert(items, `{item.id}x{item.quantity}`)
			end
		end
		local inv = table.concat(items, ",")
		if inv ~= TRACE.inv then
			TRACE.inv = inv
			Log.log(NAME, `TRACE inv {inv}`)
		end
	end
end

local SKIP = { kinds = {} :: { [Kind]: boolean }, uid = -1 }

local function skip_ineligible()
	if SKIP.uid < 0 then
		local last = Chat.last_message()
		SKIP.uid = if last then last.uid else 0
	end
	for _, m in Chat.new_messages(SKIP.uid) or {} do
		SKIP.uid = m.uid
		local kind = S.kind
		if kind and string.find(m.text, INELIGIBLE, 1, true) then
			Log.log(NAME, `Not eligible for this {kind} event, leaving it`)
			SKIP.kinds[kind] = true
		end
	end
end

function Events.skipped(kind: Kind): boolean
	return SKIP.kinds[kind] == true
end

function Events.find(trees: { Tile }): Active?
	skip_ineligible()
	local present: { [Kind]: boolean } = {}
	local best: Active? = nil
	local best_d = math.huge
	local function consider(kind: Kind?, x: number, y: number)
		if kind == nil then
			return
		end
		present[kind] = true
		local d = math.huge
		for _, tree in trees do
			d = math.min(d, Walker.distance(tree, { x = x, y = y }))
		end
		if d <= RADIUS and d < best_d and not SKIP.kinds[kind] then
			best, best_d = { kind = kind, at = { x = x, y = y } }, d
		end
	end
	for _, npc in Host.npcs() or {} do
		consider(NPC_KIND[npc.id], npc.x, npc.y)
	end
	for _, loc in Host.locs() or {} do
		consider(LOC_KIND[loc.id], loc.x, loc.y)
	end
	for kind in SKIP.kinds do
		if not present[kind] then
			SKIP.kinds[kind] = nil
		end
	end
	return best
end

local function chop_roots(me: Tile): boolean
	local target = nearest_loc({ ID.ANIMA_ROOT }, me) or nearest_loc({ ID.ROOT }, me)
	if target == nil then
		return false
	end
	local key = key_of(target.x, target.y, target.id)
	if busy_with(key) then
		return true
	end
	Log.log(NAME, if target.id == ID.ANIMA_ROOT then "Chopping the anima-infused roots" else "Chopping the tree roots")
	acted(key)
	use_loc(target, "Chop down", me)
	return true
end

local function disarm_traps(me: Tile): boolean
	for _, m in new_chat() do
		local trap = S.clicked
		if trap and string.find(m.text, "successfully disarm the trap", 1, true) then
			S.done[trap] = true
		end
	end
	local traps = {}
	for _, trap in npcs_of({ ID.TRAP }) do
		if not S.done[trap.index] then
			table.insert(traps, trap)
		end
	end
	local trap = near(traps, me)
	if trap == nil then
		return true
	end
	local key = key_of(trap.x, trap.y, trap.index)
	if busy_with(key) then
		return true
	end
	Log.log(NAME, `Disarming the fox trap at {trap.x}, {trap.y}`)
	acted(key)
	S.clicked = trap.index
	use_npc(trap, "Disarm", me)
	return true
end

local function stand_in_rainbow(me: Tile): boolean
	for _, m in new_chat() do
		local target = S.target
		if target and not S.rainbows[target] and string.find(m.text, "more in touch with the trees", 1, true) then
			S.rainbows[target] = true
			Biometrics.sleep(0, RAINBOW_DELAY_MS)
		end
	end
	for _, rainbow in locs_of({ ID.RAINBOW }) do
		local key = key_of(rainbow.x, rainbow.y, rainbow.id)
		if not S.rainbows[key] then
			if Objects.distance(rainbow, me) == 0 then
				S.target = key
				return true
			end
			if not S.rainbows_seen[key] then
				S.rainbows_seen[key] = true
				Biometrics.sleep(0, RAINBOW_DELAY_MS)
			end
			if busy_with(key) then
				return true
			end
			Log.log(NAME, `Walking under the rainbow at {rainbow.x}, {rainbow.y}`)
			acted(key)
			local tile = { x = rainbow.x, y = rainbow.y }
			if Objects.distance(rainbow, me) > FAR or not Walker.walk_tile(tile) then
				Walker.walk(
					{ x = rainbow.x, y = rainbow.y, plane = rainbow.plane },
					{ near = 0, plane = rainbow.plane }
				)
			end
			return true
		end
	end
	return false
end

local function build_beehive(me: Tile, logs: string): boolean
	for _, m in new_chat() do
		local hive = S.clicked
		if hive and string.find(m.text, "won't benefit from any more wood", 1, true) then
			S.done[hive] = true
		end
	end
	if (Inventory.count(logs) or 0) == 0 then
		return false
	end
	local boxes = {}
	for _, box in npcs_of(ID.BEEBOXES) do
		if not S.done[box.index] then
			table.insert(boxes, box)
		end
	end
	local box = near(boxes, me)
	if box == nil then
		return false
	end
	local key = key_of(box.x, box.y, box.index)
	if busy_with(key) then
		return true
	end
	Log.log(NAME, "Adding logs to the beehive")
	acted(key)
	S.clicked = box.index
	local before = Inventory.count(logs) or 0
	if use_npc(box, "Build", me) then
		local t0 = time()
		local animated = false
		while time() - t0 < BUILD_MS or (animated and Player.is_animating()) do
			Host.sleep(150)
			if Player.is_animating() and not animated then
				animated = true
				Log.log(NAME, `TRACE building, animation {Player.animation() or -1}`)
			end
			if Npcs.refresh(box) == nil then
				Log.log(NAME, "TRACE the beehive changed")
				break
			end
			if (Inventory.count(logs) or 0) < before then
				Log.log(NAME, "TRACE logs used")
				break
			end
			local replied = false
			for _, m in new_chat() do
				if string.find(m.text, "won't benefit from any more wood", 1, true) then
					S.done[box.index] = true
					replied = true
				elseif string.find(m.text, "no logs to build", 1, true) then
					replied = true
				end
			end
			if replied then
				break
			end
		end
	end
	return true
end

local function ritual_circle(): Npc?
	local circles: { Npc } = {}
	local shapes: { [number]: number } = {}
	local colours: { [number]: number } = {}
	for _, npc in Host.npcs() or {} do
		if npc.id >= ID.CIRCLE_FIRST and npc.id <= ID.CIRCLE_LAST then
			local n = npc.id - ID.CIRCLE_FIRST
			local shape, colour = n // 4, n % 4
			shapes[shape] = (shapes[shape] or 0) + 1
			colours[colour] = (colours[colour] or 0) + 1
			table.insert(circles, npc)
		end
	end
	local best: Npc? = nil
	local best_score = math.huge
	for _, npc in circles do
		local n = npc.id - ID.CIRCLE_FIRST
		local score = shapes[n // 4] + colours[n % 4]
		if score < best_score then
			best, best_score = npc, score
		end
	end
	return best
end

local function stand_on_circle(me: Tile): boolean
	local circle = ritual_circle()
	if circle == nil then
		return false
	end
	if me.x == circle.x and me.y == circle.y then
		return true
	end
	local key = key_of(circle.x, circle.y, circle.id)
	if busy_with(key) then
		return true
	end
	Log.log(NAME, `Standing on the odd circle at {circle.x}, {circle.y}`)
	acted(key)
	Walker.walk_tile({ x = circle.x, y = circle.y })
	return true
end

local function watch_nests(): { Loc }
	local now = time()
	local fresh, due = {}, {}
	local seen: { [string]: number } = {}
	for _, nest in locs_of(ID.NESTS) do
		local key = key_of(nest.x, nest.y, 0)
		if nest.id == ID.OPEN_NEST then
			seen[key] = S.open_since[key] or now
			table.insert(if now - seen[key] < NEST_SAFE_MS then fresh else due, nest)
		end
	end
	S.open_since = seen
	local open = {}
	for _, nest in fresh do
		local beside_due = false
		for _, other in due do
			if math.max(math.abs(other.x - nest.x), math.abs(other.y - nest.y)) <= NEST_NEIGHBOUR then
				beside_due = true
			end
		end
		if not beside_due then
			table.insert(open, nest)
		end
	end
	for _, m in new_chat() do
		if string.find(string.lower(m.text), "stunned", 1, true) then
			S.stunned_until = math.max(S.stunned_until, now + STUN_MS)
		end
	end
	return open
end

local function pheasant_eggs(me: Tile): boolean
	local open = watch_nests()
	if time() < S.stunned_until then
		return true
	end
	if (Inventory.count(ID.EGG) or 0) > 0 then
		local forester = near(npcs_of({ ID.FORESTER }), me)
		if forester == nil then
			return false
		end
		local key = key_of(0, 0, forester.index)
		if busy_with(key) then
			return true
		end
		Log.log(NAME, "Handing the egg to the Freaky Forester")
		if use_npc(forester, "Talk-to", me) then
			acted(key)
		end
		return true
	end
	local best: Loc? = nil
	local best_d = math.huge
	for _, nest in open do
		local d = Objects.distance(nest, me)
		if d < best_d then
			best, best_d = nest, d
		end
	end
	if best == nil then
		return true
	end
	local key = key_of(best.x, best.y, best.id)
	if busy_with(key) then
		return true
	end
	Log.log(NAME, `Taking an egg from the nest at {best.x}, {best.y}`)
	acted(key)
	local nest = best
	local key_open = key_of(nest.x, nest.y, 0)
	if
		use_loc(nest, "Retrieve-egg", me, function(): boolean
			local since = S.open_since[key_open]
			return since ~= nil and time() - since < NEST_SAFE_MS
		end)
	then
		local forester = near(npcs_of({ ID.FORESTER }), me)
		if forester then
			Npcs.hover_async(forester)
		end
	end
	return true
end

local function entling(index: number): Entling
	local e = S.ent[index]
	if e == nil then
		local fresh: Entling = { request = nil, cut = {}, stale = nil }
		S.ent[index] = fresh
		return fresh
	end
	return e
end

local function hear_entlings(entlings: { Npc })
	local indices = {}
	for _, npc in entlings do
		table.insert(indices, npc.index)
	end
	local said = Host.npc_overhead_text(indices) or {}
	for _, npc in entlings do
		local e = entling(npc.index)
		local text: string? = said[npc.index]
		if text == nil then
			e.stale = nil
		elseif ENT_REQUESTS[text] and text ~= e.stale and e.request == nil then
			e.request = text
			e.cut = {}
		end
	end
end

local function next_cut(e: Entling): string?
	for _, cut in ENT_REQUESTS[e.request or ""] or {} do
		if not e.cut[cut] then
			return cut
		end
	end
	return nil
end

local function forget_request(e: Entling)
	e.stale, e.request, e.cut = e.request, nil, {}
end

local function prune_entlings(me: Tile): boolean
	local entlings = npcs_of({ ID.ENTLING })
	if #entlings == 0 then
		return false
	end
	hear_entlings(entlings)
	local asking = {}
	for _, npc in entlings do
		if next_cut(entling(npc.index)) then
			table.insert(asking, npc)
		end
	end
	local target = near(asking, me)
	if target == nil then
		return true
	end
	local e = entling(target.index)
	local cut = next_cut(e) :: string
	Log.log(NAME, `Pruning the entling at {target.x}, {target.y}: {cut} for "{e.request}"`)
	acted(key_of(0, 0, target.index))
	new_chat()
	if not use_npc(target, cut, me) then
		return true
	end
	local pruned, wrong = false, false
	local t0 = time()
	while time() - t0 < ENT_RESULT_MS and not (pruned or wrong) do
		for _, m in new_chat() do
			local text = string.lower(m.text)
			pruned = pruned or string.find(text, "you prune the entling", 1, true) ~= nil
			wrong = wrong or string.find(text, "not the cut i asked for", 1, true) ~= nil
		end
		if Npcs.refresh(target) == nil then
			break
		end
		Host.sleep(100)
	end
	if pruned then
		e.cut[cut] = true
		if next_cut(e) == nil then
			forget_request(e)
		end
	elseif wrong then
		Log.log(NAME, `The entling wanted something else than {cut} for "{e.request}"`)
		forget_request(e)
		Host.sleep(Random.int(2600, 3400))
	end
	return true
end

local function sapling_feedback(): number?
	local sap = S.sapling
	local value: number? = nil
	for _, m in new_chat() do
		local text = string.lower(m.text)
		local ingredient, position = string.match(text, "seems to love (.-) as the (%a+) ingredient")
		if ingredient and position and POSITIONS[position] then
			for _, known in INGREDIENTS do
				if string.lower(known.name) == ingredient then
					sap.known[POSITIONS[position]] = known.name
				end
			end
		end
		local percent = string.match(text, "nutritional value of the mulch to be (%d+)%%")
		if percent then
			value = tonumber(percent)
		end
	end
	return value
end

local function sapling_plan(): { string }
	local sap = S.sapling
	local plan = {}
	for pos = 1, 3 do
		local pick = sap.known[pos]
		if pick == nil then
			for _, name in sap.order do
				if not sap.wrong[pos][name] then
					pick = name
					break
				end
			end
		end
		plan[pos] = pick or sap.order[1]
	end
	return plan
end

local function tend_sapling(me: Tile): boolean
	local sap = S.sapling
	sapling_feedback()
	local sapling = nearest_loc(ID.SAPLINGS, me)
	if sapling == nil then
		return false
	end
	local has_mulch = (Inventory.count(ID.MULCH) or 0) > 0
	if #sap.seq >= 3 and has_mulch then
		local key = key_of(sapling.x, sapling.y, sapling.id)
		if busy_with(key) then
			return true
		end
		Log.log(NAME, `Adding mulch: {table.concat(sap.seq, ", ")}`)
		if use_loc(sapling, "Add-mulch", me) then
			acted(key)
			local t0 = time()
			local value: number? = nil
			while value == nil and time() - t0 < FEEDBACK_MS do
				Host.sleep(100)
				value = sapling_feedback()
			end
			for pos, name in sap.seq do
				if value == 100 then
					sap.known[pos] = name
				elseif value and sap.known[pos] ~= name then
					sap.wrong[pos][name] = true
				end
			end
			sap.seq = {}
		end
		return true
	end
	if #sap.seq > 0 and not has_mulch then
		sap.seq = {}
	end
	local want = sapling_plan()[#sap.seq + 1]
	local ids = {}
	for _, ingredient in INGREDIENTS do
		if ingredient.name == want then
			ids = ingredient.ids
		end
	end
	local pile = nearest_loc(ids, me)
	if pile == nil then
		return true
	end
	local key = key_of(pile.x, pile.y, #sap.seq)
	if busy_with(key) then
		return true
	end
	local before = mulch_state()
	Log.log(NAME, `Collecting {want}`)
	acted(key)
	if use_loc(pile, "Collect", me) then
		local t0 = time()
		while time() - t0 < COLLECT_MS do
			if mulch_state() ~= before then
				table.insert(sap.seq, want)
				break
			end
			Host.sleep(100)
		end
	end
	return true
end

local BUSH_REFUSALS = {
	"no open, unpollinated flowers",
	"not yet opened enough",
	"finished flowering",
	"already fruiting",
}

local function mark_active(bush: number)
	local f = S.flowering
	if not table.find(f.active, bush) then
		if #f.active == 2 then
			f.active = {}
		end
		table.insert(f.active, bush)
	end
end

local function flowering_feedback(): boolean
	local f = S.flowering
	local answered = false
	for _, m in new_chat() do
		local text = m.text
		local bush = f.clicked
		if bush then
			local refused = false
			for _, phrase in BUSH_REFUSALS do
				if string.find(text, phrase, 1, true) then
					refused = true
				end
			end
			if
				string.find(text, "apply your pollen", 1, true)
				or string.find(text, "collect some Strange pollen", 1, true)
				or string.find(text, "Anima-infused bark", 1, true)
			then
				mark_active(bush)
				f.source, f.held_from, answered = bush, {}, true
			elseif string.find(text, "You took the pollen from this bush", 1, true) then
				f.held_from[bush], answered = true, true
			elseif refused then
				f.refused[bush] = time()
				if table.find(f.active, bush) then
					f.active = {}
				end
				answered = true
			end
		end
		if string.find(text, "started producing fruit", 1, true) then
			f.source, f.active, f.held_from, f.refused = nil, {}, {}, {}
		end
	end
	return answered
end

local function watch_tenders(bushes: { Npc })
	local f = S.flowering
	local present: { [number]: boolean } = {}
	for _, bush in bushes do
		present[bush.index] = true
	end
	for _, bush in f.active do
		if not present[bush] then
			f.active = {}
			break
		end
	end
	for _, player in Host.players() or {} do
		if player.animation == ID.TEND_ANIMATION and present[player.interacting_npc] then
			mark_active(player.interacting_npc)
		end
	end
end

local function pollinate(me: Tile): boolean
	local bushes = npcs_of(ID.FLOWER_BUSHES)
	if #bushes == 0 then
		return false
	end
	flowering_feedback()
	watch_tenders(bushes)
	local f = S.flowering
	local holding = (Inventory.count(ID.POLLEN) or 0) > 0
	local function usable(index: number): boolean
		return not (holding and (f.source == index or f.held_from[index]))
	end
	local target: Npc? = nil
	for _, wanted in f.active do
		for _, bush in bushes do
			if target == nil and bush.index == wanted and usable(wanted) then
				target = bush
			end
		end
	end
	if target == nil and #f.active == 2 then
		for _, wanted in f.active do
			for _, bush in bushes do
				if target == nil and bush.index == wanted and not f.held_from[wanted] then
					target = bush
				end
			end
		end
	end
	local known = target ~= nil
	if target == nil then
		local candidates = {}
		for _, bush in bushes do
			local refused_at = f.refused[bush.index]
			local fresh = refused_at == nil or time() - refused_at > FLOWER_RETRY_MS
			if fresh and usable(bush.index) then
				table.insert(candidates, bush)
			end
		end
		target = Random.nearest_weighted(candidates, function(b: Npc): number
			return Npcs.distance(b, me)
		end, 2)
	end
	if target == nil then
		return true
	end
	Log.log(
		NAME,
		`{if holding then "Taking the pollen to" else "Tending"} the bush {target.id} at {target.x}, {target.y}{if known
			then " (active)"
			else ""}`
	)
	acted(key_of(0, 0, target.index))
	f.clicked = target.index
	if use_npc(target, "Tend-to", me) then
		local t0 = time()
		while not flowering_feedback() and time() - t0 < FEEDBACK_MS do
			Host.sleep(100)
		end
		Host.sleep(Random.int(300, 600))
	end
	return true
end

function Events.step(active: Active, me: Tile, logs: string): boolean
	if S.kind ~= active.kind then
		Events.reset()
		S.kind = active.kind
		Log.log(NAME, `Event: {active.kind}`)
	end
	local kind = active.kind
	if kind == "ROOTS" then
		return chop_roots(me)
	elseif kind == "POACHERS" then
		return disarm_traps(me)
	elseif kind == "LEPRECHAUN" then
		return stand_in_rainbow(me)
	elseif kind == "BEEHIVE" then
		return build_beehive(me, logs)
	elseif kind == "RITUAL" then
		return stand_on_circle(me)
	elseif kind == "PHEASANT" then
		return pheasant_eggs(me)
	elseif kind == "ENT" then
		return prune_entlings(me)
	elseif kind == "SAPLING" then
		return tend_sapling(me)
	elseif kind == "FLOWERING" then
		return pollinate(me)
	end
	return false
end

return Events
