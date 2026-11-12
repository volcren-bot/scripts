# Luau scripts

Agent guide to this repo. Paths below are relative to the repo root. The code runs inside the injector's Luau sandbox; the sandbox itself is documented in the client repo's `docs/injector-and-sandbox.md`.

| Path | What |
| --- | --- |
| `scripts/` | Real scripts that do a job in the game. |

The reusable API (`lib/`), its docs and its examples live in the separate `lib` repo; see its `docs/` for the API of each module.

Everything is strict Luau (`--!strict`).

## Scripts

Each lives in its own folder under `scripts/` and `require`s the lib by relative path, so anything specific to a script lives in that folder. Most are one file; a script that grows parts worth keeping apart splits them into files beside its entry file and `require("./name")`s them. `zulrah/` does this: `zulrah.luau` is the entry and the shared fight loop, and its form's Melee checkbox picks `melee.luau` or, unticked, `ranged.luau` (ranged and magic), which each decide where to stand (melee never takes a dodge tile in place of the phase's tile, and stands on 56,62 or 56,61 for phase 1; `melee.luau` also holds the island's edge strips facing each Zulrah position, `STRIPS`, and per-phase routes, `ROUTES`, whose stops are each attacked once, moving on when the swing starts), when a whip is dodged, whether Zulrah can be attacked from the current tile and which steps to take on the way to a later tile. At start, and on each settings change, every equipment layout set in the form (each form's and the special attack's) must suit the box: ticked, a weapon that attacks from at most 2 tiles (or none) and no autocast spell; unticked, a weapon that attacks from 3 or more tiles (item param 13) or an autocast spell. A spell set to be cast by hand is refused, since the script never casts by hand.

`agility/` runs the rooftop courses, one `Step` per obstacle (the obstacle's id, the box the player stands in before it and `start`, the tile the previous obstacle lands the player on). It knows an obstacle is done from the server, not the screen: the server tile (`Host.movement`) is in the next step's box and the obstacle's XP has arrived, which happen in the same tick, the one the server lets go of the player. The next click follows after a human reaction (`REACT_MS`), with no fixed waits; the step is read from the server tile too, so a model still sliding to the landing never makes it click the obstacle it just did. A fall is known the moment hitpoints drop below what they were when the obstacle started (the server puts the player on the ground in the same tick), or, for a fall that does no damage, once the player has stood still for `FALL_TICKS` ticks outside the step's box and the next one's. The wait has no per-step length: it lasts while the player animates, the server moves them or the scene loads, ends once they have stood still for `FALL_TICKS` ticks (on the same step, the obstacle didn't go), and gives up only after `OBSTACLE_MS`. After a fall it clicks again only once the fall's animation is over (the server ignores clicks until then), and a click that hasn't moved the player or started an animation within `START_TICKS` ticks counts as ignored and is retried at once.

