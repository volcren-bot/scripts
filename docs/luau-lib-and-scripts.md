# Luau scripts

Agent guide to this repo. Paths below are relative to the repo root. The code runs inside the injector's Luau sandbox; the sandbox itself is documented in the client repo's `docs/injector-and-sandbox.md`.

| Path | What |
| --- | --- |
| `scripts/` | Real scripts that do a job in the game. |

The reusable API (`lib/`), its docs and its examples live in the separate `lib` repo; see its `docs/` for the API of each module.

Everything is strict Luau (`--!strict`).

## Scripts

Each is one standalone file that `require`s the lib by relative path, so anything specific to a script lives in it. Run from the loader or with:

```sh
injector run --script scripts/<name>.luau <pid> < scripts/<name>.luau
```

`--script` lets `require` read the lib from disk; without it, the lib embedded in the injector is used. Typical shape:

```luau
--!strict
local Host = require("../lib/host")
local Login = require("../lib/main/interfaces/login/login")

local ok = Login.sign_in()
assert(ok, "couldn't sign in")
```

Scripts keep their settings in a `CONFIG` table at the top (e.g. `scripts/tempoross.luau`). Module conventions (return values, logging with `Log.log`) are described in the lib repo's docs; follow them here too.

## Publishing and stats

A script is published as a revision: a set of files uploaded on the script's page on the website, or by CI. The newest published revision is the live one, and the loader runs it. Old revisions are only kept as history.

- **Entry file:** the loader starts `main.luau`. A revision without one can't run.
- **Several files:** a revision can have up to 50 files of at most 5 MB each. Put them next to `main.luau` and `require("./util")` them. Use flat names (letters, digits, `_`, `.`, `-`), no folders: the loader refuses file names with a `/`.
- **The lib:** `require("../lib/host")` and the other `../lib/...` modules work in a store run, because the loader keeps the newest lib it can run next to the script folders. You don't upload it.
- **CI:** create a deploy token on the script's page, keep it as a secret, and upload the files after each push:

```sh
curl -fsS \
  -H "Authorization: Bearer $DEPLOY_TOKEN" \
  -H "Origin: https://volcren.com" \
  -F files=@main.luau -F files=@util.luau \
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
