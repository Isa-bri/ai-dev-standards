#!/usr/bin/env bash
# Formats the file that was just edited with the project's local Prettier.
#
# Why this exists: without it, every change becomes an "edit -> run lint ->
# find a quote style issue -> edit again" cycle. Formatting should never cost
# a reasoning turn.
#
# Silent by contract: a failure here must never interrupt the agent's work.
set -uo pipefail

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.md | *.yml | *.yaml) ;;
  *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$root" ] || exit 0
[ -x "$root/node_modules/.bin/prettier" ] || exit 0

# --ignore-unknown respects .prettierignore (generated files, lockfiles, ...).
(cd "$root" && ./node_modules/.bin/prettier --write --ignore-unknown "$file") >/dev/null 2>&1

exit 0