While an obstacle runs, the script does its camera fidgets (the antiban's async "game" tasks and the walk tasks, which hold all its camera tasks), then, when the next obstacle is within `WALK_UP.DIRECT` tiles of the landing (past that no turn shows it and the walk faces it anyway), turns the camera for it as it will look from the landing tile (`Objects.projected`, `Camera.face` and `Camera.look_at` with a `from` tile), then pre-hovers it; nothing moves the camera or the mouse from then until the click, and that click skips `Camera.face` when the obstacle shows. An obstacle up to `WALK_UP.DIRECT` tiles away is clicked straight from where the player lands (the click turns the camera to it when needed) and the server walks there; a farther one is approached (`Objects.approach`: clicked from the landing when it already shows, otherwise picked while walking as soon as it does). When an obstacle can't be clicked because it can't be brought on screen (`Clickbox.reveal` gave up, e.g. in a small game window), the script walks to within `WALK_UP.CLOSE` tiles of it and tries again. Its walks may left-click a tree in the way (`WALK_THROUGH`, "Chop down") instead of right-clicking for "Walk here": the next walk click carries on.

When hitpoints reach the eating mark (`eat_at_hitpoints`) it uses the first inventory item that `Consumables` says would raise them, with that item's own option ("Eat", "Drink", ...); it doesn't eat again within the game's food delay (`FOOD_DELAY_TICKS`), when a second bite would be ignored; with none, the script stops rather than risk more falls.

`blast_furnace/` reads the furnace from varbits instead of checking the melting pot: the ore and coal in the furnace (949 to 959, lead and nickel 18167 and 18168), the bars in the dispenser (941 to 948, lead and cupronickel 18169 and 18170) and the coins in the coffer (5357, 12 coins a tick). Each bank visit picks the trip from those: ore when the furnace's coal (or tin, for bronze) plus a full coal bag covers the ratio for a full inventory of ore and what ore is already waiting, otherwise coal. The game keeps no var for the coal bag, so the script counts it from how the bank's and the inventory's coal change on each Fill and Empty, and empties it in the bank once at the start to know where it stands. Gold is smelted in goldsmith gauntlets, which give their XP as the ore smelts, so they are put on in the bank and swapped for the ice gloves only once the furnace holds no gold ore. Under 60 Smithing the foreman is paid 2,500 coins ("Pay", then "Yes"); no var holds his permission, so the script times the ten minutes from his "you can use the furnace for ten minutes" line, pays again a minute before they run out (he takes the fee while the permission still holds), and pays at once when a "permission" message turns up (the first time each run). Coins for the coffer are withdrawn only when it falls under `coffer_min`, and only the withdrawn amount goes in, since coins in the coffer can't be taken back out. The coffer keeps draining during breaks.

`wintertodt/` has two modes, picked by the form's Mode: Group, which works one side's brazier among other players, and Solo, which plays a round alone. Both mix their own rejuvenation potions at Herblore 3 or above and use Brew'ma below it, and both dodge two attacks shown as spot animation 502 a few ticks before they land: a snowfall, 502 on a tile with 1311 on its four diagonals, hitting that 3 x 3 area; and the brazier attack that breaks a brazier, 502 on the brazier's corner tile at that brazier's `break_z` height (10 higher than the attack that only puts it out, which is left alone), hitting the brazier and the ring around it. The dodge steps to the nearest safe tile, and after a breaking attack on the brazier it is working, waits for it to land and fixes or lights it before anything else. Every wait polls for these attacks each `POLL_MS` (50), and plain pauses use `Wait.sleep`, which returns as soon as one threatens the player's tile. During a round, while it waits on an activity (`ACTIVITY_WAITS`), it may run the tiny async antiban of the `"game"` scope as tempoross does (tiny camera, pitch and zoom changes, small rotations and mouse moves, hovering an NPC or a player); between rounds it runs the `"outside"` ones. Solo keeps the Solo-only settings: the goal (Points or Experience), the potions to keep (counted as doses, lowest dose drunk first, topped up between rounds, and during a round only once they have run out) and, for Points, the points that end a round (5000, plus a random 0 to 1000 drawn each round). It hops to a plain members world (activity "-" in the world switcher) while anyone else is in the room and the round has under 500 points. A round opens by lighting all four braziers: SE, NE, over the Gap to NW, then SW when the player may use the Gap (`Transports.allowed_climbs` has its row), otherwise NE, SE, SW, NW; braziers that go out are relit while the energy is above a random 20 to 30%. Then it works the SW brazier (fixing and lighting it, helping its pyromancer only when incapacitated, chopping, fletching beside it and feeding; Experience burns roots unfletched). For Points it lights nothing below 8% energy, since the boss regains energy while every brazier is out, and chops, fletches and visits the other pyromancers instead. Once the points are reached it ends the round at whichever of SW and SE is nearer, relighting it at once and feeding everything. It does one thing at a time; the only cancel is on a walk between braziers, turning back when the brazier just left goes out and is nearer. Run from the loader or with:

```sh
injector run --script scripts/<name>.luau --lib ../lib <pid> < scripts/<name>.luau
```

`--script` lets `require` read the lib from disk; `@lib` is an alias for the `lib` folder beside the scripts repo (set in `.luaurc` for the analyzer, built into the injector); without it, the lib embedded in the injector is used. When developing, point the script at your own lib checkout with `--lib <dir>` (in the loader: Settings → "lib folder"): the script's `require("@lib/...")` then reads from that folder instead of from beside the script file. Store scripts ignore this and always use the downloaded lib. Typical shape:

```luau
--!strict
local Host = require("@lib/host")
local Login = require("@lib/main/interfaces/login/login")

local ok = Login.sign_in()
assert(ok, "couldn't sign in")
```

Scripts keep their settings in a `CONFIG` table at the top (e.g. `scripts/tempoross.luau`). Module conventions (return values, logging with `Log.log`) are described in the lib repo's docs; follow them here too.

## Publishing and stats

A script is published as a revision: a set of files uploaded on the script's page on the website, or by CI. The newest published revision is the live one, and the loader runs it. Old revisions are only kept as history.

- **Entry file:** the file the loader starts, of any name. With one file, that file is the entry. With several, name it: pick it on the upload form, or send an `entry` field in CI.
- **Several files:** a revision can have up to 50 files of at most 5 MB each. Put them next to the entry file and `require("./util")` them. Use flat names (letters, digits, `_`, `.`, `-`), no folders: the loader refuses file names with a `/`.
- **The lib:** `require("@lib/host")` and the other `@lib/...` modules work in a store run, because the loader keeps the newest lib it can run next to the script folders. You don't upload it.
- **CI:** create a deploy token on the script's page, keep it as a secret, and upload the files after each push:

```sh
curl -fsS \
  -H "Authorization: Bearer $DEPLOY_TOKEN" \
  -H "Origin: https://volcren.com" \
  -F files=@main.luau -F files=@util.luau -F entry=main.luau \
  "https://volcren.com/api/scripts/<script-id>/revisions"
```

  A new revision goes live as soon as the upload finishes. If one is still pending from a failed upload, discard it on the script page first.

### Stats

Scripts tell Volcren what they gained, and it shows in the script's totals. Use `Utils.StatsReport` from the lib (see its docs): create a tracker once and call `StatsReport.update(tracker, state.skills)` each time through the main loop. It sends the experience gained once a minute. `Host.report_stats(experience, gold, custom)` is the function underneath. See `scripts/tempoross.luau` for a script that does it.

Each script has limits per minute of runtime for experience, gold and each custom counter, set on its page. A report outside the limits is refused, and the script keeps running. Leave both bounds of a value at 0 for no limit. Runtime is measured by the loader, so a script can't report more time than really passed. Stats are only collected in store runs.

## Lint

`tools/lint.sh` runs StyLua and `luau-analyze` over `scripts` (tools from `mise.toml`: `mise install`). `--fix` formats in place; `--types` adds type errors, which are noisy because the analyzer doesn't know the sandbox globals. Run it before finishing Luau changes.

## Gotchas

- Coordinates: world tiles are `x`/`y`; the scene is 128 units per tile; angles are 16384 per turn; scene heights are negative upwards.
- Wait with `Host.sleep` and the tick helpers (`Utils.Ticks`).
- Menu rows in the native client are 22.5 px high with a 16 px header (not Java's 19/15).
