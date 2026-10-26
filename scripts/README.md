# scripts

Scripts meant to be run for real: they do a job in the game from start to finish. Each one is a single
Luau file built on the API in the sibling `lib` repo (its docs are in `lib/docs/`), run from the loader or with
`injector run --script scripts/<name>.luau <pid> < scripts/<name>.luau` (`--script` is what lets `require("../lib/...")` read the lib from disk).

Probes and small examples that check a feature against a live client go in `lib/examples/` (in the lib repo) instead.
