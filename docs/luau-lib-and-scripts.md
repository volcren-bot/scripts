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

## Lint

`tools/lint.sh` runs StyLua and `luau-analyze` over `scripts` (tools from `mise.toml`: `mise install`). `--fix` formats in place; `--types` adds type errors, which are noisy because the analyzer doesn't know the sandbox globals. Run it before finishing Luau changes.

## Gotchas

- Coordinates: world tiles are `x`/`y`; the scene is 128 units per tile; angles are 16384 per turn; scene heights are negative upwards.
- Wait with `Host.sleep` and the tick helpers (`Utils.Ticks`).
- Menu rows in the native client are 22.5 px high with a 16 px header (not Java's 19/15).
