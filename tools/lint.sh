#!/usr/bin/env bash
# Format check (StyLua) and lint (luau-analyze) for the Luau scripts.
#   tools/lint.sh           check only; fails on format diffs or lint warnings
#   tools/lint.sh --fix     format in place first
#   tools/lint.sh --types   also report type errors (noisy: the sandbox's API is not known to luau-analyze)
set -euo pipefail

# Resolve the script directory before changing cwd.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Locate the StyLua config in the same directory as this script.
config_file=""
for candidate in "stylua.toml" ".stylua.toml"; do
	if [[ -f "$script_dir/$candidate" ]]; then
		config_file="$script_dir/$candidate"
		break
	fi
done
if [[ -z "$config_file" ]]; then
	echo "error: no stylua.toml or .stylua.toml found in $script_dir" >&2
	exit 1
fi

cd "$script_dir/.."

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
	stylua --config-path "$config_file" "${dirs[@]}"
else
	stylua --config-path "$config_file" --check "${dirs[@]}"
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
