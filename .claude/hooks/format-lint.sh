#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): format the touched file, then lint it.
# Formatting is silent. Lint findings go to stderr with exit 2 so Claude sees and fixes them.
set -uo pipefail

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')
[[ -n "$f" && -f "$f" ]] || exit 0
root=$(cd "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root" || exit 0
out=""
[[ $f == *.luau ]] || exit 0
rel=${f#"$root"/}
stylua --config-path tools/stylua.toml "$rel" >/dev/null 2>&1
# Lint warnings only (type errors are noisy per-file), matching tools/lint.sh.
out=$(luau-analyze "$rel" 2>&1 | grep -E '^\S+\([0-9]+,[0-9]+\): ' | grep -v ': TypeError' || true)

if [[ -n "$out" ]]; then
	printf 'Lint issues in %s:\n%s\n' "$f" "$out" >&2
	exit 2
fi
exit 0
