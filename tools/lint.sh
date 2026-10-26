#!/usr/bin/env bash
# Format check (StyLua) and lint (luau-analyze) for the Luau scripts.
#   tools/lint.sh           check only; fails on format diffs or lint warnings
#   tools/lint.sh --fix     format in place first
#   tools/lint.sh --types   also report type errors (noisy: the sandbox's API is not known to luau-analyze)
set -euo pipefail
cd "$(dirname "$0")/.."

dirs=(scripts)
fix=0 types=0
for arg in "$@"; do
	case "$arg" in
	--fix) fix=1 ;;
	--types) types=1 ;;
	*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

if ((fix)); then
	stylua "${dirs[@]}"
else
	stylua --check "${dirs[@]}"
fi

out=$(luau-analyze "${dirs[@]}" 2>&1 || true)
if ((types)); then
	diagnostics=$out
else
	# Lint warnings only: type errors are everything the analyzer reports as TypeError.
	diagnostics=$(grep -E '^\S+\([0-9]+,[0-9]+\): ' <<<"$out" | grep -v ': TypeError' || true)
fi
if [[ -n "$diagnostics" ]]; then
	echo "$diagnostics"
	exit 1
fi
