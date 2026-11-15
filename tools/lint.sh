#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
config=tools/stylua.toml

dirs=()
fix=0
for arg in "$@"; do
	case "$arg" in
	--fix) fix=1 ;;
	-*) echo "unknown option: $arg" >&2; exit 2 ;;
	*) dirs+=("$arg") ;;
	esac
done
((${#dirs[@]})) || dirs=(scripts)

if ((fix)); then
	stylua --config-path "$config" "${dirs[@]}"
else
	stylua --config-path "$config" --check "${dirs[@]}"
fi

diagnostics=$(luau-analyze "${dirs[@]}" 2>&1 | sed "s#^$PWD/#./#" | grep -E '^\S+\([0-9]+,[0-9]+\): ' | sort -u || true)
if [[ -n "$diagnostics" ]]; then
	echo "$diagnostics"
	exit 1
fi
