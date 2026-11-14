# scripts

Scripts meant to be run for real: they do a job in the game from start to finish. Each one is a single
Luau file built on the API in the sibling `lib` repo (its docs are in `lib/docs/`), run from the loader or with
`injector run --script scripts/<name>.luau <pid> < scripts/<name>.luau` (`--script` is what lets `require("@lib/...")` read the lib from disk).

A script's settings live in a `manifest.json` beside its entry file, read with `Host.settings()` (see `Host.settings` in `lib/docs/host.md` for the format). The loader shows them before the script starts, and `injector run` without the loader uses their defaults. The deploy uploads the manifest with the revision, unencrypted, and the site refuses an invalid one. A script marked `queueable` there promises to start from any safe idle state, to wrap up when `Handoff.finishing()` turns true and to report `Handoff.blocked` when it can't go on (`lib/docs/main/handoff.md`); only mark it once that has run on a live client.

Probes and small examples that check a feature against a live client go in `lib/examples/` (in the lib repo) instead.
