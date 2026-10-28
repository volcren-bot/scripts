#!/usr/bin/env bash
# Format a Luau buffer: reads stdin, writes the result to stdout (for editor integration).
set -euo pipefail

# Run from the repo root so mise resolves the stylua version from mise.toml, whatever the caller's cwd.
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
exec stylua --config-path tools/stylua.toml -
