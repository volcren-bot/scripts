#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory containing this script, regardless of where it is called from.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Find the config file in the same directory as this script.
# Supports both stylua.toml and the newer .stylua.toml naming.
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

# Read the buffer from stdin and write the formatted result to stdout.
# --syntax Luau ensures stdin input is parsed as Luau, not generic Lua.
exec stylua --config-path "$config_file" --syntax Luau -
